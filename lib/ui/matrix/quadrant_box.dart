import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import '../common/glass.dart';
import '../tasks/task_editor.dart';
import 'matrix_card.dart';

/// The single switch that turns the boxes' blur off for older devices
/// (design §13): false paints only the translucent fill.
const matrixBoxesBlur = true;

/// One box of the matrix for one list: title, hint and open count, the open
/// cards, "+ Add", then the folded "Finished (n)" section.
///
/// With [scrollable] the cards scroll inside the box (the 2×2 grid, the box
/// gets a fixed height). Without it the box is a sliver, a section of the
/// page's [CustomScrollView] as tall as its content (the single column, the
/// page scrolls), whose rows are built only when they come on screen; there
/// its header row carries `Key('box-<quadrant>')`.
///
/// It is also the drop target of card drags: a card dropped on a card goes
/// before it when over its upper half, after it otherwise; dropped below the
/// cards it goes to the end.
class QuadrantBox extends StatefulWidget {
  const QuadrantBox({
    super.key,
    required this.app,
    required this.listId,
    required this.quadrant,
    this.scrollable = true,
  });

  final AppController app;
  final String listId;
  final Quadrant quadrant;
  final bool scrollable;

  @override
  State<QuadrantBox> createState() => _QuadrantBoxState();
}

class _QuadrantBoxState extends State<QuadrantBox> {
  bool _showFinished = false;

  /// The sliver box's rows a dragged card is over (each row is a drop target).
  final _hovered = ValueNotifier<int>(0);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  /// A row's count change; a row disposed mid-drag (scrolled away during
  /// layout) reports after the frame, when the box may be gone.
  void _hover(int delta, {bool later = false}) {
    if (!later) {
      _hovered.value += delta;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hovered.value += delta;
    });
  }

  /// Where each open card is on screen, to place a dropped card.
  final _cardKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(QuadrantBox old) {
    super.didUpdateWidget(old);
    if (old.listId != widget.listId) _showFinished = false;
  }

  AppController get _app => widget.app;
  Quadrant get _q => widget.quadrant;

  void _drop(DragTargetDetails<String> d) {
    final id = d.data;
    final task = _app.tasks.where((t) => t.id == id).firstOrNull;
    if (task == null) return;
    if (MatrixDrag.isShort(d.offset)) {
      showCardMenu(context, _app, task);
      return;
    }
    final y = MatrixDrag.pointer(d.offset).dy;
    final open = _app.tasksIn(widget.listId, _q);
    final others = [for (final t in open) if (t.id != id) t.id];
    int? index;
    // Cards are in order top to bottom; the first whose middle is below the
    // finger is the one to go before. Cards scrolled out of the box are not
    // built and are skipped, which keeps that order.
    for (final t in open) {
      final box = _cardKeys[t.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final mid = box.localToGlobal(box.size.center(Offset.zero)).dy;
      if (y < mid) {
        index = t.id == id ? open.indexOf(t) : others.indexOf(t.id);
        break;
      }
    }
    _app.moveTask(id, listId: widget.listId, quadrant: _q, index: index);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final open = _app.tasksIn(widget.listId, _q);
    final finished = _app.tasksIn(widget.listId, _q, done: true);
    _cardKeys.removeWhere((id, _) => !open.any((t) => t.id == id));

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    s.quadrantTitle(_q),
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: c.onSurface),
                  ),
                ),
                Text(s.quadrantHint(_q), style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: s.openTasks(open.length),
            excludeSemantics: true,
            child: Text('${open.length}', style: t.textTheme.titleSmall?.copyWith(color: c.onSurfaceVariant)),
          ),
        ],
      ),
    );

    // The rows below the header, built on demand in the grid.
    final rows = <Widget Function()>[
      if (open.isEmpty)
        () => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(s.boxEmpty, style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
            ),
      for (final task in open)
        () => Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: KeyedSubtree(
                key: _cardKeys.putIfAbsent(task.id, GlobalKey.new),
                child: MatrixCard(key: Key('matrix-card-${task.id}'), app: _app, task: task),
              ),
            ),
      () => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                key: Key('box-add-${_q.name}'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => showTaskEditor(
                  context,
                  _app,
                  _app.draftTask(listId: widget.listId, quadrant: _q),
                  isNew: true,
                  boxChosen: true,
                ),
                icon: const Icon(Icons.add_rounded),
                label: Text(s.addToBox),
              ),
            ),
          ),
      if (finished.isNotEmpty)
        () => Semantics(
              button: true,
              expanded: _showFinished,
              child: InkWell(
                key: Key('box-finished-${_q.name}'),
                onTap: () => setState(() => _showFinished = !_showFinished),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _showFinished ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 20,
                          color: c.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            s.finishedCount(finished.length),
                            style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      if (_showFinished)
        for (final task in finished)
          () => Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: MatrixCard(key: Key('matrix-card-${task.id}'), app: _app, task: task, draggable: false),
              ),
    ];

    final radius = BorderRadius.circular(24);
    BoxDecoration highlight(bool on) => BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: on ? c.primary : Colors.transparent, width: 2),
        );

    if (!widget.scrollable) {
      // The single column: every row is its own drop target, and the box
      // shows the highlight while a card is over any of them.
      Widget row(Widget child) => _RowDropTarget(onHover: _hover, onDrop: _drop, child: child);
      final list = SliverPadding(
        padding: const EdgeInsets.only(bottom: 4),
        sliver: SliverList.builder(
          itemCount: rows.length + 1,
          itemBuilder: (context, i) =>
              i == 0 ? row(KeyedSubtree(key: Key('box-${_q.name}'), child: header)) : row(rows[i - 1]()),
        ),
      );
      return ValueListenableBuilder<int>(
        valueListenable: _hovered,
        child: SliverGlassPanel(sliver: list),
        builder: (context, n, panel) => DecoratedSliver(
          position: DecorationPosition.foreground,
          decoration: highlight(n > 0),
          sliver: panel,
        ),
      );
    }

    final Widget content = Column(
      children: [
        header,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: rows.length,
            itemBuilder: (context, i) => rows[i](),
          ),
        ),
      ],
    );

    return DragTarget<String>(
      onAcceptWithDetails: _drop,
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: highlight(candidates.isNotEmpty),
        child: GlassPanel(blurred: matrixBoxesBlur, child: content),
      ),
    );
  }
}

/// One row of a sliver [QuadrantBox] as a drop target. While a card is over
/// it, it counts itself in through [onHover]; it counts itself out when the
/// card leaves, drops, or the row is scrolled away and disposed mid-drag.
class _RowDropTarget extends StatefulWidget {
  const _RowDropTarget({required this.onHover, required this.onDrop, required this.child});

  final void Function(int delta, {bool later}) onHover;
  final void Function(DragTargetDetails<String>) onDrop;
  final Widget child;

  @override
  State<_RowDropTarget> createState() => _RowDropTargetState();
}

class _RowDropTargetState extends State<_RowDropTarget> {
  bool _over = false;

  void _set(bool over) {
    if (over == _over) return;
    _over = over;
    widget.onHover(over ? 1 : -1);
  }

  @override
  void dispose() {
    // Disposed during layout (a lazy list dropping an off-screen row): no rebuild now.
    if (_over) widget.onHover(-1, later: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          _set(true);
          return true;
        },
        onLeave: (_) => _set(false),
        onAcceptWithDetails: (d) {
          _set(false);
          widget.onDrop(d);
        },
        builder: (context, _, _) => widget.child,
      );
}

