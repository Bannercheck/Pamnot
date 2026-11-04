import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/canvas/session.dart';
import 'package:pamnot/boards/model/board_item.dart';

import 'canvas_harness.dart';

void main() {
  testWidgets('mouse drag of a sticky moves it with one write on drop', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final id = e.addSticky(at: const Offset(700, 100));
    var writes = 0;
    e.onLocalChange = () => writes++;
    final h = await pumpCanvas(tester, board);

    final g = await tester.startGesture(const Offset(800, 200), kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(10, 5));
      await tester.pump();
    }
    expect(writes, 0, reason: 'nothing is written while dragging');
    expect(e.item(id)!.x, 700);
    expect(h.session.lifted.ids, {id});
    await g.up();
    await tester.pump();
    expect(writes, 1);
    expect(e.item(id)!.x, 800);
    expect(e.item(id)!.y, 150);
    expect(h.session.lifted.isEmpty, isTrue);
    expect(h.session.selection.value, {id});
    await unmount(tester);
  });

  testWidgets('a quick touch swipe over an unselected card pans instead of moving it', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final col = e.columns.first.id;
    final card = e.addCard(columnId: col, title: 'Logo tasarımı');
    final order = e.item(card)!.order;
    var writes = 0;
    e.onLocalChange = () => writes++;
    final h = await pumpCanvas(tester, board);
    final vp = h.session.viewport;
    final before = vp.offset;

    final g = await tester.startGesture(const Offset(150, 80));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    expect(writes, 0);
    expect(e.item(card)!.columnId, col);
    expect(e.item(card)!.order, order);
    expect(vp.offset.dy - before.dy, closeTo(180, 0.01), reason: 'the canvas followed the finger');
    expect(h.session.lifted.isEmpty, isTrue);
    await unmount(tester);
  });

  testWidgets('long-press then drag moves a card to another lane, with an undo snack', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final a = e.columns[0].id, b = e.columns[1].id;
    final card = e.addCard(columnId: a, title: 'Taşınacak');
    e.addCard(columnId: b, title: 'B1');
    var writes = 0;
    e.onLocalChange = () => writes++;
    final h = await pumpCanvas(tester, board);

    final g = await tester.startGesture(const Offset(150, 76));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.session.lifted.ids, {card}, reason: 'the long press lifts the card');
    // Into lane B, below its card.
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(32.4, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(h.session.drop.value?.columnId, b);
    await g.up();
    await tester.pump();
    expect(writes, 1);
    expect(e.item(card)!.columnId, b);
    expect(e.cardsIn(b).map((c) => c.title), ['B1', 'Taşınacak']);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('«Taşınacak» → B'), findsOneWidget);
    expect(h.session.lifted.isEmpty, isTrue);

    // The snack's undo puts it back.
    await tester.tap(find.text('Geri al'));
    await tester.pump();
    expect(e.item(card)!.columnId, a);
    await unmount(tester);
  });

  testWidgets('a card dropped outside every lane goes back, with the hint once', (tester) async {
    BoardSession.cardsHintShown = false;
    final board = makeBoard();
    final e = board.editor;
    final a = e.columns[0].id;
    final card = e.addCard(columnId: a, title: 'Kart');
    var writes = 0;
    e.onLocalChange = () => writes++;
    final h = await pumpCanvas(tester, board);

    final g = await tester.startGesture(const Offset(150, 76), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(h.session.drop.value, isNull);
    await g.up();
    await tester.pump();
    expect(writes, 0);
    expect(e.item(card)!.columnId, a);
    expect(h.session.settling, isTrue, reason: 'it animates back');
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.session.lifted.isEmpty, isTrue);
    expect(find.textContaining('Kartlar sütunlarda durur'), findsOneWidget);
    expect(BoardSession.cardsHintShown, isTrue);
    await unmount(tester);
  });

  testWidgets('dragging the lane header strip moves the block in one write', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    e.addCard(columnId: e.columns[0].id, title: 'k');
    var writes = 0;
    e.onLocalChange = () => writes++;
    final h = await pumpCanvas(tester, board);
    final g = await tester.startGesture(const Offset(474, 26), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(20, 30));
      await tester.pump();
    }
    expect(h.session.lifted.lanes, isTrue);
    expect(writes, 0);
    await g.up();
    await tester.pump();
    expect(writes, 1);
    expect(e.laneOrigin, const Offset(100, 150));
    await unmount(tester);
  });

  testWidgets('two-finger pinch zooms around the fingers', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    final vp = h.session.viewport;
    final focal = vp.toCanvas(const Offset(650, 400));
    final g1 = await tester.startGesture(const Offset(600, 400), pointer: 1);
    final g2 = await tester.startGesture(const Offset(700, 400), pointer: 2);
    for (var i = 0; i < 5; i++) {
      await g1.moveBy(const Offset(-10, 0));
      await g2.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(vp.scale, closeTo(2, 1e-9));
    expect(vp.toScreen(focal).dx, closeTo(650, 1e-6), reason: 'the point between the fingers stays put');
    await g1.up();
    await g2.up();
    await tester.pump();
    expect(h.session.selection.value, isEmpty);
    expect(board.editor.canvasItems, isEmpty, reason: 'a pinch never creates anything');
    await unmount(tester);
  });

  testWidgets('stylus draws an ink item and its eraser end removes it', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final h = await pumpCanvas(tester, board);
    await tester.tap(find.byTooltip('Kalem (P)'));
    await tester.pump();
    expect(h.session.tool.value, BoardTool.pen);

    final g = await tester.startGesture(const Offset(1000, 500), kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(6, 2));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(h.stylusSeen, 1);
    final ink = e.canvasItems.where((i) => i.kind == ItemKind.ink).toList();
    expect(ink, hasLength(1));
    // Points are relative to the item origin (its top-left).
    final scene = h.session.scene.byId(ink.single.id)!;
    expect(scene.bounds.contains(const Offset(1036, 512)), isTrue);
    expect(scene.stroke!.x(0), greaterThanOrEqualTo(0));
    expect(e.item(ink.single.id)!.x, lessThan(1000));

    final eraser = await tester.startGesture(const Offset(1036, 530), kind: PointerDeviceKind.invertedStylus);
    await eraser.moveBy(const Offset(0, -18));
    await tester.pump();
    expect(h.session.lifted.hidden, contains(ink.single.id), reason: 'erased strokes vanish at once');
    await eraser.up();
    await tester.pump();
    expect(e.item(ink.single.id)!.deleted, isTrue);
    expect(h.session.lifted.hidden, isEmpty);
    // One undo brings it back.
    h.session.undo();
    expect(e.item(ink.single.id)!.deleted, isFalse);
    await unmount(tester);
  });

  testWidgets('with stylusOnly, a finger in the pen tool pans instead of drawing', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board, stylusOnly: true);
    h.session.setTool(BoardTool.pen);
    final before = h.session.viewport.offset;
    final g = await tester.startGesture(const Offset(1000, 500));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(board.editor.canvasItems, isEmpty);
    expect(h.session.viewport.offset.dy - before.dy, closeTo(100, 0.01));
    await unmount(tester);
  });

  testWidgets('a palm (large touch) is ignored in ink tools', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    h.session.setTool(BoardTool.pen);
    final before = h.session.viewport.offset;
    await tester.sendEventToBinding(const PointerDownEvent(pointer: 9, position: Offset(1000, 500), radiusMajor: 40));
    await tester.sendEventToBinding(const PointerMoveEvent(pointer: 9, position: Offset(1000, 560), radiusMajor: 40));
    await tester.sendEventToBinding(const PointerUpEvent(pointer: 9, position: Offset(1000, 560)));
    await tester.pump();
    expect(board.editor.canvasItems, isEmpty);
    expect(h.session.viewport.offset, before);
    await unmount(tester);
  });

  testWidgets('a second finger soon after a finger stroke cancels it and pinches', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    h.session.setTool(BoardTool.pen);
    final g1 = await tester.startGesture(const Offset(900, 400), pointer: 1);
    await g1.moveBy(const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 50));
    final g2 = await tester.startGesture(const Offset(1000, 400), pointer: 2);
    await tester.pump();
    expect(h.session.activeInk.stroke, isNull);
    for (var i = 0; i < 4; i++) {
      await g2.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();
    expect(board.editor.canvasItems, isEmpty, reason: 'no stray dot from the pinch');
    expect(h.session.viewport.scale, greaterThan(1.2));
    await unmount(tester);
  });

  testWidgets('double-tap on empty space creates a sticky and opens its editor', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    await tester.tapAt(const Offset(1000, 600));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(1000, 600));
    await tester.pumpAndSettle();
    final stickies = board.editor.canvasItems.where((i) => i.kind == ItemKind.sticky).toList();
    expect(stickies, hasLength(1));
    expect(stickies.single.x, 900, reason: 'centred where tapped');
    expect(h.session.editing.value, stickies.single.id);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Fikir');
    // Tapping elsewhere commits.
    await tester.tapAt(const Offset(1100, 300));
    await tester.pump();
    expect(h.session.editing.value, isNull);
    expect(board.editor.item(stickies.single.id)!.text, 'Fikir');
    await unmount(tester);
  });

  testWidgets('double-tap on a card opens the card sheet', (tester) async {
    final board = makeBoard();
    final card = board.editor.addCard(columnId: board.editor.columns[1].id, title: 'Kart');
    final h = await pumpCanvas(tester, board);
    await tester.tapAt(const Offset(474, 76));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(474, 76));
    await tester.pump();
    expect(h.opened, [card]);
    expect(h.session.selection.value, {card});
    await unmount(tester);
  });

  testWidgets('Delete removes the selection but not while editing text', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final a = e.addSticky(at: const Offset(700, 100), text: 'bir');
    final b = e.addSticky(at: const Offset(950, 450), text: 'iki');
    final h = await pumpCanvas(tester, board);
    await tester.tapAt(const Offset(800, 200), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.session.selection.value, {a});
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(e.item(a)!.deleted, isTrue);
    expect(h.session.selection.value, isEmpty);

    // Edit b, then press Backspace and Delete: they edit the text.
    await tester.tapAt(const Offset(1050, 550), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(1050, 550), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.session.editing.value, b);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(e.item(b)!.deleted, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ik',
      reason: 'Backspace edited the text',
    );
    expect(e.canvasItems.where((i) => i.kind == ItemKind.sticky), hasLength(1), reason: 'N did not add a sticky');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(h.session.editing.value, isNull);
    expect(e.item(b)!.deleted, isFalse);
    // Back on the canvas, Delete works again.
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(e.item(b)!.deleted, isTrue);
    await unmount(tester);
  });

  testWidgets('undo and redo from the keyboard and the toolbar', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final s = e.addSticky(at: const Offset(700, 100));
    await pumpCanvas(tester, board);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(e.item(s)!.deleted, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(e.item(s)!.deleted, isFalse);
    await tester.tap(find.byTooltip('Geri al'));
    await tester.pump();
    expect(e.item(s)!.deleted, isTrue);
    await tester.tap(find.byTooltip('Yinele'));
    await tester.pump();
    expect(e.item(s)!.deleted, isFalse);
    await unmount(tester);
  });

  testWidgets('mouse marquee selects what it touches; wheel pans, ctrl+wheel zooms', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final a = e.addSticky(at: const Offset(700, 450));
    final b = e.addSticky(at: const Offset(950, 450));
    final h = await pumpCanvas(tester, board);
    final g = await tester.startGesture(const Offset(680, 430), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(1000, 500));
    await tester.pump();
    expect(h.session.marquee.value, isNotNull);
    await g.up();
    await tester.pump();
    expect(h.session.selection.value, {a, b});
    expect(h.session.marquee.value, isNull);

    final vp = h.session.viewport;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(600, 400)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(vp.offset.dy, closeTo(-120, 0.01));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final focal = vp.toCanvas(const Offset(600, 400));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vp.scale, greaterThan(2.5));
    expect(vp.toScreen(focal).dy, closeTo(400, 1e-6));
    await unmount(tester);
  });

  testWidgets('trackpad pan/zoom moves the view', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    final vp = h.session.viewport;
    final pointer = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(const Offset(600, 400)));
    final anchor = vp.toCanvas(const Offset(600, 400));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(const Offset(600, 400), pan: const Offset(30, 10), scale: 1.5),
    );
    await tester.pump();
    expect(vp.scale, closeTo(1.5, 1e-9));
    expect(vp.toScreen(anchor).dx, closeTo(630, 1e-6), reason: 'the point under the fingers moved with the pan');
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();
    await unmount(tester);
  });

  testWidgets('read-only boards draw nothing new', (tester) async {
    final board = makeBoard();
    board.editor.addSticky(at: const Offset(700, 100));
    board.doc.state = BoardState.revoked;
    final h = await pumpCanvas(tester, board);
    await tester.tapAt(const Offset(1000, 600));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(1000, 600));
    await tester.pumpAndSettle();
    expect(board.editor.canvasItems, hasLength(1));
    final g = await tester.startGesture(const Offset(800, 200), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(50, 50));
    await g.up();
    await tester.pump();
    expect(board.editor.canvasItems.single.x, 700);
    h.session.setTool(BoardTool.pen);
    expect(h.session.tool.value, BoardTool.select);
    await unmount(tester);
  });
}
