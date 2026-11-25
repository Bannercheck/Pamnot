import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart';
import '../../state/app_controller.dart';
import '../common/format.dart';
import '../common/prediction_bar.dart';
import '../common/soft.dart';

Future<void> showReminderEditor(BuildContext context, AppController app, Reminder r, {bool isNew = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _ReminderEditor(app: app, reminder: r, isNew: isNew),
    );

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.app, required this.reminder, required this.isNew});

  final AppController app;
  final Reminder reminder;
  final bool isNew;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late Reminder _r = widget.reminder;
  late final _title = TextEditingController(text: widget.reminder.title);
  late final _note = TextEditingController(text: widget.reminder.note);
  final _titleFocus = FocusNode();
  final _noteFocus = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = widget.app.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _r.at,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => _r = _r.copyWith(at: DateTime(d.year, d.month, d.day, _r.at.hour, _r.at.minute)));
  }

  Future<void> _pickTime() async {
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_r.at));
    if (tm != null) {
      setState(() => _r = _r.copyWith(at: DateTime(_r.at.year, _r.at.month, _r.at.day, tm.hour, tm.minute)));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final nav = Navigator.of(context);
    if (title.isNotEmpty) {
      widget.app.upsertReminder(_r.copyWith(title: title, note: _note.text.trim(), enabled: true));
      // An alarm rings without notification permission, but turns into a notification when
      // the alarm permission is revoked: it asks only if the app never has.
      if (widget.app.ringsAsAlarm(_r.alertKind)) {
        await widget.app.ensureNotificationPermission();
      } else {
        await widget.app.requestNotifications();
      }
    }
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final now = widget.app.now();
    final quick = <(String, DateTime)>[
      ('+1 ${s.isTr ? 'saat' : 'hour'}', now.add(const Duration(hours: 1))),
      ('${s.tomorrow} 09:00', DateTime(now.year, now.month, now.day + 1, 9)),
      ('${s.isTr ? 'Bu akşam' : 'Tonight'} 20:00', DateTime(now.year, now.month, now.day, 20)),
    ].where((q) => q.$2.isAfter(now)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: PredictionKeys(
              barKey: _barKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(widget.isNew ? s.newReminder : s.edit, style: t.textTheme.titleLarge)),
                      if (!widget.isNew)
                        IconButton(
                          tooltip: s.delete,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () {
                            final messenger = ScaffoldMessenger.of(context);
                            final removed = widget.app.deleteReminder(_r.id);
                            Navigator.pop(context);
                            if (removed != null) {
                              showUndoSnack(messenger, s.deleted, () => widget.app.restoreReminder(removed), s.undo);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    focusNode: _titleFocus,
                    autofocus: widget.isNew,
                    textCapitalization: TextCapitalization.sentences,
                    style: t.textTheme.titleMedium,
                    decoration: InputDecoration(hintText: s.reminderTitleHint, prefixIcon: const Icon(Icons.notifications_none_rounded)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _note,
                    focusNode: _noteFocus,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: s.notesHint, prefixIcon: const Icon(Icons.notes_rounded)),
                  ),
                  const SizedBox(height: 16),
                  if (quick.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, at) in quick)
                          SoftChip(
                            label: label,
                            icon: Icons.bolt_rounded,
                            selected: _r.at == at,
                            onTap: () => setState(() => _r = _r.copyWith(at: at)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SoftChip(
                          label: formatWhen(s, _r.at, now: now, withTime: false),
                          icon: Icons.calendar_month_rounded,
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SoftChip(label: hhmm(_r.at), icon: Icons.schedule_rounded, onTap: _pickTime),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(s.repeat, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in Repeat.values)
                        ChoiceChip(
                          label: Text(repeatLabel(s, r)),
                          selected: _r.repeat == r,
                          onSelected: (_) => setState(() => _r = _r.copyWith(repeat: r)),
                        ),
                    ],
                  ),
                  if (widget.app.alarmSupported) ...[
                    const SizedBox(height: 16),
                    AlertKindPicker(
                      app: widget.app,
                      value: _r.alertKind,
                      onChanged: (k) => setState(() => _r = _r.copyWith(alertKind: k)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PastelPicker(selected: _r.colorIndex, onChanged: (i) => setState(() => _r = _r.copyWith(colorIndex: i))),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _save, child: Text(s.save)),
                ],
              ),
            ),
          ),
          PredictionBar(
            key: _barKey,
            fields: [PredictiveField(_title, _titleFocus), PredictiveField(_note, _noteFocus)],
          ),
        ],
      ),
    );
  }
}

/// "Alert type": Notification or Alarm (design §7.1), for reminders and
/// tasks. Shown only where alarms are supported. Picking Alarm asks for the
/// alarm permission the first time; when it is refused the choice returns
/// to Notification and says why.
class AlertKindPicker extends StatefulWidget {
  const AlertKindPicker({super.key, required this.app, required this.value, required this.onChanged});

  final AppController app;
  final AlertKind value;
  final ValueChanged<AlertKind> onChanged;

  @override
  State<AlertKindPicker> createState() => _AlertKindPickerState();
}

class _AlertKindPickerState extends State<AlertKindPicker> {
  /// The last Alarm pick was refused; the line below says so.
  bool _denied = false;

  /// The latest pick; an older one waiting on the system prompt yields.
  AlertKind? _picked;

  Future<void> _pick(AlertKind k) async {
    _picked = k;
    widget.onChanged(k);
    if (k != AlertKind.alarm) {
      setState(() => _denied = false);
      return;
    }
    final allowed = await widget.app.ensureAlarmAccess();
    // Another pick may have come while the system asked.
    if (!mounted || _picked != AlertKind.alarm) return;
    setState(() => _denied = !allowed);
    if (allowed) return;
    _picked = AlertKind.notification;
    widget.onChanged(AlertKind.notification);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(S.of(context).alarmDenied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.alertKind, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: 8),
        SegmentedButton<AlertKind>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: AlertKind.notification,
              label: Text(s.alertNotification),
              icon: const Icon(Icons.notifications_none_rounded, size: 18),
            ),
            ButtonSegment(value: AlertKind.alarm, label: Text(s.alertAlarm), icon: const Icon(Icons.alarm_rounded, size: 18)),
          ],
          selected: {widget.value},
          onSelectionChanged: (v) => _pick(v.first),
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: _denied,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(_denied ? Icons.info_outline_rounded : Icons.alarm_rounded, size: 16, color: c.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _denied ? s.alarmDenied : s.alarmHint,
                  style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
