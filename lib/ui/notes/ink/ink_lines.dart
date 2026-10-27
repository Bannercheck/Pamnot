import 'dart:math' as math;

import '../../../models/ink.dart';

/// Groups handwriting into lines (top to bottom), keeping each line's strokes
/// in the order they were written, which is what recognisers expect.
/// Highlighter strokes are not handwriting and are left out.
List<List<InkStroke>> segmentLines(List<InkStroke> strokes) {
  final pen = [for (final s in strokes) if (s.tool == InkTool.pen && s.length > 0) s];
  if (pen.isEmpty) return const [];
  final order = {for (var i = 0; i < pen.length; i++) pen[i]: i};
  final byTop = [...pen]..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

  final lines = <List<InkStroke>>[];
  var top = 0.0, bottom = 0.0;
  for (final s in byTop) {
    final b = s.bounds;
    final band = math.max(bottom - top, 24.0);
    final fits = lines.isNotEmpty && b.center.dy <= bottom + band * 0.35 && b.center.dy >= top - band * 0.35;
    if (fits) {
      lines.last.add(s);
      top = math.min(top, b.top);
      bottom = math.max(bottom, b.bottom);
    } else {
      lines.add([s]);
      top = b.top;
      bottom = b.bottom;
    }
  }
  for (final l in lines) {
    l.sort((a, b) => order[a]!.compareTo(order[b]!));
  }
  return lines;
}
