import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/sync/backend.dart';
import 'package:pamnot/l10n/strings.dart';

import 'harness.dart';

/// A short editing session on Ada's device while Bora edits too. Ada's
/// steps stop once her process is dead.
void _editingScript(World w, Client a, Client b) {
  void onA(void Function() step) {
    if (!a.store.dead) step();
  }

  var card = '', s = '';
  onA(() {
    card = a.editor.addCard(columnId: a.editor.columns.first.id, title: 'K1');
    s = a.editor.addSticky(at: const Offset(100, 100), text: 'bir');
  });
  w.run(const Duration(milliseconds: 200));
  final bs = b.editor.addSticky(at: const Offset(400, 100), text: 'B1');
  w.run(const Duration(milliseconds: 600));
  onA(() {
    a.editor.moveCard(card, columnId: a.editor.columns[1].id, index: 0);
    a.editor.addInk(origin: const Offset(20, 20), strokes: 'PINK1:abc');
  });
  w.run(const Duration(milliseconds: 450));
  onA(() => a.editor.updateSticky(s, text: 'iki'));
  if (b.doc.items.containsKey(card)) b.editor.updateCard(card, {F.title: 'Bora adı'});
  w.run(const Duration(seconds: 1));
  onA(() {
    a.editor.deleteItems({s});
    a.editor.setTitle('Yeni pano');
  });
  b.editor.moveTo({bs: const Offset(450, 150)});
  w.run(const Duration(seconds: 2));
  onA(() => a.editor.undo());
  w.run(const Duration(seconds: 1));
  b.editor.addCard(columnId: b.editor.columns.last.id, title: 'B kart');
  w.run(const Duration(milliseconds: 700));
  onA(() => a.editor.addColumn(title: 'Yeni sütun'));
  w.run(const Duration(milliseconds: 700));
  onA(() {
    final cols = a.editor.columns;
    a.editor.deleteColumn(cols[cols.length - 2].id);
  });
  w.run(const Duration(seconds: 3));
}

/// Ada's device-only board with some content, shared under an id someone
/// else already has, so the upload also re-mints it.
String _uploadSetup(World w, Client a) {
  final id = w.wait(a.controller.createBoard(title: 'Yükleme', colorIndex: 4, template: BoardTemplate.tasks, strings: S.tr));
  a.open(id);
  final e = a.editor;
  for (var i = 0; i < 3; i++) {
    e.addCard(columnId: e.columns[i].id, title: 'Kart $i');
  }
  e.addSticky(at: const Offset(1000, 0), text: 'Not');
  e.addInk(origin: const Offset(1000, 300), strokes: 'PINK1:xyz');
  w.wait(a.controller.flush());
  w.server.createBoard('u-someone', id);
  return id;
}

void main() {
  test('crash at every write point while editing, then heal', () {
    // Count the write points first.
    late int total;
    inFakeTime((async) {
      final w = World(async, seed: 7);
      final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
      final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
      final (_, code) = w.share(a);
      w.join(b, code);
      final start = a.store.writes;
      _editingScript(w, a, b);
      total = a.store.writes - start;
    });
    expect(total, greaterThan(8));
    for (var k = 1; k <= total; k++) {
      inFakeTime((async) {
        final w = World(async, seed: 7);
        final da = Device(w, userId: 'u-ada', name: 'Ada');
        var a = da.boot();
        final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
        final (id, code) = w.share(a);
        w.join(b, code);
        a.store.crashAfterWrites = a.store.writes + k;
        _editingScript(w, a, b);
        expect(a.store.dead, isTrue, reason: 'crash point $k');
        a = da.boot()..open(id);
        heal(w, [a, b]);
        expectConverged(w, id, [a, b]);
      });
    }
  });

  test('crash at every write point of an upload (with a re-mint), then heal', () {
    late int total;
    inFakeTime((async) {
      final w = World(async, seed: 11);
      final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
      final id = _uploadSetup(w, a);
      final start = a.store.writes;
      w.wait(a.controller.beginUpload(id, a.session.account!));
      w.run(const Duration(seconds: 5));
      expect(a.board!.id, isNot(id));
      total = a.store.writes - start;
    });
    expect(total, greaterThan(5));
    for (var k = 1; k <= total; k++) {
      inFakeTime((async) {
        final w = World(async, seed: 11);
        final da = Device(w, userId: 'u-ada', name: 'Ada');
        var a = da.boot();
        final id = _uploadSetup(w, a);
        final content = {for (final it in a.doc.items.values) if (it.kind != ItemKind.meta) it.id};
        a.store.crashAfterWrites = a.store.writes + k;
        // Never completes if the process dies in the middle.
        unawaited(a.controller.beginUpload(id, a.session.account!));
        w.run(const Duration(seconds: 5));
        expect(a.store.dead, isTrue, reason: 'crash point $k');
        // The board is still there after the restart, under one id or the
        // other; sharing resumes (or is started again if it never began).
        a = da.boot();
        final mine = a.controller.boards.where((b) => b.title == 'Yükleme').toList();
        expect(mine, hasLength(1), reason: 'crash point $k: the board survives');
        a.open(mine.single.id);
        if (a.doc.state == BoardState.local) {
          w.wait(a.controller.beginUpload(a.board!.id, a.session.account!));
        }
        heal(w, [a]);
        final fid = a.board!.id;
        expect(a.doc.state, BoardState.shared, reason: 'crash point $k');
        expect(fid, isNot(id), reason: 'never uploaded under the taken id');
        expect(w.server.boards[id]!.items, isEmpty);
        expect(w.server.boards[fid]!.ownerId, 'u-ada');
        expect(w.server.boards[fid]!.items.keys.toSet(), containsAll(content));
        expectConverged(w, fid, [a]);
      });
    }
  });

  for (final seed in [1, 2, 3, 4]) {
    test('3 clients, random edits, partitions, drops, duplicates and crashes converge (seed $seed)',
        () => inFakeTime((async) => runProperty(async, seed)));
  }
}

void runProperty(dynamic async, int seed, {int steps = 160}) {
  final w = World(async, seed: seed);
  final r = math.Random(seed * 997 + 1);
  final devices = [
    Device(w, userId: 'u-ada', name: 'Ada', colorIndex: 1),
    Device(w, userId: 'u-bora', name: 'Bora', colorIndex: 4, skewMs: 3500),
    Device(w, userId: 'u-cem', name: 'Cem', colorIndex: 6, skewMs: -2500),
  ];
  final clients = [for (final d in devices) d.boot()];
  final (id, code) = w.share(clients[0]);
  w.join(clients[1], code);
  w.join(clients[2], code);
  final latency = [for (var i = 0; i < 3; i++) Duration(milliseconds: r.nextInt(120))];
  for (var i = 0; i < 3; i++) {
    clients[i].backend.latency = latency[i];
  }
  var crashes = 0, edits = 0;

  Client live(int i) {
    var c = clients[i];
    if (c.store.dead || c.backend.killed) {
      crashes++;
      c = clients[i] = devices[i].boot()..backend.latency = latency[i];
      c.open(id);
    }
    return c;
  }

  for (var step = 0; step < steps; step++) {
    final c = live(r.nextInt(3));
    final roll = r.nextDouble();
    if (roll < 0.55) {
      randomEdit(c.editor, r);
      edits++;
    } else if (roll < 0.63) {
      c.backend.online = !c.backend.online;
    } else if (roll < 0.68) {
      c.foreground.value ? c.pause() : c.resume();
    } else if (roll < 0.71) {
      // Dies a few writes from now, possibly in the middle of a flush.
      c.store.crashAfterWrites = c.store.writes + 1 + r.nextInt(6);
    } else if (roll < 0.74) {
      c.crash();
    } else if (roll < 0.82) {
      if (c.backend.channels.isNotEmpty) {
        final ch = c.channel;
        switch (r.nextInt(4)) {
          case 0:
            ch.failReplication();
          case 1:
            ch.emitStatus(SubscribeStatus.channelError, 'flaky');
          case 2:
            ch.rejoin();
          default:
            ch.emitSystem({'extension': 'postgres_changes', 'status': 'ok'});
        }
      }
    } else if (roll < 0.92) {
      c.backend
        ..dropRate = r.nextDouble() * 0.4
        ..duplicateRate = r.nextDouble() * 0.3
        ..truncateRate = r.nextDouble() * 0.1
        ..partialRate = r.nextDouble() * 0.1
        ..maxDelay = Duration(milliseconds: r.nextInt(1500))
        ..lossRate = r.nextDouble() * 0.3;
    } else {
      switch (r.nextInt(3)) {
        case 0:
          c.sync.retry();
        case 1:
          c.sync.setActivity(view: r.nextBool() ? 'canvas' : 'kanban');
        default:
          c.sync.sendCursor(Offset(r.nextDouble() * 500, r.nextDouble() * 500));
      }
    }
    w.run(Duration(milliseconds: r.nextInt(2500)));
  }
  // No crash scheduled for later; restart whoever is down.
  for (final c in clients) {
    c.store.crashAfterWrites = null;
  }
  for (var i = 0; i < 3; i++) {
    live(i);
  }
  heal(w, clients);
  expect(edits, greaterThan(60));
  expect(crashes, greaterThan(0));
  expect(w.server.boards[id]!.items.length, greaterThan(10));
  expectConverged(w, id, clients);
  // Everyone sees the other two.
  for (final c in clients) {
    expect(c.sync.peers.value.map((p) => p.key).toSet(),
        {for (final o in clients) if (o != c) o.clock.node});
  }
}
