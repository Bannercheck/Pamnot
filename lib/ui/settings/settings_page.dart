import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/settings.dart';
import '../../services/handwriting.dart';
import '../../services/links.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/soft.dart';
import 'calendar_settings.dart';
import 'voice_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.settings});
    final s = S.of(context);
    final t = Theme.of(context);
    final st = app.settings;
    void set(AppSettings v) => app.updateSettings(v);

    Widget group(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title),
              SoftCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
            ],
          ),
        );

    /// A small explanatory line inside a group.
    Widget note(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: Text(text, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          ContentWidth(
            maxWidth: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                group(s.language, [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<AppLanguage>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: AppLanguage.system, label: Text(s.systemDefault)),
                        ButtonSegment(value: AppLanguage.tr, label: Text(s.turkish)),
                        ButtonSegment(value: AppLanguage.en, label: Text(s.english)),
                      ],
                      selected: {st.language},
                      onSelectionChanged: (v) => set(st.copyWith(language: v.first)),
                    ),
                  ),
                ]),
                group(s.theme, [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: ThemeMode.system, label: Text(s.systemDefault), icon: const Icon(Icons.brightness_auto_rounded)),
                        ButtonSegment(value: ThemeMode.light, label: Text(s.themeLight), icon: const Icon(Icons.light_mode_rounded)),
                        ButtonSegment(value: ThemeMode.dark, label: Text(s.themeDark), icon: const Icon(Icons.dark_mode_rounded)),
                      ],
                      selected: {st.themeMode},
                      onSelectionChanged: (v) => set(st.copyWith(themeMode: v.first)),
                    ),
                  ),
                ]),
                group(s.wordPrediction, [
                  SwitchListTile(
                    title: Text(s.wordPrediction),
                    subtitle: Text(s.wordPredictionSub),
                    value: st.prediction,
                    onChanged: (v) => set(st.copyWith(prediction: v)),
                  ),
                  ListTile(
                    title: Text(s.predictionLanguage),
                    trailing: DropdownButton<PredictionLanguage>(
                      value: st.predictionLanguage,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(16),
                      items: [
                        DropdownMenuItem(value: PredictionLanguage.auto, child: Text(s.auto)),
                        DropdownMenuItem(value: PredictionLanguage.tr, child: Text(s.turkish)),
                        DropdownMenuItem(value: PredictionLanguage.en, child: Text(s.english)),
                      ],
                      onChanged: st.prediction ? (v) => set(st.copyWith(predictionLanguage: v)) : null,
                    ),
                  ),
                ]),
                group(s.pencil, [
                  SwitchListTile(
                    title: Text(s.stylusOnly),
                    subtitle: Text(s.stylusOnlySub),
                    value: st.stylusOnly,
                    onChanged: (v) => set(st.copyWith(stylusOnly: v)),
                  ),
                  SwitchListTile(
                    title: Text(s.autoStylus),
                    value: st.autoStylusOnly,
                    onChanged: (v) => set(st.copyWith(autoStylusOnly: v)),
                  ),
                  if (app.handwriting.isSupported) ...[
                    _ModelTiles(app: app),
                    note(s.handwritingPrivacyNote),
                  ],
                ]),
                group(s.planner, [
                  SwitchListTile(
                    title: Text(s.weekStartsMonday),
                    value: st.mondayFirst,
                    onChanged: (v) => set(st.copyWith(mondayFirst: v)),
                  ),
                ]),
                if (app.speech.isSupported) VoiceSettingsGroup(app: app),
                if (app.calendar.isSupported) CalendarSettingsGroup(app: app),
                group(s.notifications, [_NotificationTiles(app: app)]),
                group(s.about, [
                  ListTile(
                    leading: const ExcludeSemantics(child: Text('☁️', style: TextStyle(fontSize: 24))),
                    title: const Text('Pamnot'),
                    subtitle: Text(s.aboutText),
                  ),
                  note(s.dataNote),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(s.privacyPolicy),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => openExternal(Uri.parse(privacyPolicyUrl)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: Text(s.support),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => openExternal(Uri.parse(supportUrl)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(s.licenses),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLicensePage(context: context, applicationName: 'Pamnot'),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Nunito font © The Nunito Project Authors, SIL Open Font License 1.1',
                  textAlign: TextAlign.center,
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTiles extends StatefulWidget {
  const _ModelTiles({required this.app});

  final AppController app;

  @override
  State<_ModelTiles> createState() => _ModelTilesState();
}

class _ModelTilesState extends State<_ModelTiles> {
  final Map<String, bool?> _ready = {};
  final Set<String> _busy = {};

  static final _models = {
    HandwritingRecognizer.modelFor('tr'): 'Türkçe',
    HandwritingRecognizer.modelFor('en'): 'English',
  };

  @override
  void initState() {
    super.initState();
    for (final m in _models.keys) {
      widget.app.handwriting.isModelReady(m).then((v) {
        if (mounted) setState(() => _ready[m] = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      children: [
        ListTile(title: Text(s.handwritingModels), dense: true),
        for (final e in _models.entries)
          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: Text(e.value),
            trailing: _busy.contains(e.key)
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : _ready[e.key] == true
                    ? Chip(label: Text(s.ready))
                    : TextButton(
                        onPressed: () async {
                          setState(() => _busy.add(e.key));
                          final ok = await widget.app.handwriting.prepare(e.key);
                          if (mounted) {
                            setState(() {
                              _busy.remove(e.key);
                              _ready[e.key] = ok;
                            });
                          }
                        },
                        child: Text(s.download),
                      ),
          ),
      ],
    );
  }
}

/// The notification status line and the test notification. The status is
/// read when the page opens and again whenever the app comes back to the
/// foreground (e.g. from the system Settings app).
class _NotificationTiles extends StatefulWidget {
  const _NotificationTiles({required this.app});

  final AppController app;

  @override
  State<_NotificationTiles> createState() => _NotificationTilesState();
}

class _NotificationTilesState extends State<_NotificationTiles> {
  late final AppLifecycleListener _lifecycle;

  /// Null until the first answer arrives.
  NotificationAccess? _access;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final access = await widget.app.notificationAccess();
    if (mounted) setState(() => _access = access);
  }

  Future<void> _request() async {
    await widget.app.requestNotifications();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = widget.app;
    final st = app.settings;
    final motivationAt = DateTime(2000, 1, 1, st.motivationMinutes ~/ 60, st.motivationMinutes % 60);
    return Column(
      children: [
        switch (_access) {
          // One row's height, so nothing jumps when the answer arrives.
          null => const SizedBox(height: 56),
          NotificationAccess.notAsked => ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(s.notificationsAllow),
              onTap: _request,
            ),
          // The system prompt does not come back; only Settings can change it.
          NotificationAccess.denied => ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(s.notificationsDenied),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: openAppSettings,
            ),
          NotificationAccess.granted => ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text(s.notificationsOn),
            ),
        },
        ListTile(
          leading: const Icon(Icons.send_rounded),
          title: Text(s.testNotification),
          onTap: () async {
            await _request();
            await widget.app.scheduler.showNow('Pamnot', s.testNotificationBody);
          },
        ),
        // Daily motivation: turning it on asks for nothing; without
        // notification permission the system simply shows nothing.
        // Without an icon, like the page's other switches.
        SwitchListTile(
          title: Text(s.dailyMotivation),
          subtitle: Text(s.dailyMotivationSub),
          value: st.dailyMotivation,
          onChanged: (v) => app.updateSettings(st.copyWith(dailyMotivation: v)),
        ),
        if (st.dailyMotivation)
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(s.motivationTime),
            trailing: Text(hhmm(motivationAt), style: Theme.of(context).textTheme.titleMedium),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(motivationAt));
              if (picked == null) return;
              app.updateSettings(app.settings.copyWith(motivationMinutes: picked.hour * 60 + picked.minute));
            },
          ),
      ],
    );
  }
}
