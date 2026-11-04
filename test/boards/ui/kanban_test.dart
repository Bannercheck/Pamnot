import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/canvas/board_canvas_view.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/ui/card_face.dart';
import 'package:pamnot/boards/ui/kanban_view.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/theme/pamnot_theme.dart';

import 'harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  /// Opens [id] in Kanban whatever the size.
  Future<void> openKanban(WidgetTester tester, AppController c, String id, {Size size = phone}) async {
    c.boards.saveView(id, const BoardViewState(view: 'kanban'));
    await tester.runAsync(c.boards.flush);
    await pumpBoardPage(tester, c, id, size: size);
    expect(find.byType(KanbanView), findsOneWidget);
  }

  testWidgets('+ Kart ekle reads the due date and stays open for the next card', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['İlk'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;

    await tester.tap(find.text('Kart ekle').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'logo tasarımı yarın');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final added = b.editor.cardsIn(b.editor.columns.first.id).last;
    expect(added.title, 'Logo tasarımı');
    expect(added.due, '2026-10-28');
    expect(find.text('28 Eki'), findsOneWidget, reason: 'the due chip on the card face');

    // Still open and focused: type the next one.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Rapor');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['İlk', 'Logo tasarımı', 'Rapor']);

    // Esc closes it.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('screen reader actions move cards; a column move can be undone', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo', 'Afiş'],
      ['X'],
    ]);
    await openKanban(tester, c, id, size: tablet);
    final b = c.boards.openBoard(id)!;

    final logo = find.semantics.byLabel(RegExp(r'^Kart: Logo\.'));
    tester.semantics.customAction(logo, const CustomSemanticsAction(label: 'Aşağı taşı'));
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Afiş', 'Logo']);
    tester.semantics.customAction(logo, const CustomSemanticsAction(label: 'Yukarı taşı'));
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Logo', 'Afiş']);

    tester.semantics.customAction(logo, const CustomSemanticsAction(label: 'Sonraki sütuna taşı'));
    await tester.pumpAndSettle();
    expect(titles(b), [
      ['Afiş'],
      ['X', 'Logo'],
      [],
    ]);
    expect(find.text('«Logo» → Yapılıyor'), findsOneWidget);

    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(titles(b), [
      ['Logo', 'Afiş'],
      ['X'],
      [],
    ]);

    // The first column has no "previous column" action; the top card no "up".
    final node = find.semantics.byLabel(RegExp(r'^Kart: Logo\.')).evaluate().single;
    final actions = [
      for (final id in node.getSemanticsData().customSemanticsActionIds!) CustomSemanticsAction.getAction(id)!.label,
    ];
    expect(actions, unorderedEquals(['Sonraki sütuna taşı', 'Aşağı taşı']));
    semantics.dispose();
    await shutdown(tester, c);
  });

  testWidgets('a mouse drags a card to another column at the insertion line', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['Logo', 'Afiş'],
      ['X', 'Y'],
    ]);
    await openKanban(tester, c, id, size: tablet);
    final b = c.boards.openBoard(id)!;

    final g = await tester.startGesture(tester.getCenter(find.text('Logo')), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    // Just above Y's middle: between X and Y.
    final target = tester.getTopLeft(find.text('Y')) + const Offset(20, -1);
    await g.moveTo(target);
    await tester.pump();
    await g.moveTo(target + const Offset(2, 0));
    await tester.pump();
    expect(find.text('Logo'), findsNWidgets(2), reason: 'placeholder and feedback');
    final primary = PamnotTheme.light().colorScheme.primary;
    final line = find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == primary);
    expect(line, findsOneWidget, reason: 'the insertion line');
    expect(tester.getCenter(line).dy, lessThan(tester.getTopLeft(find.text('Y')).dy));
    await g.up();
    await tester.pumpAndSettle();
    expect(titles(b), [
      ['Afiş'],
      ['X', 'Logo', 'Y'],
      [],
    ]);
    expect(find.text('«Logo» → Yapılıyor'), findsOneWidget);

    // Dropped outside the columns: nothing moves.
    final g2 = await tester.startGesture(tester.getCenter(find.text('Afiş')), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g2.moveBy(const Offset(10, 0));
    await tester.pump();
    await g2.moveTo(const Offset(600, 20)); // the top bar
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['Afiş']);
    await shutdown(tester, c);
  });

  testWidgets('touch: hold 300 ms with a haptic tick, then drag to reorder', (tester) async {
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['a', 'b', 'c'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;

    // A quick swipe does not pick a card up.
    final quick = await tester.startGesture(tester.getCenter(find.text('a')));
    await quick.moveBy(const Offset(0, 40));
    await tester.pump();
    await quick.up();
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['a', 'b', 'c']);
    expect(haptics, 0);

    final g = await tester.startGesture(tester.getCenter(find.text('a')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(haptics, 1);
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(tester.getBottomLeft(find.text('c')) + const Offset(10, 30));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(titles(b)[0], ['b', 'c', 'a']);
    expect(find.textContaining('→'), findsNothing, reason: 'no undo snack within a column');
    await shutdown(tester, c);
  });

  testWidgets('dragging near the bottom edge scrolls the column; a phone side edge turns the page', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      [for (var i = 0; i < 30; i++) 'Kart $i'],
      ['X'],
    ]);
    await openKanban(tester, c, id);
    final b = c.boards.openBoard(id)!;
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    final position = tester.state<ScrollableState>(list).position;
    expect(position.pixels, 0);

    final g = await tester.startGesture(tester.getCenter(find.text('Kart 0')));
    await tester.pump(const Duration(milliseconds: 350));
    final rect = tester.getRect(list);
    await g.moveTo(Offset(rect.center.dx, rect.bottom - 10));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(50));

    // Hold at the right edge: the next column comes into view.
    await g.moveTo(Offset(phone.width - 8, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pages.page, closeTo(1, 0.01));
    await g.moveTo(Offset(phone.width / 2, rect.center.dy));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(titles(b)[1], contains('Kart 0'));
    await shutdown(tester, c);
  });

  testWidgets('column menu: rename, colour, done, move, delete with relocation', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['a'],
      ['b'],
      [],
    ]);
    await openKanban(tester, c, id, size: tablet);
    final e = c.boards.openBoard(id)!.editor;
    List<String> names() => e.columns.map((x) => x.title).toList();

    Future<void> menu(int column, String item) async {
      await tester.tap(find.byTooltip('Sütun').at(column));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await menu(0, 'Yeniden adlandır');
    await tester.enterText(find.byType(TextField), 'Fikirler');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(names(), ['Fikirler', 'Yapılıyor', 'Bitti']);

    await menu(0, 'Renk');
    await tester.tap(find.bySemanticsLabel('rose'));
    await tester.pumpAndSettle();
    expect(e.columns.first.colorIndex, 6);

    await menu(1, 'Tamamlanan sütunu');
    expect(e.columns[1].isDone, isTrue);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: 'b now shows as done');

    await menu(0, 'Sağa taşı');
    expect(names(), ['Yapılıyor', 'Fikirler', 'Bitti']);
    await menu(1, 'Sola taşı');
    expect(names(), ['Fikirler', 'Yapılıyor', 'Bitti']);

    // Deleting "Yapılıyor" moves its card to the neighbour.
    await menu(1, 'Sütunu sil');
    expect(find.text('Bu sütundaki 1 kart «Fikirler» sütununa taşınacak.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sütunu sil'));
    await tester.pumpAndSettle();
    expect(names(), ['Fikirler', 'Bitti']);
    expect(e.cardsIn(e.columns.first.id).map((x) => x.title), ['a', 'b']);

    // Undo brings the column and its card back.
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(names(), ['Fikirler', 'Yapılıyor', 'Bitti']);
    expect(e.cardsIn(e.columns[1].id).map((x) => x.title), ['b']);

    // An empty column goes without asking.
    await menu(2, 'Sütunu sil');
    expect(names(), ['Fikirler', 'Yapılıyor']);
    await menu(1, 'Sütunu sil');
    await tester.tap(find.widgetWithText(FilledButton, 'Sütunu sil'));
    await tester.pumpAndSettle();
    expect(names(), ['Fikirler']);

    // The last column offers to delete its cards too.
    await menu(0, 'Sütunu sil');
    expect(find.textContaining('Bu son sütun; içindeki 2 kart da silinecek.'), findsOneWidget);
    await tester.tap(find.text('Kartları da sil'));
    await tester.pumpAndSettle();
    expect(e.columns, isEmpty);
    expect(e.cardCount, 0);
    expect(find.text('Bu panoda henüz sütun yok.'), findsOneWidget);

    // Add a column back from the empty state.
    await tester.tap(find.widgetWithText(FilledButton, 'Sütun ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Yeni');
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(names(), ['Yeni']);
    await shutdown(tester, c);
  });

  testWidgets('the add field stays above the keyboard; the ghost column adds a column', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c, cards: [
      ['a'],
    ]);
    await openKanban(tester, c, id);
    await tester.tap(find.text('Kart ekle').first);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThanOrEqualTo(phone.height - 320));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await shutdown(tester, c);

    final c2 = await makeApp(tester);
    final id2 = await makeBoard(tester, c2);
    await openKanban(tester, c2, id2, size: const Size(1400, 900));
    await tester.tap(find.text('Sütun ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test');
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    expect(c2.boards.openBoard(id2)!.editor.columns.map((x) => x.title), ['Yapılacak', 'Yapılıyor', 'Bitti', 'Test']);
    expect(find.text('Test'), findsOneWidget);
    await shutdown(tester, c2);
  });

  testWidgets('card faces: overdue, done columns, subtasks, notes; canvas footer', (tester) async {
    final c = await makeApp(tester);
    final id = await makeBoard(tester, c);
    late String late, finished;
    await tester.runAsync(() async {
      final b = (await c.boards.open(id))!;
      final cols = b.editor.columns;
      late = b.editor.addCard(columnId: cols[0].id, title: 'Geç kalan', due: '2026-10-20', notes: 'Ayrıntı');
      b.editor.updateCard(late, {
        F.subtasks: [
          const CardSubtask(id: 's1', title: 'bir', done: true).toJson(),
          const CardSubtask(id: 's2', title: 'iki').toJson(),
        ],
      });
      finished = b.editor.addCard(columnId: cols[2].id, title: 'Bitmiş', due: '2026-10-20');
      b.editor.addSticky(at: Offset.zero, text: 'not');
      await c.boards.release(b);
    });
    await settleReal(tester);
    await openKanban(tester, c, id, size: tablet);

    expect(find.text('Gecikti · 20 Eki'), findsOneWidget);
    expect(find.text('20 Eki'), findsOneWidget, reason: 'not overdue once done');
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
    final done = find.ancestor(of: find.text('Bitmiş'), matching: find.byType(CardFace));
    expect(find.descendant(of: done, matching: find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    expect(tester.widget<CardFace>(done).card.id, finished);
    expect(
      find.bySemanticsLabel(RegExp(r'^Kart: Geç kalan\. Sütun: Yapılacak\. Son tarih: Gecikti · 20 Eki\. Alt görevler: 1/2\.$')),
      findsOneWidget,
    );
    expect(tester.widget<CardFace>(find.ancestor(of: find.text('Geç kalan'), matching: find.byType(CardFace))).card.id, late);

    expect(find.text('Tuvalde 1 not ve çizim var'), findsOneWidget);
    await tester.tap(find.text('Tuvalde gör'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardCanvasView), findsOneWidget);
    await shutdown(tester, c);
  });
}
