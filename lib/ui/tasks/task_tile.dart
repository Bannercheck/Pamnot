import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/task.dart';
import '../../state/app_controller.dart';
import '../../theme/pamnot_theme.dart';
import '../common/format.dart';
import 'task_editor.dart';

class SoftCheck extends StatelessWidget {
  const SoftCheck({super.key, required this.done, required this.onTap, this.colorIndex = 2, this.size = 26});

  final bool done;
  final VoidCallback onTap;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = pastelAt(colorIndex).accent;
    return Semantics(
      checked: done,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? accent : Colors.transparent,
              border: Border.all(color: done ? accent : accent.withValues(alpha: 0.7), width: 2),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: done
                  ? Icon(Icons.check_rounded, key: const ValueKey(1), size: size * 0.65, color: Colors.white)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.app, required this.task, this.showDate = true});

  final AppController app;
  final TaskItem task;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final now = app.now();
    final overdue = !task.done && task.due != null && dateOnly(task.due!).isBefore(dateOnly(now));
    final meta = <Widget>[
      if (showDate && task.due != null)
        _Meta(
          icon: Icons.event_rounded,
          text: formatWhen(s, task.due!, now: now, withTime: task.hasTime),
          color: overdue ? c.error : null,
        )
      else if (!showDate && task.hasTime && task.due != null)
        _Meta(icon: Icons.schedule_rounded, text: hhmm(task.due!)),
      if (task.subtasks.isNotEmpty)
        _Meta(icon: Icons.checklist_rounded, text: '${task.subtasksDone}/${task.subtasks.length}'),
      if (task.remindAt != null && !task.done) const _Meta(icon: Icons.notifications_none_rounded, text: ''),
      if (task.priority == Priority.high) _Meta(icon: Icons.flag_rounded, text: s.high, color: pastelAt(1).accent),
    ];
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: c.errorContainer, borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.delete_outline_rounded, color: c.onErrorContainer),
      ),
      onDismissed: (_) {
        final removed = app.deleteTask(task.id);
        if (removed == null) return;
        final m = ScaffoldMessenger.of(context);
        m.hideCurrentSnackBar();
        m.showSnackBar(SnackBar(
          content: Text(s.deleted),
          action: SnackBarAction(label: s.undo, onPressed: () => app.restoreTask(removed)),
        ));
      },
      child: Material(
        color: c.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showTaskEditor(context, app, task),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            child: Row(
              children: [
                SoftCheck(done: task.done, colorIndex: task.colorIndex, onTap: () => app.toggleTask(task.id)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: t.textTheme.titleSmall!.copyWith(
                          fontSize: 15.5,
                          color: task.done ? c.onSurfaceVariant.withValues(alpha: 0.7) : c.onSurface,
                          decoration: task.done ? TextDecoration.lineThrough : null,
                          decorationColor: c.onSurfaceVariant,
                        ),
                        child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 10, runSpacing: 2, children: meta),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final col = color ?? t.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: col),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(text, style: t.textTheme.labelMedium?.copyWith(color: col)),
        ],
      ],
    );
  }
}
