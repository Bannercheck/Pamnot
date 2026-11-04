import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/canvas/board_text.dart';
import 'package:pamnot/boards/canvas/lanes.dart';
import 'package:pamnot/boards/canvas/painters.dart';
import 'package:pamnot/boards/canvas/presence.dart';
import 'package:pamnot/boards/canvas/scene.dart';
import 'package:pamnot/boards/canvas/viewport.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/models/ink.dart';

import 'canvas_harness.dart';

String strokeAt(List<Offset> pts, {double width = 4}) => InkCodec.encode([
  InkStroke(
    data: Float32List.fromList([
      for (final p in pts) ...[p.dx, p.dy, 0.5, 0],
    ]),
    color: 0xFF3E3A4A,
    width: width,
  ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardViewport', () {
    BoardViewport vp() => BoardViewport()..setSize(const Size(1000, 800));

    test('toCanvas and toScreen are inverses', () {
      final v = vp()..set(const Offset(120, -40), 2.5);
      for (final p in [Offset.zero, const Offset(333, 21), const Offset(-50, 900)]) {
        expect(v.toScreen(v.toCanvas(p)), offsetMoreOrLessEquals(p));
      }
      expect(v.toScreen(const Offset(10, 10)), const Offset(145, -15));
      expect(v.visibleCanvasRect, rectMoreOrLessEquals(const Rect.fromLTWH(-48, 16, 400, 320)));
      expect(v.matrix[0], 2.5);
      expect(v.matrix[12], 120);
      expect(v.matrix[13], -40);
    });

    test('zoomAt keeps the canvas point under the focal point', () {
      final v = vp();
      const focal = Offset(300, 200);
      final c = v.toCanvas(focal);
      v.zoomAt(focal, 1.7);
      expect(v.toScreen(c), offsetMoreOrLessEquals(focal));
      v.zoomAt(focal, 0.3);
      expect(v.toScreen(c), offsetMoreOrLessEquals(focal));
      expect(v.scale, closeTo(0.51, 1e-9));
    });

    test('scale is clamped; the minimum follows the board', () {
      final v = vp();
      v.zoomAt(Offset.zero, 100);
      expect(v.scale, BoardViewport.maxScale);
      v.zoomAt(Offset.zero, 1e-6);
      expect(v.scale, BoardViewport.minScaleCeiling);
      v.setFitScale(0.01);
      expect(v.minScale, BoardViewport.minScaleFloor);
      v.zoomAt(Offset.zero, 1e-6);
      expect(v.scale, BoardViewport.minScaleFloor);
      v.setFitScale(0.5);
      expect(v.minScale, BoardViewport.minScaleCeiling);
      expect(v.scale, BoardViewport.minScaleCeiling, reason: 'raised to the new minimum');
    });

    test('pan is clamped to the world and near the content', () {
      final v = vp();
      v.panBy(const Offset(-1e9, 0));
      expect(v.canvasCenter.dx, closeTo(BoardViewport.worldLimit, 1e-6));
      v.contentBounds = const Rect.fromLTWH(0, 0, 500, 500);
      v.centerOn(const Offset(100000, 0), 1);
      expect(v.canvasCenter.dx, closeTo(500 + 1000, 1e-6), reason: 'within a screen of the content');
    });

    test('resizing keeps the centre', () {
      final v = vp()..centerOn(const Offset(42, 24), 1.5);
      v.setSize(const Size(400, 900));
      expect(v.canvasCenter, offsetMoreOrLessEquals(const Offset(42, 24)));
    });

    test('zoom percentage only notifies when the number changes', () {
      final v = vp();
      var n = 0;
      v.zoomPercent.addListener(() => n++);
      v.zoomAt(Offset.zero, 1.001);
      expect(n, 0);
      v.zoomAt(Offset.zero, 1.2);
      expect(n, 1);
      expect(v.zoomPercent.value, 120);
    });

    test('silent changes notify once on flush', () {
      final v = vp();
      var n = 0;
      v.addListener(() => n++);
      v.silently(() => v.centerOn(const Offset(5, 5), 2));
      expect(n, 0);
      expect(v.scale, 2);
      v.flush();
      expect(n, 1);
      expect(v.zoomPercent.value, 200);
    });
  });

  group('level of detail', () {
    test('hysteresis between levels', () {
      expect(lodFor(1, 2), 2);
      expect(lodFor(0.40, 2), 2, reason: 'stays detailed down to 0.38');
      expect(lodFor(0.37, 2), 1);
      expect(lodFor(0.40, 1), 1, reason: 'needs 0.42 to come back');
      expect(lodFor(0.42, 1), 2);
      expect(lodFor(0.15, 1), 1, reason: 'stays at 1 down to 0.14');
      expect(lodFor(0.13, 1), 0);
      expect(lodFor(0.15, 0), 0, reason: 'needs 0.16 to come back');
      expect(lodFor(0.16, 0), 1);
      expect(lodFor(0.5, 0), 2);
      expect(lodFor(0.1, 2), 0);
    });

    test('the viewport tracks the level through a pinch', () {
      final v = BoardViewport()..setSize(const Size(800, 600));
      final seen = <int>[];
      for (final s in [1.0, 0.5, 0.39, 0.37, 0.40, 0.41, 0.2, 0.145, 0.13, 0.15, 0.17, 0.5]) {
        v.centerOn(Offset.zero, s);
        seen.add(v.lod);
      }
      expect(seen, [2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 1, 2]);
    });

    test('grid spacing doubles to stay at least 18 px apart', () {
      expect(GridPainter.spacingFor(0.5), 40);
      expect(GridPainter.spacingFor(0.45), 40);
      expect(GridPainter.spacingFor(0.44), 80);
      expect(GridPainter.spacingFor(0.15), 160);
      expect(GridPainter.spacingFor(1), 20);
      expect(GridPainter.spacingFor(4), 5);
      for (final s in [0.15, 0.2, 0.33, 0.7, 1.3, 4.0]) {
        expect(GridPainter.spacingFor(s) * s, greaterThanOrEqualTo(18));
        expect(GridPainter.spacingFor(s) * s, lessThan(36.01));
      }
    });
  });

  group('lanes', () {
    test('layout: widths, gaps, header, padding and the shared height', () {
      final l = LaneLayout.compute(const Offset(100, 50), [
        ('a', [('c1', 60.0), ('c2', 80.0)]),
        ('b', const []),
      ]);
      expect(l.lanes[0].rect, const Rect.fromLTWH(100, 50, 300, 420));
      expect(l.lanes[1].rect.left, 100 + 300 + 24);
      expect(l.cardRect('c1'), const Rect.fromLTWH(112, 102, 276, 60));
      expect(l.cardRect('c2'), const Rect.fromLTWH(112, 174, 276, 80));
      expect(l.bounds, const Rect.fromLTRB(100, 50, 724, 470));
    });

    test('tall lanes grow and all lanes share the tallest height', () {
      final l = LaneLayout.compute(Offset.zero, [
        ('a', [for (var i = 0; i < 6; i++) ('c$i', 100.0)]),
        ('b', const []),
      ]);
      // 52 header + 6 × 100 + 5 × 12 gaps + 12 bottom padding.
      expect(l.lanes[0].rect.height, 52 + 600 + 60 + 12);
      expect(l.lanes[1].rect.height, l.lanes[0].rect.height);
    });

    test('drop position maps to (column, index among the others)', () {
      final l = LaneLayout.compute(Offset.zero, [
        ('a', [('c1', 60.0), ('c2', 60.0), ('c3', 60.0)]),
        ('b', [('d1', 60.0)]),
      ]);
      // c1 52..112, c2 124..184, c3 196..256.
      expect(l.dropTarget(const Offset(150, 60)), (columnId: 'a', index: 0));
      expect(l.dropTarget(const Offset(150, 150)), (columnId: 'a', index: 1));
      expect(l.dropTarget(const Offset(150, 300)), (columnId: 'a', index: 3));
      // Moving c1 down past c2 within its own lane: c1 is not counted.
      expect(l.dropTarget(const Offset(150, 190), exclude: 'c1'), (columnId: 'a', index: 1));
      expect(l.dropTarget(const Offset(450, 60)), (columnId: 'b', index: 0));
      expect(l.dropTarget(const Offset(450, 200)), (columnId: 'b', index: 1));
      expect(l.dropTarget(const Offset(312, 100)), isNull, reason: 'the gap between lanes is outside');
      expect(l.dropTarget(const Offset(150, 500)), isNull);
      expect(l.dropTarget(const Offset(-10, 100)), isNull);
      final a = l.lanes[0];
      expect(l.insertionY(a, 0), 46);
      expect(l.insertionY(a, 1), 118);
      expect(l.insertionY(a, 3), 262);
    });

    test('header strip and cards are found by position', () {
      final l = LaneLayout.compute(Offset.zero, [
        ('a', [('c1', 60.0)]),
      ]);
      expect(l.headerAt(const Offset(150, 20))?.columnId, 'a');
      expect(l.headerAt(const Offset(150, 60)), isNull);
      expect(l.cardAt(const Offset(150, 60))?.id, 'c1');
      expect(l.cardAt(const Offset(150, 300)), isNull);
      expect(l.cardAt(const Offset(150, 115), slop: 4)?.id, 'c1');
    });
  });

  group('BoardScene', () {
    test('lays out cards from columns with measured heights', () {
      final board = makeBoard();
      final e = board.editor;
      final a = e.columns[0].id;
      final short = e.addCard(columnId: a, title: 'Kısa');
      final long = e.addCard(columnId: a, title: List.filled(40, 'uzun').join(' '));
      final dated = e.addCard(columnId: a, title: 'Tarihli', due: '2026-11-10');
      final scene = BoardScene(e, text: BoardTextCache())..rebuild();
      final hs = scene.byId(short)!.bounds.height;
      final hl = scene.byId(long)!.bounds.height;
      final hd = scene.byId(dated)!.bounds.height;
      expect(hl, greaterThan(hs), reason: 'three title lines are taller than one');
      expect(hl - hs, lessThan(3 * 1.3 * CardGeometry.titleSize + 1), reason: 'titles stop at three lines');
      // One title line (strut-forced 1.3 × 15) plus the meta row.
      expect(
        hd,
        closeTo(
          2 * CardGeometry.padV + 1.3 * CardGeometry.titleSize + CardGeometry.metaGap + CardGeometry.metaHeight,
          1,
        ),
      );
      expect(hs, CardGeometry.minHeight);
      expect(scene.byId(short)!.bounds.left, LaneMetrics.padding);
      expect(scene.byId(long)!.bounds.top, scene.byId(short)!.bounds.bottom + LaneMetrics.cardGap);
    });

    test('follows the editor incrementally and keeps z order', () {
      final board = makeBoard();
      final e = board.editor;
      final scene = BoardScene(e, text: BoardTextCache())..rebuild();
      e.addListener(scene.sync);
      final s1 = e.addSticky(at: const Offset(1000, 0));
      final s2 = e.addSticky(at: const Offset(1050, 50));
      expect(scene.free.map((i) => i.id), [s1, s2]);
      final r0 = scene.revision;
      e.moveTo({s1: const Offset(2000, 0)});
      expect(scene.revision, r0 + 1);
      expect(scene.byId(s1)!.bounds.topLeft, const Offset(2000, 0));
      e.bringToFront({s1});
      expect(scene.free.map((i) => i.id), [s2, s1]);
      e.deleteItems({s2});
      expect(scene.byId(s2), isNull);
      // Moving the lane block moves the cards, which store no position.
      final c = e.addCard(columnId: e.columns[1].id, title: 'k');
      final before = scene.byId(c)!.bounds;
      e.setLaneOrigin(const Offset(10, 20));
      expect(scene.byId(c)!.bounds, before.shift(const Offset(10, 20)));
      e.moveCard(c, columnId: e.columns[0].id, index: 0);
      expect(scene.byId(c)!.columnId, e.columns[0].id);
      expect(scene.byId(c)!.bounds.left, 10 + LaneMetrics.padding);
      expect(scene.contentBounds.right, 2200);
    });

    test('ink bounds come from the stroke, relative to the item origin', () {
      final board = makeBoard();
      final e = board.editor;
      final id = e.addInk(
        origin: const Offset(500, 500),
        strokes: strokeAt([const Offset(10, 10), const Offset(60, 30)]),
      );
      final scene = BoardScene(e, text: BoardTextCache())..rebuild();
      final si = scene.byId(id)!;
      expect(si.bounds, const Rect.fromLTRB(506, 506, 564, 534));
      expect(si.polyline, [10, 10, 60, 30]);
    });

    test('hit testing: free items top first, then cards, then lane headers, then nothing', () {
      final board = makeBoard();
      final e = board.editor;
      final card = e.addCard(columnId: e.columns[0].id, title: 'k');
      final under = e.addSticky(at: const Offset(100, 60));
      final over = e.addSticky(at: const Offset(150, 100));
      final ink = e.addInk(
        origin: const Offset(100, 300),
        strokes: strokeAt([const Offset(0, 0), const Offset(100, 0)]),
      );
      final scene = BoardScene(e, text: BoardTextCache())..rebuild();
      expect(scene.hitTest(const Offset(200, 200), slop: 2).id, over);
      expect(scene.hitTest(const Offset(120, 70), slop: 2).id, under);
      expect(scene.hitTest(const Offset(200, 200), slop: 2, exclude: {over}).id, under);
      expect(scene.hitTest(const Offset(30, 80), slop: 2).id, card);
      expect(scene.hitTest(const Offset(30, 80), slop: 2).kind, HitKind.card);
      final header = scene.hitTest(const Offset(30, 20), slop: 2);
      expect(header.kind, HitKind.laneHeader);
      expect(header.columnId, e.columns[0].id);
      expect(scene.hitTest(const Offset(150, 300), slop: 2).id, ink, reason: 'on the stroke');
      expect(
        scene.hitTest(const Offset(150, 330), slop: 2).kind,
        HitKind.none,
        reason: 'inside the lane but off the stroke: empty space',
      );
      expect(scene.hitTest(const Offset(2000, 2000), slop: 2), same(SceneHit.none));
      expect(scene.inkAt(const Offset(150, 305), 6), [ink]);
      expect(scene.query(const Rect.fromLTWH(0, 0, 160, 120)), {card, under, over});
    });
  });

  group('text', () {
    test('sticky text is fitted from 28 down to 12', () {
      final (big, tp1) = fitStickyText('Kısa', const Color(0xFF000000));
      expect(big, 28);
      final (small, tp2) = fitStickyText(List.filled(60, 'kelime').join(' '), const Color(0xFF000000));
      expect(small, lessThan(28));
      expect(small, greaterThanOrEqualTo(12));
      expect(tp2.height, lessThanOrEqualTo(StickyMetrics.inner + 0.5));
      final (tiny, tp3) = fitStickyText(List.filled(400, 'kelime').join(' '), const Color(0xFF000000));
      expect(tiny, 12);
      expect(tp3.didExceedMaxLines, isTrue, reason: 'too long even at 12: cut with an ellipsis');
      for (final t in [tp1, tp2, tp3]) {
        t.dispose();
      }
      expect(estimateStickyFont(''), 28);
      expect(estimateStickyFont(List.filled(400, 'k').join(' ')), 12);
    });

    test('the cache evicts the least recently used and keeps a layout budget', () {
      final cache = BoardTextCache(capacity: 2, budget: Duration.zero);
      final c = const Color(0xFF000000);
      TextPainter lay(String t) => boardPainter(t, boardText(14, c))..layout();
      cache.put('a', 'a', 14, c, lay('a'));
      cache.put('b', 'b', 14, c, lay('b'));
      expect(cache.peek('a', 'a', 14, c), isNotNull);
      cache.put('c', 'c', 14, c, lay('c'));
      expect(cache.peek('b', 'b', 14, c), isNull, reason: 'b was used least recently');
      expect(cache.peek('a', 'a', 14, c), isNotNull);
      expect(cache.peek('a', 'changed', 14, c), isNull);
      cache.beginFrame();
      expect(cache.obtain('d', 'd', 14, c, () => lay('d')), isNull, reason: 'no budget left this frame');
      expect(cache.obtain('d', 'd', 14, c, () => lay('d'), force: true), isNotNull);
      cache.dispose();
    });
  });

  group('presence', () {
    testWidgets('cursors ease toward their target and fade after 10 s', (tester) async {
      final conn = _FakeConnection();
      var now = Duration.zero;
      final vp = BoardViewport()..setSize(const Size(800, 600));
      final m = PresenceModel(vsync: const TestVSync(), viewport: vp, clock: () => now);
      m.attach(conn);
      conn.peersN.value = const [Peer(key: 'k1', userId: 'u', name: 'Ayşe', colorIndex: 3)];
      conn.cursorsN.value = {
        'k1': PeerCursor(key: 'k1', name: 'Ayşe', colorIndex: 3, position: Offset.zero, at: DateTime(2026)),
      };
      expect(m.dots.single.position, Offset.zero);
      conn.cursorsN.value = {
        'k1': PeerCursor(key: 'k1', name: 'Ayşe', colorIndex: 3, position: const Offset(100, 0), at: DateTime(2026)),
      };
      m.advance(0.060);
      // One time constant covers 1 − 1/e of the way.
      expect(m.dots.single.position.dx, closeTo(100 * (1 - 0.36788), 0.01));
      for (var i = 0; i < 40; i++) {
        m.advance(0.016);
      }
      expect(m.dots.single.position.dx, 100);
      now = const Duration(seconds: 10, milliseconds: 150);
      m.advance(0.016);
      expect(m.dots.single.opacity, closeTo(0.5, 0.01));
      now = const Duration(seconds: 11);
      m.advance(0.016);
      expect(m.dots.single.opacity, 0);
      // A peer who switched to Kanban has no canvas cursor.
      conn.peersN.value = const [Peer(key: 'k1', userId: 'u', name: 'Ayşe', colorIndex: 3, view: 'kanban')];
      expect(m.dots, isEmpty);
      m.dispose();
    });
  });

  test('frame scheduling stays idle when nothing is pending', () {
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
  });

  test('stroke helpers produce valid codec strings', () {
    final s = InkCodec.decode(strokeAt([const Offset(1, 2), const Offset(3, 4)]));
    expect(s.single.length, 2);
    expect(ItemKind.ink.name, 'ink');
  });
}

class _FakeConnection implements BoardConnection {
  final peersN = ValueNotifier<List<Peer>>(const []);
  final cursorsN = ValueNotifier<Map<String, PeerCursor>>(const {});

  @override
  ValueListenable<List<Peer>> get peers => peersN;

  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => cursorsN;

  @override
  ValueListenable<SyncState> get state => ValueNotifier(const SyncState(SyncStatus.local));

  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) {}

  @override
  void setActivity({required String view, String? editing}) {}

  @override
  void kick() {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> close() async {}
}
