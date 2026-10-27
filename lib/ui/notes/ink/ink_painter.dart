import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../../models/ink.dart';

final _paths = Expando<Path>('inkPath');

/// The filled outline of a stroke in page units, computed once per stroke.
Path strokePath(InkStroke s) => _paths[s] ??= buildStrokePath(
      [for (var i = 0; i < s.length; i++) pf.PointVector(s.x(i), s.y(i), s.hasPressure ? s.pressure(i) : null)],
      width: s.width,
      tool: s.tool,
      hasPressure: s.hasPressure,
      complete: true,
    );

Path buildStrokePath(
  List<pf.PointVector> points, {
  required double width,
  required InkTool tool,
  required bool hasPressure,
  required bool complete,
}) {
  final path = Path();
  if (points.isEmpty) return path;
  final highlighter = tool == InkTool.highlighter;
  final outline = pf.getStroke(
    points,
    options: pf.StrokeOptions(
      size: width,
      thinning: highlighter ? 0 : (hasPressure ? 0.62 : 0.5),
      smoothing: 0.55,
      streamline: hasPressure ? 0.35 : 0.5,
      simulatePressure: !highlighter && !hasPressure,
      isComplete: complete,
    ),
  );
  if (outline.length < 3) {
    return path..addOval(Rect.fromCircle(center: points.first, radius: width / 2));
  }
  path.moveTo(outline.first.dx, outline.first.dy);
  for (var i = 1; i < outline.length - 1; i++) {
    final p = outline[i], q = outline[i + 1];
    path.quadraticBezierTo(p.dx, p.dy, (p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
  }
  path.close();
  return path;
}

Paint strokePaint(int argb, InkTool tool) {
  final color = Color(argb);
  return Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = tool == InkTool.highlighter ? color.withValues(alpha: 0.42) : color;
}

void paintStroke(Canvas canvas, InkStroke s) => canvas.drawPath(strokePath(s), strokePaint(s.color, s.tool));

/// Remembers the last rendered stroke list as a [ui.Picture]. Adding a stroke
/// records only that stroke on top of the old picture, so a page with
/// thousands of strokes stays as fast as an empty one.
class InkPictureCache {
  List<InkStroke> _strokes = const [];
  ui.Picture? _picture;

  /// Appends since the last full recording; past a limit the picture is
  /// re-recorded flat so nested pictures don't pile up.
  int _depth = 0;
  static const _maxDepth = 40;

  ui.Picture pictureFor(List<InkStroke> strokes) {
    final old = _picture;
    if (old != null && identical(strokes, _strokes)) return old;
    final appended = old != null &&
        _depth < _maxDepth &&
        _strokes.isNotEmpty &&
        strokes.length > _strokes.length &&
        identical(strokes.first, _strokes.first) &&
        identical(strokes[_strokes.length - 1], _strokes.last);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (appended) {
      canvas.drawPicture(old);
      for (var i = _strokes.length; i < strokes.length; i++) {
        paintStroke(canvas, strokes[i]);
      }
    } else {
      for (final s in strokes) {
        paintStroke(canvas, s);
      }
    }
    _depth = appended ? _depth + 1 : 0;
    old?.dispose();
    _strokes = strokes;
    return _picture = recorder.endRecording();
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }
}

class StrokesPainter extends CustomPainter {
  StrokesPainter({required this.strokes, required this.scale, required this.cache});

  final List<InkStroke> strokes;
  final double scale;
  final InkPictureCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.drawPicture(cache.pictureFor(strokes));
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokesPainter old) => !identical(old.strokes, strokes) || old.scale != scale;
}

/// The stroke under the pen right now. Repaints on its own, without
/// rebuilding any widget.
class ActiveStroke {
  ActiveStroke({required this.color, required this.width, required this.tool, required this.hasPressure});

  final int color;
  final double width;
  final InkTool tool;
  final bool hasPressure;
  final List<pf.PointVector> points = [];
}

/// Holds the in-progress stroke and pings its painter on every new point.
class ActiveInk extends ChangeNotifier {
  ActiveStroke? stroke;

  void start(ActiveStroke s) {
    stroke = s;
    notifyListeners();
  }

  void addPoint(pf.PointVector p) {
    stroke?.points.add(p);
    notifyListeners();
  }

  void end() {
    stroke = null;
    notifyListeners();
  }
}

class ActiveStrokePainter extends CustomPainter {
  ActiveStrokePainter({required this.active, required this.scale}) : super(repaint: active);

  final ActiveInk active;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final a = active.stroke;
    if (a == null || a.points.isEmpty) return;
    canvas.save();
    canvas.scale(scale);
    canvas.drawPath(
      buildStrokePath(a.points, width: a.width, tool: a.tool, hasPressure: a.hasPressure, complete: false),
      strokePaint(a.color, a.tool),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ActiveStrokePainter old) => old.scale != scale || old.active != active;
}

class PaperPainter extends CustomPainter {
  PaperPainter({required this.style, required this.color, required this.lineColor, required this.scale});

  final PaperStyle style;
  final Color color;
  final Color lineColor;
  final double scale;

  static const spacing = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final step = spacing * scale;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    switch (style) {
      case PaperStyle.blank:
        break;
      case PaperStyle.lined:
        for (var y = step * 2; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case PaperStyle.grid:
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
      case PaperStyle.dotted:
        final dot = Paint()..color = lineColor.withValues(alpha: (lineColor.a * 1.8).clamp(0, 1));
        for (var y = step; y < size.height; y += step) {
          for (var x = step; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.4, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.style != style || old.color != color || old.lineColor != lineColor || old.scale != scale;
}

/// Small, scaled-down preview of a page for note cards.
class InkThumbnailPainter extends CustomPainter {
  InkThumbnailPainter(this.strokes);

  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / kPageWidth);
    final visibleBottom = size.height / (size.width / kPageWidth);
    for (final s in strokes) {
      if (s.bounds.top > visibleBottom) continue;
      paintStroke(canvas, s);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(InkThumbnailPainter old) => !identical(old.strokes, strokes);
}
