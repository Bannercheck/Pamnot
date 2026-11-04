import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../models/ink.dart';
import '../../ui/notes/ink/ink_painter.dart';
import 'viewport.dart';

/// Builds stroke outlines (perfect_freehand) off the first frame: a few
/// milliseconds per frame from a queue, so opening a board with thousands
/// of strokes never freezes. Strokes still in the queue are drawn as
/// polylines.
class InkOutlines extends ChangeNotifier {
  InkOutlines({this.budget = const Duration(milliseconds: 3)});

  final Duration budget;
  final Expando<Path> _ready = Expando('boardInkOutline');
  final LinkedHashSet<InkStroke> _queue = LinkedHashSet.identity();
  bool _scheduled = false;
  bool _disposed = false;
  int _settled = 0;

  /// Bumped when the queue runs dry, so cached overview pictures re-record
  /// once with real outlines instead of once per frame while building.
  int get settledRevision => _settled;

  bool get busy => _queue.isNotEmpty;

  /// The outline if built; otherwise queues it and returns null.
  Path? pathOf(InkStroke s) {
    final p = _ready[s];
    if (p != null) return p;
    if (_queue.add(s)) _schedule();
    return null;
  }

  /// Builds now (a stroke just drawn here, so it never flashes as a
  /// polyline).
  Path buildNow(InkStroke s) {
    final p = _ready[s] ??= strokePath(s);
    _queue.remove(s);
    return p;
  }

  /// Builds queued outlines for up to [limit]; true when something was
  /// built. Public so headless tests can drain the queue.
  bool pump([Duration? limit]) {
    final sw = Stopwatch()..start();
    final max = limit ?? budget;
    var built = false;
    while (_queue.isNotEmpty && sw.elapsed < max) {
      final s = _queue.first;
      _queue.remove(s);
      _ready[s] ??= strokePath(s);
      built = true;
    }
    if (built && _queue.isEmpty) _settled++;
    return built;
  }

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      if (pump()) notifyListeners();
      if (_queue.isNotEmpty) _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    super.dispose();
  }
}

/// Paints for ink, cached per colour and tool.
class InkPaints {
  final Map<int, Paint> _fill = {};
  final Map<int, Paint> _line = {};

  Paint fill(InkStroke s) => _fill[s.color ^ (s.tool.index << 31)] ??= strokePaint(s.color, s.tool);

  /// Round-capped polyline for strokes whose outline is not built yet.
  Paint line(InkStroke s) {
    final key = s.color ^ (s.tool.index << 31) ^ (s.width * 64).round() << 1;
    return _line[key] ??= Paint()
      ..color = strokePaint(s.color, s.tool).color
      ..strokeWidth = s.width * 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
  }
}

/// Draws [stroke] (points relative to [origin]) with its outline when built,
/// else as a polyline.
void paintInk(
  Canvas canvas,
  InkStroke stroke,
  Float32List? polyline,
  Offset origin,
  InkOutlines outlines,
  InkPaints paints,
) {
  final path = outlines.pathOf(stroke);
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  if (path != null) {
    canvas.drawPath(path, paints.fill(stroke));
  } else if (polyline != null && polyline.length >= 4) {
    canvas.drawRawPoints(ui.PointMode.polygon, polyline, paints.line(stroke));
  } else if (polyline != null && polyline.length == 2) {
    canvas.drawCircle(Offset(polyline[0], polyline[1]), stroke.width / 2, paints.fill(stroke));
  }
  canvas.restore();
}

/// The stroke under the pen, in canvas coordinates; repaints on its own on
/// every point and viewport change.
class BoardActiveStrokePainter extends CustomPainter {
  BoardActiveStrokePainter(this.active, this.viewport) : super(repaint: Listenable.merge([active, viewport]));

  final ActiveInk active;
  final BoardViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final a = active.stroke;
    if (a == null || a.points.isEmpty) return;
    canvas.save();
    canvas.transform(viewport.matrix);
    canvas.drawPath(
      buildStrokePath(a.points, width: a.width, tool: a.tool, hasPressure: a.hasPressure, complete: false),
      strokePaint(a.color, a.tool),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardActiveStrokePainter old) => old.active != active || old.viewport != viewport;
}
