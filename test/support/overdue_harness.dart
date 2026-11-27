import 'dart:convert';

import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/sharing/task_policy.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';

/// A policy that silences alerts of tasks in [quiet].
class QuietPolicy implements TaskPolicy {
  final Set<String> quiet = {};

  @override
  String get me => '';

  @override
  bool alertsHere(TaskItem t) => !quiet.contains(t.id);
}

/// Boots seeded, Turkish [AppController]s on a movable clock and disposes
/// them in [disposeAll].
class OverdueHarness {
  DateTime now = DateTime(2026, 11, 27, 9);
  final _controllers = <AppController>[];

  Future<AppController> boot({bool overdueNotice = true, TaskPolicy? policy}) async {
    final settings = AppSettings(language: AppLanguage.tr, seeded: true, overdueNotice: overdueNotice);
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
      scheduler: NoopScheduler(),
      clock: () => now,
      saveDelay: const Duration(hours: 1),
      policy: policy,
    );
    _controllers.add(c);
    await c.load();
    return c;
  }

  /// Saves an open task due at [due] and returns it as stored.
  TaskItem add(AppController c, String title, {DateTime? due, bool hasTime = true, DateTime? remindAt}) {
    final t = c.draftTask().copyWith(title: title, due: () => due, hasTime: hasTime, remindAt: () => remindAt);
    c.upsertTask(t);
    return c.tasks.firstWhere((x) => x.id == t.id);
  }

  void disposeAll() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }
}
