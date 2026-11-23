import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/voice_log.dart';
import '../../state/app_controller.dart';
import '../common/format.dart';
import '../common/soft.dart';

/// Settings > "Add by voice": where the shortcut can be found, how to put it
/// on Back Tap and Voice Control, the opt-in log of recognised text and the
/// privacy note. Only shown when [AppController.speech] is supported; it never
/// calls the recogniser, so it asks for no permission.
///
/// There are deliberately no Action button steps: the system's own Action
/// button settings already list the shortcut (HIG Action button).
class VoiceSettingsGroup extends StatelessWidget {
  const VoiceSettingsGroup({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final st = app.settings;

    Widget guide(IconData icon, String title, String steps) => ExpansionTile(
          leading: Icon(icon),
          title: Text(title),
          // No divider lines inside the card.
          shape: const Border(),
          collapsedShape: const Border(),
          expandedAlignment: Alignment.centerLeft,
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [Text(steps, style: t.textTheme.bodyMedium)],
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(s.voiceSettings),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(leading: const Icon(Icons.bolt_outlined), title: Text(s.voiceSetupReady)),
                ListTile(leading: const Icon(Icons.record_voice_over_outlined), title: Text(s.voiceSiriHint)),
                guide(Icons.touch_app_outlined, s.voiceBackTapTitle, s.voiceBackTapSteps),
                guide(Icons.settings_voice_outlined, s.voiceVoiceControlTitle, s.voiceVoiceControlSteps),
                SwitchListTile(
                  secondary: const Icon(Icons.history_rounded),
                  title: Text(s.voiceKeepLog),
                  subtitle: Text(s.voiceKeepLogSub),
                  value: st.keepVoiceLog,
                  // Turning it off also deletes what was kept (AppController).
                  onChanged: (v) => app.updateSettings(st.copyWith(keepVoiceLog: v)),
                ),
                if (st.keepVoiceLog) _RecentLog(app: app),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    s.voicePrivacyNote,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Recently recognised": each raw transcript with what the parser made of it.
class _RecentLog extends StatelessWidget {
  const _RecentLog({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final log = app.voiceLog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(s.voiceRecent, style: t.textTheme.titleSmall),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: log.isEmpty ? null : app.clearVoiceLog,
                child: Text(s.voiceClearLog),
              ),
            ],
          ),
        ),
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.voiceRecentEmpty,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final e in log)
            ListTile(
              title: Text(e.transcript),
              subtitle: Text(_parsed(s, e)),
            ),
      ],
    );
  }

  /// "Title · Tomorrow 10:00", "Title · Someday" or "Text · Note".
  String _parsed(S s, VoiceLogEntry e) {
    final String what;
    if (e.isNote) {
      what = s.voiceNoteChip;
    } else if (e.due case final due?) {
      what = formatWhen(s, due, now: app.now(), withTime: e.hasTime);
    } else {
      what = s.someday;
    }
    return '${e.title} · $what';
  }
}
