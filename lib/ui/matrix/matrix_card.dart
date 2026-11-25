import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/task.dart';
import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import '../../theme/pamnot_theme.dart';
import '../common/format.dart';
import '../common/soft.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_tile.dart';
import 'list_icons.dart';

/// The drag in progress on the Matrix screen: where the finger picked the
/// card up and where on the card it holds it. Only one drag runs at a time.
abstract final class MatrixDrag {
  static Offset _origin = Offset.zero;
  static Offset _anchor = Offset.zero;

  /// A drop closer than this to the pick-up point is a long press, not a move.
  static const shortDistance = 12.0;

  /// The finger's global position for a feedback drawn at [avatar].
  static Offset pointer(Offset avatar) => avatar + _anchor;

  /// Whether the card dropped at [avatar] moved less than [shortDistance].
  static bool isShort(Offset avatar) => (pointer(avatar) - _origin).distance < shortDistance;

  /// Like [childDragAnchorStrategy] (the card stays under the finger where
  /// it was held), and remembers the pick-up point.
  static Offset anchor(Draggable<Object> draggable, BuildContext context, Offset position) {
    final box = context.findRenderObject()! as RenderBox;
    _origin = position;
    _anchor = box.globalToLocal(position);
    return _anchor;
  }
}

/// A task on the Matrix screen: a flat pastel card (never glass) with the
/// check, the title (two lines at most), the date chip and the subtask count.
///
/// Tap opens the editor. A long press lifts it for dragging into another box
/// or place; let go without moving and the menu opens instead. VoiceOver gets
/// the same moves as actions, so nothing needs a drag.
class MatrixCard extends StatelessWidget {
  const MatrixCard({super.key, required this.app, required this.task, this.draggable = true});

  final AppController app;
  final TaskItem task;

  /// Finished cards are not dragged; a long press opens the menu at once.
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Semantics(
      container: true,
      customSemanticsActions: {
        for (final q in Quadrant.values)
          if (q != task.quadrant)
            CustomSemanticsAction(label: s.moveToBox(s.quadrantTitle(q))): () => app.moveTask(task.id, quadrant: q),
        CustomSemanticsAction(label: s.moveToList): () => pickListAndMove(context, app, task),
        CustomSemanticsAction(label: s.delete): () => deleteTaskWithUndo(context, app, task),
      },
      child: draggable ? _draggable(context) : _face(context, interactive: true),
    );
  }

  Widget _draggable(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => LongPressDraggable<String>(
          data: task.id,
          dragAnchorStrategy: MatrixDrag.anchor,
          hapticFeedbackOnStart: false,
          onDragStarted: HapticFeedback.mediumImpact,
          onDraggableCanceled: (_, offset) {
            if (MatrixDrag.isShort(offset) && context.mounted) showCardMenu(context, app, task);
          },
          feedback: SizedBox(
            width: constraints.maxWidth,
            child: Material(
              type: MaterialType.transparency,
              elevation: 8,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              child: _face(context, interactive: false),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _face(context, interactive: false)),
          child: _face(context, interactive: true),
        ),
      );

  Widget _face(BuildContext context, {required bool interactive}) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final now = app.now();
    final due = task.due;
    final overdue = !task.done && due != null && dateOnly(due).isBefore(dateOnly(now));
    final meta = <Widget>[
      if (due != null)
        overdue
            // Said with an icon and a word too, not by colour alone.
            ? _Meta(
                icon: Icons.error_outline_rounded,
                text: '${s.overdueLabel} · ${formatWhen(s, due, now: now, withTime: task.hasTime)}',
                color: c.error,
              )
            : _Meta(
                icon: task.hasTime ? Icons.schedule_rounded : Icons.event_rounded,
                text: formatWhen(s, due, now: now, withTime: task.hasTime),
              ),
      if (task.subtasks.isNotEmpty)
        _Meta(icon: Icons.checklist_rounded, text: '${task.subtasksDone}/${task.subtasks.length}'),
    ];
    final radius = BorderRadius.circular(16);
    return Material(
      color: pastelAt(task.colorIndex).paper(t.brightness),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: interactive ? () => showTaskEditor(context, app, task) : null,
        onLongPress: interactive && !draggable ? () => showCardMenu(context, app, task) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 10, 2),
          child: Row(
            children: [
              SoftCheck(
                done: task.done,
                label: task.title,
                colorIndex: task.colorIndex,
                size: 22,
                onTap: interactive ? () => app.toggleTask(task.id) : () {},
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: task.done ? c.onSurfaceVariant : c.onSurface,
                          decoration: task.done ? TextDecoration.lineThrough : null,
                          decorationColor: c.onSurfaceVariant,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 10, runSpacing: 2, children: meta),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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
        const SizedBox(width: 3),
        // Wraps rather than overflows at large text sizes.
        Flexible(child: Text(text, style: t.textTheme.labelMedium?.copyWith(color: col))),
      ],
    );
  }
}

/// The long-press menu of a card: move to another list, done, delete.
Future<void> showCardMenu(BuildContext context, AppController app, TaskItem task) {
  final s = S.of(context);
  final c = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(s.moveToList),
            onTap: () {
              Navigator.pop(sheet);
              pickListAndMove(context, app, task);
            },
          ),
          ListTile(
            leading: Icon(task.done ? Icons.undo_rounded : Icons.check_circle_outline_rounded),
            title: Text(task.done ? s.markUndone : s.markDone),
            onTap: () {
              Navigator.pop(sheet);
              app.toggleTask(task.id);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: c.error),
            title: Text(s.delete, style: TextStyle(color: c.error)),
            onTap: () {
              Navigator.pop(sheet);
              deleteTaskWithUndo(context, app, task);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Asks for another list and moves [task] there (same box, at its end).
Future<void> pickListAndMove(BuildContext context, AppController app, TaskItem task) async {
  final s = S.of(context);
  final m = ScaffoldMessenger.of(context);
  final current = app.tasks.where((t) => t.id == task.id).firstOrNull?.listId ?? task.listId;
  final target = await showModalBottomSheet<TaskList>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) {
      final t = Theme.of(sheet);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(s.moveToList, style: t.textTheme.titleMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in app.lists)
                    if (l.id != current)
                      ListTile(
                        key: Key('move-to-${l.id}'),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PastelDot(l.colorIndex),
                            const SizedBox(width: 8),
                            Icon(listIconOf(l.icon), color: t.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(sheet, l),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (target == null) return;
  app.moveTask(task.id, listId: target.id);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(s.movedTo(target.name))));
}

/// Deletes [task] and offers to bring it back.
void deleteTaskWithUndo(BuildContext context, AppController app, TaskItem task) {
  final s = S.of(context);
  final m = ScaffoldMessenger.of(context);
  final removed = app.deleteTask(task.id);
  if (removed == null) return;
  HapticFeedback.mediumImpact();
  showUndoSnack(m, s.deleted, () => app.restoreTask(removed), s.undo);
}
