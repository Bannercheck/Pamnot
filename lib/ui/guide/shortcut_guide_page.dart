import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/settings.dart';
import '../../services/links.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/soft.dart';
import 'guide_step_card.dart';
import 'phone_hand_animation.dart';

/// "Shortcuts & Siri" (design §10): a card per step of
/// `AppSettings.guideSteps`, then how to use the shortcut with Voice Control.
///
/// The shortcut step turns "Done" by itself when the shortcut opens Pamnot
/// (HomeShell, `shortcutRuns`); the others are marked by hand. "Open
/// Settings" opens Pamnot's page in the Settings app (`app-settings:`, never
/// a private scheme), after starting the step's short video in Picture in
/// Picture where the device supports it; the video stops when the app is
/// back in front.
class ShortcutGuidePage extends StatelessWidget {
  const ShortcutGuidePage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShortcutGuidePage()));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.settings});
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).guideTitle)),
      body: _GuideBody(app: app),
    );
  }
}

class _GuideBody extends StatefulWidget {
  const _GuideBody({required this.app});

  final AppController app;

  @override
  State<_GuideBody> createState() => _GuideBodyState();
}

class _GuideBodyState extends State<_GuideBody> with WidgetsBindingObserver {
  /// How long "Open Settings" waits for Picture in Picture to start.
  static const _pipWait = Duration(milliseconds: 800);

  /// Asked once; the hint and the video depend on it.
  late final Future<bool> _pipSupported = widget.app.pip.isSupported();
  bool _pip = false;

  /// A video was started for the trip to Settings; stopped on return.
  bool _pipStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_pipSupported.then((v) {
      if (mounted && v != _pip) setState(() => _pip = v);
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pipStarted) {
      _pipStarted = false;
      unawaited(widget.app.pip.stop());
    }
  }

  static const _scenes = {
    'shortcut': GuideScene.shortcut,
    'actionButton': GuideScene.actionButton,
    'backTap': GuideScene.backTap,
    'outlook': GuideScene.outlook,
  };

  /// The bundled video of each step that opens Settings (Task 24 makes them).
  static const _videos = {
    'actionButton': 'assets/guide/action_button.mp4',
    'backTap': 'assets/guide/back_tap.mp4',
    'outlook': 'assets/guide/outlook.mp4',
  };

  Future<void> _prepare(String step) async {
    if (await _pipSupported) await widget.app.pip.prepare(_videos[step]!);
  }

  Future<void> _openSettings() async {
    if (await _pipSupported) {
      _pipStarted = true;
      await widget.app.pip.start().timeout(_pipWait, onTimeout: () => false);
    }
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final app = widget.app;
    final pad = MediaQuery.sizeOf(context).width >= 560 ? 28.0 : 16.0;

    Widget wide(Widget button) => SizedBox(width: double.infinity, child: button);

    List<Widget> actions(String step) {
      if (step == 'shortcut') {
        return [
          if (voiceShortcutShareUrl.isNotEmpty)
            wide(FilledButton.icon(
              key: const Key('guide-add-shortcut'),
              onPressed: () => openExternal(Uri.parse(voiceShortcutShareUrl)),
              icon: const Icon(Icons.add_rounded),
              label: Text(s.guideAddShortcut),
            )),
          wide(FilledButton.tonalIcon(
            key: const Key('guide-run-shortcut'),
            onPressed: () => openExternal(runShortcutUri()),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(s.guideRunShortcut),
          )),
        ];
      }
      final done = app.guideStepDone(step);
      return [
        wide(FilledButton.tonalIcon(
          key: Key('guide-open-settings-$step'),
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: Text(s.guideOpenSettings),
        )),
        if (_pip)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.picture_in_picture_alt_outlined, size: 18, color: t.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.guidePipHint,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        wide(OutlinedButton.icon(
          key: Key('guide-mark-$step'),
          onPressed: () => app.markGuideStep(step, done: !done),
          icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded),
          label: Text(done ? s.guideMarkUndone : s.guideMarkDone),
        )),
      ];
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final step in AppSettings.guideSteps) ...[
                GuideStepCard(
                  step: step,
                  scene: _scenes[step]!,
                  done: app.guideStepDone(step),
                  lines: s.guideStepLines(step),
                  actions: actions(step),
                  onOpen: _videos.containsKey(step) ? () => unawaited(_prepare(step)) : null,
                ),
                const SizedBox(height: 12),
              ],
              // Voice Control has no Settings shortcut of its own; it is told here.
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings_voice_outlined, color: t.colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(s.voiceVoiceControlTitle, style: t.textTheme.titleMedium),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(s.voiceVoiceControlSteps, style: t.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
