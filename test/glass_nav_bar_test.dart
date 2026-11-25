import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/system_accessibility.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/glass.dart';
import 'package:pamnot/ui/common/glass_nav_bar.dart';

import 'support/contrast.dart';

const _items = [
  GlassNavItem(Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Bugün'),
  GlassNavItem(Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded, 'Notlar'),
  GlassNavItem(Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'Takip'),
  GlassNavItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Plan'),
];

/// The bar as HomeShell places it: the bottom of an extended-body Scaffold
/// over a page of text.
Widget _host({
  int selected = 0,
  ValueChanged<int>? onSelected,
  VoidCallback? onCenter,
  ThemeData? theme,
}) =>
    MaterialApp(
      theme: theme ?? PamnotTheme.light(),
      home: Scaffold(
        extendBody: true,
        body: ListView(children: [for (var i = 0; i < 40; i++) Text('satır $i')]),
        bottomNavigationBar: GlassNavBar(
          items: _items,
          selectedIndex: selected,
          onSelected: onSelected ?? (_) {},
          centerIcon: Icons.mic_rounded,
          centerLabel: 'Sesle görev ekle',
          onCenter: onCenter ?? () {},
        ),
      ),
    );

void main() {
  tearDown(() => SystemAccessibility.reduceTransparency.value = false);

  testWidgets('dört sekme ve orta düğme; seçili sekme Semantics(selected: true)', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <int>[];
    var center = 0;
    await tester.pumpWidget(_host(selected: 1, onSelected: picked.add, onCenter: () => center++));

    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('nav-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('nav-center')), findsOneWidget);
    expect(find.byType(GlassPanel), findsOneWidget);
    // Selected: filled icon; the others outlined.
    expect(find.descendant(of: find.byKey(const Key('nav-1')), matching: find.byIcon(Icons.sticky_note_2_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('nav-0')), matching: find.byIcon(Icons.wb_sunny_outlined)), findsOneWidget);

    expect(
      tester.getSemantics(find.byKey(const Key('nav-1'))),
      isSemantics(label: 'Notlar', isButton: true, isSelected: true, hasSelectedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('nav-0'))),
      isSemantics(label: 'Bugün', isButton: true, isSelected: false, hasSelectedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('nav-center'))),
      isSemantics(label: 'Sesle görev ekle', isButton: true, hasTapAction: true),
    );

    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.tap(find.byKey(const Key('nav-center')));
    expect(picked, [3]);
    expect(center, 1);
    handle.dispose();
  });

  testWidgets('her hedef ≥ 44×44 pt; orta düğme 60 pt', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    for (var i = 0; i < 4; i++) {
      final size = tester.getSize(find.byKey(Key('nav-$i')));
      expect(size.width, greaterThanOrEqualTo(44), reason: 'nav-$i');
      expect(size.height, greaterThanOrEqualTo(44), reason: 'nav-$i');
    }
    expect(tester.getSize(find.byKey(const Key('nav-center'))), const Size(60, 60));
    // The bar is 64 pt high, floats 12 pt from the sides and the centre
    // button rises 14 pt above it.
    final panel = tester.getRect(find.byType(GlassPanel));
    expect(panel.height, 64);
    expect(panel.left, 12);
    expect(panel.right, 375 - 12);
    expect(tester.getRect(find.byKey(const Key('nav-center'))).top, panel.top - 14);
    expect(tester.getCenter(find.byKey(const Key('nav-center'))).dx, 375 / 2);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('metin ölçeği 2,0 ve 375 pt genişlikte taşma yok', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_host(selected: 2));
    expect(tester.takeException(), isNull);
    // Labels grow at most to 1.3.
    final label = find.descendant(of: find.byKey(const Key('nav-1')), matching: find.text('Notlar'));
    expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), closeTo(13, 0.001));
  });

  testWidgets('açık ve koyu temada seçili/seçili olmayan etiket kontrastı ≥ 4,5', (tester) async {
    for (final theme in [PamnotTheme.light(), PamnotTheme.dark()]) {
      final s = theme.colorScheme;
      final b = s.brightness;
      await tester.pumpWidget(_host(selected: 0, theme: theme));
      await tester.pumpAndSettle();

      Color labelColor(String text) => tester.widget<Text>(find.text(text)).style!.color!;
      final selected = labelColor('Bugün');
      final unselected = labelColor('Notlar');
      expect(selected, s.primary);
      expect(unselected, s.onSurfaceVariant);

      // The selected tab sits on its own opaque indicator.
      final indicator = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byKey(const Key('nav-0')), matching: find.byType(DecoratedBox)))
          .map((d) => (d.decoration as BoxDecoration).color)
          .whereType<Color>()
          .single;
      expect(indicator.a, 1);
      expect(contrast(selected, indicator), greaterThanOrEqualTo(4.5), reason: '$b selected');

      // The others on the glass, over the worst backdrop (as in glass_test),
      // and on the plain surface used with Reduce Transparency.
      final backdrops = [s.surface, s.primary, s.secondary, for (final p in pastels) p.paper(b)];
      for (final bg in backdrops) {
        final glass = Color.alphaBlend(GlassPanel.fill(b), bg);
        expect(contrast(unselected, glass), greaterThanOrEqualTo(4.5), reason: '$b unselected on $bg');
      }
      final plain = b == Brightness.dark ? s.surfaceContainerHigh : s.surfaceContainerLowest;
      expect(contrast(unselected, plain), greaterThanOrEqualTo(4.5));
      expect(contrast(selected, indicator), greaterThanOrEqualTo(4.5));
      // The centre icon on its primary disc: ≥ 3.
      final mic = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
      expect(contrast(mic.color!, s.primary), greaterThanOrEqualTo(3));

      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: '$b');
    }
  });

  testWidgets('Saydamlığı Azalt açıkken düz yüzey', (tester) async {
    SystemAccessibility.reduceTransparency.value = true;
    await tester.pumpWidget(_host());
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(GlassPanel), findsOneWidget);
  });
}
