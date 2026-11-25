import 'package:flutter/material.dart';
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
/// gets a fixed height); without it the box is as tall as its content (the
/// single column, the page scrolls).
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

    final Widget content = widget.scrollable
        ? Column(
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
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, for (final r in rows) r()],
            ),
          );

    final radius = BorderRadius.circular(24);
    return DragTarget<String>(
      onAcceptWithDetails: _drop,
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: candidates.isNotEmpty ? c.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: GlassPanel(blurred: matrixBoxesBlur, child: content),
      ),
    );
  }
}

