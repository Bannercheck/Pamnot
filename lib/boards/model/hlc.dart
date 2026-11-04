import 'dart:math' as math;

/// Hybrid logical clock for per-field last-writer-wins.
///
/// Format (fixed width, ASCII, 38 chars): `MMMMMMMMMMMMMMM-CCCCC-NNNNNNNNNNNNNNNN`
/// — 15-digit wall milliseconds, 5-digit counter, 16 lowercase hex node.
/// Plain string comparison orders it, in Dart and in Postgres `COLLATE "C"`.
class HlcClock {
  HlcClock({String? node, int Function()? wallMs})
      : node = node ?? _randomNode(),
        _wall = wallMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Random per process: two devices of one user, or a restored backup,
  /// never share a node.
  final String node;
  final int Function() _wall;

  /// Server time minus device time, measured on connect.
  int offsetMs = 0;

  int _ms = 0;
  int _c = 0;

  static final pattern = RegExp(r'^\d{15}-\d{5}-[0-9a-f]{16}$');

  static bool isValid(String h) => pattern.hasMatch(h);

  String tick() {
    final w = _wall() + offsetMs;
    if (w > _ms) {
      _ms = w;
      _c = 0;
    } else if (++_c > 99999) {
      _ms++;
      _c = 0;
    }
    return format(_ms, _c, node);
  }

  /// Moves the clock past [h] so the next tick sorts after it.
  void observe(String h) {
    if (!isValid(h)) return;
    final ms = int.parse(h.substring(0, 15));
    final c = int.parse(h.substring(16, 21));
    if (ms > _ms || (ms == _ms && c > _c)) {
      _ms = ms;
      _c = c;
    }
  }

  static String format(int ms, int counter, String node) =>
      '${ms.toString().padLeft(15, '0')}-${counter.toString().padLeft(5, '0')}-$node';

  static String _randomNode() {
    final r = math.Random.secure();
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      b.write(r.nextInt(16).toRadixString(16));
    }
    return b.toString();
  }
}
