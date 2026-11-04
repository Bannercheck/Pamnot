import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/ui/card_face.dart';
import 'package:pamnot/state/app_controller.dart';

import 'harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  Future<void> openKanban(WidgetTester tester, AppController c, String id, {Size size = phone}) async {
    c.boards.saveView(id, const BoardViewState(view: 'kanban'));
    await tester.runAsync(c.boards.flush);
    await pumpBoardPage(tester, c, id, size: size);
  }

  Future<void> swipeDown(WidgetTester tester) async {
    // From the drag handle: the sheet's content is a scroll view.
    final sheet = tester.getRect(find.byType(BottomSheet));
    await tester.flingFrom(Offset(sheet.center.dx, sheet.top + 12), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();
  }

  testWidgets('every edit lands in one write when the sheet is swiped away', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
      ['Var olan'],
    ]);
    await openKanban(tester, c, id);
    final e = c.boards.openBoard(id)!.editor;
    final cols = e.columns;
    final cardId = e.cardsIn(cols[0].id).single.id;
    final before = Map.of(e.item(cardId)!.h);

    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    expect(find.text('Kart'), findsOneWidget);
    final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Logo v2');
    await tester.enterText(fields.at(1), 'Mor tonlar');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yapılıyor'));
    await tester.pump();
    await tester.enterText(fields.at(2), 'Renk seç');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('rose'));
    await tester.pump();
    await tester.tap(find.text('Son tarih'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('Tamam')));
    await tester.pumpAndSettle();
    expect(find.text('Son tarih: 30 Eki'), findsOneWidget);

    final rev = e.revision;
    expect(e.item(cardId)!.title, 'Logo', reason: 'nothing is written while the sheet is open');

    await swipeDown(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(e.revision, rev + 1, reason: 'one notification');
    final it = e.item(cardId)!;
    expect(it.title, 'Logo v2');
    expect(it.notes, 'Mor tonlar');
    expect(it.columnId, cols[1].id);
    expect(e.cardsIn(cols[1].id).map((x) => x.title), ['Var olan', 'Logo v2'], reason: 'appended to the column');
    expect(it.due, '2026-10-30');
    expect(it.subtasks.single.title, 'Renk seç');
    expect(it.colorIndex, 6);
    final changed = [F.title, F.notes, F.columnId, F.order, F.due, F.subtasks, F.colorIndex];
    expect({for (final k in changed) it.h[k]}, hasLength(1), reason: 'one HLC tick for the commit');
    expect(it.h[F.assigneeId], before[F.assigneeId]);
    expect(it.h[F.deleted], before[F.deleted]);

    // One undo step takes it all back.
    e.undo();
    await tester.pump();
    expect(e.item(cardId)!.title, 'Logo');
    expect(e.item(cardId)!.columnId, cols[0].id);
    expect(e.item(cardId)!.due, isNull);
    await shutdown(tester, c);
  });

  testWidgets('closing without changes writes nothing; back and Tamam commit too', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);
    await openKanban(tester, c, id);
    final e = c.boards.openBoard(id)!.editor;
    final cardId = e.cardsIn(e.columns.first.id).single.id;
    final h = Map.of(e.item(cardId)!.h);
    final rev = e.revision;

    // Barrier tap.
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    // Swipe.
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await swipeDown(tester);
    // Tamam.
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();
    expect(e.revision, rev);
    expect(e.item(cardId)!.h, h);
    expect(e.canUndo, isFalse);

    // Back (system) commits an edit.
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    final title = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first;
    await tester.enterText(title, '  Logo  ');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(e.revision, rev, reason: 'only whitespace changed');
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await tester.enterText(title, 'Afiş');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(e.item(cardId)!.title, 'Afiş');
    expect(e.revision, rev + 1);
    await shutdown(tester, c);
  });

  testWidgets('Sil deletes the card with an undo snack', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo', 'Afiş'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;

    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sil').first);
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Afiş']);
    expect(find.text('Silindi'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Logo', 'Afiş']);
    await shutdown(tester, c);
  });

  testWidgets('a stale undo snack never reverts a later edit', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo', 'Afiş'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sil').first);
    await tester.pumpAndSettle();
    // Another edit before the snack's undo is tapped.
    b.editor.addCard(columnId: b.editor.columns.first.id, title: 'Yeni');
    await tester.pump();
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Afiş', 'Yeni']);
    await shutdown(tester, c);
  });

  testWidgets('shared boards: presence while editing, assignee, footer', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);
    const ayse = Peer(key: 'k1', userId: 'u-ayse', name: 'Ayşe', colorIndex: 1, view: 'kanban');
    final latest = await shareBoard(tester, c, id, peers: const [ayse]);
    await openKanban(tester, c, id);
    final conn = latest();
    final e = c.boards.openBoard(id)!.editor;
    final cardId = e.cardsIn(e.columns.first.id).single.id;
    expect(conn.activity.last, ('kanban', null));

    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    expect(conn.activity.last, ('kanban', cardId));
    expect(find.textContaining('Şu an düzenleyen'), findsNothing);
    conn.peersN.value = [
      const Peer(key: 'k1', userId: 'u-ayse', name: 'Ayşe', colorIndex: 1, view: 'kanban', editing: null),
      Peer(key: 'k2', userId: 'u-mert', name: 'Mert', colorIndex: 4, view: 'canvas', editing: cardId),
    ];
    await tester.pump();
    expect(find.text('Şu an düzenleyen: Mert'), findsOneWidget);
    expect(find.textContaining('Kapatınca kaydedilir'), findsOneWidget);

    expect(find.widgetWithText(ChoiceChip, 'Atanmamış'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Ben'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ayşe'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(e.item(cardId)!.assigneeId, 'u-ayse');
    expect(conn.activity.last, ('kanban', null));

    // The card face shows who it is assigned to.
    final face = tester.widget<CardFace>(find.byType(CardFace));
    expect(face.assignee!.label, 'Ayşe');
    expect(find.bySemanticsLabel(RegExp('Atanan: Ayşe')), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('read-only boards open the sheet for viewing only', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;
    b.doc.state = BoardState.revoked;
    b.editor.touch();
    await tester.pump();
    final rev = b.editor.revision;
    await tester.tap(find.text('Logo'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sil'), findsNothing);
    final field = tester.widget<TextField>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first);
    expect(field.readOnly, isTrue);
    await tester.tap(find.widgetWithText(FilledButton, 'Tamam'));
    await tester.pumpAndSettle();
    expect(b.editor.revision, rev);
    await shutdown(tester, c);
  });
}
