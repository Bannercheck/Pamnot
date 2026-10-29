import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/prediction/word_predictor.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/notes/ink/ink_canvas.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 10, 27, 9, 0);

  Future<AppController> boot(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())}),
      clock: () => now,
    );
    await tester.runAsync(() async {
      await c.load();
      c.attachPredictor(await WordPredictor.load(rootBundle));
    });
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  testWidgets('phone: tabs, notes and word suggestions', (tester) async {
    final c = await boot(tester, const Size(390, 844));
    expect(find.text('Günaydın'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    for (final tab in ['Notlar', 'Takip', 'Plan', 'Hatırlatma', 'Bugün']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Notlar').last);
    await tester.pumpAndSettle();
    expect(find.text('Alışveriş listesi'), findsOneWidget);

    await tester.tap(find.text('Yeni not'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Yarın sabah topl');
    await tester.pumpAndSettle();
    expect(find.text('toplantı'), findsWidgets);

    await tester.tap(find.text('toplantı').first);
    await tester.pump();
    final body = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(body.controller!.text, 'Yarın sabah toplantı ');

    // The tooltip is localised ('Geri'), so pageBack() can't find it.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(c.notes.any((n) => n.body.startsWith('Yarın sabah toplantı')), isTrue);
    await shutdown(tester, c);
  });

  testWidgets('tablet: rail navigation and ink mode', (tester) async {
    final c = await boot(tester, const Size(1366, 1024));
    expect(find.byType(NavigationRail), findsOneWidget);

    await tester.tap(find.text('Notlar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('El yazısı not'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kalem'), findsWidgets);

    // A stroke drawn with a stylus lands in the note.
    final center = tester.getCenter(find.byType(InkCanvas));
    final g = await tester.startGesture(center, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(8, 3));
    }
    await g.up();
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(c.notes.any((n) => n.ink.isNotEmpty), isTrue);
    expect(c.settings.stylusOnly, isTrue, reason: 'stylus detection turns palm rejection on');
    await shutdown(tester, c);
  });
}
