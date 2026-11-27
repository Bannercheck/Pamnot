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
/// a private scheme) and nothing else.
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

class _GuideBody extends StatelessWidget {
  const _GuideBody({required this.app});

  final AppController app;

  static const _scenes = {
    'shortcut': GuideScene.shortcut,
    'actionButton': GuideScene.actionButton,
    'backTap': GuideScene.backTap,
    'outlook': GuideScene.outlook,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
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
          onPressed: openAppSettings,
          icon: const Icon(Icons.settings_outlined),
          label: Text(s.guideOpenSettings),
        )),
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
