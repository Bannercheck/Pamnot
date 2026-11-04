import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The one text style of the canvas. The painter and the in-place editor
/// share it (with a forced strut and no text scaling) so text never reflows
/// when an edit starts or ends, and lays out the same on every device.
TextStyle boardText(double size, Color color, {FontWeight weight = FontWeight.w600}) => TextStyle(
  fontFamily: 'Nunito',
  fontSize: size,
  fontWeight: weight,
  height: 1.3,
  leadingDistribution: TextLeadingDistribution.even,
  color: color,
);

StrutStyle boardStrut(double size, {FontWeight weight = FontWeight.w600}) =>
    StrutStyle(fontFamily: 'Nunito', fontSize: size, fontWeight: weight, height: 1.3, forceStrutHeight: true);

TextPainter boardPainter(String text, TextStyle style, {int? maxLines, bool strut = true}) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
  maxLines: maxLines,
  ellipsis: maxLines == null ? null : '…',
  strutStyle: strut ? boardStrut(style.fontSize ?? 14, weight: style.fontWeight ?? FontWeight.w600) : null,
);

/// Sticky geometry: fixed 200 × 200 in v1, text fitted from 28 down to 12.
abstract final class StickyMetrics {
  static const size = 200.0;
  static const pad = 16.0;
  static const inner = size - 2 * pad;
  static const maxFont = 28;
  static const minFont = 12;
  static const radius = 8.0;
}

/// The largest font size (28 → 12) at which [text] fits a sticky, and its
/// laid-out painter. Below 12 the text is cut with an ellipsis.
(double, TextPainter) fitStickyText(String text, Color color) {
  bool fits(TextPainter tp) => tp.height <= StickyMetrics.inner + 0.5;
  TextPainter lay(int f, {int? maxLines}) =>
      boardPainter(text, boardText(f.toDouble(), color), maxLines: maxLines)..layout(maxWidth: StickyMetrics.inner);

  var lo = StickyMetrics.minFont, hi = StickyMetrics.maxFont;
  TextPainter? best;
  var bestSize = 0;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    final tp = lay(mid);
    if (fits(tp)) {
      best?.dispose();
      best = tp;
      bestSize = mid;
      lo = mid;
    } else {
      tp.dispose();
      hi = mid - 1;
    }
  }
  if (best != null && bestSize == lo) return (lo.toDouble(), best);
  best?.dispose();
  final first = lay(lo);
  if (fits(first)) return (lo.toDouble(), first);
  first.dispose();
  final lines = (StickyMetrics.inner / (1.3 * lo)).floor();
  return (lo.toDouble(), lay(lo, maxLines: lines < 1 ? 1 : lines));
}

/// A guess of the fitted size, for greek bars before (or instead of) layout.
double estimateStickyFont(String text) {
  if (text.isEmpty) return StickyMetrics.maxFont.toDouble();
  for (var f = StickyMetrics.maxFont; f > StickyMetrics.minFont; f -= 2) {
    final perLine = (StickyMetrics.inner / (0.52 * f)).floor();
    var lines = 0;
    for (final l in text.split('\n')) {
      lines += l.isEmpty ? 1 : (l.length / perLine).ceil();
    }
    if (lines * 1.3 * f <= StickyMetrics.inner) return f.toDouble();
  }
  return StickyMetrics.minFont.toDouble();
}

/// Line widths of a guess at how [text] wraps at [size] in [width].
List<double> estimateLines(String text, double size, double width, {int maxLines = 99}) {
  final perLine = (width / (0.52 * size)).floor().clamp(1, 1000);
  final out = <double>[];
  for (final l in text.split('\n')) {
    var n = l.length;
    if (n == 0) {
      out.add(0);
    }
    while (n > 0) {
      final take = n > perLine ? perLine : n;
      out.add(take * 0.52 * size);
      n -= take;
      if (out.length >= maxLines) return out;
    }
    if (out.length >= maxLines) return out;
  }
  return out;
}

class _TextEntry {
  _TextEntry(this.text, this.size, this.color, this.painter);

  final String text;
  final double size;
  final Color color;
  final TextPainter painter;
}

/// Laid-out paragraphs of the canvas, least recently used first out (and
/// disposed), with a per-frame layout budget: a zoom into a dense lane lays
/// out a few milliseconds' worth per frame and greeks the rest until the
/// next frame, instead of hitching.
class BoardTextCache extends ChangeNotifier {
  BoardTextCache({this.capacity = 800, this.budget = const Duration(milliseconds: 4)});

  final int capacity;
  final Duration budget;
  final LinkedHashMap<String, _TextEntry> _lru = LinkedHashMap();
  final Stopwatch _spent = Stopwatch();
  bool _starved = false;
  bool _pingScheduled = false;
  bool _disposed = false;

  int get length => _lru.length;

  /// Starts a frame's budget (the world painter calls it first thing).
  void beginFrame() {
    _spent
      ..reset()
      ..stop();
    _starved = false;
  }

  /// Whether a new layout may run now.
  bool get hasBudget => _spent.elapsed < budget;

  /// A cached painter for [key] if it still matches.
  TextPainter? peek(String key, String text, double size, Color color) {
    final e = _lru[key];
    if (e == null || e.size != size || e.color != color || e.text != text) return null;
    // Move to the most recently used end.
    _lru.remove(key);
    _lru[key] = e;
    return e.painter;
  }

  /// The painter for [key], laid out by [build] if missing and the budget
  /// allows; null otherwise (draw greek bars and try next frame). [force]
  /// ignores the budget.
  TextPainter? obtain(
    String key,
    String text,
    double size,
    Color color,
    TextPainter Function() build, {
    bool force = false,
  }) {
    final hit = peek(key, text, size, color);
    if (hit != null) return hit;
    if (!force && !hasBudget) {
      _starve();
      return null;
    }
    _spent.start();
    final tp = build();
    _spent.stop();
    put(key, text, size, color, tp);
    return tp;
  }

  /// Times [fn] against this frame's budget; false (and [fn] not run) when
  /// the budget is gone.
  bool spend(void Function() fn) {
    if (!hasBudget) {
      _starve();
      return false;
    }
    _spent.start();
    fn();
    _spent.stop();
    return true;
  }

  void put(String key, String text, double size, Color color, TextPainter tp) {
    final old = _lru.remove(key);
    if (old != null && !identical(old.painter, tp)) old.painter.dispose();
    _lru[key] = _TextEntry(text, size, color, tp);
    while (_lru.length > capacity) {
      final k = _lru.keys.first;
      _lru.remove(k)!.painter.dispose();
    }
  }

  void remove(String key) => _lru.remove(key)?.painter.dispose();

  /// Some text was left out this frame: paint again after it.
  void _starve() {
    if (_starved) return;
    _starved = true;
    if (_pingScheduled) return;
    _pingScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pingScheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void clear() {
    for (final e in _lru.values) {
      e.painter.dispose();
    }
    _lru.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
