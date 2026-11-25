import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/notes/note_card.dart';
import 'package:pamnot/ui/today/today_page.dart';

/// Removing a pinned note from Today's pinned strip and from Notes, with
/// an undo that pins it again (v2 design, Task 5).
void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 10, 27, 9, 0);

  Future<AppController> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(
      store: MemoryStore({
        'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson()),
      }),
      clock: () => now,
    );
    await tester.runAsync(c.load);
    c.upsertNote(Note(
      id: 'p1',
      title: 'Sabit not',
      body: 'Raptiyeli',
      pinned: true,
      colorIndex: 2,
      createdAt: now,
      updatedAt: now,
    ));
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  }

  Finder pinnedCard() => find.widgetWithText(NoteCard, 'Sabit not');

  /// Long-presses the pinned note on Today and taps "Sabitlemeyi kaldır".
  Future<void> unpinFromToday(WidgetTester tester) async {
    expect(find.byType(TodayPage), findsOneWidget);
    await tester.ensureVisible(pinnedCard());
    await tester.pumpAndSettle();
    await tester.longPress(pinnedCard());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sabitlemeyi kaldır'));
    await tester.pumpAndSettle();
  }

  testWidgets('Bugün: sabitli karta uzun basınca menü açılır, "Sabitlemeyi kaldır" notu sabitten çıkarır',
      (tester) async {
    final c = await boot(tester);
    await unpinFromToday(tester);
    expect(c.noteById('p1')!.pinned, isFalse);
    expect(find.text('Sabitleme kaldırıldı'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Geri al'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('Geri al notu yeniden sabitler', (tester) async {
    final c = await boot(tester);
    await unpinFromToday(tester);
    expect(c.noteById('p1')!.pinned, isFalse);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Geri al'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isTrue);
    await shutdown(tester, c);
  });

  testWidgets('Notlar: aynı menü ve snack', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('Notlar').last);
    await tester.pumpAndSettle();
    await tester.longPress(pinnedCard());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sabitlemeyi kaldır'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isFalse);
    expect(find.text('Sabitleme kaldırıldı'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Geri al'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isTrue);

    // Pinning shows no snack.
    c.togglePin('p1');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.longPress(pinnedCard());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sabitle'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('not düzenleyicideki raptiye hâlâ aç/kapa çalışır', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('Notlar').last);
    await tester.pumpAndSettle();
    await tester.tap(pinnedCard());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sabitlemeyi kaldır'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isFalse);
    await tester.tap(find.byTooltip('Sabitle'));
    await tester.pumpAndSettle();
    expect(c.noteById('p1')!.pinned, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('silinmiş nota "Geri al" hata vermez', (tester) async {
    final c = await boot(tester);
    await unpinFromToday(tester);
    c.deleteNote('p1');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, 'Geri al'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(c.noteById('p1'), isNull);
    await shutdown(tester, c);
  });
}
