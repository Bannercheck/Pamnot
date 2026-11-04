import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/canvas/board_canvas_view.dart';
import 'package:pamnot/boards/canvas/presence.dart';
import 'package:pamnot/boards/canvas/session.dart';
import 'package:pamnot/boards/canvas/toolbar.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';

import 'canvas_harness.dart';

class _LiveConnection implements BoardConnection {
  final peersN = ValueNotifier<List<Peer>>(const []);
  final cursorsN = ValueNotifier<Map<String, PeerCursor>>(const {});
  final sent = <Offset?>[];
  final activity = <(String, String?)>[];

  @override
  ValueListenable<List<Peer>> get peers => peersN;

  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => cursorsN;

  @override
  ValueListenable<SyncState> get state => ValueNotifier(const SyncState(SyncStatus.synced));

  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) => sent.add(canvasPosition);

  @override
  void setActivity({required String view, String? editing}) => activity.add((view, editing));

  @override
  void kick() {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('first open zooms to fit and remembers it; later opens restore the view', (tester) async {
    final board = makeBoard();
    board.editor.addSticky(at: const Offset(3000, 2000));
    final h = await pumpCanvas(tester, board, useDefaultView: false);
    final vp = h.session.viewport;
    expect(vp.scale, lessThan(1));
    final content = h.session.scene.contentBounds;
    final shown = vp.visibleCanvasRect;
    expect(shown.contains(content.topLeft) && shown.contains(content.bottomRight), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(h.views, isNotEmpty);
    expect(h.views.last.fitted, isTrue);
    expect(h.views.last.view, 'canvas');
    await unmount(tester);

    // Restored at the saved centre and scale.
    final saved = BoardViewState(view: 'canvas', offset: const Offset(500, 300), scale: 0.75, fitted: true);
    final h2 = await pumpCanvas(tester, board, view: saved);
    expect(h2.session.viewport.scale, 0.75);
    expect(h2.session.viewport.canvasCenter, offsetMoreOrLessEquals(const Offset(500, 300)));
    // A pan is reported once it settles, and again on dispose if pending.
    h2.session.viewport.panBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h2.views, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(h2.views, hasLength(1));
    h2.session.viewport.panBy(const Offset(10, 0));
    await unmount(tester);
    expect(h2.views, hasLength(2), reason: 'saved on dispose');
  });

  testWidgets('phone: bottom pill, stickies edited in a sheet', (tester) async {
    final board = makeBoard();
    final s = board.editor.addSticky(at: const Offset(0, 500), text: 'eski');
    final h = await pumpCanvas(
      tester,
      board,
      size: const Size(390, 844),
      view: const BoardViewState(view: 'canvas', offset: Offset(100, 600), scale: 1, fitted: true),
    );
    expect(find.byType(PhoneToolbar), findsOneWidget);
    expect(find.byType(WideToolbar), findsNothing);
    expect(find.byType(ZoomControls), findsNothing);
    // Sticky (0..200, 500..700) is at screen (95..295, 322..522).
    await tester.tapAt(const Offset(195, 420));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(195, 420));
    await tester.pumpAndSettle();
    expect(find.text('Yapışkan not'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'yeni metin');
    // Closing the sheet any way commits.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(board.editor.item(s)!.text, 'yeni metin');
    expect(h.session.editing.value, isNull);
    await unmount(tester);
  });

  testWidgets('phone: Kalem shows the ink row; Not adds a sticky in the middle', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board, size: const Size(390, 844));
    await tester.tap(find.byTooltip('Kalem'));
    await tester.pump();
    expect(h.session.tool.value, BoardTool.pen);
    expect(find.byType(InkOptions), findsOneWidget);
    await tester.tap(find.byTooltip('Fosforlu').first);
    await tester.pump();
    expect(h.session.tool.value, BoardTool.highlighter);
    await tester.tap(find.byTooltip('Kalem'));
    await tester.pump();
    expect(h.session.tool.value, BoardTool.select, reason: 'tapping the active ink tool goes back to Seç');
    await tester.tap(find.byTooltip('Not'));
    await tester.pumpAndSettle();
    final stickies = board.editor.canvasItems.where((i) => i.kind == ItemKind.sticky).toList();
    expect(stickies, hasLength(1));
    final centre = h.session.viewport.toScreen(Offset(stickies.single.x + 100, stickies.single.y + 100));
    expect(centre.dx, closeTo(195, 1));
    // The phone edits in a sheet.
    expect(find.text('Yapışkan not'), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('wide: Kart adds a card to the first open column and opens it', (tester) async {
    final board = makeBoard(columns: const [('Bitti', 2, true), ('Yapılacak', 3, false)]);
    final h = await pumpCanvas(tester, board);
    h.session.setTool(BoardTool.pen);
    await tester.tap(find.byTooltip('Kart (K)'));
    await tester.pumpAndSettle();
    expect(h.session.tool.value, BoardTool.select, reason: 'Not and Kart go back to Seç');
    expect(h.opened, hasLength(1));
    final card = board.editor.item(h.opened.single)!;
    expect(card.columnId, board.editor.columns[1].id);
    await unmount(tester);
  });

  testWidgets('selection toolbar: colours, turn into card, hidden while dragging', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final s = e.addSticky(at: const Offset(700, 400), text: 'Başlık\nAyrıntı');
    final h = await pumpCanvas(tester, board);
    await tester.tapAt(const Offset(800, 500), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Karta dönüştür'), findsOneWidget);

    // It hides while the sticky is dragged and comes back after.
    final g = await tester.startGesture(const Offset(800, 500), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(find.byTooltip('Karta dönüştür'), findsNothing);
    await g.up();
    await tester.pump();
    expect(find.byTooltip('Karta dönüştür'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('Renk sky')));
    await tester.pump();
    expect(e.item(s)!.colorIndex, 4);
    await tester.tap(find.byTooltip('Karta dönüştür'));
    await tester.pump();
    expect(e.item(s)!.deleted, isTrue);
    final card = e.cardsIn(e.columns.first.id).single;
    expect(card.title, 'Başlık');
    expect(card.notes, 'Ayrıntı');
    expect(h.session.selection.value, {card.id});
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('peers: cursors drawn from the connection, editing reported, own cursor sent', (tester) async {
    final board = makeBoard();
    final conn = _LiveConnection();
    board.connection = conn;
    final s = board.editor.addSticky(at: const Offset(700, 400));
    final h = await pumpCanvas(tester, board);
    conn.peersN.value = const [Peer(key: 'p1', userId: 'u1', name: 'Mert', colorIndex: 4)];
    conn.cursorsN.value = {
      'p1': PeerCursor(key: 'p1', name: 'Mert', colorIndex: 4, position: const Offset(300, 300), at: DateTime(2026)),
    };
    await tester.pump(const Duration(milliseconds: 16));
    final model = h.session.presence;
    expect(model.dots.single.name, 'Mert');
    conn.cursorsN.value = {
      'p1': PeerCursor(key: 'p1', name: 'Mert', colorIndex: 4, position: const Offset(400, 300), at: DateTime(2026)),
    };
    await tester.pump(const Duration(milliseconds: 16));
    expect(model.animating, isTrue);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(model.dots.single.position.dx, 400);
    expect(model.animating, isFalse, reason: 'the ticker stops once settled');
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is PresencePainter), findsOneWidget);

    // Hovering sends this device's cursor in canvas units; leaving clears it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1000, 100));
    await mouse.moveTo(const Offset(1010, 120));
    await tester.pump();
    expect(conn.sent.whereType<Offset>(), isNotEmpty);
    expect(conn.sent.last, const Offset(1010, 120));
    await mouse.removePointer();

    // Editing a sticky tells the others.
    await tester.tapAt(const Offset(800, 500));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(800, 500));
    await tester.pumpAndSettle();
    expect(conn.activity.last, ('canvas', s));
    await tester.tapAt(const Offset(1100, 300));
    await tester.pump();
    expect(conn.activity.last, ('canvas', null));
    await tester.pump(const Duration(seconds: 11));
    await unmount(tester);
  });

  testWidgets('a teammate editing an item is shown on the canvas', (tester) async {
    final board = makeBoard();
    final conn = _LiveConnection();
    board.connection = conn;
    final s = board.editor.addSticky(at: const Offset(700, 400));
    final h = await pumpCanvas(tester, board);
    conn.peersN.value = [Peer(key: 'p1', userId: 'u1', name: 'Ayşe', colorIndex: 6, editing: s)];
    await tester.pump();
    expect(h.session.peers.value.single.editing, s);
    await unmount(tester);
  });

  testWidgets('reduced motion: fit and zoom jump instead of animating', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board, disableAnimations: true);
    expect(h.session.reduceMotion, isTrue);
    await tester.tap(find.byTooltip('Yakınlaştır'));
    await tester.pump();
    expect(h.session.viewport.scale, closeTo(1.25, 1e-9));
    expect(h.session.animatingView, isFalse);
    await unmount(tester);
  });

  testWidgets('one semantics label summarises the canvas', (tester) async {
    final board = makeBoard();
    board.editor.addSticky(at: const Offset(700, 400));
    final handle = tester.ensureSemantics();
    await pumpCanvas(tester, board);
    expect(find.bySemanticsLabel('Tuval, 1 öğe. Liste için Kanban görünümüne geç.'), findsOneWidget);
    board.editor.addCard(columnId: board.editor.columns.first.id, title: 'k');
    await tester.pump();
    expect(find.bySemanticsLabel('Tuval, 2 öğe. Liste için Kanban görünümüne geç.'), findsOneWidget);
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('a touch fling keeps panning after the finger lifts', (tester) async {
    final board = makeBoard();
    final h = await pumpCanvas(tester, board);
    final vp = h.session.viewport;
    final pointer = TestPointer(5);
    var t = const Duration(seconds: 1);
    await tester.sendEventToBinding(pointer.down(const Offset(1000, 400), timeStamp: t));
    for (var i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 10);
      await tester.sendEventToBinding(pointer.move(Offset(1000 - 30.0 * (i + 1), 400), timeStamp: t));
    }
    await tester.sendEventToBinding(pointer.up(timeStamp: t));
    final atUp = vp.offset.dx;
    expect(h.session.flinging, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(vp.offset.dx, lessThan(atUp - 50));
    // A new touch stops it.
    await tester.tapAt(const Offset(1000, 400));
    expect(h.session.flinging, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('dragging a sticky to the edge auto-pans', (tester) async {
    final board = makeBoard();
    final s = board.editor.addSticky(at: const Offset(900, 300));
    final h = await pumpCanvas(tester, board);
    final vp = h.session.viewport;
    final g = await tester.startGesture(const Offset(1000, 400), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(1190, 400));
    await tester.pump();
    final before = vp.offset.dx;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(vp.offset.dx, lessThan(before - 20), reason: 'the view moves right under the pointer');
    await g.up();
    await tester.pump();
    // The sticky stayed under the pointer the whole way.
    final x = board.editor.item(s)!.x;
    expect(vp.toScreen(Offset(x + 100, 0)).dx, closeTo(1190, 0.5));
    await unmount(tester);
  });

  testWidgets('closing the canvas mid-edit keeps the text; a second edit keeps the first', (tester) async {
    final board = makeBoard();
    final e = board.editor;
    final a = e.addSticky(at: const Offset(700, 100));
    final b = e.addSticky(at: const Offset(950, 450));
    final h = await pumpCanvas(tester, board);
    unawaited(h.session.beginEdit(a));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ilk');
    unawaited(h.session.beginEdit(b));
    await tester.pumpAndSettle();
    expect(e.item(a)!.text, 'ilk');
    expect(h.session.editing.value, b);
    await tester.enterText(find.byType(TextField), 'yarım kaldı');
    await tester.pumpWidget(const SizedBox());
    expect(e.item(b)!.text, 'yarım kaldı');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('inside an outer PageView the canvas keeps touch and trackpad pans', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final board = makeBoard();
    final pages = PageController();
    addTearDown(pages.dispose);
    final app = AppController(store: MemoryStore(), saveDelay: Duration.zero);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      AppScope(
        controller: app,
        child: MaterialApp(
          home: Scaffold(
            // An outer scrollable that takes every device, trackpads included.
            body: PageView(
              scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              controller: pages,
              children: [
                BoardCanvasView(
                  board: board,
                  viewState: const BoardViewState(view: 'canvas', offset: Offset(600, 400), scale: 1, fitted: true),
                  onViewChanged: (_) {},
                  onOpenCard: (_) {},
                  stylusOnly: false,
                ),
                const Center(child: Text('Kanban')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final session = debugCanvasSession(tester.state(find.byType(BoardCanvasView)));
    final vp = session.viewport;
    // Checked mid-gesture: a page view that took part would spring back
    // after it.
    final g = await tester.startGesture(const Offset(1000, 400));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-50, 0));
      await tester.pump();
    }
    expect(pages.position.pixels, 0);
    await g.up();
    await tester.pumpAndSettle();
    expect(vp.offset.dx, closeTo(-400, 0.01));
    final pointer = TestPointer(3, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(const Offset(1000, 400)));
    for (var i = 1; i <= 6; i++) {
      await tester.sendEventToBinding(pointer.panZoomUpdate(const Offset(1000, 400), pan: Offset(-50.0 * i, 0)));
      await tester.pump();
    }
    expect(pages.position.pixels, 0, reason: 'trackpad pans belong to the canvas too');
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(vp.offset.dx, closeTo(-700, 0.01));
    await unmount(tester);
  });
}
