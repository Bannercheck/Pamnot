import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/quick_parse.dart';
import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/common/soft.dart';
import '../board_editor.dart';
import '../boards_controller.dart';
import '../connection.dart';
import '../model/board_item.dart';
import 'board_widgets.dart';
import 'card_face.dart';

/// The Kanban view of a board (docs/boards/DESIGN.md §9, ux_specs §5).
///
/// Phones page through the columns (one at a time, the next one peeking);
/// wider screens show 300 dp columns side by side. Every column listens to
/// the editor on its own and rebuilds only when its cards or its own item
/// changed, so a move rebuilds two columns, not the board. Drags run on
/// value notifiers (insertion line) and a ticker (edge auto-scroll): no
/// widget rebuilds while a card is in the air.
class KanbanView extends StatefulWidget {
  const KanbanView({super.key, required this.board, required this.onOpenCard, required this.onShowCanvas});

  final OpenBoard board;
  final void Function(String cardId) onOpenCard;
  final VoidCallback onShowCanvas;

  @override
  State<KanbanView> createState() => _KanbanViewState();
}

/// What the view itself depends on; columns handle the rest.
typedef _Shape = ({String columns, int canvas, bool readOnly, bool shared});

_Shape _shapeOf(BoardEditor e) => (
  columns: e.columns.map((c) => c.id).join('\n'),
  canvas: e.canvasItems.length,
  readOnly: e.readOnly,
  shared: e.doc.isShared,
);

class _KanbanViewState extends State<KanbanView> with SingleTickerProviderStateMixin {
  BoardEditor get _e => widget.board.editor;
  late _Shape _shape = _shapeOf(_e);
  late final _drag = _KanbanDrag(this);
  final _page = ValueNotifier(0);
  final _hScroll = ScrollController();
  final _viewportKey = GlobalKey();
  PageController? _pages;
  bool _phone = false;

  BoardConnection? _connection;
  Map<String, Peer> _peers = const {};

  List<String> get _columnIds => _shape.columns.isEmpty ? const [] : _shape.columns.split('\n');

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _listenPeers();
  }

  @override
  void didUpdateWidget(KanbanView old) {
    super.didUpdateWidget(old);
    if (old.board != widget.board) {
      old.board.editor.removeListener(_onEditor);
      _e.addListener(_onEditor);
      _shape = _shapeOf(_e);
      _listenPeers();
    }
  }

  @override
  void dispose() {
    _e.removeListener(_onEditor);
    _connection?.peers.removeListener(_onPeers);
    _drag.dispose();
    _page.dispose();
    _hScroll.dispose();
    _pages?.dispose();
    super.dispose();
  }

  void _onEditor() {
    if (!identical(_connection, widget.board.connection)) _listenPeers();
    final next = _shapeOf(_e);
    if (next == _shape) return;
    setState(() => _shape = next);
    // Columns came or went: the dots follow the page actually shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = _pages;
      if (mounted && p != null && p.hasClients && p.page != null) _page.value = p.page!.round();
    });
  }

  /// Assignee names come from presence (members are not stored offline).
  void _listenPeers() {
    _connection?.peers.removeListener(_onPeers);
    _connection = widget.board.connection;
    _connection!.peers.addListener(_onPeers);
    _peers = _peerMap();
  }

  Map<String, Peer> _peerMap() => {for (final p in widget.board.connection.peers.value) p.userId: p};

  void _onPeers() {
    if (!_shape.shared) return;
    // Cards only show names and colours; editing and view changes are not
    // worth a rebuild.
    Map<String, (String, int)> look(Map<String, Peer> m) => m.map((k, v) => MapEntry(k, (v.name, v.colorIndex)));
    final next = _peerMap();
    if (!mapEquals(look(next), look(_peers))) setState(() => _peers = next);
  }

  CardAssignee? assigneeOf(BoardItem card, S s) {
    if (!_shape.shared) return null;
    final id = card.assigneeId;
    if (id == null) return null;
    final p = _peers[id];
    if (p != null) return CardAssignee(label: p.name, avatarName: p.name, colorIndex: p.colorIndex);
    if (id == AppScope.of(context).boards.currentAccount()?.userId) return CardAssignee(label: s.me);
    return CardAssignee(label: s.someone);
  }

  Rect? get viewportRect {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool get isPhone => _phone;

  // ---------------------------------------------------------------- moves

  /// Moves a card and, across columns, offers to undo it.
  void moveCard(String cardId, String toColumn, int index) {
    final card = _e.item(cardId);
    final target = _e.item(toColumn);
    if (card == null || target == null) return;
    final from = _e.columnOf(cardId);
    final before = _e.undoToken;
    _e.moveCard(cardId, columnId: toColumn, index: index);
    if (from != toColumn && !identical(before, _e.undoToken)) {
      final s = S.of(context);
      final title = card.title.trim().isEmpty ? s.untitled : card.title;
      showBoardUndo(ScaffoldMessenger.maybeOf(context), _e, s.movedTo(title, target.title), s);
    }
  }

  /// Moves a card to the end of the column [direction] steps away.
  void moveToNeighbour(String cardId, int direction) {
    final cols = _e.columns;
    final from = _e.columnOf(cardId);
    final i = cols.indexWhere((c) => c.id == from);
    final j = i + direction;
    if (i < 0 || j < 0 || j >= cols.length) return;
    moveCard(cardId, cols[j].id, _e.cardsIn(cols[j].id).length);
  }

  // -------------------------------------------------------------- columns

  Future<void> addColumn() async {
    final s = S.of(context);
    final title = await promptText(context, title: s.addColumn, hint: s.columnName, action: s.add);
    if (title == null || !mounted) return;
    final cols = _e.columns;
    final color = cols.isEmpty ? 3 : (cols.last.colorIndex + 1) % pastels.length;
    final id = _e.addColumn(title: title, colorIndex: color);
    followColumn(id);
  }

  /// On phones, turns to the page of [columnId] after the next layout.
  void followColumn(String columnId) {
    if (!_phone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _columnIds.indexOf(columnId);
      final p = _pages;
      if (i < 0 || p == null || !p.hasClients) return;
      unawaited(p.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic));
    });
  }

  Future<void> turnPage(int direction) async {
    final p = _pages;
    if (p == null || !p.hasClients) return;
    final count = _columnIds.length + (_shape.readOnly ? 0 : 1);
    final next = (_page.value + direction).clamp(0, math.max(0, count - 1)).toInt();
    if (next == _page.value) return;
    await p.animateToPage(next, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ids = _columnIds;
    // The page does not resize for the keyboard, so these constraints stay
    // put while it moves; only the inset padding below rebuilds.
    return LayoutBuilder(
      builder: (context, box) {
        _phone = box.maxWidth < 600;
        final Widget columns;
        if (ids.isEmpty) {
          columns = EmptyState(
            emoji: '🗂️',
            text: s.noColumns,
            action: _shape.readOnly
                ? null
                : FilledButton.tonalIcon(
                    onPressed: addColumn,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(s.addColumn),
                  ),
          );
        } else {
          // Built once per view rebuild: entering or leaving the target
          // rebuilds the target only, not the columns under it.
          final content = _phone ? _phoneColumns(ids) : _wideColumns(ids);
          columns = DragTarget<String>(
            onWillAcceptWithDetails: (d) => _e.item(d.data)?.kind == ItemKind.card,
            onMove: (d) => _drag.move(d.offset),
            onLeave: (_) => _drag.leave(),
            onAcceptWithDetails: (_) => _drag.drop(),
            builder: (context, _, _) => content,
          );
        }
        return _KeyboardInset(
          child: Column(
            children: [
              Expanded(
                child: KeyedSubtree(key: _viewportKey, child: columns),
              ),
              if (_phone && ids.isNotEmpty)
                _PageDots(count: ids.length + (_shape.readOnly ? 0 : 1), page: _page, onTap: _goToPage),
              if (_shape.canvas > 0) _CanvasFooter(count: _shape.canvas, onShow: widget.onShowCanvas),
            ],
          ),
        );
      },
    );
  }

  void _goToPage(int i) =>
      _pages?.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);

  Widget _column(String id) =>
      _ColumnView(key: ValueKey(id), kanban: this, columnId: id, readOnly: _shape.readOnly, peers: _peers);

  Widget _phoneColumns(List<String> ids) {
    final pages = _pages ??= PageController(viewportFraction: 0.86);
    final count = ids.length + (_shape.readOnly ? 0 : 1);
    return PageView.builder(
      controller: pages,
      padEnds: false,
      itemCount: count,
      onPageChanged: (i) => _page.value = i,
      findChildIndexCallback: (key) {
        final i = key is ValueKey<String> ? ids.indexOf(key.value) : -1;
        return i < 0 ? null : i;
      },
      itemBuilder: (context, i) => Padding(
        key: i < ids.length ? ValueKey(ids[i]) : const ValueKey('ghost'),
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 8),
        child: i < ids.length ? _column(ids[i]) : _GhostColumn(onTap: addColumn),
      ),
    );
  }

  Widget _wideColumns(List<String> ids) {
    final count = ids.length + (_shape.readOnly ? 0 : 1);
    return Scrollbar(
      controller: _hScroll,
      child: ListView.separated(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        findItemIndexCallback: (key) {
          final i = key is ValueKey<String> ? ids.indexOf(key.value) : -1;
          return i < 0 ? null : i;
        },
        itemBuilder: (context, i) => SizedBox(
          key: i < ids.length ? ValueKey(ids[i]) : const ValueKey('ghost'),
          width: 300,
          child: i < ids.length ? _column(ids[i]) : _GhostColumn(onTap: addColumn),
        ),
      ),
    );
  }

  /// Horizontal auto-scroll of the wide layout; returns whether it moved.
  bool scrollHorizontally(double delta) {
    if (!_hScroll.hasClients) return false;
    final p = _hScroll.position;
    final to = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to == p.pixels) return false;
    p.jumpTo(to);
    return true;
  }
}

/// Keeps the columns above the keyboard (the board page does not resize,
/// for the canvas). Only this padding rebuilds while the keyboard moves;
/// its child is the same widget, so the columns just lay out again.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}

// ------------------------------------------------------------------ drag

/// Where a dragged card would land: before [beforeId] (or at the end) of a
/// column; [index] counts the column's cards without the dragged one.
@immutable
class _Slot {
  const _Slot(this.columnId, this.index, this.beforeId);

  final String columnId;
  final int index;
  final String? beforeId;

  @override
  bool operator ==(Object other) =>
      other is _Slot && other.columnId == columnId && other.index == index && other.beforeId == beforeId;

  @override
  int get hashCode => Object.hash(columnId, index, beforeId);
}

/// One card drag across the view. Positions come from the view-wide drag
/// target (so a source card scrolled out of view does not end the drag);
/// the insertion line is a notifier, auto-scroll a ticker.
class _KanbanDrag {
  _KanbanDrag(this.view);

  final _KanbanViewState view;

  String? cardId;
  Offset _anchor = Offset.zero;
  double feedbackWidth = 276;
  Offset? _pointer;
  final slot = ValueNotifier<_Slot?>(null);
  final Map<String, _ColumnViewState> columns = {};

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _vx = 0, _vy = 0;
  _ColumnViewState? _scrollColumn;
  Timer? _edgeTimer;
  int _edgeDir = 0;

  static const _edgeZone = 48.0;
  static const _pageZone = 28.0;
  static const _maxSpeed = 900.0;

  /// Starts the drag: keeps the grab point under the finger and the card
  /// width for the feedback. Runs before the drag avatar exists, so the
  /// first position it reports already belongs to this drag.
  Offset anchor(Draggable<Object> d, BuildContext context, Offset position) {
    final a = childDragAnchorStrategy(d, context, position);
    _anchor = a;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) feedbackWidth = box.size.width;
    cardId = d.data as String?;
    _pointer = null;
    slot.value = null;
    return a;
  }

  /// [feedbackTopLeft] is where the drag target saw the feedback.
  void move(Offset feedbackTopLeft) {
    if (cardId == null) return;
    _pointer = feedbackTopLeft + _anchor;
    _locate();
    _autoScroll();
  }

  void leave() {
    _pointer = null;
    slot.value = null;
    _stopAutoScroll();
  }

  void drop() {
    final s = slot.value, id = cardId;
    _reset();
    if (s != null && id != null) view.moveCard(id, s.columnId, s.index);
  }

  /// The source card reports the end of its drag (after [drop], if any).
  void end() => _reset();

  void _reset() {
    cardId = null;
    _pointer = null;
    slot.value = null;
    _stopAutoScroll();
  }

  void _locate() {
    final p = _pointer, id = cardId;
    if (p == null || id == null) return;
    _ColumnViewState? best;
    var bestDistance = double.infinity;
    for (final c in columns.values) {
      final r = c.globalRect;
      if (r == null) continue;
      final dx = p.dx < r.left ? r.left - p.dx : (p.dx > r.right ? p.dx - r.right : 0.0);
      if (dx < bestDistance) {
        best = c;
        bestDistance = dx;
      }
    }
    // Between two columns, the nearer one takes the card.
    _scrollColumn = best;
    slot.value = best?.slotAt(p, id);
  }

  void _autoScroll() {
    final p = _pointer;
    final viewport = view.viewportRect;
    if (p == null || viewport == null) return _stopAutoScroll();
    final list = _scrollColumn?.listRect;
    _vy = list == null || !list.inflate(_edgeZone).contains(p) ? 0 : _speed(p.dy, list.top, list.bottom);
    if (view.isPhone) {
      _vx = 0;
      _edgePaging(p, viewport);
    } else {
      _vx = _speed(p.dx, viewport.left, viewport.right);
    }
    if (_vx == 0 && _vy == 0) {
      _ticker?.stop();
      return;
    }
    final t = _ticker ??= view.createTicker(_tick);
    if (!t.isActive) {
      _lastTick = Duration.zero;
      t.start();
    }
  }

  static double _speed(double v, double start, double end) {
    if (v < start + _edgeZone) return -_maxSpeed * ((start + _edgeZone - v) / _edgeZone).clamp(0.0, 1.0);
    if (v > end - _edgeZone) return _maxSpeed * ((v - end + _edgeZone) / _edgeZone).clamp(0.0, 1.0);
    return 0;
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    var moved = false;
    if (_vy != 0) moved |= _scrollColumn?.scrollBy(_vy * dt) ?? false;
    if (_vx != 0) moved |= view.scrollHorizontally(_vx * dt);
    if (moved) {
      _locate();
    } else {
      _ticker?.stop();
    }
  }

  /// Phones: holding a card at a side edge turns to the neighbouring column.
  void _edgePaging(Offset p, Rect viewport) {
    final dir = p.dx < viewport.left + _pageZone ? -1 : (p.dx > viewport.right - _pageZone ? 1 : 0);
    if (dir == _edgeDir) return;
    _edgeDir = dir;
    _edgeTimer?.cancel();
    if (dir != 0) _edgeTimer = Timer(const Duration(milliseconds: 500), _page);
  }

  void _page() {
    if (_edgeDir == 0 || cardId == null) return;
    unawaited(view.turnPage(_edgeDir).then((_) => _locate()));
    _edgeTimer = Timer(const Duration(milliseconds: 900), _page);
  }

  void _stopAutoScroll() {
    _vx = _vy = 0;
    _ticker?.stop();
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeDir = 0;
  }

  void dispose() {
    _edgeTimer?.cancel();
    _ticker?.dispose();
    slot.dispose();
  }
}

/// A [Draggable] that starts after a 300 ms hold for touch and stylus (with
/// a haptic tick), or right away for a mouse; nest one of each.
class _CardDraggable extends Draggable<String> {
  const _CardDraggable({
    required this.touch,
    required super.child,
    required super.feedback,
    required super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragEnd,
  }) : super(maxSimultaneousDrags: 1);

  final bool touch;

  static const _touchKinds = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) {
    if (!touch) {
      return ImmediateMultiDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.mouse})..onStart = onStart;
    }
    return DelayedMultiDragGestureRecognizer(delay: const Duration(milliseconds: 300), supportedDevices: _touchKinds)
      ..onStart = (position) {
        final drag = onStart(position);
        if (drag != null) unawaited(HapticFeedback.selectionClick());
        return drag;
      };
  }
}

// --------------------------------------------------------------- columns

enum _ColumnAction { rename, color, done, left, right, delete }

class _ColumnView extends StatefulWidget {
  const _ColumnView({
    super.key,
    required this.kanban,
    required this.columnId,
    required this.readOnly,
    required this.peers,
  });

  final _KanbanViewState kanban;
  final String columnId;
  final bool readOnly;

  /// Changes when presence names change, so assignee avatars refresh.
  final Map<String, Peer> peers;

  @override
  State<_ColumnView> createState() => _ColumnViewState();
}

class _ColumnViewState extends State<_ColumnView> {
  BoardEditor get _e => widget.kanban._e;
  _KanbanDrag get _drag => widget.kanban._drag;
  String get columnId => widget.columnId;

  late BoardItem _column = _e.item(columnId)!;
  late List<BoardItem> _cards = _e.cardsIn(columnId);
  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  /// Built card items, for drop positions.
  final Map<String, _CardItemState> items = {};
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _e.addListener(_onEditor);
    _drag.columns[columnId] = this;
  }

  @override
  void dispose() {
    _e.removeListener(_onEditor);
    if (identical(_drag.columns[columnId], this)) _drag.columns.remove(columnId);
    _scroll.dispose();
    super.dispose();
  }

  void _onEditor() {
    final col = _e.item(columnId);
    if (col == null || col.deleted) return; // the view drops this column
    final changed = _e.lastChanged;
    final cards = _e.cardsIn(columnId);
    final rebuild =
        changed.isEmpty ||
        changed.contains(columnId) ||
        cards.length != _cards.length ||
        !_sameIds(cards, _cards) ||
        cards.any((c) => changed.contains(c.id));
    if (rebuild) {
      setState(() {
        _column = col;
        _cards = cards;
      });
    }
  }

  static bool _sameIds(List<BoardItem> a, List<BoardItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Rect? get globalRect {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? get listRect {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool scrollBy(double delta) {
    if (!_scroll.hasClients) return false;
    final p = _scroll.position;
    final to = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to == p.pixels) return false;
    p.jumpTo(to);
    return true;
  }

  /// The insertion point for [p] among the built cards, ignoring [dragId].
  _Slot slotAt(Offset p, String dragId) {
    final others = [
      for (final c in _cards)
        if (c.id != dragId) c,
    ];
    int? lastBuilt;
    for (var i = 0; i < others.length; i++) {
      final box = items[others[i].id]?.context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (p.dy < top + box.size.height / 2) return _Slot(columnId, i, others[i].id);
      lastBuilt = i;
    }
    final i = lastBuilt == null ? others.length : lastBuilt + 1;
    return _Slot(columnId, i, i < others.length ? others[i].id : null);
  }

  // ---------------------------------------------------------------- edits

  void _addCard(String text) {
    final app = AppScope.of(context);
    final r = quickParse(text, app.now());
    final title = r.title.trim();
    if (title.isEmpty) return;
    _e.addCard(columnId: columnId, title: title, due: r.due == null ? null : dueKey(r.due!));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  Future<void> _onMenu(_ColumnAction a) async {
    final s = S.of(context);
    switch (a) {
      case _ColumnAction.rename:
        final title = await promptText(context, title: s.rename, initial: _column.title, hint: s.columnName);
        if (title != null) _e.updateColumn(columnId, title: title);
      case _ColumnAction.color:
        final i = await pickPastel(context, selected: _column.colorIndex);
        if (i != null) _e.updateColumn(columnId, colorIndex: i);
      case _ColumnAction.done:
        _e.updateColumn(columnId, isDone: !_column.isDone);
      case _ColumnAction.left:
        _e.moveColumn(columnId, -1);
        widget.kanban.followColumn(columnId);
      case _ColumnAction.right:
        _e.moveColumn(columnId, 1);
        widget.kanban.followColumn(columnId);
      case _ColumnAction.delete:
        await _delete();
    }
  }

  Future<void> _delete() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final cols = _e.columns;
    final i = cols.indexWhere((c) => c.id == columnId);
    if (i < 0) return;
    final n = _cards.length;
    var deleteCards = false;
    if (n > 0) {
      // Same neighbour rule as BoardEditor.deleteColumn.
      final target = cols.length > 1 ? cols[i == 0 ? 1 : i - 1] : null;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.deleteColumn),
          content: Text(target == null ? s.cardsWillBeDeleted(n) : s.cardsWillMove(n, target.title)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(target == null ? s.deleteCardsToo : s.deleteColumn),
            ),
          ],
        ),
      );
      if (ok != true) return;
      deleteCards = target == null;
    }
    _e.deleteColumn(columnId, deleteCards: deleteCards);
    showBoardUndo(messenger, _e, s.deleted, s);
  }

  Map<CustomSemanticsAction, VoidCallback> _actions(S s, int index, int columnIndex, int columnCount) {
    final id = _cards[index].id;
    return {
      if (columnIndex + 1 < columnCount)
        CustomSemanticsAction(label: s.moveToNextColumn): () => widget.kanban.moveToNeighbour(id, 1),
      if (columnIndex > 0)
        CustomSemanticsAction(label: s.moveToPreviousColumn): () => widget.kanban.moveToNeighbour(id, -1),
      if (index > 0)
        CustomSemanticsAction(label: s.moveUp): () => _e.moveCard(id, columnId: columnId, index: index - 1),
      if (index + 1 < _cards.length)
        CustomSemanticsAction(label: s.moveDown): () => _e.moveCard(id, columnId: columnId, index: index + 1),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final now = AppScope.of(context).now();
    final cols = _e.columns;
    final columnIndex = cols.indexWhere((x) => x.id == columnId);
    final readOnly = widget.readOnly;
    final title = _column.title.trim().isEmpty ? s.untitled : _column.title;

    return Container(
      decoration: BoxDecoration(color: c.surfaceContainer, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, readOnly ? 16 : 4, 0),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  PastelDot(_column.colorIndex, size: 12),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                  ),
                  Text('  · ${_cards.length}', style: t.textTheme.titleSmall?.copyWith(color: c.onSurfaceVariant)),
                  if (_column.isDone) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_circle_outline_rounded, size: 16, color: c.tertiary, semanticLabel: s.doneColumn),
                  ],
                  const Spacer(),
                  if (!readOnly) _menu(s),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: _listKey,
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              itemCount: _cards.length + 1,
              itemBuilder: (context, i) {
                if (i == _cards.length) return _EndSlot(columnId: columnId, slot: _drag.slot);
                final card = _cards[i];
                return _CardItem(
                  key: ValueKey(card.id),
                  column: this,
                  card: card,
                  face: CardFace(
                    card: card,
                    columnTitle: title,
                    now: now,
                    done: _column.isDone,
                    assignee: widget.kanban.assigneeOf(card, s),
                    onTap: () => widget.kanban.widget.onOpenCard(card.id),
                    actions: readOnly ? const {} : _actions(s, i, columnIndex, cols.length),
                  ),
                  readOnly: readOnly,
                  index: i,
                  columnIndex: columnIndex,
                  columnCount: cols.length,
                );
              },
            ),
          ),
          if (!readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _adding
                  ? _AddCardField(onSubmit: _addCard, onClose: () => setState(() => _adding = false))
                  : SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: c.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onPressed: () => setState(() => _adding = true),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: Text(s.addCard),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _menu(S s) {
    final t = Theme.of(context);
    PopupMenuItem<_ColumnAction> item(_ColumnAction a, IconData icon, String label, {bool enabled = true}) =>
        PopupMenuItem(
          value: a,
          enabled: enabled,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Flexible(child: Text(label)),
            ],
          ),
        );
    return PopupMenuButton<_ColumnAction>(
      tooltip: s.column,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (a) => unawaited(_onMenu(a)),
      itemBuilder: (_) {
        // Read at open time: a neighbour may have moved since the build.
        final cols = _e.columns;
        final columnIndex = cols.indexWhere((x) => x.id == columnId);
        return [
          item(_ColumnAction.rename, Icons.edit_outlined, s.rename),
          item(_ColumnAction.color, Icons.palette_outlined, s.color),
          PopupMenuItem(
            value: _ColumnAction.done,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.doneColumn),
                      Text(
                        s.doneColumnSub,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The whole row toggles; the switch only shows the state.
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Switch(value: _column.isDone, onChanged: (_) {}),
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          item(_ColumnAction.left, Icons.arrow_back_rounded, s.moveLeft, enabled: columnIndex > 0),
          item(_ColumnAction.right, Icons.arrow_forward_rounded, s.moveRight, enabled: columnIndex + 1 < cols.length),
          const PopupMenuDivider(),
          item(_ColumnAction.delete, Icons.delete_outline_rounded, s.deleteColumn),
        ];
      },
    );
  }
}

/// One card in a column: the face, its drag handles and the insertion
/// line drawn in the gap above it.
class _CardItem extends StatefulWidget {
  const _CardItem({
    super.key,
    required this.column,
    required this.card,
    required this.face,
    required this.readOnly,
    required this.index,
    required this.columnIndex,
    required this.columnCount,
  });

  final _ColumnViewState column;
  final BoardItem card;
  final CardFace face;
  final bool readOnly;
  final int index;
  final int columnIndex;
  final int columnCount;

  @override
  State<_CardItem> createState() => _CardItemState();
}

class _CardItemState extends State<_CardItem> {
  @override
  void initState() {
    super.initState();
    widget.column.items[widget.card.id] = this;
  }

  @override
  void didUpdateWidget(_CardItem old) {
    super.didUpdateWidget(old);
    if (old.card.id != widget.card.id || old.column != widget.column) {
      if (identical(old.column.items[old.card.id], this)) old.column.items.remove(old.card.id);
      widget.column.items[widget.card.id] = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.column.items[widget.card.id], this)) widget.column.items.remove(widget.card.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final column = widget.column;
    final drag = column._drag;
    final id = widget.card.id;
    Widget card = widget.face;
    if (!widget.readOnly) {
      final kanban = column.widget.kanban;
      final mod = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
      SingleActivator key(LogicalKeyboardKey k) => SingleActivator(k, meta: mod, control: !mod);
      final i = widget.index, ci = widget.columnIndex;
      card = CallbackShortcuts(
        bindings: {
          if (ci + 1 < widget.columnCount) key(LogicalKeyboardKey.arrowRight): () => kanban.moveToNeighbour(id, 1),
          if (ci > 0) key(LogicalKeyboardKey.arrowLeft): () => kanban.moveToNeighbour(id, -1),
          if (i > 0)
            key(LogicalKeyboardKey.arrowUp): () => kanban._e.moveCard(id, columnId: column.columnId, index: i - 1),
          if (i + 1 < column._cards.length)
            key(LogicalKeyboardKey.arrowDown): () => kanban._e.moveCard(id, columnId: column.columnId, index: i + 1),
        },
        child: card,
      );
      final feedback = _DragFeedback(drag: drag, child: widget.face.asFeedback());
      final placeholder = Opacity(opacity: 0.35, child: widget.face);
      _CardDraggable draggable(bool touch, Widget child) => _CardDraggable(
        touch: touch,
        data: id,
        feedback: feedback,
        childWhenDragging: placeholder,
        dragAnchorStrategy: drag.anchor,
        onDragEnd: (_) => drag.end(),
        child: child,
      );
      card = draggable(true, draggable(false, card));
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(top: 10), child: card),
        Positioned(
          top: 3.5,
          left: 2,
          right: 2,
          child: _DropLine(slot: drag.slot, columnId: column.columnId, beforeId: id),
        ),
      ],
    );
  }
}

/// The space after the last card, where a drop appends.
class _EndSlot extends StatelessWidget {
  const _EndSlot({required this.columnId, required this.slot});

  final String columnId;
  final ValueListenable<_Slot?> slot;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Stack(
      children: [
        Positioned(
          top: 3.5,
          left: 2,
          right: 2,
          child: _DropLine(slot: slot, columnId: columnId, beforeId: null),
        ),
      ],
    ),
  );
}

class _DropLine extends StatelessWidget {
  const _DropLine({required this.slot, required this.columnId, required this.beforeId});

  final ValueListenable<_Slot?> slot;
  final String columnId;
  final String? beforeId;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<_Slot?>(
      valueListenable: slot,
      builder: (context, s, _) {
        final on = s != null && s.columnId == columnId && s.beforeId == beforeId;
        return SizedBox(
          height: 3,
          child: on
              ? DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                )
              : null,
        );
      },
    );
  }
}

/// The lifted card: tilted 2°, raised, as wide as the original.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.drag, required this.child});

  final _KanbanDrag drag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: 2 * math.pi / 180,
    child: SizedBox(width: drag.feedbackWidth, child: child),
  );
}

/// "+ Kart ekle": Enter adds the card (quickParse reads a due date) and
/// keeps the field open; Esc or leaving the field closes it.
class _AddCardField extends StatefulWidget {
  const _AddCardField({required this.onSubmit, required this.onClose});

  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;

  @override
  State<_AddCardField> createState() => _AddCardFieldState();
}

class _AddCardFieldState extends State<_AddCardField> {
  final _c = TextEditingController();
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
  }

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_f.hasFocus) widget.onClose();
  }

  void _submit() {
    final text = _c.text.trim();
    if (text.isNotEmpty) widget.onSubmit(text);
    _c.clear();
    _f.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _f.unfocus()},
      child: TextField(
        controller: _c,
        focusNode: _f,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        // Keep the keyboard up for the next card.
        onEditingComplete: () {},
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: s.taskTitleHint,
          isDense: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          suffixIcon: IconButton(tooltip: s.addCard, icon: const Icon(Icons.arrow_upward_rounded), onPressed: _submit),
        ),
      ),
    );
  }
}

/// "+ Sütun ekle" at the end of the columns.
class _GhostColumn extends StatelessWidget {
  const _GhostColumn({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: c.outline, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(Icons.add_rounded, color: c.onSurfaceVariant),
                const SizedBox(width: 10),
                Text(s.addColumn, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page, required this.onTap});

  final int count;
  final ValueListenable<int> page;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (context, page, _) {
          final p = page.clamp(0, count - 1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++)
                  GestureDetector(
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                      width: i == p ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == p ? c.primary : c.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Stickies and ink live on the canvas only; Kanban says so quietly.
class _CanvasFooter extends StatelessWidget {
  const _CanvasFooter({required this.count, required this.onShow});

  final int count;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
        child: Row(
          children: [
            Icon(Icons.gesture_rounded, size: 18, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.canvasItemsNote(count),
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: onShow, child: Text(s.showOnCanvas)),
          ],
        ),
      ),
    );
  }
}
