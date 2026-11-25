import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// What a guide step's drawing shows.
enum GuideScene { shortcut, actionButton, backTap, outlook }

/// A phone frame and a hand (a fingertip circle with a tap wave) that moves
/// to the scene's target and taps it: the "+" in Shortcuts, the Action button
/// on the upper left side, a double tap on the back, the account row in
/// Calendar settings. Drawn with a [CustomPainter] in the theme's colours; it
/// holds no text and is hidden from screen readers (the numbered lines say
/// the same).
///
/// [progress] 0..1 is one round; at 1 the hand rests on the target, which is
/// the still frame shown when the user asked for less motion. Without it the
/// widget loops a round every six seconds.
class PhoneHandAnimation extends StatelessWidget {
  const PhoneHandAnimation({super.key, required this.scene, this.progress});

  final GuideScene scene;
  final double? progress;

  /// The length of one round when the widget loops by itself.
  static const period = Duration(seconds: 6);

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return ExcludeSemantics(
      child: p == null
          ? _Looping(scene: scene)
          : CustomPaint(
              painter: PhoneHandPainter(scene: scene, progress: p, colors: Theme.of(context).colorScheme),
              size: Size.infinite,
            ),
    );
  }
}

class _Looping extends StatefulWidget {
  const _Looping({required this.scene});

  final GuideScene scene;

  @override
  State<_Looping> createState() => _LoopingState();
}

class _LoopingState extends State<_Looping> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: PhoneHandAnimation.period)
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: PhoneHandPainter(
            scene: widget.scene,
            progress: _controller.value,
            colors: Theme.of(context).colorScheme,
          ),
          size: Size.infinite,
        ),
      );
}

/// Paints one frame of [PhoneHandAnimation].
///
/// A round: the hand travels to the target (0 to 0.4), taps it with a
/// spreading wave (0.4 to 0.6; twice on the back for Back Tap), then rests on
/// it while the target stays highlighted (0.6 to 1).
class PhoneHandPainter extends CustomPainter {
  PhoneHandPainter({required this.scene, required double progress, required this.colors})
      : progress = progress.clamp(0.0, 1.0);

  final GuideScene scene;
  final double progress;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // The phone: about half as wide as tall, centred.
    final h = size.height * 0.92;
    final w = math.min(h * 0.5, size.width * 0.9);
    final phone = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
    final frame = RRect.fromRectAndRadius(phone, Radius.circular(w * 0.18));
    final screen = RRect.fromRectAndRadius(phone.deflate(w * 0.06), Radius.circular(w * 0.13));

    final outline = Paint()
      ..color = colors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(frame, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawRRect(screen, Paint()..color = colors.surface);
    canvas.drawRRect(frame, outline);

    final lit = _highlight;
    final target = _drawScene(canvas, phone, screen.outerRect, lit);
    _drawHand(canvas, size, target);
  }

  /// How strongly the target is highlighted: from the tap on.
  double get _highlight => Curves.easeOut.transform(((progress - 0.4) / 0.2).clamp(0.0, 1.0));

  /// Draws the scene's content and answers where the hand taps.
  Offset _drawScene(Canvas canvas, Rect phone, Rect screen, double lit) {
    final line = Paint()..color = colors.outlineVariant;
    final accent = Paint()..color = colors.primary;
    final soft = Paint()..color = Color.lerp(colors.surfaceContainerHigh, colors.primaryContainer, lit)!;
    final u = screen.width;

    Rect row(int i, {double top = 0.18, double gap = 0.13}) => Rect.fromLTWH(
          screen.left + u * 0.1,
          screen.top + screen.height * (top + gap * i),
          u * 0.8,
          screen.height * 0.08,
        );

    switch (scene) {
      case GuideScene.shortcut:
        // The "+" at the top right and a list of shortcut tiles.
        final plus = Offset(screen.right - u * 0.18, screen.top + screen.height * 0.1);
        canvas.drawCircle(plus, u * 0.1 * (1 + 0.2 * lit), soft);
        final cross = Paint()
          ..color = colors.primary
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(plus.translate(-u * 0.05, 0), plus.translate(u * 0.05, 0), cross);
        canvas.drawLine(plus.translate(0, -u * 0.05), plus.translate(0, u * 0.05), cross);
        for (var i = 0; i < 4; i++) {
          final r = row(i, top: 0.24, gap: 0.16);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width, r.height * 1.4), Radius.circular(u * 0.04)),
            i == 0 ? (Paint()..color = Color.lerp(colors.surfaceContainerHigh, colors.primary, 0.35 * lit)!) : line,
          );
        }
        return plus;
      case GuideScene.actionButton:
        // The side button on the upper left edge.
        final button = Rect.fromLTWH(phone.left - u * 0.07, phone.top + phone.height * 0.16, u * 0.07, phone.height * 0.1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(button.inflate(u * 0.02 * lit), Radius.circular(u * 0.03)),
          Paint()..color = Color.lerp(colors.outline, colors.primary, lit)!,
        );
        for (var i = 0; i < 4; i++) {
          canvas.drawRRect(RRect.fromRectAndRadius(row(i), Radius.circular(u * 0.03)), line);
        }
        return button.center;
      case GuideScene.backTap:
        // A double tap on the back: two rings spreading from the centre.
        final c = screen.center;
        for (var i = 0; i < 4; i++) {
          canvas.drawRRect(RRect.fromRectAndRadius(row(i, top: 0.12, gap: 0.22), Radius.circular(u * 0.03)), line);
        }
        for (final start in [0.4, 0.5]) {
          final t = ((progress - start) / 0.25).clamp(0.0, 1.0);
          if (t <= 0 || t >= 1) continue;
          canvas.drawCircle(
            c,
            lerpDouble(u * 0.1, u * 0.45, t)!,
            Paint()
              ..color = colors.primary.withValues(alpha: 1 - t)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        canvas.drawCircle(c, u * 0.12, Paint()..color = colors.primaryContainer.withValues(alpha: lit));
        return c;
      case GuideScene.outlook:
        // Account rows in Calendar settings; the third one is the target.
        late Rect target;
        for (var i = 0; i < 5; i++) {
          final r = row(i, top: 0.14, gap: 0.15);
          final rr = RRect.fromRectAndRadius(r, Radius.circular(u * 0.03));
          if (i == 2) {
            target = r;
            canvas.drawRRect(rr.inflate(u * 0.03), soft);
            canvas.drawCircle(Offset(r.left + r.height / 2, r.center.dy), r.height / 2, accent);
          } else {
            canvas.drawRRect(rr, line);
          }
        }
        return target.center;
    }
  }

  void _drawHand(Canvas canvas, Size size, Offset target) {
    // From below and outside the phone towards the target.
    final from = Offset(size.width * 0.85, size.height * 1.05);
    final travel = Curves.easeInOut.transform((progress / 0.4).clamp(0.0, 1.0));
    final at = Offset.lerp(from, target, travel)!;
    final tip = size.shortestSide * 0.07;

    // The tap wave, once (twice on the back for Back Tap).
    final taps = scene == GuideScene.backTap ? [0.4, 0.5] : [0.4];
    for (final start in taps) {
      final t = ((progress - start) / 0.2).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      canvas.drawCircle(
        at,
        tip * (1 + 1.6 * t),
        Paint()
          ..color = colors.primary.withValues(alpha: 0.8 * (1 - t))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    // The fingertip presses in a little while it taps.
    final press = progress > 0.4 && progress < 0.6 ? 0.85 : 1.0;
    canvas.drawCircle(at, tip * press, Paint()..color = colors.primary.withValues(alpha: 0.35));
    canvas.drawCircle(
      at,
      tip * press,
      Paint()
        ..color = colors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(PhoneHandPainter old) =>
      old.scene != scene || old.progress != progress || old.colors != colors;
}
