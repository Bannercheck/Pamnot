import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/soft.dart';

/// WCAG 2.x contrast ratio: (L1 + 0.05) / (L2 + 0.05), where L is the relative
/// luminance (Color.computeLuminance follows the W3C definition).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, t) in [('açık', PamnotTheme.light()), ('koyu', PamnotTheme.dark())]) {
    final c = t.colorScheme;

    test('$name tema: metin çiftleri en az 4,5:1', () {
      for (final (fg, bg) in [
        (c.onSurface, c.surface),
        (c.onSurfaceVariant, c.surface),
        (c.onSurfaceVariant, c.surfaceContainer),
        (c.onSurfaceVariant, c.surfaceContainerLow),
        (c.onSurfaceVariant, c.surfaceContainerLowest),
        (c.primary, c.surface),
        (c.primary, c.surfaceContainerLowest),
        (c.onPrimary, c.primary),
        (c.error, c.surface),
        (c.error, c.surfaceContainerLowest),
        (c.onPrimaryContainer, c.primaryContainer),
        (c.onErrorContainer, c.errorContainer),
        (c.onInverseSurface, c.inverseSurface),
      ]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg / $bg');
      }
    });

    test('$name tema: ikon ve kenar çiftleri en az 3:1', () {
      expect(contrast(c.onTertiary, c.tertiary), greaterThanOrEqualTo(3));
      expect(contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
      for (final p in pastels) {
        expect(contrast(inkOnPastel, p.accent), greaterThanOrEqualTo(3), reason: p.name);
      }
    });

    test('$name tema: ipucu metni saydam değil', () {
      expect(t.inputDecorationTheme.hintStyle!.color, c.onSurfaceVariant);
    });
  }

  Future<(Duration, Curve)> readMotion(WidgetTester tester) async {
    late Duration d;
    late Curve k;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      d = motion(c, const Duration(milliseconds: 220));
      k = motionCurve(c, Curves.easeOutBack);
      return const SizedBox();
    })));
    return (d, k);
  }

  testWidgets('motion: Hareketi Azalt açıkken süre sıfır, eğri easeOut', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(await readMotion(tester), (Duration.zero, Curves.easeOut));
  });

  testWidgets('motion: Animasyonları Kaldır (disableAnimations) açıkken süre sıfır, eğri easeOut', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(await readMotion(tester), (Duration.zero, Curves.easeOut));
  });

  testWidgets('motion: ayarlar kapalıyken süre ve eğri aynen kalır', (tester) async {
    expect(await readMotion(tester), (const Duration(milliseconds: 220), Curves.easeOutBack));
  });
}
