import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../state/app_scope.dart';
import 'notes/note_editor_page.dart';
import 'notes/notes_page.dart';
import 'planner/planner_page.dart';
import 'reminders/reminders_page.dart';
import 'tasks/track_page.dart';
import 'today/today_page.dart';

/// Payloads of tapped notifications (`r:<id>` or `t:<id>`) and home-screen
/// widgets (`w:today`).
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

  static const _pages = <Widget>[TodayPage(), NotesPage(), TrackPage(), PlannerPage(), RemindersPage()];

  @override
  void initState() {
    super.initState();
    notificationTaps.addListener(_onNotification);
    // A tap that launched the app may have arrived before this shell existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotification());
  }

  @override
  void dispose() {
    notificationTaps.removeListener(_onNotification);
    super.dispose();
  }

  void _onNotification() {
    final p = notificationTaps.value;
    if (p == null) return;
    _go(p.startsWith('w:') ? 0 : (p.startsWith('t:') ? 2 : 4));
    notificationTaps.value = null;
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
      (Icons.notifications_none_rounded, Icons.notifications_rounded, rail ? s.reminders : s.remindersShort),
    ];

    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _pages.length; i++)
          _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
      ],
    );

    final mod = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.keyN, meta: mod, control: !mod): () {
        final app = AppScope.of(context);
        NoteEditorPage.open(context, app.draftNote());
      },
      for (var i = 0; i < 5; i++)
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
                      ),
                    ),
                    VerticalDivider(width: 1, color: c.outlineVariant),
                    Expanded(child: body),
                  ],
                ),
              )
            : Scaffold(
                body: body,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: [
                    for (final (icon, sel, label) in dests)
                      NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
                  ],
                ),
              ),
      ),
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
      child: const Text('☁️', style: TextStyle(fontSize: 22)),
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
