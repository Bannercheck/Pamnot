import '../../models/task.dart';
import '../../services/reminder_scheduler.dart';
import '../../state/app_controller.dart';

/// The notification category of a single final notice; it carries the
/// Done and Snooze actions.
const overdueCategory = 'overdue';

/// More than this many notices in the same minute become one summary.
const overdueSummaryThreshold = 5;

/// When the final notice of [t] fires: an hour after a timed due, 09:00 the
/// day after a date-only due. Null for a finished task or one without a due.
DateTime? noticeAt(TaskItem t) {
  final due = t.due;
  if (t.done || due == null) return null;
  if (t.hasTime) return due.add(const Duration(hours: 1));
  return DateTime(due.year, due.month, due.day + 1, 9);
}

/// The final notices still ahead ([AlertProvider]). Each due gets one: once
/// its moment has passed it is not produced again, and a snoozed task gets
/// a new moment for its new due. A finished or deleted task is simply
/// absent, so the next sync removes its notice.
List<Alert> overdueAlerts(AppController app) {
  if (!app.settings.overdueNotice) return const [];
  final now = app.now();
  final s = app.strings;
  final byMinute = <int, List<Alert>>{};
  for (final t in app.tasks) {
    final at = noticeAt(t);
    if (at == null || !at.isAfter(now) || !app.policy.alertsHere(t)) continue;
    final alert = Alert(
      key: 'o:${t.id}',
      title: s.overdueTitle(t.title),
      body: s.overdueBody,
      at: at,
      category: overdueCategory,
    );
    (byMinute[at.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute] ??= []).add(alert);
  }
  final minutes = byMinute.keys.toList()..sort();
  return [
    for (final m in minutes)
      if (byMinute[m]!.length > overdueSummaryThreshold)
        Alert(
          key: 'o:sum:$m',
          title: s.overdueSummary(byMinute[m]!.length),
          body: s.overdueBody,
          at: byMinute[m]!.map((a) => a.at).reduce((a, b) => a.isBefore(b) ? a : b),
        )
      else
        ...byMinute[m]!,
  ];
}

/// Open tasks past their due that alert on this device, oldest due first.
/// A date-only task is past its due from the next day on.
List<TaskItem> overdueNow(AppController app) {
  final now = app.now();
  final today = DateTime(now.year, now.month, now.day);
  final list = [
    for (final t in app.tasks)
      if (!t.done &&
          t.due != null &&
          (t.hasTime ? t.due!.isBefore(now) : t.due!.isBefore(today)) &&
          app.policy.alertsHere(t))
        t,
  ];
  return list..sort((a, b) => a.due!.compareTo(b.due!));
}
