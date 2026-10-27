import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Ink is stored on a virtual page that is [kPageWidth] units wide, so a note
/// written on an iPad in landscape looks the same on a phone or a desktop.
const double kPageWidth = 1000;

enum InkTool { pen, highlighter }

enum PaperStyle { blank, lined, grid, dotted }

/// One pen-down to pen-up stroke. Points live in a flat [Float32List]
/// (x, y, pressure, t per point): compact in memory, cheap to copy to a
/// background isolate and fast to serialise.
class InkStroke {
  InkStroke({
    required this.data,
    required this.color,
    required this.width,
    this.tool = InkTool.pen,
    this.hasPressure = false,
    this.startedAt = 0,
  }) : assert(data.length % 4 == 0);

  static const stride = 4;

  /// x, y (page units), pressure (0..1), t (ms since [startedAt]).
  final Float32List data;

  /// ARGB colour.
  final int color;
  final double width;
  final InkTool tool;

  /// False for mouse and finger strokes; the renderer then simulates pressure
  /// from speed.
  final bool hasPressure;

  /// Epoch milliseconds of the first point.
  final int startedAt;

  int get length => data.length ~/ stride;
  double x(int i) => data[i * stride];
  double y(int i) => data[i * stride + 1];
  double pressure(int i) => data[i * stride + 2];
  int t(int i) => data[i * stride + 3].round();

  Rect? _bounds;

  Rect get bounds {
    final cached = _bounds;
    if (cached != null) return cached;
    if (length == 0) return _bounds = Rect.zero;
    var minX = data[0], maxX = minX, minY = data[1], maxY = minY;
    for (var i = 0; i < data.length; i += stride) {
      final px = data[i], py = data[i + 1];
      if (px < minX) minX = px;
      if (px > maxX) maxX = px;
      if (py < minY) minY = py;
      if (py > maxY) maxY = py;
    }
    final pad = width;
    return _bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  /// Whether a circle at [p] with [radius] touches this stroke.
  bool hitTest(Offset p, double radius) {
    final r = radius + width / 2;
    if (!bounds.inflate(radius).contains(p)) return false;
    if (length == 1) return (Offset(x(0), y(0)) - p).distance <= r;
    for (var i = 1; i < length; i++) {
      if (_segmentDistance(p, Offset(x(i - 1), y(i - 1)), Offset(x(i), y(i))) <= r) return true;
    }
    return false;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Bottom edge of the ink on a page, used to size the page and thumbnails.
double inkExtent(List<InkStroke> strokes) {
  var maxY = 0.0;
  for (final s in strokes) {
    maxY = math.max(maxY, s.bounds.bottom);
  }
  return maxY;
}

/// Binary ink format, base64 encoded so it fits any key-value store:
/// "PINK1:" + [count:u32] then per stroke
/// [color:u32][width:f32][tool:u8][pressure:u8][pad:u16][startedAt:f64][points:u32][points*4 f32].
class InkCodec {
  static const _magic = 'PINK1:';

  static String encode(List<InkStroke> strokes) {
    var size = 4;
    for (final s in strokes) {
      size += 24 + s.data.lengthInBytes;
    }
    final bytes = ByteData(size);
    var o = 0;
    bytes.setUint32(o, strokes.length, Endian.little);
    o += 4;
    final out = Uint8List.view(bytes.buffer);
    for (final s in strokes) {
      bytes
        ..setUint32(o, s.color, Endian.little)
        ..setFloat32(o + 4, s.width, Endian.little)
        ..setUint8(o + 8, s.tool.index)
        ..setUint8(o + 9, s.hasPressure ? 1 : 0)
        ..setFloat64(o + 12, s.startedAt.toDouble(), Endian.little)
        ..setUint32(o + 20, s.length, Endian.little);
      o += 24;
      final src = s.data.buffer.asUint8List(s.data.offsetInBytes, s.data.lengthInBytes);
      if (Endian.host == Endian.little) {
        out.setRange(o, o + src.length, src);
      } else {
        for (var i = 0; i < s.data.length; i++) {
          bytes.setFloat32(o + i * 4, s.data[i], Endian.little);
        }
      }
      o += src.length;
    }
    return _magic + base64Encode(out);
  }

  static List<InkStroke> decode(String text) {
    if (!text.startsWith(_magic)) return const [];
    final raw = base64Decode(text.substring(_magic.length));
    final bytes = ByteData.sublistView(raw);
    var o = 0;
    final count = bytes.getUint32(o, Endian.little);
    o += 4;
    final strokes = <InkStroke>[];
    for (var k = 0; k < count && o + 24 <= raw.length; k++) {
      final color = bytes.getUint32(o, Endian.little);
      final width = bytes.getFloat32(o + 4, Endian.little);
      final tool = InkTool.values[bytes.getUint8(o + 8).clamp(0, InkTool.values.length - 1)];
      final pressure = bytes.getUint8(o + 9) == 1;
      final started = bytes.getFloat64(o + 12, Endian.little).toInt();
      final n = bytes.getUint32(o + 20, Endian.little);
      o += 24;
      final floats = n * InkStroke.stride;
      if (o + floats * 4 > raw.length) break;
      final data = Float32List(floats);
      final start = raw.offsetInBytes + o;
      if (Endian.host == Endian.little && start % 4 == 0) {
        data.setAll(0, raw.buffer.asFloat32List(start, floats));
      } else {
        for (var i = 0; i < floats; i++) {
          data[i] = bytes.getFloat32(o + i * 4, Endian.little);
        }
      }
      o += floats * 4;
      strokes.add(InkStroke(
        data: data,
        color: color,
        width: width,
        tool: tool,
        hasPressure: pressure,
        startedAt: started,
      ));
    }
    return strokes;
  }
}
