import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../../models/ink.dart';
import 'ink_controller.dart';
import 'ink_painter.dart';

/// A scrolling page you write on with Apple Pencil, a stylus, a mouse or a
/// finger.
///
/// With [stylusOnly] (palm rejection) only the pencil draws and fingers
/// scroll. Otherwise fingers draw too and the hand tool scrolls. The eraser
/// end of a stylus erases whatever tool is selected.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.controller,
    required this.paper,
    required this.paperColor,
    required this.stylusOnly,
    this.onStylusDetected,
    this.bottomInset = 0,
  });

  final InkController controller;
  final PaperStyle paper;
  final Color paperColor;
  final bool stylusOnly;
  final VoidCallback? onStylusDetected;

  /// Space kept free at the bottom for the floating toolbar.
  final double bottomInset;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  final _cache = InkPictureCache();
  final _active = ActiveInk();
  final _scroll = ScrollController();

  int? _pointer;
  bool _erasing = false;
  final List<double> _buf = [];
  int _t0 = 0;
  int _t0Epoch = 0;
  double _scale = 1;
  bool _sawStylus = false;

  /// Page grows while you write near its bottom edge.
  double _grow = 0;

  static const _eraserRadius = 14.0;

  @override
  void dispose() {
    _cache.dispose();
    _active.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _isStylus(PointerDeviceKind k) => k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  bool _draws(PointerDownEvent e) {
    final tool = widget.controller.tool;
    if (tool == CanvasTool.hand) return false;
    return switch (e.kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.touch => !widget.stylusOnly,
      PointerDeviceKind.mouse => e.buttons == kPrimaryButton,
      _ => false,
    };
  }

  Set<PointerDeviceKind> get _dragDevices {
    if (widget.controller.tool == CanvasTool.hand) {
      return {...PointerDeviceKind.values}..remove(PointerDeviceKind.unknown);
    }
    return widget.stylusOnly
        ? {PointerDeviceKind.touch, PointerDeviceKind.trackpad}
        : {PointerDeviceKind.trackpad};
  }

  Offset _page(Offset local) => local / _scale;

  double _pressure(PointerEvent e) {
    if (!_isStylus(e.kind) || e.pressureMax <= e.pressureMin) return 0.5;
    final n = ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
    // Apple Pencil reports light everyday pressure as small values; lift it.
    return math.pow(n, 0.6).toDouble().clamp(0.08, 1.0);
  }

  void _down(PointerDownEvent e) {
    if (_isStylus(e.kind) && !_sawStylus) {
      _sawStylus = true;
      widget.onStylusDetected?.call();
    }
    if (_pointer != null || !_draws(e)) return;
    _pointer = e.pointer;
    final c = widget.controller;
    if (e.kind == PointerDeviceKind.invertedStylus || c.tool == CanvasTool.eraser) {
      _erasing = true;
      c.beginErase();
      c.eraseAt(_page(e.localPosition), _eraserRadius);
      return;
    }
    final highlighter = c.tool == CanvasTool.highlighter;
    final hasPressure = _isStylus(e.kind) && e.pressureMax > e.pressureMin && !highlighter;
    _t0 = e.timeStamp.inMilliseconds;
    _t0Epoch = DateTime.now().millisecondsSinceEpoch;
    _buf.clear();
    _active.start(ActiveStroke(
      color: c.activeColor.toARGB32(),
      width: highlighter ? 22 : c.penWidth,
      tool: highlighter ? InkTool.highlighter : InkTool.pen,
      hasPressure: hasPressure,
    ));
    _addPoint(e);
  }

  void _addPoint(PointerEvent e) {
    final a = _active.stroke;
    if (a == null) return;
    final p = _page(e.localPosition);
    if (_buf.length >= 4) {
      final dx = p.dx - _buf[_buf.length - 4], dy = p.dy - _buf[_buf.length - 3];
      // Skip sub-pixel jitter; it only adds weight to the stroke.
      if (dx * dx + dy * dy < 0.25) return;
    }
    final pressure = _pressure(e);
    _buf.addAll([p.dx, p.dy, pressure, (e.timeStamp.inMilliseconds - _t0).toDouble()]);
    _active.addPoint(pf.PointVector(p.dx, p.dy, a.hasPressure ? pressure : null));
    _maybeGrow(p.dy);
  }

  void _maybeGrow(double y) {
    final extent = _pageHeight(0) - 260;
    if (y > extent) setState(() => _grow += 600);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_erasing) {
      widget.controller.eraseAt(_page(e.localPosition), _eraserRadius);
      return;
    }
    _addPoint(e);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_erasing) {
      _erasing = false;
      widget.controller.endErase();
      return;
    }
    final a = _active.stroke;
    if (a == null || _buf.isEmpty) {
      _active.end();
      return;
    }
    widget.controller.add(InkStroke(
      data: Float32List.fromList(_buf),
      color: a.color,
      width: a.width,
      tool: a.tool,
      hasPressure: a.hasPressure,
      startedAt: _t0Epoch,
    ));
    // Cleared after the stroke is committed so there is no blank frame.
    _active.end();
    _buf.clear();
  }

  double _viewport = 0;

  double _pageHeight(double minimum) =>
      math.max(math.max(minimum, _viewport / _scale), inkExtent(widget.controller.strokes) + 520 + _grow);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(builder: (context, cons) {
      final wide = cons.maxWidth > 700;
      final pageW = math.min(cons.maxWidth - (wide ? 48 : 0), 940.0);
      _scale = pageW / kPageWidth;
      _viewport = cons.maxHeight;
      return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final strokes = widget.controller.strokes;
          final height = _pageHeight(0) * _scale + widget.bottomInset;
          final page = SizedBox(
            width: pageW,
            height: height,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: PaperPainter(
                        style: widget.paper,
                        color: widget.paperColor,
                        lineColor: t.colorScheme.primary.withValues(alpha: t.brightness == Brightness.dark ? 0.16 : 0.13),
                        scale: _scale,
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(painter: StrokesPainter(strokes: strokes, scale: _scale, cache: _cache)),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(painter: ActiveStrokePainter(active: _active, scale: _scale)),
                  ),
                ],
              ),
            ),
          );
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: _dragDevices, scrollbars: wide),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.symmetric(vertical: wide ? 20 : 0),
              child: Center(
                child: wide
                    ? Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: t.colorScheme.shadow.withValues(alpha: t.brightness == Brightness.dark ? 0.3 : 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(borderRadius: BorderRadius.circular(20), child: page),
                      )
                    : page,
              ),
            ),
          );
        },
      );
    });
  }
}
