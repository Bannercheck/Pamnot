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
      await widget.app.scheduler.requestPermission();
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
