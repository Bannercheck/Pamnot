import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Level of detail for scale [s], given the previous level. 2 is full detail
/// (drawn immediately), 1 an overview without text, 0 the far view. The gaps
/// between the up and down thresholds keep a pinch that hovers at a
/// boundary from flipping the picture every frame.
int lodFor(double s, int prev) => switch (prev) {
  2 => s < 0.38 ? (s < 0.14 ? 0 : 1) : 2,
  1 => s >= 0.42 ? 2 : (s < 0.14 ? 0 : 1),
  _ => s >= 0.42 ? 2 : (s >= 0.16 ? 1 : 0),
};

/// Where the canvas is on screen: `screen = canvas * scale + offset`.
///
/// Painters listen to it through `repaint:`, so panning and zooming never
/// rebuild a widget.
class BoardViewport extends ChangeNotifier {
  static const maxScale = 4.0;
  static const minScaleFloor = 0.02;
  static const minScaleCeiling = 0.1;

  /// Items are clamped to ±this many units, so float32 transforms stay exact
  /// to a few hundredths of a pixel.
  static const worldLimit = 100000.0;

  Offset _offset = Offset.zero;
  double _scale = 1;
  Size _size = Size.zero;
  double _minScale = minScaleCeiling;
  int _lod = 2;
  Rect? _content;
  Float64List? _matrix;
  final ValueNotifier<int> _percent = ValueNotifier(100);

  Offset get offset => _offset;
  double get scale => _scale;
  Size get size => _size;
  double get minScale => _minScale;
  int get lod => _lod;

  /// Rounded zoom percentage; notifies only when the number changes, so the
  /// zoom label rebuilds a few times per pinch instead of every frame.
  ValueListenable<int> get zoomPercent => _percent;

  Offset toCanvas(Offset screen) => (screen - _offset) / _scale;
  Offset toScreen(Offset canvas) => canvas * _scale + _offset;
  Rect rectToScreen(Rect r) => Rect.fromLTRB(
    r.left * _scale + _offset.dx,
    r.top * _scale + _offset.dy,
    r.right * _scale + _offset.dx,
    r.bottom * _scale + _offset.dy,
  );

  Rect get visibleCanvasRect =>
      Rect.fromLTWH(-_offset.dx / _scale, -_offset.dy / _scale, _size.width / _scale, _size.height / _scale);

  /// The canvas point at the centre of the view.
  Offset get canvasCenter => toCanvas(_size.center(Offset.zero));

  /// Column-major `translate(offset) · scale(s)` for [Canvas.transform].
  Float64List get matrix => _matrix ??= Float64List(16)
    ..[0] = _scale
    ..[5] = _scale
    ..[10] = 1
    ..[15] = 1
    ..[12] = _offset.dx
    ..[13] = _offset.dy;

  double clampScale(double s) => s.clamp(_minScale, maxScale).toDouble();

  /// Lets the minimum follow the board: 80 % of the scale that fits it, so a
  /// big board can always be seen whole.
  void setFitScale(double fit) {
    final m = (fit * 0.8).clamp(minScaleFloor, minScaleCeiling).toDouble();
    if (m == _minScale) return;
    _minScale = m;
    if (_scale < m) _apply(_offset, m);
  }

  /// The board's content, for the pan limit (null: only the world limit).
  set contentBounds(Rect? r) => _content = r;

  /// The view was resized: the canvas point at its centre stays put.
  void setSize(Size s) {
    if (s == _size) return;
    if (_size.isEmpty) {
      _size = s;
      _apply(_offset, _scale, force: true);
      return;
    }
    final c = canvasCenter;
    _size = s;
    _apply(s.center(Offset.zero) - c * _scale, _scale, force: true);
  }

  void panBy(Offset screenDelta) {
    if (screenDelta == Offset.zero) return;
    _apply(_offset + screenDelta, _scale);
  }

  /// Zooms by [factor] keeping the canvas point under [focal] in place.
  void zoomAt(Offset focal, double factor) {
    final s1 = clampScale(_scale * factor);
    final c = toCanvas(focal);
    _apply(focal - c * s1, s1);
  }

  /// Puts [canvasAnchor] under [screenPoint] at [newScale] (pinch, trackpad).
  void setFromAnchor(Offset canvasAnchor, Offset screenPoint, double newScale) {
    final s = clampScale(newScale);
    _apply(screenPoint - canvasAnchor * s, s);
  }

  void centerOn(Offset canvasPoint, double newScale) {
    final s = clampScale(newScale);
    _apply(_size.center(Offset.zero) - canvasPoint * s, s);
  }

  /// Raw set, used by animations.
  void set(Offset offset, double scale) => _apply(offset, clampScale(scale));

  bool _silent = false;
  bool _pending = false;

  /// Runs [fn] without notifying anyone: the view sets its size during
  /// layout, when listeners must not rebuild. Painters read the new values
  /// in the paint that follows; call [flush] after the frame for the rest.
  void silently(void Function() fn) {
    _silent = true;
    try {
      fn();
    } finally {
      _silent = false;
    }
  }

  /// Delivers a change made [silently].
  void flush() {
    if (!_pending) return;
    _pending = false;
    _percent.value = (_scale * 100).round();
    notifyListeners();
  }

  void _apply(Offset o, double s, {bool force = false}) {
    o = _clampPan(o, s);
    if (!force && o == _offset && s == _scale) return;
    _offset = o;
    _scale = s;
    _matrix = null;
    _lod = lodFor(s, _lod);
    if (_silent) {
      _pending = true;
      return;
    }
    _percent.value = (s * 100).round();
    notifyListeners();
  }

  /// Keeps the view centre inside the world and within a screen of the
  /// content, so the board can't be lost off-screen.
  Offset _clampPan(Offset o, double s) {
    if (_size.isEmpty) return o;
    final half = _size.center(Offset.zero);
    final c = (half - o) / s;
    var area = const Rect.fromLTRB(-worldLimit, -worldLimit, worldLimit, worldLimit);
    final content = _content;
    if (content != null) {
      final reach = content.inflate(math.max(_size.width, _size.height) / s);
      area = Rect.fromLTRB(
        math.max(area.left, reach.left),
        math.max(area.top, reach.top),
        math.min(area.right, reach.right),
        math.min(area.bottom, reach.bottom),
      );
    }
    if (area.isEmpty) return o;
    final cx = c.dx.clamp(area.left, area.right).toDouble();
    final cy = c.dy.clamp(area.top, area.bottom).toDouble();
    if (cx == c.dx && cy == c.dy) return o;
    return half - Offset(cx, cy) * s;
  }

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }
}
