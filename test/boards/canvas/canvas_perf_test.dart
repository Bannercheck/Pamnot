// Headless paint/record timings for a large generated board. The numbers
// are from the debug JIT in flutter_tester, so the thresholds are generous
// (an order of magnitude above what is measured) and the test is about
// catching regressions in kind (e.g. per-frame work over the whole board),
// not about absolute speed. The real gate is the profile-mode run on a
// device (DESIGN.md §8).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/canvas/item_painter.dart';
import 'package:pamnot/boards/canvas/painters.dart';
import 'package:pamnot/boards/canvas/retained_picture.dart';
import 'package:pamnot/boards/canvas/session.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/ink.dart';
import 'package:pamnot/theme/pamnot_theme.dart';

import 'canvas_harness.dart';

class _Host implements BoardCanvasHost {
  @override
  bool get inlineEditing => true;
  @override
  bool get stylusOnly => false;
  @override
  EdgeInsets get chromeInsets => EdgeInsets.zero;
  @override
  S get strings => S.tr;
  @override
  Future<String?> editStickyInSheet(String stickyId, String text) async => null;
  @override
  void openCard(String cardId) {}
  @override
  void showSnack(String text, {VoidCallback? undo}) {}
  @override
  void showItemMenu(Offset screen) {}
  @override
  void renameColumn(String columnId) {}
  @override
  void stylusDetected() {}
  @override
  void viewChanged() {}
}

const _words = ['müşteri', 'tasarım', 'sprint', 'rapor', 'toplantı', 'logo', 'geri bildirim', 'yayın', 'test', 'plan'];

/// 900 cards in 6 lanes, 2,100 stickies and 2,000 strokes: 5,000 items.
OpenBoard generatedBoard() {
  final board = makeBoard(columns: [for (var i = 0; i < 6; i++) ('Sütun $i', i, i == 5)]);
  final e = board.editor;
  final r = math.Random(7);
  String words(int n) => [for (var i = 0; i < n; i++) _words[r.nextInt(_words.length)]].join(' ');
  e.batch(() {
    for (final c in e.columns) {
      for (var i = 0; i < 150; i++) {
        e.addCard(
          columnId: c.id,
          title: words(2 + r.nextInt(10)),
          due: i % 4 == 0 ? '2026-11-${(1 + i % 28).toString().padLeft(2, '0')}' : null,
          notes: i % 3 == 0 ? 'not' : '',
        );
      }
    }
    // Stickies in a grid to the right of the lanes (lanes end at x = 1920).
    for (var i = 0; i < 2100; i++) {
      e.addSticky(
        at: Offset(2000 + (i % 60) * 230.0, (i ~/ 60) * 230.0),
        text: words(1 + r.nextInt(14)),
        colorIndex: i % 8,
      );
    }
    // Strokes scattered over the same area, 60–140 points each.
    for (var i = 0; i < 2000; i++) {
      final n = 60 + r.nextInt(80);
      var x = 0.0, y = 0.0;
      final pts = <double>[];
      for (var k = 0; k < n; k++) {
        x += r.nextDouble() * 4;
        y += r.nextDouble() * 4 - 2;
        pts.addAll([x, y, 0.5, k * 8.0]);
      }
      final s = InkStroke(data: Float32List.fromList(pts), color: inkColors[i % inkColors.length].toARGB32(), width: 3);
      e.addInk(origin: Offset(2000 + r.nextDouble() * 13800, r.nextDouble() * 8000), strokes: InkCodec.encode([s]));
    }
  });
  return board;
}

double _ms(int micros) => micros / 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('5,000 items with 2,000 strokes: world paint at LOD 2, 1 and 0', () {
    final sw = Stopwatch()..start();
    final board = generatedBoard();
    final genMs = sw.elapsedMilliseconds;
    expect(board.editor.cardCount + board.editor.canvasItems.length, 5000);
    expect(board.editor.canvasItems.where((i) => i.kind == ItemKind.ink).length, 2000);

    sw.reset();
    final session = BoardSession(board: board, vsync: const TestVSync(), host: _Host());
    final sceneMs = sw.elapsedMilliseconds;
    final vp = session.viewport..setSize(const Size(1366, 1024));
    final palette = BoardPalette.of(PamnotTheme.light());
    final world = BoardWorldPainter(session, palette, S.tr);
    const size = Size(1366, 1024);

    int paintOnce() {
      final t = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      world.paint(Canvas(rec), size);
      rec.endRecording().dispose();
      return t.elapsedMicroseconds;
    }

    int median(List<int> xs) => (xs..sort())[xs.length ~/ 2];

    // LOD 2 over the densest region: stickies and ink overlap there.
    vp.centerOn(const Offset(2700, 600), 1.0);
    expect(vp.lod, 2);
    final cold = paintOnce();
    // Let the per-frame budgets finish their work, as frames would.
    sw.reset();
    session.outlines.pump(const Duration(seconds: 30));
    final outlineMs = sw.elapsedMilliseconds;
    for (var i = 0; i < 400; i++) {
      paintOnce();
    }
    final lod2 = median([for (var i = 0; i < 15; i++) paintOnce()]);

    // Lanes at detail zoom: cards with text, chips and icons.
    vp.centerOn(const Offset(960, 500), 1.0);
    for (var i = 0; i < 200; i++) {
      paintOnce();
    }
    final lanes2 = median([for (var i = 0; i < 15; i++) paintOnce()]);

    // LOD 1 and 0: one recording of the whole board per level.
    final overview = BoardOverviewSource(session, palette, S.tr);
    int recordOverview() {
      final t = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      overview.record(Canvas(rec));
      rec.endRecording().dispose();
      return t.elapsedMicroseconds;
    }

    vp.centerOn(const Offset(8000, 4000), 0.3);
    expect(vp.lod, 1);
    final record1 = recordOverview();
    vp.centerOn(const Offset(8000, 4000), 0.05);
    expect(vp.lod, 0);
    final record0 = recordOverview();
    session.outlines.pump(const Duration(seconds: 30));
    final record0Paths = recordOverview();

    // A drag of 200 stickies is recorded once per lift.
    vp.centerOn(const Offset(2700, 600), 1.0);
    final ids = [for (final si in session.scene.free.where((s) => s.kind == ItemKind.sticky).take(200)) si.id];
    session.lifted.lift(ids.toSet());
    final lifted = LiftedSource(session, palette, S.tr);
    final t = Stopwatch()..start();
    final rec = ui.PictureRecorder();
    lifted.record(Canvas(rec));
    rec.endRecording().dispose();
    final liftRecord = t.elapsedMicroseconds;
    session.lifted.drop();

    // ignore: avoid_print
    print('''
canvas perf (debug JIT, flutter_tester; compare relative numbers only)
  generate board: $genMs ms; scene build (900 card measures, 2,000 stroke decodes): $sceneMs ms
  outline build for the strokes that paint queued: $outlineMs ms (3 ms per frame in the app)
  LOD 2 dense region: first paint ${_ms(cold)} ms (budgeted), warm ${_ms(lod2)} ms
  LOD 2 lanes (cards with text): ${_ms(lanes2)} ms
  LOD 1 overview recording ${_ms(record1)} ms; LOD 0 ${_ms(record0)} ms (polylines), ${_ms(record0Paths)} ms (outlines)
  lift of 200 stickies: recording ${_ms(liftRecord)} ms''');

    expect(_ms(cold), lessThan(250), reason: 'the first frame is budgeted, not proportional to the board');
    expect(_ms(lod2), lessThan(60));
    expect(_ms(lanes2), lessThan(60));
    expect(_ms(record1), lessThan(1000));
    expect(_ms(record0), lessThan(1000));
    expect(_ms(liftRecord), lessThan(200));
    session.dispose();
  });

  testWidgets('panning at overview zoom and dragging 200 items record nothing per frame', (tester) async {
    final board = generatedBoard();
    final h = await pumpCanvas(
      tester,
      board,
      size: const Size(1366, 1024),
      view: const BoardViewState(view: 'canvas', offset: Offset(8000, 4000), scale: 0.3, fitted: true),
    );
    final vp = h.session.viewport;
    expect(vp.lod, 1);
    final layers = tester.renderObjectList<RenderRetainedPicture>(find.byType(RetainedPicture)).toList();
    final overview = layers[0], lifted = layers[1];
    expect(overview.debugRecordCount, 1);
    final firstRecord = overview.lastRecordMicros;
    // Stroke outlines are built a few milliseconds per frame; when the
    // queue runs dry the overview records once more, with real outlines.
    var frames = 0;
    while (h.session.outlines.busy && frames++ < 500) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    // A slow recording (a loaded test machine) is deferred by the throttle;
    // give its retry timer a chance to fire.
    await tester.pump(RenderRetainedPicture.rerecordEvery);
    await tester.pump();
    expect(h.session.outlines.busy, isFalse);
    expect(overview.debugRecordCount, 2);
    // ignore: avoid_print
    print('outlines for 2,000 strokes built over $frames frames');

    int frame(void Function() change) {
      change();
      final t = Stopwatch()..start();
      tester.binding.handleBeginFrame(null);
      tester.binding.handleDrawFrame();
      return t.elapsedMicroseconds;
    }

    int median(List<int> xs) => (xs..sort())[xs.length ~/ 2];
    final pan1 = median([for (var i = 0; i < 30; i++) frame(() => vp.panBy(const Offset(7, 3)))]);
    final zoom1 = median([for (var i = 0; i < 20; i++) frame(() => vp.zoomAt(const Offset(683, 512), 1.01))]);
    expect(vp.lod, 1);
    expect(overview.debugRecordCount, 2, reason: 'pan and zoom move a transform; the board is not re-recorded');

    vp.centerOn(const Offset(8000, 4000), 0.05);
    await tester.pump();
    expect(vp.lod, 0);
    // Recording this board takes over 4 ms, so a level change shows the
    // stale picture and records within 200 ms.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(overview.debugRecordCount, 3);
    final pan0 = median([for (var i = 0; i < 30; i++) frame(() => vp.panBy(const Offset(7, 3)))]);
    expect(overview.debugRecordCount, 3);

    // A drag of 200 stickies at detail zoom: one recording, then transforms.
    vp.centerOn(const Offset(2700, 600), 1.0);
    await tester.pump();
    final ids = [for (final si in h.session.scene.free.where((s) => s.kind == ItemKind.sticky).take(200)) si.id];
    h.session.lifted.lift(ids.toSet());
    await tester.pump();
    final liftedRecords = lifted.debugRecordCount;
    final drag = median([for (var i = 0; i < 30; i++) frame(() => h.session.lifted.move(Offset(i * 4.0, i * 2.0)))]);
    expect(lifted.debugRecordCount, liftedRecords, reason: 'moving lifted items records nothing');
    h.session.lifted.drop();
    await tester.pump();

    // ignore: avoid_print
    print('''
canvas frames (debug JIT, flutter_tester, whole pipeline incl. grid/overlay)
  overview first recording ${_ms(firstRecord)} ms
  LOD 1 pan frame ${_ms(pan1)} ms, zoom frame ${_ms(zoom1)} ms; LOD 0 pan frame ${_ms(pan0)} ms
  drag of 200 stickies: frame ${_ms(drag)} ms''');
    expect(_ms(pan1), lessThan(40));
    expect(_ms(zoom1), lessThan(40));
    expect(_ms(pan0), lessThan(40));
    expect(_ms(drag), lessThan(40));
    await unmount(tester);
  });
}
