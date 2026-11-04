import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/canvas/board_canvas_view.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/ui/board_list.dart';
import 'package:pamnot/boards/ui/board_page.dart';
import 'package:pamnot/boards/ui/kanban_view.dart';
import 'package:pamnot/data/store.dart';

import 'harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  Map<String, Object?>? savedView(MemoryStore store, String id) {
    final raw = store.data[BoardsRepository.viewKey(id)];
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  testWidgets('Kanban on a phone, the canvas on a tablet; the choice is remembered', (tester) async {
    final store = MemoryStore();
    final c = await makeApp(tester, store: store);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);

    await pumpBoardPage(tester, c, id, size: phone);
    expect(find.byType(KanbanView), findsOneWidget);
    expect(find.byType(BoardCanvasView), findsNothing);
    expect(find.byTooltip('Tuval'), findsOneWidget, reason: 'icon-only switch below 600 dp');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await pumpBoardPage(tester, c, id, size: tablet);
    expect(find.byType(BoardCanvasView), findsOneWidget);
    expect(find.text('Kanban'), findsOneWidget, reason: 'labelled switch from 600 dp');
    expect(savedView(store, id), isNull, reason: 'the default is not stored');

    await tester.tap(find.text('Kanban'));
    await tester.pumpAndSettle();
    expect(find.byType(KanbanView), findsOneWidget);
    await tester.runAsync(c.boards.flush);
    expect(savedView(store, id)!['view'], 'kanban');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await pumpBoardPage(tester, c, id, size: tablet);
    expect(find.byType(KanbanView), findsOneWidget, reason: 'remembered on this device');
    await shutdown(tester, c);
  });

  testWidgets('the canvas gets the stored viewport, saves it, opens cards and detects a stylus', (tester) async {
    final store = MemoryStore();
    final c = await makeApp(tester, store: store);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);
    c.boards.saveView(id, const BoardViewState(view: 'canvas', offset: Offset(10, 20), scale: 0.5, fitted: true));
    await tester.runAsync(c.boards.flush);
    await pumpBoardPage(tester, c, id, size: tablet);

    var canvas = tester.widget<BoardCanvasView>(find.byType(BoardCanvasView));
    expect(canvas.viewState!.scale, 0.5);
    expect(canvas.viewState!.offset, const Offset(10, 20));
    expect(canvas.stylusOnly, isFalse);

    canvas.onViewChanged(const BoardViewState(view: 'canvas', offset: Offset(-5, 7), scale: 2, fitted: true));
    await tester.runAsync(c.boards.flush);
    expect(savedView(store, id), containsPair('scale', 2.0));

    canvas.onStylusDetected!();
    await tester.pumpAndSettle();
    expect(c.settings.stylusOnly, isTrue);
    canvas = tester.widget<BoardCanvasView>(find.byType(BoardCanvasView));
    expect(canvas.stylusOnly, isTrue);

    final cardId = c.boards.openBoard(id)!.editor.cardsIn(c.boards.openBoard(id)!.editor.columns.first.id).single.id;
    canvas.onOpenCard(cardId);
    await tester.pumpAndSettle();
    expect(find.text('Kart'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await shutdown(tester, c);
  });

  testWidgets('title tap renames; ⋯ changes the colour', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c);
    await pumpBoardPage(tester, c, id);
    final e = c.boards.openBoard(id)!.editor;

    await tester.tap(find.text('Proje'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lansman');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(e.title, 'Lansman');
    expect(find.text('Lansman'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Paylaş'), findsOneWidget, reason: 'phones share from the menu');
    await tester.tap(find.text('Renk'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('sky'));
    await tester.pumpAndSettle();
    expect(e.colorIndex, 4);
    await shutdown(tester, c);
  });

  testWidgets('shared boards show others (Turkish initials, +n) and a sync icon that retries', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c);
    final latest = await shareBoard(tester, c, id, state: const SyncState(SyncStatus.error), peers: const [
      Peer(key: 'k1', userId: 'u1', name: 'ilker kaya', colorIndex: 1),
      Peer(key: 'k2', userId: 'u2', name: 'Ayşe', colorIndex: 2),
      Peer(key: 'k3', userId: 'u3', name: 'Mert', colorIndex: 4),
      Peer(key: 'k4', userId: 'u4', name: 'Zeynep', colorIndex: 5),
    ]);
    await pumpBoardPage(tester, c, id, size: tablet);
    final conn = latest();
    expect(conn.activity.first, ('canvas', null));

    expect(find.text('İK'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('Z'), findsNothing);
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.byTooltip('Eşitlenemedi. Tekrar denemek için dokun.'));
    await tester.pump();
    expect(conn.retries, 1);
    conn.stateN.value = const SyncState(SyncStatus.sending, pending: 3);
    await tester.pump();
    expect(find.byTooltip('3 değişiklik gönderiliyor'), findsOneWidget);
    conn.stateN.value = const SyncState(SyncStatus.offline);
    await tester.pump();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Paylaş'), findsOneWidget);

    // Switching views is presence too.
    await tester.tap(find.text('Kanban'));
    await tester.pumpAndSettle();
    expect(conn.activity.last, ('kanban', null));
    await shutdown(tester, c);
  });

  testWidgets('device-only boards have no sync icon', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c);
    await pumpBoardPage(tester, c, id, size: tablet);
    for (final i in [Icons.cloud_done_outlined, Icons.cloud_off_outlined, Icons.cloud_upload_outlined, Icons.error_outline_rounded]) {
      expect(find.byIcon(i), findsNothing);
    }
    await shutdown(tester, c);
  });

  testWidgets('a deleted board is read-only; Kopyayı sakla keeps a device-only copy', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);
    await tester.runAsync(() async {
      final b = (await c.boards.open(id))!;
      b.doc.state = BoardState.deleted;
      c.boards.stateChanged(b.doc);
      await c.boards.release(b);
    });
    await settleReal(tester);
    await pumpBoardPage(tester, c, id);
    expect(find.textContaining('Bu pano sahibi tarafından silindi'), findsOneWidget);
    expect(find.text('Kart ekle'), findsNothing);
    expect(find.byTooltip('Sütun'), findsNothing);

    await tester.tap(find.text('Kopyayı sakla'));
    await tester.pumpAndSettle();
    expect(find.text('Kopya bu cihaza kaydedildi.'), findsOneWidget);
    expect(find.textContaining('Bu pano sahibi tarafından silindi'), findsNothing);
    final copy = c.boards.boards.firstWhere((b) => b.id != id);
    expect(copy.state, BoardState.local);
    expect(copy.title, 'Proje');
    expect(copy.cardCount, 1);
    expect(find.text('Kart ekle'), findsWidgets, reason: 'the copy is editable');
    await shutdown(tester, c);
  });

  testWidgets('Sil in the ⋯ menu removes a device-only board and closes the page', (tester) async {
    final c = await bootApp(tester);
    await makeBoard(tester, c, title: 'Silinecek');
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panolar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Silinecek'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardPage), findsNothing);
    expect(find.byType(BoardTile), findsNothing);
    expect(c.boards.boards, isEmpty);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);
  });
}
