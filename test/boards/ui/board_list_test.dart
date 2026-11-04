import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/boards/canvas/board_canvas_view.dart';
import 'package:pamnot/boards/ui/board_list.dart';
import 'package:pamnot/boards/ui/kanban_view.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/ui/home_shell.dart';

import 'harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  tearDown(() => notificationTaps.value = null);

  Future<void> openBoards(WidgetTester tester) async {
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panolar'));
    await tester.pumpAndSettle();
  }

  TrackSegment selectedSegment(WidgetTester tester) =>
      tester.widget<SegmentedButton<TrackSegment>>(find.byType(SegmentedButton<TrackSegment>)).selected.single;

  testWidgets('the sample board is seeded the first time, and only once', (tester) async {
    final c = await bootApp(tester, settings: const AppSettings(language: AppLanguage.tr, seeded: true));
    expect(c.settings.boardsSeeded, isFalse);
    await openBoards(tester);
    expect(c.settings.boardsSeeded, isTrue);
    expect(c.settings.trackSegment, TrackSegment.boards);
    expect(find.text('İlk panom 🌷'), findsOneWidget);
    expect(find.text('Cihazda'), findsOneWidget);
    expect(find.text('1/4 bitti'), findsOneWidget);
    expect(find.text('Yeni pano'), findsOneWidget, reason: 'the FAB follows the segment');
    expect(find.byTooltip('Davete katıl'), findsOneWidget);

    // Remove it from the tile menu: the empty state shows, nothing reseeds.
    await tester.longPress(find.text('İlk panom 🌷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(c.boards.boards, isEmpty);
    expect(find.textContaining('İlk panonu oluştur'), findsOneWidget);
    expect(find.text('Davetim var'), findsOneWidget);

    await tester.tap(find.text('Görevler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panolar'));
    await tester.pumpAndSettle();
    expect(c.boards.boards, isEmpty);
    expect(find.text('İlk panom 🌷'), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('new boards from both templates open in the right view', (tester) async {
    final c = await bootApp(tester);
    await openBoards(tester);
    expect(find.textContaining('İlk panonu oluştur'), findsOneWidget);

    // Görev panosu (default): Yapılacak · Yapılıyor · Bitti, Kanban on a phone.
    await tester.tap(find.text('Yeni pano').last);
    await tester.pumpAndSettle();
    expect(find.text('Görev panosu'), findsOneWidget);
    expect(find.text('Boş tuval'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Web sitesi');
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();
    expect(find.byType(KanbanView), findsOneWidget);
    expect(find.text('Web sitesi'), findsOneWidget);
    expect(find.text('Yapılacak'), findsOneWidget);
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardTile), findsOneWidget);

    // Boş tuval: no columns, opens on the canvas even on a phone.
    await tester.tap(find.text('Yeni pano').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fikirler');
    await tester.tap(find.text('Boş tuval'));
    await tester.pump();
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardCanvasView), findsOneWidget);
    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();

    final list = c.boards.boards;
    expect(list.map((b) => b.title), containsAll(['Web sitesi', 'Fikirler']));
    expect(list.firstWhere((b) => b.title == 'Web sitesi').columns.map((x) => x.$1), ['Yapılacak', 'Yapılıyor', 'Bitti']);
    expect(list.firstWhere((b) => b.title == 'Fikirler').columns, isEmpty);
    expect(find.byType(BoardTile), findsNWidgets(2));
    await shutdown(tester, c);
  });

  testWidgets('rename and recolour from the tile menu', (tester) async {
    final c = await bootApp(tester);
    final id = await makeBoard(tester, c, title: 'Eski ad', cards: [
      ['a', 'b'],
      [],
      ['c'],
    ]);
    await openBoards(tester);
    expect(find.text('1/3 bitti'), findsOneWidget);

    await tester.longPress(find.text('Eski ad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeniden adlandır'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Yeni ad');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Yeni ad'), findsOneWidget);
    expect(c.boards.summary(id)!.title, 'Yeni ad');

    await tester.longPress(find.text('Yeni ad'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('mint'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.boards.summary(id)!.colorIndex, 2);
    await shutdown(tester, c);
  });

  testWidgets('two columns of tiles from 560 dp', (tester) async {
    final c = await bootApp(tester, size: tablet);
    await makeBoard(tester, c, title: 'Bir');
    await makeBoard(tester, c, title: 'İki');
    await openBoards(tester);
    final a = tester.getTopLeft(find.text('Bir'));
    final b = tester.getTopLeft(find.text('İki'));
    expect(a.dy, b.dy, reason: 'side by side');
    expect(a.dx, isNot(b.dx));
    await shutdown(tester, c);
  });

  testWidgets('the segment is remembered; a task notification switches to tasks', (tester) async {
    final store = MemoryStore({
      'settings': jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true, boardsSeeded: true).toJson()),
    });
    var c = await bootApp(tester, store: store);
    await openBoards(tester);
    expect(c.settings.trackSegment, TrackSegment.boards);
    await shutdown(tester, c);

    // Next launch: Takip opens on Panolar.
    c = await makeApp(tester, store: store);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    expect(c.settings.trackSegment, TrackSegment.boards);
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    expect(selectedSegment(tester), TrackSegment.boards);

    // Back to Bugün, then a task reminder is tapped.
    await tester.tap(find.text('Bugün').last);
    await tester.pumpAndSettle();
    notificationTaps.value = 't:task-1';
    await tester.pumpAndSettle();
    expect(c.settings.trackSegment, TrackSegment.tasks);
    expect(selectedSegment(tester), TrackSegment.tasks);
    expect(find.text('Yeni görev'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('segment icons only from 420 dp', (tester) async {
    final c = await bootApp(tester, size: const Size(360, 740));
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    final narrow = tester.widget<SegmentedButton<TrackSegment>>(find.byType(SegmentedButton<TrackSegment>));
    expect(narrow.segments.every((x) => x.icon == null), isTrue);
    await shutdown(tester, c);

    final c2 = await bootApp(tester, size: const Size(430, 900));
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    final roomy = tester.widget<SegmentedButton<TrackSegment>>(find.byType(SegmentedButton<TrackSegment>));
    expect(roomy.segments.every((x) => x.icon != null), isTrue);
    await shutdown(tester, c2);
  });

  test('about text no longer promises that everything stays on the device', () {
    expect(S.tr.aboutText, contains('Paylaştığın panolar dışında'));
    expect(S.en.aboutText, contains('Apart from boards you share'));
  });
}
