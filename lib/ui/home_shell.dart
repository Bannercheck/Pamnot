import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/launch_actions.dart';
import '../state/app_scope.dart';
import 'common/glass.dart';
import 'common/glass_nav_bar.dart';
import 'notes/note_editor_page.dart';
import 'notes/notes_page.dart';
import 'planner/planner_page.dart';
import 'tasks/task_editor.dart';
import 'tasks/track_page.dart';
import 'today/today_page.dart';
import 'voice/voice_capture_page.dart';

/// Payloads of tapped notifications (`r:<id>` or `t:<id>`) and home-screen
/// widgets (`w:today`). `w:` opens Today, `t:` Track and `r:` the Reminders
/// section of Plan.
final notificationTaps = ValueNotifier<String?>(null);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Tabs are built the first time they are opened, then kept alive.
  final Set<int> _visited = {0};

  /// 0 Today, 1 Notes, 2 Track, 3 Plan (Reminders live inside Plan).
  static const _pages = <Widget>[TodayPage(), NotesPage(), TrackPage(), PlannerPage()];

  @override
  void initState() {
    super.initState();
    // A new shell starts on the agenda; a reminder tap below may change it.
    planSection.value = PlanSection.agenda;
    notificationTaps.addListener(_onNotification);
    voiceRequests.addListener(_onVoiceRequest);
    // A tap or a voice request that launched the app may have arrived before
    // this shell existed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onNotification();
      _onVoiceRequest();
    });
  }

  @override
  void dispose() {
    notificationTaps.removeListener(_onNotification);
    voiceRequests.removeListener(_onVoiceRequest);
    super.dispose();
  }

  void _onNotification() {
    final p = notificationTaps.value;
    if (p == null) return;
    if (p.startsWith('w:')) {
      _go(0);
    } else if (p.startsWith('t:')) {
      _go(2);
    } else {
      planSection.value = PlanSection.reminders;
      _go(3);
    }
    notificationTaps.value = null;
  }

  /// Opens the voice screen for a request from the shortcut, a link or the
  /// microphone button; a link opens it paused, waiting for a tap. A
  /// shortcut while the screen is showing goes to it: it listens again if it
  /// waits for a tap (paused), and is ignored while it listens, previews or
  /// is being corrected. A link while it is showing changes nothing.
  void _onVoiceRequest() {
    final request = voiceRequests.value;
    if (request == null || !mounted) return;
    voiceRequests.value = null;
    final listen = request == VoiceRequest.listen;
    if (VoiceCapturePage.isOpen) {
      if (listen) VoiceCapturePage.requestAgain();
      return;
    }
    unawaited(VoiceCapturePage.open(context, autoListen: listen));
  }

  /// The middle button: voice entry where speech is supported, otherwise a
  /// new task in the editor.
  void _onCenter() {
    final app = AppScope.of(context);
    if (app.speech.isSupported) {
      voiceRequests.value = VoiceRequest.listen;
    } else {
      unawaited(showTaskEditor(context, app, app.draftTask(), isNew: true));
    }
  }

  void _go(int i) => setState(() {
        _index = i;
        _visited.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final rail = width >= 640;
    final dests = [
      (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, s.today),
      (Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, s.notes),
      (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, s.tasks),
      (Icons.calendar_month_outlined, Icons.calendar_month_rounded, s.planner),
    ];
    final voice = AppScope.of(context).speech.isSupported;
    final centerIcon = voice ? Icons.mic_rounded : Icons.add_rounded;
    final centerLabel = voice ? s.voiceMicTooltip : s.navAddTask;

    final body = GlassScope(
      child: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _pages.length; i++)
            _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
        ],
      ),
    );

    final mod = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyN, meta: mod, control: !mod): () {
        final app = AppScope.of(context);
        NoteEditorPage.open(context, app.draftNote());
      },
      for (var i = 0; i < _pages.length; i++)
        SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), meta: mod, control: !mod): () => _go(i),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: rail
            ? Scaffold(
                body: Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        extended: width >= 1100,
                        minExtendedWidth: 210,
                        selectedIndex: _index,
                        onDestinationSelected: _go,
                        groupAlignment: -0.85,
                        leading: Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 20),
                          child: _Logo(extended: width >= 1100),
                        ),
                        destinations: [
                          for (final (icon, sel, label) in dests)
                            NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
                        ],
                        trailing: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: FloatingActionButton.small(
                            key: const Key('nav-center'),
                            heroTag: 'nav-center',
                            tooltip: centerLabel,
                            onPressed: _onCenter,
                            child: Icon(centerIcon),
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: c.outlineVariant),
                    Expanded(child: body),
                  ],
                ),
              )
            : Scaffold(
                // The pages scroll on under the floating glass bar.
                extendBody: true,
                body: _AboveBar(child: body),
                // Like the iOS tab bar, the labels grow only a little with
                // the system text size (GlassNavBar clamps them at 1.3); the
                // pages above follow it in full.
                bottomNavigationBar: GlassNavBar(
                  items: [for (final (icon, sel, label) in dests) GlassNavItem(icon, sel, label)],
                  selectedIndex: _index,
                  onSelected: _go,
                  centerIcon: centerIcon,
                  centerLabel: centerLabel,
                  onCenter: _onCenter,
                ),
              ),
      ),
    );
  }
}

/// Inside the extended body the bar's height arrives as bottom padding;
/// copied into the view padding too, the pages' own floating action buttons
/// (placed by `minViewPadding`) float above the bar instead of under it.
class _AboveBar extends StatelessWidget {
  const _AboveBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.viewPadding.bottom, mq.padding.bottom);
    return MediaQuery(
      data: mq.copyWith(viewPadding: mq.viewPadding.copyWith(bottom: bottom)),
      child: child,
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mark = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFC9BCF5), Color(0xFFFBC9B4)]),
        borderRadius: BorderRadius.circular(16),
      ),
      // Decoration only; VoiceOver skips it.
      child: const ExcludeSemantics(child: Text('☁️', style: TextStyle(fontSize: 22))),
    );
    if (!extended) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text('Pamnot', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
