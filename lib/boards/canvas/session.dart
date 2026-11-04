import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/notes/ink/ink_painter.dart';
import '../board_editor.dart';
import '../boards_controller.dart';
import '../connection.dart';
import '../model/board_item.dart';
import 'board_text.dart';
import 'canvas_strings.dart';
import 'ink_layer.dart';
import 'presence.dart';
import 'scene.dart';
import 'viewport.dart';

enum BoardTool { select, pen, highlighter, eraser }

extension BoardToolX on BoardTool {
  bool get inks => this == BoardTool.pen || this == BoardTool.highlighter;
  bool get erases => this == BoardTool.eraser;
}

@immutable
class InkSettings {
  const InkSettings({this.penColor = 0xFF3E3A4A, this.highlighterColor = 0xFFFFE27A, this.penWidth = 4});

  final int penColor;
  final int highlighterColor;

  /// On-screen width at pen-down; stored in canvas units as width / scale.
  final double penWidth;

  static const highlighterWidth = 22.0;
  static const widths = [2.5, 4.0, 7.0];

  InkSettings copyWith({int? penColor, int? highlighterColor, double? penWidth}) => InkSettings(
    penColor: penColor ?? this.penColor,
    highlighterColor: highlighterColor ?? this.highlighterColor,
    penWidth: penWidth ?? this.penWidth,
  );

  @override
  bool operator ==(Object other) =>
      other is InkSettings &&
      other.penColor == penColor &&
      other.highlighterColor == highlighterColor &&
      other.penWidth == penWidth;

  @override
  int get hashCode => Object.hash(penColor, highlighterColor, penWidth);
}

/// Items drawn by the lifted layer instead of the world: dragged items (or
/// the whole lane block), the sticky being edited, and strokes erased but
/// not yet committed. Only membership changes invalidate the world's cached
/// pictures; moving the delta repaints the lifted layer alone.
class LiftedSet extends ChangeNotifier {
  Set<String> _ids = const {};
  Set<String> _hidden = const {};
  bool _lanes = false;
  String? _editing;
  Offset _delta = Offset.zero;
  bool _raised = true;
  int _rev = 0;

  Set<String> get ids => _ids;
  Set<String> get hidden => _hidden;

  /// The whole lane block (lanes and cards) is lifted.
  bool get lanes => _lanes;
  String? get editing => _editing;
  Offset get delta => _delta;

  /// Drawn with the raised look (false while settling back into place).
  bool get raised => _raised;
  int get membershipRevision => _rev;
  bool get isEmpty => _ids.isEmpty && !_lanes && _editing == null;

  bool contains(String id) => _ids.contains(id) || id == _editing;

  /// Whether the world skips [id].
  bool hides(String id) => _ids.contains(id) || id == _editing || _hidden.contains(id);

  void lift(Set<String> ids, {bool lanes = false}) {
    _ids = Set.unmodifiable(ids);
    _lanes = lanes;
    _delta = Offset.zero;
    _raised = true;
    _rev++;
    notifyListeners();
  }

  void move(Offset delta) {
    if (delta == _delta) return;
    _delta = delta;
    notifyListeners();
  }

  set raised(bool v) {
    if (v == _raised) return;
    _raised = v;
    _rev++;
    notifyListeners();
  }

  void drop() {
    if (_ids.isEmpty && !_lanes) return;
    _ids = const {};
    _lanes = false;
    _delta = Offset.zero;
    _raised = true;
    _rev++;
    notifyListeners();
  }

  void edit(String? id) {
    if (id == _editing) return;
    _editing = id;
    _rev++;
    notifyListeners();
  }

  void hide(Iterable<String> ids) {
    final next = {..._hidden, ...ids};
    if (next.length == _hidden.length) return;
    _hidden = next;
    _rev++;
    notifyListeners();
  }

  void unhideAll() {
    if (_hidden.isEmpty) return;
    _hidden = const {};
    _rev++;
    notifyListeners();
  }
}

/// Where a dragged card would land: its lane and the insertion line.
@immutable
class DropIndicator {
  const DropIndicator(this.columnId, this.y);

  final String columnId;
  final double y;

  @override
  bool operator ==(Object other) => other is DropIndicator && other.columnId == columnId && other.y == y;

  @override
  int get hashCode => Object.hash(columnId, y);
}

/// What the canvas needs from the widget around it (context, sheets, snacks).
abstract class BoardCanvasHost {
  /// Wide screens edit stickies in place; phones use a sheet.
  bool get inlineEditing;
  bool get stylusOnly;

  /// Screen insets covered by toolbars, for fitting and revealing.
  EdgeInsets get chromeInsets;
  S get strings;

  Future<String?> editStickyInSheet(String stickyId, String text);
  void openCard(String cardId);
  void showSnack(String text, {VoidCallback? undo});
  void showItemMenu(Offset screen);
  void renameColumn(String columnId);
  void stylusDetected();
  void viewChanged();
}

/// Everything one open canvas holds, kept outside AppScope: separate
/// notifiers for the viewport, scene, lifted set, selection, hover, tool and
/// presence, so each painter repaints on exactly what it draws and no widget
/// rebuilds while panning, zooming, dragging or drawing.
class BoardSession {
  BoardSession({
    required this.board,
    required this.vsync,
    required this.host,
    DateTime Function()? now,
    Color textColor = const Color(0xFF3E3A4A),
    Color mutedColor = const Color(0xFF7A7488),
  }) : now = now ?? DateTime.now {
    scene = BoardScene(editor, text: text, placeholder: host.strings.untitled)
      ..textColor = textColor
      ..mutedColor = mutedColor
      ..rebuild();
    presence = PresenceModel(vsync: vsync, viewport: viewport);
    _bind(board.connection);
    editor.addListener(_onEditor);
    viewport.contentBounds = scene.contentBounds;
    _count();
    _fling = vsync.createTicker(_onFling);
    _view = vsync.createTicker(_onViewAnim);
    _settle = vsync.createTicker(_onSettle);
  }

  final OpenBoard board;
  final TickerProvider vsync;
  final BoardCanvasHost host;
  final DateTime Function() now;

  BoardEditor get editor => board.editor;
  BoardConnection get connection => board.connection;
  BoardConnection? _connection;

  /// Teammates on the board, mirrored from the current connection (the
  /// controller swaps and closes connections on sign-in changes, so
  /// painters never listen to a connection directly).
  final peers = ValueNotifier<List<Peer>>(const []);

  void _bind(BoardConnection c) {
    // Removing a listener from a closed connection's notifier is allowed.
    _connection?.peers.removeListener(_onPeers);
    _connection = c;
    c.peers.addListener(_onPeers);
    _onPeers();
    presence.attach(c);
  }

  void _onPeers() => peers.value = _connection?.peers.value ?? const [];

  final viewport = BoardViewport();
  final text = BoardTextCache();
  final outlines = InkOutlines();
  late final BoardScene scene;
  final lifted = LiftedSet();
  final selection = ValueNotifier<Set<String>>(const {});
  final hover = ValueNotifier<String?>(null);

  /// Marquee in canvas units.
  final marquee = ValueNotifier<Rect?>(null);
  final drop = ValueNotifier<DropIndicator?>(null);
  final tool = ValueNotifier(BoardTool.select);
  final ink = ValueNotifier(const InkSettings());
  final activeInk = ActiveInk();

  /// The sticky being edited in place.
  final editing = ValueNotifier<String?>(null);

  /// A gesture is in progress (the selection toolbar hides meanwhile).
  final interacting = ValueNotifier(false);
  final cursor = ValueNotifier<MouseCursor>(SystemMouseCursors.basic);

  /// Screen position of the eraser ring for a hovering mouse or stylus.
  final eraserRing = ValueNotifier<Offset?>(null);

  /// Cards, stickies and ink (the semantics label), and columns (the Kart
  /// button and the empty hint): widgets rebuild only when these change.
  final itemCount = ValueNotifier(0);
  final columnCount = ValueNotifier(0);

  void _count() {
    itemCount.value = scene.itemCount;
    columnCount.value = scene.lanes.lanes.length;
  }

  late final PresenceModel presence;
  final keyboardFocus = FocusNode(debugLabel: 'Board canvas');

  /// MediaQuery.disableAnimations.
  bool reduceMotion = false;
  int stickyColor = 5;
  bool _disposed = false;

  /// Shown once per app run.
  static bool cardsHintShown = false;

  bool get readOnly => editor.readOnly;
  bool get isEditing => editing.value != null;

  void _onEditor() {
    if (!identical(board.connection, _connection)) _bind(board.connection);
    scene.sync();
    viewport.contentBounds = scene.contentBounds;
    updateMinScale();
    _count();
    // Drop selections of items that are gone (deleted here or by a teammate).
    final sel = selection.value;
    if (sel.isNotEmpty && sel.any((id) => scene.byId(id) == null)) {
      selection.value = {
        for (final id in sel)
          if (scene.byId(id) != null) id,
      };
    }
    final e = editing.value;
    if (e != null && scene.byId(e) == null) {
      editing.value = null;
      lifted.edit(null);
    }
  }

  /// The smallest zoom follows the board: 80 % of the scale that fits it.
  void updateMinScale() {
    final c = scene.contentBounds;
    final size = viewport.size;
    if (c.isEmpty || size.isEmpty) return;
    viewport.setFitScale(math.min(size.width / c.width, size.height / c.height));
  }

  /// Whether the last pointer anywhere on the canvas (toolbars included)
  /// was a finger: in-place editing zooms further for fingers.
  bool lastTouch = false;

  // ------------------------------------------------------------ selection

  void select(Set<String> ids) {
    if (setEquals(ids, selection.value)) return;
    selection.value = Set.unmodifiable(ids);
  }

  void clearSelection() => select(const {});

  /// Stickies and ink among [ids] (cards move only through lanes).
  Set<String> freeOf(Iterable<String> ids) => {
    for (final id in ids)
      if (scene.byId(id)?.kind case ItemKind.sticky || ItemKind.ink) id,
  };

  String? get firstOpenColumn {
    final cols = editor.columns;
    if (cols.isEmpty) return null;
    return cols.firstWhere((c) => !c.isDone, orElse: () => cols.first).id;
  }

  // --------------------------------------------------------------- actions

  void setTool(BoardTool t) {
    if (readOnly && t != BoardTool.select) return;
    tool.value = t;
    if (!t.erases) eraserRing.value = null;
  }

  /// Creates a sticky centred at [canvasPoint] and opens its editor.
  String? addStickyAt(Offset canvasPoint, {bool? touch}) {
    if (readOnly) return null;
    final id = editor.addSticky(
      at: canvasPoint - const Offset(StickyMetrics.size / 2, StickyMetrics.size / 2),
      colorIndex: stickyColor,
    );
    select({id});
    unawaited(beginEdit(id, touch: touch));
    return id;
  }

  /// Toolbar / N: a sticky in the middle of the view, nudged off any
  /// sticky already sitting exactly there.
  String? addStickyAtCenter({bool? touch}) {
    if (readOnly) return null;
    setTool(BoardTool.select);
    final insets = host.chromeInsets;
    final size = viewport.size;
    final centre = viewport.toCanvas(
      Offset(insets.left + (size.width - insets.horizontal) / 2, insets.top + (size.height - insets.vertical) / 2),
    );
    var at = centre - const Offset(StickyMetrics.size / 2, StickyMetrics.size / 2);
    for (var i = 0; i < 20; i++) {
      final taken = scene.free.any((s) => s.kind == ItemKind.sticky && (s.bounds.topLeft - at).distance < 4);
      if (!taken) break;
      at += const Offset(24, 24);
    }
    final id = editor.addSticky(at: at, colorIndex: stickyColor);
    select({id});
    unawaited(beginEdit(id, touch: touch));
    return id;
  }

  /// Toolbar / K: a card at the end of the first open column.
  String? addCard() {
    final col = firstOpenColumn;
    if (readOnly || col == null) return null;
    setTool(BoardTool.select);
    final id = editor.addCard(columnId: col, title: '');
    select({id});
    final r = scene.byId(id)?.bounds;
    if (r != null) reveal(r);
    host.openCard(id);
    return id;
  }

  void deleteSelection() {
    final ids = selection.value;
    if (readOnly || ids.isEmpty) return;
    clearSelection();
    editor.deleteItems(ids);
  }

  void duplicateSelection() {
    final ids = freeOf(selection.value);
    if (readOnly || ids.isEmpty) return;
    final copies = editor.duplicate(ids);
    select(copies.toSet());
  }

  void bringToFront() {
    final ids = freeOf(selection.value);
    if (!readOnly && ids.isNotEmpty) editor.bringToFront(ids);
  }

  void sendToBack() {
    final ids = freeOf(selection.value);
    if (!readOnly && ids.isNotEmpty) editor.sendToBack(ids);
  }

  void setColor(int colorIndex) {
    final ids = {
      for (final id in selection.value)
        if (scene.byId(id)?.kind case ItemKind.sticky || ItemKind.card) id,
    };
    if (readOnly || ids.isEmpty) return;
    if (ids.any((id) => scene.byId(id)?.kind == ItemKind.sticky)) stickyColor = colorIndex;
    editor.setColorOf(ids, colorIndex);
  }

  /// "Karta dönüştür": into the first open column, one undo step.
  String? stickyToCard(String stickyId) {
    final col = firstOpenColumn;
    if (readOnly || col == null) return null;
    final id = editor.stickyToCard(stickyId, col);
    if (id != null) {
      select({id});
      final r = scene.byId(id)?.bounds;
      if (r != null) reveal(r);
    }
    return id;
  }

  void undo() => _report(editor.undo());

  void redo() => _report(editor.redo());

  void _report(UndoOutcome o) {
    if (o.skipped) host.showSnack(host.strings.canvasChangedElsewhere);
  }

  // --------------------------------------------------------------- editing

  /// Opens a sticky's editor: in place on wide screens (after zooming so
  /// the text is big enough to type into), in a sheet on phones.
  Future<void> beginEdit(String id, {bool? touch}) async {
    if (readOnly) return;
    final finger = touch ?? lastTouch;
    final si = scene.byId(id);
    if (si == null || si.kind != ItemKind.sticky) return;
    // Another sticky being edited keeps what was typed into it.
    if (editing.value != null && editing.value != id) commitEdit?.call();
    final gen = ++_editGen;
    select({id});
    connection.setActivity(view: 'canvas', editing: id);
    if (!host.inlineEditing) {
      final editor = this.editor;
      final text = await host.editStickyInSheet(id, si.item.text);
      // The board outlives this view: keep the text even if it closed.
      if (text != null) editor.updateSticky(id, text: text);
      if (!_disposed) connection.setActivity(view: 'canvas');
      return;
    }
    final f = si.fitText == si.item.text && si.fit > 0 ? si.fit : estimateStickyFont(si.item.text);
    final minPx = finger ? 16.0 : 13.0;
    final s = viewport.scale;
    final target = math.min(BoardViewport.maxScale, math.max(s, minPx / f));
    final screen = viewport.rectToScreen(si.bounds);
    final visible = _visibleScreenRect();
    if (target > s + 1e-6 || !visible.contains(screen.topLeft) || !visible.contains(screen.bottomRight)) {
      await animateTo(si.bounds.center, target);
      // Something else started meanwhile (another edit, the view closed).
      if (_disposed || gen != _editGen) return;
    }
    if (scene.byId(id) == null || readOnly) return;
    lifted.edit(id);
    editing.value = id;
  }

  int _editGen = 0;

  /// Ends an in-place edit; [text] null discards.
  void endEdit(String id, String? text, {bool refocus = true}) {
    if (editing.value != id) return;
    if (text != null) editor.updateSticky(id, text: text);
    lifted.edit(null);
    editing.value = null;
    connection.setActivity(view: 'canvas');
    if (refocus && keyboardFocus.canRequestFocus) keyboardFocus.requestFocus();
  }

  /// Commits whatever is being edited (pointer down elsewhere, pinch).
  VoidCallback? commitEdit;

  // ----------------------------------------------------------- navigation

  Rect _visibleScreenRect() {
    final i = host.chromeInsets;
    final size = viewport.size;
    return Rect.fromLTRB(i.left, i.top, size.width - i.right, size.height - i.bottom);
  }

  /// Fits the whole board (lanes, stickies, ink) in the view, at most 100 %.
  void fitToScreen({bool animate = true}) {
    final size = viewport.size;
    if (size.isEmpty) return;
    final content = scene.contentBounds;
    final area = _visibleScreenRect().deflate(24);
    if (content.isEmpty || area.isEmpty) {
      viewport.centerOn(content.isEmpty ? Offset.zero : content.center, 1);
      return;
    }
    final fit = math.min(area.width / content.width, area.height / content.height);
    viewport.setFitScale(fit);
    final s = viewport.clampScale(math.min(fit, 1.0));
    // Centre the content in the area not covered by toolbars.
    final shift = area.center - size.center(Offset.zero);
    final canvasCentre = content.center - shift / s;
    if (animate) {
      unawaited(animateTo(canvasCentre, s));
    } else {
      viewport.centerOn(canvasCentre, s);
    }
  }

  void zoomBy(double factor) {
    final c = viewport.canvasCenter;
    unawaited(animateTo(c, viewport.clampScale(viewport.scale * factor)));
  }

  /// Pans (no zoom change) so [r] is inside the area not under toolbars.
  void reveal(Rect r) {
    final v = _visibleScreenRect().deflate(24);
    final sr = viewport.rectToScreen(r);
    var dx = 0.0, dy = 0.0;
    if (sr.width > v.width || sr.left < v.left) {
      dx = v.left - sr.left;
    } else if (sr.right > v.right) {
      dx = v.right - sr.right;
    }
    if (sr.height > v.height || sr.top < v.top) {
      dy = v.top - sr.top;
    } else if (sr.bottom > v.bottom) {
      dy = v.bottom - sr.bottom;
    }
    if (dx == 0 && dy == 0) return;
    final c = viewport.canvasCenter - Offset(dx, dy) / viewport.scale;
    unawaited(animateTo(c, viewport.scale));
  }

  // ------------------------------------------------------------ animations

  late final Ticker _view;
  Offset _fromCentre = Offset.zero, _toCentre = Offset.zero;
  double _fromScale = 1, _toScale = 1;
  Duration _viewDuration = Duration.zero;
  Completer<void>? _viewDone;

  /// Animates the view so [canvasCentre] is centred at [scale] (250 ms
  /// ease-out; instant with reduced motion).
  Future<void> animateTo(Offset canvasCentre, double scale, {Duration duration = const Duration(milliseconds: 250)}) {
    cancelFling();
    _finishView();
    if (reduceMotion || viewport.size.isEmpty) {
      viewport.centerOn(canvasCentre, scale);
      return Future.value();
    }
    _fromCentre = viewport.canvasCenter;
    _fromScale = viewport.scale;
    _toCentre = canvasCentre;
    _toScale = viewport.clampScale(scale);
    _viewDuration = duration;
    final done = _viewDone = Completer<void>();
    _view.start();
    return done.future;
  }

  void _onViewAnim(Duration elapsed) {
    final t = (elapsed.inMicroseconds / _viewDuration.inMicroseconds).clamp(0.0, 1.0);
    final k = Curves.easeOutCubic.transform(t);
    // Zoom in log space so it feels even, and move the centre along.
    final s = math.exp(ui.lerpDouble(math.log(_fromScale), math.log(_toScale), k)!);
    viewport.centerOn(Offset.lerp(_fromCentre, _toCentre, k)!, s);
    if (t >= 1) _finishView();
  }

  /// A pointer came down: the user takes over from any view animation.
  void stopViewAnimation() => _finishView();

  void _finishView() {
    if (_view.isActive) _view.stop();
    final d = _viewDone;
    _viewDone = null;
    if (d != null && !d.isCompleted) d.complete();
  }

  bool get animatingView => _view.isActive;

  // Fling: InteractiveViewer's drag constant.
  static const _kDrag = 0.0000135;
  late final Ticker _fling;
  FrictionSimulation? _fx, _fy;
  Offset _flingLast = Offset.zero;

  void fling(Offset velocity) {
    cancelFling();
    if (reduceMotion || velocity.distance < kMinFlingVelocity) return;
    final v = velocity.distance > kMaxFlingVelocity ? velocity / velocity.distance * kMaxFlingVelocity : velocity;
    _fx = FrictionSimulation(_kDrag, 0, v.dx);
    _fy = FrictionSimulation(_kDrag, 0, v.dy);
    _flingLast = Offset.zero;
    _fling.start();
  }

  void _onFling(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final fx = _fx!, fy = _fy!;
    final p = Offset(fx.x(t), fy.x(t));
    viewport.panBy(p - _flingLast);
    _flingLast = p;
    if (fx.isDone(t) && fy.isDone(t)) cancelFling();
  }

  void cancelFling() {
    if (_fling.isActive) _fling.stop();
    _fx = _fy = null;
  }

  bool get flinging => _fling.isActive;

  // Settling lifted items back into place (a card dropped outside a lane,
  // or sliding into its new slot).
  late final Ticker _settle;
  Offset _settleFrom = Offset.zero;
  VoidCallback? _settleDone;

  void settleLifted(Offset from, VoidCallback done, {Duration duration = const Duration(milliseconds: 180)}) {
    _finishSettle();
    if (reduceMotion || from.distance < 0.5) {
      done();
      return;
    }
    _settleFrom = from;
    _settleDone = done;
    lifted
      ..raised = false
      ..move(from);
    _settleDuration = duration;
    _settle.start();
  }

  Duration _settleDuration = Duration.zero;

  void _onSettle(Duration elapsed) {
    final t = (elapsed.inMicroseconds / _settleDuration.inMicroseconds).clamp(0.0, 1.0);
    lifted.move(_settleFrom * (1 - Curves.easeOutCubic.transform(t)));
    if (t >= 1) _finishSettle();
  }

  void _finishSettle() {
    if (_settle.isActive) _settle.stop();
    final d = _settleDone;
    _settleDone = null;
    d?.call();
  }

  bool get settling => _settle.isActive;

  // ------------------------------------------------------------------ misc

  /// Pastel used for cursors and outlines of a peer.
  static Color peerColor(int colorIndex) => pastelAt(colorIndex).accent;

  void dispose() {
    _disposed = true;
    editor.removeListener(_onEditor);
    _connection?.peers.removeListener(_onPeers);
    _finishView();
    _finishSettle();
    _fling.dispose();
    _view.dispose();
    _settle.dispose();
    presence.dispose();
    for (final n in <ChangeNotifier>[
      viewport,
      text,
      outlines,
      scene,
      lifted,
      selection,
      hover,
      marquee,
      drop,
      tool,
      ink,
      activeInk,
      editing,
      interacting,
      cursor,
      eraserRing,
      itemCount,
      columnCount,
      peers,
    ]) {
      n.dispose();
    }
    keyboardFocus.dispose();
  }
}
