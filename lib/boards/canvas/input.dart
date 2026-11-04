import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../models/ink.dart';
import '../../ui/notes/ink/ink_painter.dart';
import '../model/board_item.dart';
import 'canvas_strings.dart';
import 'painters.dart';
import 'scene.dart';
import 'session.dart';
import 'viewport.dart';

enum BoardGesture {
  none,
  pending,
  pan,
  pinch,
  dragItems,
  dragCard,
  dragLanes,
  marquee,
  draw,
  erase,
  secondary,
  waitAllUp,
}

/// Hand-timed thresholds (docs/boards/DESIGN.md §8).
abstract final class BoardTiming {
  static const doubleTap = kDoubleTapTimeout;
  static const longPress = Duration(milliseconds: 450);

  /// A touch held this long before moving drags the item instead of panning.
  static const hold = Duration(milliseconds: 250);

  /// A second finger this soon after a finger stroke started cancels it.
  static const pinchCancelsStroke = Duration(milliseconds: 200);
  static const pinchCancelsStrokePx = 24.0;
  static const palmRadius = 24.0;
  static const edgeBand = 40.0;

  /// Auto-pan speed at the very edge, px per 60 Hz frame.
  static const edgeSpeed = 18.0;
}

/// The canvas' one input path. A Listener feeds every pointer event here;
/// an eager recognizer above it wins every gesture arena, so no item has
/// recognizers of its own. Hit-testing is against the model, taps,
/// double-taps and long presses are timed by hand, and a second finger
/// turns whatever one finger was doing into a pinch.
class BoardInput {
  BoardInput(this.session) {
    _edge = session.vsync.createTicker(_onEdgeTick);
  }

  final BoardSession session;
  BoardViewport get _vp => session.viewport;

  BoardGesture _g = BoardGesture.none;
  BoardGesture get gesture => _g;

  int? _primary;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _downScreen = Offset.zero, _lastScreen = Offset.zero, _downCanvas = Offset.zero;
  SceneHit _hit = SceneHit.none;
  bool _shift = false;
  bool _held = false;
  bool _longPressed = false;
  Timer? _holdTimer, _longTimer;

  final Map<int, Offset> _touches = {};
  final Set<int> _ignored = {};
  final Set<int> _stylusDown = {};
  bool _sawStylus = false;

  // Pinch.
  int _pa = 0, _pb = 0;
  Offset _pinchAnchor = Offset.zero;
  double _pinchS0 = 1, _pinchSpan0 = 1;

  // Taps.
  Timer? _tapWindow;
  SceneHit? _lastTapHit;
  Offset _lastTapAt = Offset.zero;

  VelocityTracker? _tracker;

  // Drags.
  Offset _grabCanvas = Offset.zero;
  Map<String, Offset> _dragStart = const {};
  String? _dragCard;
  Rect _cardStart = Rect.zero;
  bool _listeningToView = false;
  late final Ticker _edge;
  Duration _edgeLast = Duration.zero;

  // Drawing.
  final List<double> _buf = [];
  int _t0 = 0, _t0Epoch = 0;
  bool _strokeYoung = false;
  double _strokePx = 0;
  Timer? _youngTimer;

  // Erasing.
  final Set<String> _erased = {};

  // Trackpad.
  double _pzS0 = 1;
  Offset _pzP0 = Offset.zero, _pzAnchor = Offset.zero;
  VelocityTracker? _pzTracker;
  bool _pzScaled = false;

  Offset? _lastSent;

  /// Space is held: the mouse pans.
  bool _space = false;
  bool get spaceHeld => _space;
  set spaceHeld(bool v) {
    if (v == _space) return;
    _space = v;
    _updateCursor(null);
  }

  // ----------------------------------------------------------------- down

  void down(PointerDownEvent e) {
    session.cancelFling();
    session.stopViewAnimation();
    if (session.isEditing) session.commitEdit?.call();
    if (!session.isEditing && session.keyboardFocus.canRequestFocus) session.keyboardFocus.requestFocus();
    switch (e.kind) {
      case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus:
        _stylus(e);
      case PointerDeviceKind.touch:
        _touch(e);
      default:
        _mouse(e);
    }
  }

  bool get _readOnly => session.readOnly;

  void _begin(PointerDownEvent e) {
    _primary = e.pointer;
    _kind = e.kind;
    _downScreen = _lastScreen = e.localPosition;
    _downCanvas = _vp.toCanvas(e.localPosition);
    _shift = HardwareKeyboard.instance.isShiftPressed;
    _held = false;
    _longPressed = false;
  }

  void _stylus(PointerDownEvent e) {
    if (!_sawStylus) {
      _sawStylus = true;
      session.host.stylusDetected();
    }
    // The pen wins over a resting hand.
    if (_primary != null && _kind == PointerDeviceKind.touch) _abortTouch();
    _ignored.addAll(_touches.keys);
    _stylusDown.add(e.pointer);
    if (_primary != null) {
      _ignored.add(e.pointer);
      return;
    }
    _begin(e);
    final t = session.tool.value;
    if (!_readOnly && (e.kind == PointerDeviceKind.invertedStylus || t.erases)) {
      _startErase(e);
    } else if (!_readOnly && t.inks) {
      _startDraw(e);
    } else {
      _startPending(e);
    }
  }

  void _touch(PointerDownEvent e) {
    final t = session.tool.value;
    if (_stylusDown.isNotEmpty || ((t.inks || t.erases) && e.radiusMajor > BoardTiming.palmRadius)) {
      _ignored.add(e.pointer);
      return;
    }
    if (_primary != null && _kind != PointerDeviceKind.touch) {
      _ignored.add(e.pointer);
      return;
    }
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 1) {
      _begin(e);
      final fingersDraw = !_readOnly && !session.host.stylusOnly;
      if (fingersDraw && t.inks) {
        _startDraw(e);
      } else if (fingersDraw && t.erases) {
        _startErase(e);
      } else {
        _startPending(e);
      }
      return;
    }
    if (_touches.length == 2) {
      switch (_g) {
        case BoardGesture.draw:
          if (_strokeYoung && _strokePx < BoardTiming.pinchCancelsStrokePx) {
            _discardStroke();
          } else {
            // A later second finger while writing is a resting knuckle.
            _touches.remove(e.pointer);
            _ignored.add(e.pointer);
            return;
          }
        case BoardGesture.erase:
          _cancelErase();
        case BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes:
          _revertDrag();
        case BoardGesture.marquee:
          _stopViewListening();
          _endMarquee(commit: false);
        default:
          break;
      }
      _startPinch();
      return;
    }
    if (_g == BoardGesture.pinch) _rebaselinePinch();
  }

  void _mouse(PointerDownEvent e) {
    if (_primary != null) return;
    _begin(e);
    final b = e.buttons;
    final macCtrlClick =
        defaultTargetPlatform == TargetPlatform.macOS &&
        (b & kPrimaryButton) != 0 &&
        HardwareKeyboard.instance.isControlPressed;
    if ((b & kMiddleMouseButton) != 0 || ((b & kPrimaryButton) != 0 && _space)) {
      _startPan();
      return;
    }
    if ((b & kSecondaryButton) != 0 || macCtrlClick) {
      _g = BoardGesture.secondary;
      _hit = _hitAt(e.localPosition, e.kind);
      return;
    }
    final t = session.tool.value;
    if (!_readOnly && t.inks) {
      _startDraw(e);
    } else if (!_readOnly && t.erases) {
      _startErase(e);
    } else {
      _startPending(e);
    }
  }

  SceneHit _hitAt(Offset screen, PointerDeviceKind kind) {
    final px = switch (kind) {
      PointerDeviceKind.touch => 8.0,
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 4.0,
      _ => 2.0,
    };
    return session.scene.hitTest(_vp.toCanvas(screen), slop: math.max(px, 4) / _vp.scale);
  }

  void _startPending(PointerDownEvent e) {
    _g = BoardGesture.pending;
    _hit = _hitAt(e.localPosition, e.kind);
    if (e.kind == PointerDeviceKind.touch) {
      _holdTimer = Timer(BoardTiming.hold, () => _held = true);
      _longTimer = Timer(BoardTiming.longPress, _onLongPress);
    }
  }

  void _onLongPress() {
    if (_g != BoardGesture.pending) return;
    _longPressed = true;
    if (_readOnly) return;
    if (_hit.isItem) {
      unawaited(HapticFeedback.selectionClick());
      _startDrag();
    } else if (_hit.kind == HitKind.laneHeader) {
      unawaited(HapticFeedback.selectionClick());
      _startDragLanes();
    }
  }

  // ----------------------------------------------------------------- move

  void move(PointerMoveEvent e) {
    if (_ignored.contains(e.pointer)) return;
    if (_touches.containsKey(e.pointer)) _touches[e.pointer] = e.localPosition;
    if (_g == BoardGesture.pinch) {
      if (e.pointer == _pa || e.pointer == _pb) _pinchMove();
      return;
    }
    if (e.pointer != _primary) return;
    final prev = _lastScreen;
    _lastScreen = e.localPosition;
    switch (_g) {
      case BoardGesture.pending:
        final slop = _kind == PointerDeviceKind.touch ? kTouchSlop : 4.0;
        if ((e.localPosition - _downScreen).distance > slop) {
          _resolvePending(e);
          if (_g != BoardGesture.pan) _checkEdge();
        }
      case BoardGesture.pan:
        _vp.panBy(e.localPosition - prev);
        _tracker?.addPosition(e.timeStamp, e.localPosition);
      case BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes:
        _updateDrag();
        _checkEdge();
        _sendCursor(e.localPosition, pointer: _kind != PointerDeviceKind.touch);
      case BoardGesture.marquee:
        _updateMarquee();
        _checkEdge();
        _sendCursor(e.localPosition, pointer: true);
      case BoardGesture.draw:
        _addPoint(e);
        _sendCursor(e.localPosition, pointer: _kind != PointerDeviceKind.touch);
      case BoardGesture.erase:
        _eraseAt(e.localPosition);
        if (_kind != PointerDeviceKind.touch) session.eraserRing.value = e.localPosition;
      default:
        break;
    }
  }

  void _resolvePending(PointerMoveEvent e) {
    _cancelTimers();
    final pointerish = _kind != PointerDeviceKind.touch;
    final hit = _hit;
    if (_readOnly) {
      pointerish ? _startMarquee() : _startPan();
    } else if (hit.kind == HitKind.laneHeader) {
      pointerish || _held ? _startDragLanes() : _startPan();
    } else if (hit.isItem) {
      final selected = session.selection.value.contains(hit.id);
      pointerish || selected || _held ? _startDrag() : _startPan();
    } else if (!pointerish) {
      _longPressed ? _startMarquee() : _startPan();
    } else {
      _startMarquee();
    }
  }

  // ------------------------------------------------------------------ pan

  void _startPan() {
    _g = BoardGesture.pan;
    session.interacting.value = true;
    _tracker = VelocityTracker.withKind(_kind);
    // Keep the canvas point under the finger where the finger went down.
    _vp.panBy(_lastScreen - _downScreen);
    _updateCursor(null);
  }

  // ---------------------------------------------------------------- pinch

  void _startPinch() {
    if (session.isEditing) session.commitEdit?.call();
    _cancelTimers();
    // A finger left over from an earlier pinch takes part again.
    _ignored.removeAll(_touches.keys);
    _tracker = null;
    _g = BoardGesture.pinch;
    session.interacting.value = true;
    final keys = _touches.keys.toList();
    _pa = keys[0];
    _pb = keys[1];
    _rebaselinePinch();
  }

  void _rebaselinePinch() {
    final keys = _touches.keys.toList();
    if (keys.length < 2) return;
    _pa = keys[0];
    _pb = keys[1];
    final a = _touches[_pa]!, b = _touches[_pb]!;
    _pinchSpan0 = math.max((a - b).distance, 1);
    _pinchS0 = _vp.scale;
    _pinchAnchor = _vp.toCanvas((a + b) / 2);
  }

  void _pinchMove() {
    final a = _touches[_pa], b = _touches[_pb];
    if (a == null || b == null) return;
    final span = (a - b).distance;
    _vp.setFromAnchor(_pinchAnchor, (a + b) / 2, _pinchS0 * span / _pinchSpan0);
  }

  // ---------------------------------------------------------------- drags

  void _startDrag() {
    final id = _hit.id;
    if (id == null) return;
    var sel = session.selection.value;
    if (!sel.contains(id)) {
      sel = _shift ? {...sel, id} : {id};
      session.select(sel);
    }
    final si = session.scene.byId(id);
    if (si == null) {
      // Gone meanwhile (a teammate deleted it).
      _kind == PointerDeviceKind.touch ? _startPan() : _startMarquee();
      return;
    }
    if (_hit.kind == HitKind.card) {
      _g = BoardGesture.dragCard;
      _dragCard = id;
      _cardStart = si.bounds;
      session.lifted.lift({id});
    } else {
      var ids = session.freeOf(sel);
      if (ids.isEmpty) ids = {id};
      _dragStart = {for (final i in ids) i: session.scene.byId(i)!.origin};
      _g = BoardGesture.dragItems;
      session.lifted.lift(ids);
    }
    _beginDragCommon();
  }

  void _startDragLanes() {
    if (session.scene.lanes.isEmpty) {
      _startPan();
      return;
    }
    _g = BoardGesture.dragLanes;
    session.lifted.lift(const {}, lanes: true);
    _beginDragCommon();
  }

  void _beginDragCommon() {
    _cancelTimers();
    _grabCanvas = _downCanvas;
    session.interacting.value = true;
    if (!_listeningToView) {
      _vp.addListener(_updateDrag);
      _listeningToView = true;
    }
    _updateDrag();
    _updateCursor(null);
  }

  /// Item position = start + (canvas point under the pointer now − where it
  /// grabbed); re-run on every viewport change so wheel pans and edge
  /// auto-pan keep the item under the pointer.
  void _updateDrag() {
    switch (_g) {
      case BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes:
        break;
      case BoardGesture.marquee:
        _updateMarquee();
        return;
      default:
        return;
    }
    final delta = _vp.toCanvas(_lastScreen) - _grabCanvas;
    session.lifted.move(delta);
    if (_g == BoardGesture.dragCard) {
      final scene = session.scene;
      final t = scene.lanes.dropTarget(_cardStart.center + delta, exclude: _dragCard);
      if (t == null) {
        session.drop.value = null;
      } else {
        final lane = scene.lanes.laneById(t.columnId)!;
        session.drop.value = DropIndicator(t.columnId, scene.lanes.insertionY(lane, t.index, exclude: _dragCard));
      }
    }
  }

  void _endDrag() {
    final lifted = session.lifted;
    final delta = lifted.delta;
    final editor = session.editor;
    switch (_g) {
      case BoardGesture.dragItems:
        final moved = delta.distance > 0.01;
        if (moved && !_readOnly) {
          editor.moveTo({
            for (final e in _dragStart.entries)
              if (editor.item(e.key)?.live ?? false) e.key: e.value + delta,
          });
        }
        lifted.drop();
      case BoardGesture.dragLanes:
        if (delta.distance > 0.01 && !_readOnly) editor.setLaneOrigin(editor.laneOrigin + delta);
        lifted.drop();
      case BoardGesture.dragCard:
        _dropCard(delta);
      default:
        break;
    }
    session.drop.value = null;
    _dragStart = const {};
    _dragCard = null;
  }

  void _dropCard(Offset delta) {
    final id = _dragCard!;
    final scene = session.scene;
    final lifted = session.lifted;
    final editor = session.editor;
    final card = editor.item(id);
    if (card == null || card.deleted || delta.distance < 0.01) {
      lifted.drop();
      return;
    }
    final target = scene.lanes.dropTarget(_cardStart.center + delta, exclude: id);
    if (target == null || _readOnly) {
      // Back to its slot.
      session.settleLifted(delta, lifted.drop);
      if (!BoardSession.cardsHintShown && target == null) {
        BoardSession.cardsHintShown = true;
        session.host.showSnack(session.host.strings.canvasCardsLiveInColumns);
      }
      return;
    }
    final from = scene.byId(id)?.columnId;
    final drawnAt = _cardStart.topLeft + delta;
    editor.moveCard(id, columnId: target.columnId, index: target.index);
    final slot = scene.byId(id)?.bounds;
    // Slide from where it was dropped into its new slot.
    if (slot != null) {
      session.settleLifted(drawnAt - slot.topLeft, lifted.drop, duration: const Duration(milliseconds: 150));
    } else {
      lifted.drop();
    }
    if (from != target.columnId) {
      final s = session.host.strings;
      final title = card.title.isEmpty ? s.untitled : card.title;
      final col = editor.item(target.columnId)?.title ?? '';
      session.host.showSnack(s.canvasCardMoved(title, col), undo: session.undo);
    }
  }

  void _revertDrag() {
    _stopViewListening();
    session.drop.value = null;
    final d = session.lifted.delta;
    if (_g == BoardGesture.dragCard || _g == BoardGesture.dragItems || _g == BoardGesture.dragLanes) {
      session.settleLifted(d, session.lifted.drop);
    }
    _dragStart = const {};
    _dragCard = null;
    _g = BoardGesture.none;
  }

  // -------------------------------------------------------------- marquee

  Set<String> _marqueeBase = const {};

  void _startMarquee() {
    _g = BoardGesture.marquee;
    session.interacting.value = true;
    _marqueeBase = _shift ? session.selection.value : const {};
    if (!_listeningToView) {
      _vp.addListener(_updateDrag);
      _listeningToView = true;
    }
    _updateMarquee();
  }

  void _updateMarquee() {
    final r = Rect.fromPoints(_downCanvas, _vp.toCanvas(_lastScreen));
    session.marquee.value = r;
    session.select({..._marqueeBase, ...session.scene.query(r)});
  }

  void _endMarquee({bool commit = true}) {
    if (!commit) session.select(_marqueeBase);
    session.marquee.value = null;
    _marqueeBase = const {};
  }

  // ----------------------------------------------------------- edge pan

  Offset _edgeVelocity() {
    final size = _vp.size;
    final p = _lastScreen;
    const band = BoardTiming.edgeBand;
    const speed = BoardTiming.edgeSpeed * 60;
    double axis(double v, double extent) {
      if (extent <= band * 2) return 0;
      if (v < band) return speed * (1 - (v / band).clamp(0.0, 1.0));
      if (v > extent - band) return -speed * (1 - ((extent - v) / band).clamp(0.0, 1.0));
      return 0;
    }

    return Offset(axis(p.dx, size.width), axis(p.dy, size.height));
  }

  void _checkEdge() {
    if (_edge.isActive || _edgeVelocity() == Offset.zero) return;
    _edgeLast = Duration.zero;
    _edge.start();
  }

  void _onEdgeTick(Duration elapsed) {
    final dt = (elapsed - _edgeLast).inMicroseconds / 1e6;
    _edgeLast = elapsed;
    final v = _edgeVelocity();
    final dragging = switch (_g) {
      BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes || BoardGesture.marquee => true,
      _ => false,
    };
    if (!dragging || v == Offset.zero) {
      _edge.stop();
      return;
    }
    _vp.panBy(v * dt);
  }

  // -------------------------------------------------------------- drawing

  void _startDraw(PointerDownEvent e) {
    _g = BoardGesture.draw;
    session.interacting.value = true;
    final s = _vp.scale;
    final ink = session.ink.value;
    final hi = session.tool.value == BoardTool.highlighter;
    final screenWidth = hi ? InkSettings.highlighterWidth : ink.penWidth;
    final stylus = e.kind == PointerDeviceKind.stylus;
    _t0 = e.timeStamp.inMilliseconds;
    _t0Epoch = session.now().millisecondsSinceEpoch;
    _buf.clear();
    _strokePx = 0;
    _strokeYoung = true;
    _youngTimer = Timer(BoardTiming.pinchCancelsStroke, () => _strokeYoung = false);
    session.activeInk.start(
      ActiveStroke(
        color: hi ? ink.highlighterColor : ink.penColor,
        width: (screenWidth / s).clamp(0.5, 400).toDouble(),
        tool: hi ? InkTool.highlighter : InkTool.pen,
        hasPressure: stylus && e.pressureMax > e.pressureMin && !hi,
      ),
    );
    _addPoint(e);
  }

  double _pressure(PointerEvent e) {
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    if (!stylus || e.pressureMax <= e.pressureMin) return 0.5;
    final n = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
    // Apple Pencil reports light everyday pressure as small values; lift it.
    return math.pow(n, 0.6).toDouble().clamp(0.08, 1.0);
  }

  void _addPoint(PointerEvent e) {
    final a = session.activeInk.stroke;
    if (a == null) return;
    final s = _vp.scale;
    final p = _vp.toCanvas(e.localPosition);
    if (_buf.length >= 4) {
      final dx = p.dx - _buf[_buf.length - 4], dy = p.dy - _buf[_buf.length - 3];
      final d2 = dx * dx + dy * dy;
      // Half a screen pixel, in canvas units, whatever the zoom.
      final min = 0.5 / s;
      if (d2 < min * min) return;
      _strokePx += math.sqrt(d2) * s;
    }
    final pressure = _pressure(e);
    _buf.addAll([p.dx, p.dy, pressure, (e.timeStamp.inMilliseconds - _t0).toDouble()]);
    session.activeInk.addPoint(pf.PointVector(p.dx, p.dy, a.hasPressure ? pressure : null));
  }

  void _commitDraw() {
    final a = session.activeInk.stroke;
    if (a == null || _buf.isEmpty || _readOnly) {
      _discardStroke();
      return;
    }
    final raw = InkStroke(
      data: Float32List.fromList(_buf),
      color: a.color,
      width: a.width,
      tool: a.tool,
      hasPressure: a.hasPressure,
    );
    final origin = raw.bounds.topLeft;
    final local = Float32List.fromList(_buf);
    for (var i = 0; i < local.length; i += InkStroke.stride) {
      local[i] -= origin.dx;
      local[i + 1] -= origin.dy;
    }
    final stroke = InkStroke(
      data: local,
      color: a.color,
      width: a.width,
      tool: a.tool,
      hasPressure: a.hasPressure,
      startedAt: _t0Epoch,
    );
    final id = session.editor.addInk(origin: origin, strokes: InkCodec.encode([stroke]));
    // Build the outline now so the new stroke never flashes as a polyline.
    final built = session.scene.byId(id)?.stroke;
    if (built != null) session.outlines.buildNow(built);
    // Cleared after the commit so there is no blank frame.
    session.activeInk.end();
    _buf.clear();
  }

  void _discardStroke() {
    _youngTimer?.cancel();
    session.activeInk.end();
    _buf.clear();
  }

  // -------------------------------------------------------------- erasing

  void _startErase(PointerDownEvent e) {
    _g = BoardGesture.erase;
    session.interacting.value = true;
    _erased.clear();
    _eraseAt(e.localPosition);
  }

  void _eraseAt(Offset screen) {
    final r = BoardInputConstants.eraserRadius / _vp.scale;
    final hits = session.scene.inkAt(_vp.toCanvas(screen), r, exclude: _erased);
    if (hits.isEmpty) return;
    _erased.addAll(hits);
    session.lifted.hide(hits);
  }

  /// One erase gesture is one undo step and one write.
  void _commitErase() {
    if (_erased.isNotEmpty && !_readOnly) session.editor.deleteItems({..._erased});
    session.lifted.unhideAll();
    _erased.clear();
  }

  void _cancelErase() {
    session.lifted.unhideAll();
    _erased.clear();
  }

  // ------------------------------------------------------------------- up

  void up(PointerUpEvent e) => _finish(e, cancelled: false);

  void cancel(PointerCancelEvent e) => _finish(e, cancelled: true);

  void _finish(PointerEvent e, {required bool cancelled}) {
    _touches.remove(e.pointer);
    _stylusDown.remove(e.pointer);
    if (_ignored.remove(e.pointer)) {
      if (_g == BoardGesture.waitAllUp && _touches.isEmpty) _reset();
      return;
    }
    if (_g == BoardGesture.pinch) {
      if (_touches.length >= 2) {
        _rebaselinePinch();
      } else {
        // Ignore the remaining finger until every finger is up.
        _g = BoardGesture.waitAllUp;
        _ignored.addAll(_touches.keys);
        session.interacting.value = false;
        if (_touches.isEmpty) _reset();
      }
      return;
    }
    if (_g == BoardGesture.waitAllUp) {
      if (_touches.isEmpty) _reset();
      return;
    }
    if (e.pointer != _primary) return;
    _lastScreen = e.localPosition;
    switch (_g) {
      case BoardGesture.pending:
        if (!cancelled) _tap(e);
      case BoardGesture.pan:
        final v = _tracker?.getVelocity().pixelsPerSecond;
        if (!cancelled && v != null && _kind == PointerDeviceKind.touch) session.fling(v);
      case BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes:
        _stopViewListening();
        cancelled ? _revertDrag() : _endDrag();
      case BoardGesture.marquee:
        _stopViewListening();
        _endMarquee(commit: !cancelled);
      case BoardGesture.draw:
        cancelled ? _discardStroke() : _commitDraw();
      case BoardGesture.erase:
        cancelled ? _cancelErase() : _commitErase();
      case BoardGesture.secondary:
        if (!cancelled) _secondaryTap(e);
      default:
        break;
    }
    _reset();
  }

  void _tap(PointerEvent e) {
    final hit = _hit;
    final slop = _kind == PointerDeviceKind.touch ? 24.0 : 6.0;
    final last = _lastTapHit;
    final isDouble =
        (_tapWindow?.isActive ?? false) &&
        last != null &&
        last.sameTarget(hit) &&
        (e.localPosition - _lastTapAt).distance <= slop;
    if (isDouble) {
      _tapWindow?.cancel();
      _lastTapHit = null;
      _doubleTap(hit, e.localPosition);
      return;
    }
    final sel = session.selection.value;
    if (hit.isItem) {
      final id = hit.id!;
      if (_shift) {
        session.select(sel.contains(id) ? ({...sel}..remove(id)) : {...sel, id});
      } else {
        session.select({id});
      }
    } else if (!_shift) {
      session.clearSelection();
    }
    _lastTapHit = hit;
    _lastTapAt = e.localPosition;
    _tapWindow?.cancel();
    _tapWindow = Timer(BoardTiming.doubleTap, () {});
  }

  void _doubleTap(SceneHit hit, Offset screen) {
    final touch = _kind == PointerDeviceKind.touch;
    switch (hit.kind) {
      case HitKind.none:
        if (!_readOnly) session.addStickyAt(_vp.toCanvas(screen), touch: touch);
      case HitKind.free:
        if (session.scene.byId(hit.id!)?.kind == ItemKind.sticky) unawaited(session.beginEdit(hit.id!, touch: touch));
      case HitKind.card:
        session.host.openCard(hit.id!);
      case HitKind.laneHeader:
        if (!_readOnly) session.host.renameColumn(hit.columnId!);
    }
  }

  void _secondaryTap(PointerEvent e) {
    final hit = _hit;
    if (hit.isItem) {
      if (!session.selection.value.contains(hit.id)) session.select({hit.id!});
      session.host.showItemMenu(e.localPosition);
    } else {
      session.clearSelection();
    }
  }

  void _reset() {
    _cancelTimers();
    _stopViewListening();
    if (_edge.isActive) _edge.stop();
    _g = _touches.isEmpty ? BoardGesture.none : BoardGesture.waitAllUp;
    if (_g == BoardGesture.waitAllUp) _ignored.addAll(_touches.keys);
    _primary = null;
    _tracker = null;
    _hit = SceneHit.none;
    session.interacting.value = false;
    session.drop.value = null;
    session.marquee.value = null;
    _updateCursor(null);
  }

  void _cancelTimers() {
    _holdTimer?.cancel();
    _longTimer?.cancel();
    _holdTimer = _longTimer = null;
  }

  void _stopViewListening() {
    if (!_listeningToView) return;
    _vp.removeListener(_updateDrag);
    _listeningToView = false;
  }

  /// A pen came down on top of a finger gesture: drop the finger's gesture
  /// (a pan ends without a fling).
  void _abortTouch() {
    switch (_g) {
      case BoardGesture.draw:
        _discardStroke();
      case BoardGesture.erase:
        _cancelErase();
      case BoardGesture.dragItems || BoardGesture.dragCard || BoardGesture.dragLanes:
        _revertDrag();
      case BoardGesture.marquee:
        _stopViewListening();
        _endMarquee(commit: false);
      default:
        break;
    }
    _ignored.addAll(_touches.keys);
    _touches.clear();
    _reset();
  }

  // ---------------------------------------------------------------- hover

  void hover(PointerHoverEvent e) {
    if (e.kind == PointerDeviceKind.touch) return;
    final p = e.localPosition;
    final tool = session.tool.value;
    session.eraserRing.value = tool.erases && !_readOnly ? p : null;
    if (_g == BoardGesture.none && tool == BoardTool.select) {
      final hit = _hitAt(p, e.kind);
      session.hover.value = hit.isItem ? hit.id : null;
      _updateCursor(hit);
    }
    _sendCursor(p, pointer: true);
  }

  void exit(PointerExitEvent e) {
    session.hover.value = null;
    session.eraserRing.value = null;
    _lastSent = null;
    session.connection.sendCursor(null);
  }

  void _updateCursor(SceneHit? hit) {
    final tool = session.tool.value;
    final MouseCursor c;
    if (_g == BoardGesture.pan) {
      c = SystemMouseCursors.grabbing;
    } else if (_g == BoardGesture.dragLanes) {
      c = SystemMouseCursors.grabbing;
    } else if (_space) {
      c = SystemMouseCursors.grab;
    } else if (!_readOnly && (tool.inks || tool.erases)) {
      c = SystemMouseCursors.precise;
    } else if (hit?.kind == HitKind.laneHeader && !_readOnly) {
      c = SystemMouseCursors.grab;
    } else {
      c = SystemMouseCursors.basic;
    }
    session.cursor.value = c;
  }

  /// This device's pointer for teammates: hover and drags only, after a
  /// 2 px move (the connection throttles and skips it when alone).
  void _sendCursor(Offset screen, {required bool pointer}) {
    final last = _lastSent;
    if (last != null && (screen - last).distance < 2) return;
    _lastSent = screen;
    session.connection.sendCursor(_vp.toCanvas(screen), pointer: pointer);
  }

  // -------------------------------------------------------------- signals

  /// Wheel, trackpad scroll and web pinch, claimed through the resolver so
  /// an outer scrollable never scrolls too.
  void signal(PointerSignalEvent e) => GestureBinding.instance.pointerSignalResolver.register(e, _resolveSignal);

  void _resolveSignal(PointerSignalEvent e) {
    if (e is PointerScrollInertiaCancelEvent) {
      session.cancelFling();
    } else if (e is PointerScaleEvent) {
      _zoom(e.localPosition, e.scale);
    } else if (e is PointerScrollEvent) {
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed || kb.isMetaPressed) {
        _zoom(e.localPosition, math.exp(-e.scrollDelta.dy / 200));
        return;
      }
      var d = e.scrollDelta;
      if (e.kind == PointerDeviceKind.mouse && kb.isShiftPressed && d.dx == 0) d = Offset(d.dy, 0);
      session.cancelFling();
      _vp.panBy(-d);
    }
  }

  void _zoom(Offset focal, double factor) {
    if (session.isEditing) session.commitEdit?.call();
    session.cancelFling();
    _vp.zoomAt(focal, factor);
  }

  void panZoomStart(PointerPanZoomStartEvent e) {
    session.cancelFling();
    _pzS0 = _vp.scale;
    _pzP0 = e.localPosition;
    _pzAnchor = _vp.toCanvas(_pzP0);
    _pzTracker = VelocityTracker.withKind(PointerDeviceKind.trackpad);
    _pzScaled = false;
  }

  void panZoomUpdate(PointerPanZoomUpdateEvent e) {
    if ((e.scale - 1).abs() >= 0.01) {
      if (!_pzScaled && session.isEditing) session.commitEdit?.call();
      _pzScaled = true;
    }
    _vp.setFromAnchor(_pzAnchor, _pzP0 + e.localPan, _pzScaled ? _pzS0 * e.scale : _pzS0);
    _pzTracker?.addPosition(e.timeStamp, e.pan);
  }

  void panZoomEnd(PointerPanZoomEndEvent e) {
    final v = _pzTracker?.getVelocity().pixelsPerSecond;
    if (!_pzScaled && v != null) session.fling(v);
    _pzTracker = null;
  }

  void dispose() {
    _cancelTimers();
    _tapWindow?.cancel();
    _youngTimer?.cancel();
    _stopViewListening();
    _edge.dispose();
  }
}
