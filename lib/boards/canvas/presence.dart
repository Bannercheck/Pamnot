import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/pamnot_theme.dart';
import '../connection.dart';
import 'board_text.dart';
import 'item_painter.dart';
import 'viewport.dart';

/// One teammate's pointer as drawn: eased toward the latest sample.
class PeerDot {
  PeerDot(this.key, this.position);

  final String key;
  Offset position;
  Offset target = Offset.zero;
  String name = '';
  int colorIndex = 0;
  bool pointer = true;

  /// When the latest sample arrived (local clock).
  Duration seen = Duration.zero;
  double opacity = 1;
}

/// Teammates' cursors on the canvas, smoothed with τ = 60 ms by a ticker
/// that stops once every cursor has settled, and faded out 10 s after a
/// cursor stops moving. Only peers whose view is the canvas are shown.
class PresenceModel extends ChangeNotifier {
  PresenceModel({required this.vsync, required this.viewport, Duration Function()? clock})
    : _clock = clock ?? _stopwatchClock() {
    _ticker = vsync.createTicker(_tick);
  }

  static Duration Function() _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  static const tau = Duration(milliseconds: 60);
  static const fadeAfter = Duration(seconds: 10);
  static const fadeFor = Duration(milliseconds: 300);

  final TickerProvider vsync;
  final BoardViewport viewport;
  final Duration Function() _clock;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Timer? _fadeTimer;
  BoardConnection? _conn;
  final Map<String, PeerDot> _dots = {};

  Iterable<PeerDot> get dots => _dots.values;
  bool get animating => _ticker.isActive;

  void attach(BoardConnection c) {
    final old = _conn;
    if (identical(old, c)) return;
    old?.cursors.removeListener(_onCursors);
    old?.peers.removeListener(_onCursors);
    _conn = c;
    c.cursors.addListener(_onCursors);
    c.peers.addListener(_onCursors);
    _dots.clear();
    _onCursors();
  }

  void _onCursors() {
    final c = _conn;
    if (c == null) return;
    final onCanvas = {
      for (final p in c.peers.value)
        if (p.view == 'canvas') p.key,
    };
    final knownPeers = c.peers.value.isNotEmpty;
    final now = _clock();
    final live = <String>{};
    for (final cur in c.cursors.value.values) {
      // A peer looking at Kanban has no meaningful canvas position.
      if (knownPeers && !onCanvas.contains(cur.key)) continue;
      live.add(cur.key);
      final d = _dots[cur.key];
      if (d == null) {
        _dots[cur.key] = PeerDot(cur.key, cur.position)
          ..target = cur.position
          ..name = cur.name
          ..colorIndex = cur.colorIndex
          ..pointer = cur.pointer
          ..seen = now;
      } else {
        if (d.target != cur.position) {
          d
            ..target = cur.position
            ..seen = now
            ..opacity = 1;
        }
        d
          ..name = cur.name
          ..colorIndex = cur.colorIndex
          ..pointer = cur.pointer;
      }
    }
    _dots.removeWhere((k, _) => !live.contains(k));
    _wake();
    notifyListeners();
  }

  void _wake() {
    if (_dots.isEmpty) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    advance(dt);
  }

  /// One smoothing step of [dt] seconds; public for tests.
  @visibleForTesting
  void advance(double dt) {
    final k = 1 - math.exp(-dt / (tau.inMicroseconds / 1e6));
    final now = _clock();
    final s = viewport.scale;
    var busy = false;
    Duration? nextFade;
    for (final d in _dots.values) {
      final gap = d.target - d.position;
      if (gap.distance * s < 0.5) {
        d.position = d.target;
      } else {
        d.position += gap * k;
        busy = true;
      }
      final age = now - d.seen;
      if (age > fadeAfter) {
        d.opacity = (1 - (age - fadeAfter).inMicroseconds / fadeFor.inMicroseconds).clamp(0.0, 1.0);
        if (d.opacity > 0) busy = true;
      } else {
        final left = fadeAfter - age;
        if (nextFade == null || left < nextFade) nextFade = left;
      }
    }
    notifyListeners();
    if (!busy && _ticker.isActive) {
      _ticker.stop();
      _fadeTimer?.cancel();
      if (nextFade != null) {
        _fadeTimer = Timer(nextFade + const Duration(milliseconds: 16), _wake);
      }
    }
  }

  @override
  void dispose() {
    _conn?.cursors.removeListener(_onCursors);
    _conn?.peers.removeListener(_onCursors);
    _fadeTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}

/// Teammates' cursors in screen space at a constant size: an arrow (mouse
/// or stylus) or a ring (touch) in the peer's colour, with a name pill.
class PresencePainter extends CustomPainter {
  PresencePainter(this.model, this.viewport, this.palette, this.labels)
    : super(repaint: Listenable.merge([model, viewport]));

  final PresenceModel model;
  final BoardViewport viewport;
  final BoardPalette palette;
  final BoardTextCache labels;

  static final Path _arrow = Path()
    ..moveTo(0, 0)
    ..lineTo(0, 17)
    ..lineTo(4.6, 12.8)
    ..lineTo(8, 20)
    ..lineTo(10.6, 18.8)
    ..lineTo(7.4, 11.8)
    ..lineTo(13.4, 11.4)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).inflate(40);
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final d in model.dots) {
      if (d.opacity <= 0) continue;
      final p = viewport.toScreen(d.position);
      if (!bounds.contains(p)) continue;
      final accent = pastelAt(d.colorIndex).accent;
      final a = d.opacity;
      if (d.pointer) {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        fill.color = accent.withValues(alpha: a);
        canvas.drawPath(_arrow, fill);
        line.color = palette.halo.withValues(alpha: a);
        canvas.drawPath(_arrow, line);
        canvas.restore();
      } else {
        line
          ..color = accent.withValues(alpha: a)
          ..strokeWidth = 3;
        canvas.drawCircle(p, 6, line);
        line.strokeWidth = 1.5;
      }
      final name = d.name;
      if (name.isEmpty) continue;
      final tp = labels.obtain(
        'p:${d.key}',
        name,
        11,
        palette.text,
        () =>
            boardPainter(name, boardText(11, palette.text, weight: FontWeight.w700), maxLines: 1, strut: false)
              ..layout(maxWidth: 160),
        force: true,
      )!;
      final at = p + const Offset(14, 18);
      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx, at.dy, tp.width + 14, tp.height + 6),
        const Radius.circular(10),
      );
      fill.color = pastelAt(d.colorIndex).paper(palette.brightness).withValues(alpha: a);
      canvas.drawRRect(pill, fill);
      line.color = accent.withValues(alpha: a);
      canvas.drawRRect(pill, line);
      // While fading, the name goes first (no saveLayer for translucent text).
      if (a >= 0.6) tp.paint(canvas, at + const Offset(7, 3));
    }
  }

  @override
  bool shouldRepaint(PresencePainter old) => old.model != model || old.viewport != viewport || old.palette != palette;
}
