import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/task.dart';
import '../../state/app_controller.dart';
import '../../ui/common/format.dart';
import '../../ui/common/glass.dart';
import '../../ui/common/soft.dart';
import 'snooze.dart';

/// The snooze screen of an open task: its title, the quick choices and a
/// date and time of the user's own. A choice moves the task's due (see
/// [snoozed]) and shows an undoable snack. An unknown or finished task opens
/// nothing.
Future<void> showSnoozeSheet(BuildContext context, AppController app, String taskId) async {
  final task = _openTask(app, taskId);
  if (task == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await showModalBottomSheet<_Choice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _SnoozeSheet(app: app, task: task),
  );
  if (picked == null) return;
  // The task may have changed or gone while the sheet was open.
  final current = _openTask(app, taskId);
  if (current == null) return;
  app.upsertTask(snoozed(current, picked.due, hasTime: picked.hasTime, now: app.now()));
  final s = app.strings;
  showUndoSnack(
    messenger,
    s.snoozed(formatWhen(s, picked.due, now: app.now(), withTime: picked.hasTime)),
    () => app.restoreTask(current),
    s.undo,
  );
}

TaskItem? _openTask(AppController app, String id) {
  for (final t in app.tasks) {
    if (t.id == id) return t.done ? null : t;
  }
  return null;
}

typedef _Choice = ({DateTime due, bool hasTime});

class _SnoozeSheet extends StatelessWidget {
  const _SnoozeSheet({required this.app, required this.task});

  final AppController app;
  final TaskItem task;

  /// Date, then time, both starting at [defaultSnooze]; cancelling either
  /// changes nothing.
  Future<void> _pick(BuildContext context) async {
    final now = app.now();
    final start = defaultSnooze(task, now);
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null || !context.mounted) return;
    Navigator.pop<_Choice>(context, (due: DateTime(date.year, date.month, date.day, time.hour, time.minute), hasTime: true));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final labels = {'tonight': s.snoozeTonight, 'tomorrow': s.snoozeTomorrow, 'nextWeek': s.snoozeNextWeek};
    final icons = {
      'tonight': Icons.nights_stay_outlined,
      'tomorrow': Icons.wb_sunny_outlined,
      'nextWeek': Icons.date_range_outlined,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: GlassScope(
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(task.title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                Text(s.snoozeTitle, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in snoozeOptions(task, app.now()))
                      SoftChip(
                        key: Key('snooze-${o.id}'),
                        label: labels[o.id] ?? o.id,
                        icon: icons[o.id],
                        onTap: () => Navigator.pop<_Choice>(context, (due: o.due, hasTime: o.hasTime)),
                      ),
                    SoftChip(
                      key: const Key('snooze-pick'),
                      label: s.snoozePick,
                      icon: Icons.edit_calendar_outlined,
                      onTap: () => _pick(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
