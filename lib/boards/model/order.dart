import 'dart:math' as math;

/// Fractional ordering for columns and cards (sorted by `(order, id)`).
class FractionalOrder {
  FractionalOrder._();

  static const step = 1024.0;
  static final _rnd = math.Random();

  /// A value strictly between [before] and [after] (either may be null for
  /// the ends). The random spread keeps two concurrent inserts between the
  /// same neighbours from landing on the same number.
  static double between(double? before, double? after, {math.Random? random}) {
    final r = (random ?? _rnd).nextDouble();
    if (before == null && after == null) return step;
    if (before == null) return after! - step;
    if (after == null) return before + step;
    return before + (after - before) * (0.25 + 0.5 * r);
  }

  /// True when there is no usable room between [before] and [after].
  static bool exhausted(double before, double after) {
    final m = before + (after - before) / 2;
    return !(m > before && m < after) || (after - before) < 1e-9 * math.max(1, before.abs());
  }

  /// Even spacing for a renormalised list of [count] items.
  static List<double> spaced(int count) => [for (var i = 0; i < count; i++) step * (i + 1)];
}
