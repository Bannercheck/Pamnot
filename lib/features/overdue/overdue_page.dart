import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/task.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/common/format.dart';
import '../../ui/common/soft.dart';
import 'overdue_notice.dart';
import 'snooze_sheet.dart';

/// The open tasks past their due ([overdueNow]), opened from a summary
/// notice. Each row closes the task (undoable) or snoozes it.
class OverduePage extends StatelessWidget {
  const OverduePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.tasks});
    final s = S.of(context);
    final tasks = overdueNow(app);
    return Scaffold(
      appBar: AppBar(title: Text(s.overdueListTitle)),
      body: SafeArea(
        child: tasks.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.overdueEmpty, textAlign: TextAlign.center),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _OverdueRow(app: app, task: tasks[i]),
              ),
      ),
    );
  }
}

class _OverdueRow extends StatelessWidget {
  const _OverdueRow({required this.app, required this.task});

  final AppController app;
  final TaskItem task;

  void _close(BuildContext context) {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final before = task;
    if (!app.completeTask(task.id)) return;
    showUndoSnack(messenger, s.taskClosed, () => app.restoreTask(before), s.undo);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final due = task.due!;
    const minSize = Size(44, 44);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(task.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          // The state is in words as well as colour.
          Text(
            '${s.overdueLabel} · ${formatWhen(s, due, now: app.now(), withTime: task.hasTime)}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: Key('overdue-snooze-${task.id}'),
                style: TextButton.styleFrom(minimumSize: minSize),
                onPressed: () => showSnoozeSheet(context, app, task.id),
                icon: const Icon(Icons.schedule_rounded),
                label: Text(s.overdueSnooze),
              ),
              FilledButton.tonalIcon(
                key: Key('overdue-close-${task.id}'),
                style: FilledButton.styleFrom(minimumSize: minSize),
                onPressed: () => _close(context),
                icon: const Icon(Icons.check_rounded),
                label: Text(s.overdueClose),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
