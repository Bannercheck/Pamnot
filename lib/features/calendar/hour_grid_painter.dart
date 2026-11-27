import 'package:flutter/widgets.dart';

/// Hour lines, hour labels and the "now" line of a time grid, in one layer.
///
/// The labels sit in a gutter on the left; the lines run from the gutter to
/// the right edge. Minute `m` is at `inset + m / 60 * hourHeight` (see
/// [HourGridPainter.metrics]), so cards placed by the same formula line up.
class HourGridPainter extends CustomPainter {
  HourGridPainter({
    required this.hourHeight,
    required this.lineColor,
    required this.labelStyle,
    required this.labels,
    this.nowMinute,
    required this.nowColor,
  });

  final double hourHeight;
  final Color lineColor;

  /// Already scaled to the text size.
  final TextStyle labelStyle;

  /// One label per hour line, from 00:00 to 24:00.
  final List<String> labels;

  /// Minute of the day of the "now" line; null when the day is not today.
  final double? nowMinute;
  final Color nowColor;

  /// The gutter width the labels need and the top (and bottom) inset that
  /// keeps the first and last label inside the grid.
  static ({double gutter, double inset}) metrics(List<String> labels, TextStyle labelStyle) {
    final painters = _layoutAll(labels, labelStyle);
    final m = _metricsOf(painters);
    for (final tp in painters) {
      tp.dispose();
    }
    return m;
  }

  static List<TextPainter> _layoutAll(List<String> labels, TextStyle style) => [
        for (final l in labels)
          TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, maxLines: 1)
            ..layout(),
      ];

  static ({double gutter, double inset}) _metricsOf(List<TextPainter> painters) {
    var width = 0.0, height = 0.0;
    for (final tp in painters) {
      if (tp.width > width) width = tp.width;
      if (tp.height > height) height = tp.height;
    }
    return (gutter: width + 12, inset: height / 2 + 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final painters = _layoutAll(labels, labelStyle);
    final m = _metricsOf(painters);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var h = 0; h < painters.length; h++) {
      final y = m.inset + h * hourHeight;
      final tp = painters[h];
      canvas.drawLine(Offset(m.gutter, y), Offset(size.width, y), line);
      tp.paint(canvas, Offset(m.gutter - 6 - tp.width, y - tp.height / 2));
      tp.dispose();
    }
    final now = nowMinute;
    if (now != null) {
      final y = m.inset + now / 60 * hourHeight;
      final p = Paint()
        ..color = nowColor
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(m.gutter, y), 4, p);
      canvas.drawLine(Offset(m.gutter, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(HourGridPainter old) =>
      old.hourHeight != hourHeight ||
      old.lineColor != lineColor ||
      old.labelStyle != labelStyle ||
      old.nowMinute != nowMinute ||
      old.nowColor != nowColor ||
      !_sameLabels(old.labels, labels);

  static bool _sameLabels(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The hour labels 00:00 … 24:00.
final hourLabels = List<String>.unmodifiable([for (var h = 0; h <= 24; h++) '${h.toString().padLeft(2, '0')}:00']);

/// The hour height for the current text size: 56 pt × text scale, the scale
/// clipped to 1.0–1.6.
double hourHeightFor(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return 56 * scale.clamp(1.0, 1.6);
}

/// The style of the hour labels, scaled to the text size.
TextStyle hourLabelStyle(BuildContext context, TextStyle base) {
  final size = base.fontSize ?? 12;
  return base.copyWith(fontSize: MediaQuery.textScalerOf(context).scale(size));
}

/// Cards are built only for this many minutes above and below what shows.
const lazyMarginMinutes = 120;

/// The minute window whose cards are built for a viewport showing
/// [offset] .. [offset] + [viewport] of a grid: what shows, ± [lazyMarginMinutes],
/// widened to whole hours so it changes only once an hour of scrolling.
(double, double) cardWindow({
  required double offset,
  required double viewport,
  required double hourHeight,
  required double inset,
}) {
  final first = (offset - inset) / hourHeight * 60;
  final last = (offset + viewport - inset) / hourHeight * 60;
  final from = ((first - lazyMarginMinutes) / 60).floorToDouble() * 60;
  final to = ((last + lazyMarginMinutes) / 60).ceilToDouble() * 60;
  return (from, to);
}

/// The scroll offset that puts [minute]'s line (with its label) at the top
/// of the viewport, clamped to the grid.
double initialGridOffset({
  required double minute,
  required double hourHeight,
  required double inset,
  required double viewport,
}) {
  final total = 2 * inset + 24 * hourHeight;
  final y = minute / 60 * hourHeight;
  final max = total - viewport;
  return y.clamp(0, max < 0 ? 0 : max).toDouble();
}
