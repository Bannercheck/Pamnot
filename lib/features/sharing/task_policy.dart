import '../../models/task.dart';

/// Decides, per task, what this device does for tasks that may belong to a
/// shared list.
abstract class TaskPolicy {
  /// The CloudKit user record name of this device's user; '' when unknown.
  String get me;

  /// Whether this device schedules alerts for [t].
  bool alertsHere(TaskItem t);
}

/// No sharing: the user is unknown and every task alerts on this device.
class LocalTaskPolicy implements TaskPolicy {
  const LocalTaskPolicy();

  @override
  String get me => '';

  @override
  bool alertsHere(TaskItem t) => true;
}
