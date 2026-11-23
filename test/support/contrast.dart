import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.x contrast ratio: (L1 + 0.05) / (L2 + 0.05), where L is the relative
/// luminance (Color.computeLuminance follows the W3C definition).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
