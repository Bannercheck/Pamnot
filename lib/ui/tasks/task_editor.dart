import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/task.dart';
import '../../state/app_controller.dart';
import '../common/format.dart';
import '../common/prediction_bar.dart';
import '../common/soft.dart';
import 'task_tile.dart';

Future<void> showTaskEditor(BuildContext context, AppController app, TaskItem task, {bool isNew = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => TaskEditor(app: app, task: task, isNew: isNew),
    );

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.app, required this.task, this.isNew = false});

  final AppController app;
  final TaskItem task;
  final bool isNew;

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late TaskItem _t = widget.task;
  late final _title = TextEditingController(text: widget.task.title);
  late final _notes = TextEditingController(text: widget.task.notes);
  final _sub = TextEditingController();
  final _titleFocus = FocusNode();
  final _notesFocus = FocusNode();
  final _subFocus = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();

  @override
  void dispose() {
    for (final c in [_title, _notes, _sub]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _notesFocus, _subFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  DateTime get _now => widget.app.now();

  void _setDay(DateTime? day) => setState(() {
        if (day == null) {
          _t = _t.copyWith(due: () => null, hasTime: false);
        } else {
          final old = _t.due;
          final h = _t.hasTime && old != null ? old.hour : 0, m = _t.hasTime && old != null ? old.minute : 0;
          _t = _t.copyWith(due: () => DateTime(day.year, day.month, day.day, h, m));
        }
      });

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _t.due ?? _now,
      firstDate: DateTime(_now.year - 2),
      lastDate: DateTime(_now.year + 10),
    );
    if (d != null) _setDay(d);
  }

  Future<void> _pickTime() async {
    final base = _t.due ?? _now;
    final tm = await showTimePicker(
      context: context,
      initialTime: _t.hasTime ? TimeOfDay.fromDateTime(base) : const TimeOfDay(hour: 9, minute: 0),
    );
    if (tm == null) return;
    setState(() {
      _t = _t.copyWith(due: () => DateTime(base.year, base.month, base.day, tm.hour, tm.minute), hasTime: true);
    });
  }

  Future<void> _toggleRemind() async {
    if (_t.remindAt != null) {
      setState(() => _t = _t.copyWith(remindAt: () => null));
      return;
    }
    final base = _t.due ?? addDays(dateOnly(_now), 1);
    final initial = _t.hasTime ? TimeOfDay.fromDateTime(base) : const TimeOfDay(hour: 9, minute: 0);
    final tm = await showTimePicker(context: context, initialTime: initial);
    if (tm == null) return;
    setState(() => _t = _t.copyWith(remindAt: () => DateTime(base.year, base.month, base.day, tm.hour, tm.minute)));
    await widget.app.scheduler.requestPermission();
  }

  void _addSub() {
    final text = _sub.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _t = _t.copyWith(subtasks: [..._t.subtasks, SubTask(id: widget.app.newId(), title: text)]);
      _sub.clear();
    });
    _subFocus.requestFocus();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      Navigator.pop(context);
      return;
    }
    widget.app.upsertTask(_t.copyWith(title: title, notes: _notes.text.trim()));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final today = dateOnly(_now);
    final due = _t.due;
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(widget.isNew ? s.newTask : s.edit, style: t.textTheme.titleLarge)),
                      if (!widget.isNew)
                        IconButton(
                          tooltip: s.delete,
                          onPressed: () {
                            final messenger = ScaffoldMessenger.of(context);
                            final removed = widget.app.deleteTask(_t.id);
                            Navigator.pop(context);
                            if (removed != null) {
                              showUndoSnack(messenger, s.deleted, () => widget.app.restoreTask(removed), s.undo);
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
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
                    decoration: InputDecoration(hintText: s.taskTitleHint),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    focusNode: _notesFocus,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: s.notesHint, prefixIcon: const Icon(Icons.notes_rounded)),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SoftChip(
                        label: s.dueToday,
                        icon: Icons.wb_sunny_outlined,
                        selected: due != null && isSameDay(due, today),
                        onTap: () => _setDay(today),
                      ),
                      SoftChip(
                        label: s.tomorrow,
                        icon: Icons.wb_twilight_rounded,
                        selected: due != null && isSameDay(due, addDays(today, 1)),
                        onTap: () => _setDay(addDays(today, 1)),
                      ),
                      SoftChip(
                        label: due == null || isSameDay(due, today) || isSameDay(due, addDays(today, 1))
                            ? s.dueDate
                            : formatWhen(s, due, now: _now, withTime: false),
                        icon: Icons.calendar_month_rounded,
                        selected: due != null && !isSameDay(due, today) && !isSameDay(due, addDays(today, 1)),
                        onTap: _pickDay,
                      ),
                      if (due != null)
                        SoftChip(
                          label: _t.hasTime ? hhmm(due) : s.time,
                          icon: Icons.schedule_rounded,
                          selected: _t.hasTime,
                          onTap: _pickTime,
                        ),
                      if (due != null) SoftChip(label: s.noDate, icon: Icons.close_rounded, onTap: () => _setDay(null)),
                      SoftChip(
                        label: _t.remindAt == null ? s.remindMe : formatWhen(s, _t.remindAt!, now: _now),
                        icon: _t.remindAt == null ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                        selected: _t.remindAt != null,
                        onTap: _toggleRemind,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(s.priority, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  SegmentedButton<Priority>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: Priority.low, label: Text(s.low)),
                      ButtonSegment(value: Priority.normal, label: Text(s.normal)),
                      ButtonSegment(value: Priority.high, label: Text(s.high), icon: const Icon(Icons.flag_rounded, size: 16)),
                    ],
                    selected: {_t.priority},
                    onSelectionChanged: (v) => setState(() => _t = _t.copyWith(priority: v.first)),
                  ),
                  const SizedBox(height: 16),
                  Text(s.color, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  PastelPicker(selected: _t.colorIndex, onChanged: (i) => setState(() => _t = _t.copyWith(colorIndex: i))),
                  const SizedBox(height: 16),
                  Text(s.subtasks, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
                  for (final st in _t.subtasks)
                    Row(
                      children: [
                        SoftCheck(
                          done: st.done,
                          size: 22,
                          colorIndex: _t.colorIndex,
                          onTap: () => setState(() => _t = _t.copyWith(subtasks: [
                                for (final x in _t.subtasks) x.id == st.id ? x.copyWith(done: !x.done) : x,
                              ])),
                        ),
                        Expanded(
                          child: Text(
                            st.title,
                            style: TextStyle(decoration: st.done ? TextDecoration.lineThrough : null),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _t = _t.copyWith(subtasks: [
                                for (final x in _t.subtasks)
                                  if (x.id != st.id) x,
                              ])),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _sub,
                    focusNode: _subFocus,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: s.addSubtask,
                      prefixIcon: const Icon(Icons.add_rounded),
                    ),
                    onSubmitted: (_) => _addSub(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _save, child: Text(s.save)),
                ],
              ),
            ),
          ),
          PredictionBar(
            key: _barKey,
            fields: [
              PredictiveField(_title, _titleFocus),
              PredictiveField(_notes, _notesFocus),
              PredictiveField(_sub, _subFocus),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact add-task field with natural-language dates.
class QuickAddField extends StatefulWidget {
  const QuickAddField({super.key, required this.app, this.hint});

  final AppController app;
  final String? hint;

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _c = TextEditingController();
  final _f = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _submit() {
    final added = widget.app.addQuickTask(_c.text);
    if (added == null) return;
    _c.clear();
    final s = S.of(context);
    final when = added.due == null ? s.someday : formatWhen(s, added.due!, now: widget.app.now(), withTime: added.hasTime);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('✓ ${added.title} · $when')));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PredictionKeys(
          barKey: _barKey,
          child: TextField(
            controller: _c,
            focusNode: _f,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: widget.hint ?? s.quickCaptureHint,
              prefixIcon: const Icon(Icons.add_task_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_upward_rounded), onPressed: _submit),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          child: PredictionBar(key: _barKey, fields: [PredictiveField(_c, _f)]),
        ),
      ],
    );
  }
}
