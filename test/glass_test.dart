import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/system_accessibility.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/glass.dart';

import 'support/contrast.dart';

Widget _host(Widget child, {ThemeData? theme, bool highContrast = false}) => MaterialApp(
      theme: theme ?? PamnotTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: highContrast),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

const _panel = GlassPanel(child: SizedBox(width: 120, height: 80, child: Text('cam')));

/// The colour of the plain surface the panel paints when glass is off.
Color? _plainColor(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(of: find.byType(GlassPanel), matching: find.byType(DecoratedBox)),
  );
  for (final b in boxes) {
    final d = b.decoration;
    if (d is BoxDecoration && d.color != null) return d.color;
  }
  return null;
}

void main() {
  tearDown(() => SystemAccessibility.reduceTransparency.value = false);

  testWidgets('cam açıkken tek BackdropFilter, sigma 20, köşeler kırpılı', (tester) async {
    await tester.pumpWidget(_host(_panel));
    expect(find.byType(BackdropFilter), findsOneWidget);
    final f = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(f.filter, ImageFilter.blur(sigmaX: GlassPanel.sigma, sigmaY: GlassPanel.sigma));
    expect(GlassPanel.sigma, 20);
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: find.byType(GlassPanel), matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(24));
    expect(_plainColor(tester), GlassPanel.fill(Brightness.light));
    expect(find.text('cam'), findsOneWidget);
  });

  testWidgets('Saydamlığı Azalt açıkken BackdropFilter yok, düz yüzey', (tester) async {
    SystemAccessibility.reduceTransparency.value = true;
    await tester.pumpWidget(_host(_panel));
    expect(find.byType(BackdropFilter), findsNothing);
    final light = PamnotTheme.light().colorScheme;
    expect(_plainColor(tester), light.surfaceContainerLowest);
    final d = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(GlassPanel), matching: find.byType(DecoratedBox)),
        )
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color != null);
    expect((d.border! as Border).top.color, light.outlineVariant);

    SystemAccessibility.reduceTransparency.value = false;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(_plainColor(tester), GlassPanel.fill(Brightness.light));
  });

  testWidgets('Saydamlığı Azalt koyu temada surfaceContainerHigh', (tester) async {
    SystemAccessibility.reduceTransparency.value = true;
    await tester.pumpWidget(_host(_panel, theme: PamnotTheme.dark()));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(_plainColor(tester), PamnotTheme.dark().colorScheme.surfaceContainerHigh);
  });

  testWidgets('Kontrastı Artır (MediaQueryData.highContrast) açıkken düz yüzey', (tester) async {
    late bool enabled;
    await tester.pumpWidget(_host(
      Column(mainAxisSize: MainAxisSize.min, children: [
        _panel,
        Builder(builder: (c) {
          enabled = glassEnabledOf(c);
          return const SizedBox();
        }),
      ]),
      highContrast: true,
    ));
    expect(enabled, isFalse);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(_plainColor(tester), PamnotTheme.light().colorScheme.surfaceContainerLowest);
  });

  testWidgets('blurred: false bulanıklık çizmez ama dolguyu çizer', (tester) async {
    await tester.pumpWidget(_host(const GlassPanel(blurred: false, child: SizedBox(width: 50, height: 50))));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(_plainColor(tester), GlassPanel.fill(Brightness.light));
  });

  testWidgets('GlassScope altındaki iki panel aynı BackdropGroup anahtarını kullanır', (tester) async {
    await tester.pumpWidget(_host(const GlassScope(
      child: Column(mainAxisSize: MainAxisSize.min, children: [_panel, _panel]),
    )));
    expect(find.byType(BackdropGroup), findsOneWidget);
    final keys = tester
        .renderObjectList<RenderBackdropFilter>(find.byType(BackdropFilter))
        .map((r) => r.backdropKey)
        .toList();
    expect(keys, hasLength(2));
    expect(keys.first, isNotNull);
    expect(keys.first, same(keys.last));
    expect(keys.first, same(tester.widget<BackdropGroup>(find.byType(BackdropGroup)).backdropKey));
  });

  testWidgets('GlassScope yokken BackdropFilter grupsuz', (tester) async {
    await tester.pumpWidget(_host(_panel));
    expect(tester.renderObject<RenderBackdropFilter>(find.byType(BackdropFilter)).backdropKey, isNull);
  });

  test('cam renkleri tasarımdaki değerler (dolgu ve koyu ışık kontrast için ayarlandı)', () {
    expect(GlassPanel.fill(Brightness.light), const Color(0xD6FFFFFF));
    expect(GlassPanel.fill(Brightness.dark), const Color(0xE628252F));
    expect(GlassPanel.border(Brightness.light), const Color(0x8CFFFFFF));
    expect(GlassPanel.border(Brightness.dark), const Color(0x24FFFFFF));
    expect(GlassPanel.highlight(Brightness.light), const Color(0x47FFFFFF));
    expect(GlassPanel.highlight(Brightness.dark), const Color(0x0AFFFFFF));
    // Alt sınır: açık %62, koyu %58.
    expect(GlassPanel.fill(Brightness.light).a, greaterThanOrEqualTo(0.62));
    expect(GlassPanel.fill(Brightness.dark).a, greaterThanOrEqualTo(0.58));
  });

  test('cam üstünde metin kontrastı ≥ 4,5 (açık ve koyu; en kötü arka plan)', () {
    for (final t in [PamnotTheme.light(), PamnotTheme.dark()]) {
      final s = t.colorScheme;
      final b = s.brightness;
      final backgrounds = [s.surface, s.primary, s.secondary, for (final p in pastels) p.paper(b)];
      for (final bg in backgrounds) {
        // Boyanan yüzey: arka plan, üstüne dolgu, en üstte ışığın tam
        // güçte olduğu üst kenar (metnin gerçekten durduğu en kötü yer).
        final fillOnly = Color.alphaBlend(GlassPanel.fill(b), bg);
        final top = Color.alphaBlend(GlassPanel.highlight(b), fillOnly);
        for (final glass in [fillOnly, top]) {
          for (final fg in [s.onSurface, s.onSurfaceVariant]) {
            expect(contrast(fg, glass), greaterThanOrEqualTo(4.5), reason: '$b $fg on $bg -> $glass');
          }
        }
      }
    }
  });
}
