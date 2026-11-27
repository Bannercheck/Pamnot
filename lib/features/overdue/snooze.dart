import '../../models/task.dart';

/// [t] moved to [due]. A reminder moves by the same amount as the due and is
/// dropped when that puts it before [now] (the current time when omitted).
/// A date-only move keeps only the date. Nothing else changes.
TaskItem snoozed(TaskItem t, DateTime due, {required bool hasTime, DateTime? now}) {
  final newDue = hasTime ? due : DateTime(due.year, due.month, due.day);
  var remindAt = t.remindAt;
  final oldDue = t.due;
  if (remindAt != null && oldDue != null) remindAt = remindAt.add(newDue.difference(oldDue));
  if (remindAt != null && remindAt.isBefore(now ?? DateTime.now())) remindAt = null;
  return t.copyWith(due: () => newDue, hasTime: hasTime, remindAt: () => remindAt);
}

/// One quick choice on the snooze screen.
class SnoozeOption {
  const SnoozeOption({required this.id, required this.due, required this.hasTime});

  /// `tonight`, `tomorrow` or `nextWeek`.
  final String id;
  final DateTime due;
  final bool hasTime;
}

/// The quick choices for [t] at [now]: tonight at 19:00 (only before 19:00),
/// tomorrow and in a week. For a timed task the last two keep the task's
/// time of day; for a date-only task they are dates.
List<SnoozeOption> snoozeOptions(TaskItem t, DateTime now) {
  final tonight = DateTime(now.year, now.month, now.day, 19);
  return [
    if (now.isBefore(tonight)) SnoozeOption(id: 'tonight', due: tonight, hasTime: true),
    SnoozeOption(id: 'tomorrow', due: _daysAhead(t, now, 1), hasTime: _timed(t)),
    SnoozeOption(id: 'nextWeek', due: _daysAhead(t, now, 7), hasTime: _timed(t)),
  ];
}

/// The preselected snooze: tomorrow at the task's time (a date for a
/// date-only task).
DateTime defaultSnooze(TaskItem t, DateTime now) => _daysAhead(t, now, 1);

bool _timed(TaskItem t) => t.hasTime && t.due != null;

DateTime _daysAhead(TaskItem t, DateTime now, int days) {
  final due = t.due;
  if (!_timed(t) || due == null) return DateTime(now.year, now.month, now.day + days);
  return DateTime(now.year, now.month, now.day + days, due.hour, due.minute);
}
