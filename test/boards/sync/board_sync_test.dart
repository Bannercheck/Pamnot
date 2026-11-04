import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/sync/backend.dart';
import 'package:pamnot/boards/sync/board_sync.dart';
import 'package:pamnot/l10n/strings.dart';

import 'harness.dart';

/// Ada owns a shared board; Bora has joined it.
(World, Client, Client, String) pair(dynamic async, {void Function(Client a, Client b)? before}) {
  final w = World(async);
  final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
  final b = Device(w, userId: 'u-bora', name: 'Bora', colorIndex: 4).boot();
  before?.call(a, b);
  final (id, code) = w.share(a);
  w.join(b, code);
  return (w, a, b, id);
}

String sticky(Client c, String text) => c.editor.addSticky(at: const Offset(10, 10), text: text);

void main() {
  group('connect', () {
    test('subscribes before the first pull, uploads after createBoard and goes live', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final ac = a.backend.calls;
          expect(ac.indexOf('createBoard'), lessThan(ac.indexOf('subscribe')));
          expect(ac.indexOf('createBoard'), lessThan(ac.indexOf('pushItems')));
          expect(ac.indexOf('subscribe'), lessThan(ac.indexOf('boardStatus')));
          final bc = b.backend.calls;
          expect(bc.indexOf('subscribe'), lessThan(bc.indexOf('pullItems')));
          expect(a.sync.phase, SyncPhase.live);
          expect(b.sync.phase, SyncPhase.live);
          expect(a.state, const SyncState(SyncStatus.synced));
          expect(b.state, const SyncState(SyncStatus.synced));
          expect(b.editor.title, 'Ekip');
          expect(b.editor.columns.map((c) => c.title), ['Yapılacak', 'Yapılıyor', 'Bitti']);
          expectConverged(w, id, [a, b]);
        }));

    test('measures the clock offset against the server', () => inFakeTime((async) {
          final w = World(async);
          final dev = Device(w, userId: 'u-ada', name: 'Ada', skewMs: -5000);
          final a = dev.boot();
          a.backend.latency = const Duration(milliseconds: 80);
          w.share(a);
          expect(a.controller.clockOffsetMs, 5000);
          // Ticks now follow server time.
          final s = sticky(a, 'x');
          final ms = int.parse(a.doc.items[s]!.h[F.text]!.substring(0, 15));
          expect((ms - w.server.nowMs()).abs(), lessThan(50));
        }));
  });

  group('upload', () {
    test('a device-only board is created, pushed and becomes shared', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final id = w.wait(a.controller.createBoard(title: 'Plan', colorIndex: 1, template: BoardTemplate.tasks, strings: S.en));
          a.open(id);
          final s = sticky(a, 'yerel');
          a.editor.deleteItems({s}); // a local tombstone is not uploaded
          w.wait(a.controller.beginUpload(id, a.session.account!));
          w.run(const Duration(seconds: 1));
          expect(a.backend.calls.indexOf('createBoard'), lessThan(a.backend.calls.indexOf('pushItems')));
          expect(a.doc.state, BoardState.shared);
          expect(a.controller.summary(id)!.state, BoardState.shared);
          expect(w.server.boards[id]!.ownerId, 'u-ada');
          expect(w.server.boards[id]!.items.containsKey(s), isFalse);
          expect(a.state, const SyncState(SyncStatus.synced));
          expectConverged(w, id, [a]);
        }));

    test('an id owned by someone else is re-minted and uploaded under the new id', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final id = w.wait(a.controller.createBoard(title: 'Klon', colorIndex: 1, template: BoardTemplate.tasks, strings: S.tr));
          w.server.createBoard('u-someone', id); // e.g. a restored backup on another phone
          a.open(id);
          w.wait(a.controller.beginUpload(id, a.session.account!));
          w.run(const Duration(seconds: 2));
          final nid = a.board!.id;
          expect(nid, isNot(id));
          expect(a.doc.state, BoardState.shared);
          expect(a.controller.openBoard(nid), same(a.board));
          expect(a.doc.meta!.id, nid);
          expect(w.server.boards[nid]!.ownerId, 'u-ada');
          expect(w.server.boards[id]!.items, isEmpty);
          expect(a.device.disk.data.containsKey(BoardsRepository.docKey(id)), isFalse);
          expect(a.device.disk.data.containsKey(BoardsRepository.docKey(nid)), isTrue);
          expect(a.backend.calls.where((c) => c == 'createBoard'), hasLength(2));
          expectConverged(w, nid, [a]);
        }));

    test('upload waits out an unreachable server', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final id = w.wait(a.controller.createBoard(title: 'P', colorIndex: 1, template: BoardTemplate.blank, strings: S.tr));
          a.open(id);
          a.backend.online = false;
          w.wait(a.controller.beginUpload(id, a.session.account!));
          w.run(const Duration(seconds: 20));
          expect(a.state.status, SyncStatus.offline);
          expect(a.state.pending, greaterThan(0));
          expect(a.count('subscribe'), 0, reason: 'nothing before the board exists');
          a.backend.online = true;
          w.run(const Duration(seconds: 20));
          expect(a.doc.state, BoardState.shared);
          expectConverged(w, id, [a]);
        }));
  });

  group('catch-up', () {
    test('an offline edit with an old HLC reaches a client whose cursor passed later writes', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final c = Device(w, userId: 'u-cem', name: 'Cem').boot();
          w.join(c, w.server.boards[id]!.code);
          final card = a.editor.addCard(columnId: a.editor.columns.first.id, title: 'X');
          w.run(const Duration(seconds: 2));
          a.backend.online = false;
          a.editor.moveCard(card, columnId: a.editor.columns[2].id, index: 0); // 10:00, offline
          w.run(const Duration(hours: 1));
          final y = sticky(b, 'Y'); // 11:00
          w.run(const Duration(seconds: 2));
          expect(c.doc.items[y]!.text, 'Y');
          expect(c.doc.cursor, w.server.boards[id]!.rev);
          c.close();
          a.backend.online = true; // 12:00: the old-HLC move goes up
          w.run(const Duration(seconds: 70));
          expect(w.server.boards[id]!.items[card]!.data[F.columnId], a.editor.columns[2].id);
          c.open(id);
          w.run(const Duration(seconds: 2));
          expect(c.editor.item(card)!.columnId, c.editor.columns[2].id);
          expectConverged(w, id, [a, b, c]);
        }));

    test('a write in the fetch/subscribe window is recovered by the system ok event', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (id, code) = w.share(a);
          b.backend.replicationDelay = const Duration(milliseconds: 600);
          final r = w.wait(b.backend.joinBoard(code))!;
          w.wait(b.controller.addJoined(boardId: r.boardId, title: r.title, account: b.session.account!));
          b.open(id);
          final s = sticky(a, 'arada');
          w.run(const Duration(milliseconds: 400)); // pushed, but not replicated to b
          expect(w.server.boards[id]!.items.containsKey(s), isTrue);
          expect(b.doc.items.containsKey(s), isFalse);
          w.run(const Duration(milliseconds: 300));
          expect(b.doc.items[s]!.text, 'arada');
          expectConverged(w, id, [a, b]);
        }));

    test('without a system ok, a later rev gap recovers it after 1 s', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (id, code) = w.share(a);
          b.backend
            ..replicationDelay = const Duration(milliseconds: 600)
            ..systemOk = false;
          final r = w.wait(b.backend.joinBoard(code))!;
          w.wait(b.controller.addJoined(boardId: r.boardId, title: r.title, account: b.session.account!));
          b.open(id);
          final s1 = sticky(a, 'bir');
          w.run(const Duration(seconds: 1));
          expect(b.doc.items.containsKey(s1), isFalse);
          final s2 = sticky(a, 'iki');
          w.run(const Duration(milliseconds: 400));
          expect(b.doc.items[s2]!.text, 'iki', reason: 'live again');
          expect(b.doc.items.containsKey(s1), isFalse, reason: 'gap not filled yet');
          final pulls = b.count('pullItems');
          w.run(const Duration(seconds: 1));
          expect(b.count('pullItems'), pulls + 1);
          expect(b.doc.items[s1]!.text, 'bir');
          expectConverged(w, id, [a, b]);
        }));

    test('with nothing else, the 60 s foreground poll recovers it', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (id, code) = w.share(a);
          b.backend
            ..replicationDelay = const Duration(milliseconds: 600)
            ..systemOk = false;
          final r = w.wait(b.backend.joinBoard(code))!;
          w.wait(b.controller.addJoined(boardId: r.boardId, title: r.title, account: b.session.account!));
          b.open(id);
          final s = sticky(a, 'yoklama');
          w.run(const Duration(seconds: 58));
          expect(b.doc.items.containsKey(s), isFalse);
          w.run(const Duration(seconds: 3));
          expect(b.doc.items[s]!.text, 'yoklama');
          // No poll in the background.
          b.foreground.value = false;
          final pulls = b.count('boardStatus');
          w.run(const Duration(minutes: 5));
          expect(b.count('boardStatus'), pulls);
        }));

    test('a repeated subscribed after a pause catches up', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          // The app stays "foreground" here, so only `subscribed` can do it.
          b.backend.suspend();
          final ids = [for (var i = 0; i < 30; i++) sticky(a, 'n$i')];
          w.run(const Duration(seconds: 10));
          expect(ids.where(b.doc.items.containsKey), isEmpty);
          expect(b.sync.phase, SyncPhase.live, reason: 'nothing reported the drop');
          b.backend.resumeSocket();
          w.run(const Duration(seconds: 1));
          expect(ids.every(b.doc.items.containsKey), isTrue);
          expectConverged(w, id, [a, b]);
        }));

    test('app resume catches up and pushes', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          b.pause();
          final s = sticky(a, 'arkada');
          final mine = sticky(b, 'benim');
          w.run(const Duration(minutes: 3));
          expect(b.doc.items.containsKey(s), isFalse);
          expect(w.server.boards[id]!.items.containsKey(mine), isTrue, reason: 'pushed when it went to the background');
          b.foreground.value = true; // resume event before the socket is back
          w.settle();
          expect(b.doc.items[s]!.text, 'arkada');
          b.backend.resumeSocket();
          w.run(const Duration(seconds: 2));
          expectConverged(w, id, [a, b]);
        }));

    test('single flight: triggers during a catch-up cause exactly one rerun', () => inFakeTime((async) {
          final (w, a, _, _) = pair(async);
          a.backend.latency = const Duration(milliseconds: 100);
          final before = a.count('boardStatus');
          for (var i = 0; i < 5; i++) {
            a.channel.emitSystem({'extension': 'postgres_changes', 'status': 'ok'});
            w.run(const Duration(milliseconds: 20));
          }
          w.run(const Duration(seconds: 2));
          expect(a.count('boardStatus'), before + 2);
        }));

    test('rev gaps are debounced into one catch-up', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          b.backend.dropRate = 1;
          final lost = sticky(a, 'kayıp');
          w.run(const Duration(seconds: 1));
          b.backend.dropRate = 0;
          final before = b.count('boardStatus');
          for (var i = 0; i < 3; i++) {
            sticky(a, 'g$i');
            w.run(const Duration(milliseconds: 350));
          }
          expect(b.doc.items.containsKey(lost), isFalse);
          w.run(const Duration(seconds: 1));
          expect(b.count('boardStatus'), before + 1);
          expect(b.doc.items[lost]!.text, 'kayıp');
          expectConverged(w, id, [a, b]);
        }));

    test('more than 1,000 rows on first join all arrive', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final id = w.wait(a.controller.createBoard(title: 'Büyük', colorIndex: 1, template: BoardTemplate.tasks, strings: S.tr));
          a.open(id);
          a.editor.batch(() {
            for (var i = 0; i < 1100; i++) {
              a.editor.addSticky(at: Offset(i * 3.0, 0), text: 's$i');
            }
          });
          w.wait(a.controller.beginUpload(id, a.session.account!));
          w.run(const Duration(seconds: 5));
          expect(a.backend.pushedRows, [200, 200, 200, 200, 200, 104]);
          w.join(b, w.server.boards[id]!.code);
          expect(b.count('pullItems'), greaterThanOrEqualTo(3));
          expect(b.editor.canvasItems, hasLength(1100));
          expectConverged(w, id, [a, b]);
        }));

    test('a partial or truncated record never blanks a field', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final s = sticky(a, 'tam');
          w.run(const Duration(seconds: 1));
          final rev = w.server.boards[id]!.rev;
          final before = b.count('boardStatus');
          // A newer text HLC whose value did not make it into `data`.
          b.channel.handlers.onRow(RemoteRow(
            id: s,
            kind: 'sticky',
            data: const {},
            fh: {F.text: futureHlc()},
            rev: rev + 1,
          ));
          expect(b.doc.items[s]!.text, 'tam');
          expect(b.doc.cursor, rev, reason: 'an incomplete row does not move the cursor');
          w.settle();
          expect(b.count('boardStatus'), before + 1);
          b.channel.handlers.onRow(null);
          w.settle();
          expect(b.count('boardStatus'), before + 2);
          // The real thing, through the fake's faults.
          b.backend.partialRate = 1;
          a.editor.updateSticky(s, text: 'yeni');
          w.run(const Duration(seconds: 1));
          b.backend
            ..partialRate = 0
            ..truncateRate = 1;
          a.editor.updateSticky(s, colorIndex: 2);
          w.run(const Duration(seconds: 1));
          expect(b.doc.items[s]!.text, 'yeni');
          expect(b.doc.items[s]!.colorIndex, 2);
          expectConverged(w, id, [a, b]);
        }));
  });

  group('channel', () {
    test('a system-error channel is recreated after the 15 s watchdog', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final first = b.channel;
          first.failReplication();
          w.settle();
          expect(b.sync.phase, SyncPhase.offline);
          expect(b.state.status, SyncStatus.offline);
          final s = sticky(a, 'ölü kanal');
          w.run(const Duration(seconds: 14));
          expect(b.backend.channels, [first], reason: 'still waiting');
          expect(b.doc.items.containsKey(s), isFalse);
          w.run(const Duration(milliseconds: 1100));
          expect(first.removed, isTrue);
          w.run(const Duration(milliseconds: 1300)); // backoff 1 s + jitter
          expect(b.count('subscribe'), 2);
          expect(b.channel, isNot(first));
          expect(b.doc.items[s]!.text, 'ölü kanal');
          expect(b.sync.phase, SyncPhase.live);
          expect(b.state.status, SyncStatus.synced);
          // Late events from the removed channel change nothing.
          first.handlers.onStatus(SubscribeStatus.channelError, 'late');
          first.handlers.onRow(RemoteRow(id: s, kind: 'sticky', data: const {F.text: 'hayalet'}, fh: {F.text: futureHlc()}, rev: 999));
          expect(b.sync.phase, SyncPhase.live);
          expect(b.doc.items[s]!.text, 'ölü kanal');
          expectConverged(w, id, [a, b]);
        }));

    test('recreation backs off 1, 2, 4 … 30 s plus jitter while it keeps failing', () => inFakeTime((async) {
          final (w, _, b, _) = pair(async);
          b.backend.online = false;
          final times = <int>[];
          var n = b.count('subscribe');
          for (var t = 0; t < 400 * 10; t++) {
            w.run(const Duration(milliseconds: 100));
            if (b.count('subscribe') > n) {
              n = b.count('subscribe');
              times.add(t * 100);
            }
          }
          final gaps = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]];
          expect(times.first, inInclusiveRange(16000, 16300));
          final expected = [2, 4, 8, 16, 30, 30, 30];
          for (var i = 0; i < expected.length; i++) {
            final b = expected[i] * 1000;
            expect(gaps[i], inInclusiveRange(15000 + b, 15000 + b * 1.2 + 200), reason: 'gap $i');
          }
        }));

    test('a subscribed before the watchdog cancels it; no recreation in the background', () => inFakeTime((async) {
          final (w, _, b, _) = pair(async);
          b.channel.emitStatus(SubscribeStatus.channelError, 'blip');
          w.run(const Duration(seconds: 5));
          b.channel.emitStatus(SubscribeStatus.subscribed);
          w.run(const Duration(seconds: 30));
          expect(b.count('subscribe'), 1);
          b.foreground.value = false;
          b.backend.online = false;
          w.run(const Duration(minutes: 3));
          expect(b.count('subscribe'), 1);
          b.foreground.value = true;
          w.run(const Duration(seconds: 15) + const Duration(milliseconds: 1300));
          expect(b.count('subscribe'), 2, reason: 'watchdog runs again in the foreground');
          b.backend.online = true;
          w.run(const Duration(seconds: 2));
          expect(b.sync.phase, SyncPhase.live);
        }));

    test('an Unauthorized channel error checks the board status', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          w.wait(a.backend.removeMember(id, 'u-bora'));
          b.channel.emitStatus(SubscribeStatus.channelError, 'Unauthorized: You do not have permissions');
          w.settle();
          expect(b.doc.state, BoardState.revoked);
          expect(b.state.status, SyncStatus.revoked);
        }));
  });

  group('push', () {
    test('debounced 300 ms, at most 2 s after the first edit', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          w.share(a);
          var p = a.count('pushItems');
          sticky(a, 'a');
          expect(a.state, const SyncState(SyncStatus.sending, pending: 1));
          w.run(const Duration(milliseconds: 290));
          expect(a.count('pushItems'), p);
          w.run(const Duration(milliseconds: 20));
          expect(a.count('pushItems'), p + 1);
          expect(a.state, const SyncState(SyncStatus.synced));
          p = a.count('pushItems');
          final s = sticky(a, 'b');
          for (var i = 0; i < 9; i++) {
            w.run(const Duration(milliseconds: 200));
            a.editor.updateSticky(s, text: 'b$i');
          }
          // 1.8 s of typing, nothing sent yet; the cap fires at 2 s.
          expect(a.count('pushItems'), p);
          w.run(const Duration(milliseconds: 210));
          expect(a.count('pushItems'), p + 1);
        }));

    test('an edit during an in-flight push is pushed afterwards (ack race)', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final (id, _) = w.share(a);
          a.backend.latency = const Duration(milliseconds: 100);
          final s = sticky(a, 'Rapor');
          w.run(const Duration(milliseconds: 350)); // push sent at 300 ms
          a.editor.updateSticky(s, text: 'Rapor v2');
          w.run(const Duration(milliseconds: 200)); // first ack back at 500 ms
          expect(a.doc.items[s]!.d, contains(F.text));
          w.run(const Duration(seconds: 1));
          expect(w.server.boards[id]!.items[s]!.data[F.text], 'Rapor v2');
          expect(a.doc.pendingCount, 0);
          expectConverged(w, id, [a]);
        }));

    test('backs off 1…60 s while unreachable, then recovers', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final (id, _) = w.share(a);
          a.backend.online = false;
          sticky(a, 'çevrimdışı');
          final times = <int>[];
          var n = a.count('pushItems');
          for (var t = 0; t < 4000; t++) {
            w.run(const Duration(milliseconds: 100));
            if (a.count('pushItems') > n) {
              n = a.count('pushItems');
              times.add(t * 100);
            }
          }
          expect(times.first, inInclusiveRange(200, 400));
          final gaps = [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]];
          final expected = [1, 2, 4, 8, 16, 32, 60, 60];
          for (var i = 0; i < expected.length; i++) {
            final b = expected[i] * 1000;
            expect(gaps[i], inInclusiveRange(b, b * 1.2 + 200), reason: 'gap $i');
          }
          expect(a.state, const SyncState(SyncStatus.offline, pending: 1));
          a.backend.online = true; // the channel rejoins and the push goes at once
          w.run(const Duration(milliseconds: 100));
          expect(a.state, const SyncState(SyncStatus.synced));
          expectConverged(w, id, [a]);
        }));

    test('going to the background pushes at once', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          w.share(a);
          final p = a.count('pushItems');
          sticky(a, 'hemen');
          a.foreground.value = false;
          w.async.flushMicrotasks();
          expect(a.count('pushItems'), p + 1);
        }));

    test('a lost response is retried and settles without a second rev', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          final (id, _) = w.share(a);
          final revs = w.server.boards[id]!.rev;
          // No echo either, which would settle it just like an ack.
          a.backend
            ..lossRate = 1
            ..dropRate = 1;
          sticky(a, 'tekrar');
          w.run(const Duration(milliseconds: 400));
          expect(w.server.boards[id]!.rev, revs + 1);
          expect(a.doc.pendingCount, 1);
          a.backend.lossRate = 0;
          w.run(const Duration(seconds: 2));
          expect(a.doc.pendingCount, 0);
          expect(w.server.boards[id]!.rev, revs + 1);
          // Acks never move the cursor; the next poll does.
          expect(a.doc.cursor, revs);
          a.backend.dropRate = 0;
          w.run(const Duration(seconds: 61));
          expectConverged(w, id, [a]);
        }));
  });

  group('board status', () {
    test('deleted while a member is offline: nothing stuck, sync stops', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          b.backend.online = false;
          sticky(b, 'boşuna');
          b.editor.setTitle('Yeni ad');
          w.run(const Duration(seconds: 5));
          expect(b.doc.pendingCount, 2);
          w.wait(a.backend.deleteBoard(id));
          b.backend.online = true;
          w.run(const Duration(seconds: 2));
          expect(b.doc.state, BoardState.deleted);
          expect(b.doc.pendingCount, 0);
          expect(b.state, const SyncState(SyncStatus.deleted));
          expect(b.controller.summary(id)!.state, BoardState.deleted);
          expect(b.editor.readOnly, isTrue);
          w.run(const Duration(seconds: 1));
          expect(b.device.disk.data[BoardsRepository.docKey(id)], contains('"state":"deleted"'));
          final calls = b.backend.calls.length;
          w.run(const Duration(minutes: 5));
          expect(b.backend.calls.length, calls, reason: 'no more syncing');
          expect(b.backend.channels, isEmpty);
          // The owner finds out on the next catch-up.
          w.run(const Duration(seconds: 61));
          expect(a.doc.state, BoardState.deleted);
        }));

    test('a removed member is revoked by the status check or a forbidden push', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final c = Device(w, userId: 'u-cem', name: 'Cem').boot();
          w.join(c, w.server.boards[id]!.code);
          w.wait(a.backend.removeMember(id, 'u-bora'));
          w.wait(a.backend.removeMember(id, 'u-cem'));
          // Cem edits: the push is refused.
          sticky(c, 'yasak');
          w.run(const Duration(seconds: 1));
          expect(c.doc.state, BoardState.revoked);
          expect(c.doc.pendingCount, 0);
          expect(c.state.status, SyncStatus.revoked);
          // Bora is idle: the next poll finds the board gone.
          expect(b.doc.state, BoardState.shared);
          w.run(const Duration(seconds: 61));
          expect(b.doc.state, BoardState.revoked);
          expect(b.controller.summary(id)!.state, BoardState.revoked);
        }));

    test('AccessDenied (42501) revokes', () => inFakeTime((async) {
          final (w, _, b, _) = pair(async);
          b.backend.fault = (call) => call == 'pullItems' ? const AccessDenied('42501') : null;
          b.sync.retry();
          w.settle();
          expect(b.doc.state, BoardState.revoked);
        }));

    test('state: offline with pending, error with message, retry clears it', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada').boot();
          w.share(a);
          a.backend.online = false;
          sticky(a, '1');
          sticky(a, '2');
          w.run(const Duration(seconds: 1));
          expect(a.state, const SyncState(SyncStatus.offline, pending: 2));
          a.backend.online = true;
          w.run(const Duration(seconds: 1));
          expect(a.state, const SyncState(SyncStatus.synced));
          a.backend.fault = (call) => call == 'pushItems' ? StateError('boom') : null;
          sticky(a, '3');
          w.run(const Duration(seconds: 1));
          expect(a.state.status, SyncStatus.error);
          expect(a.state.message, contains('boom'));
          // A successful catch-up does not hide the failing push.
          w.run(const Duration(seconds: 61));
          expect(a.state.status, SyncStatus.error);
          a.backend.fault = null;
          a.sync.retry();
          w.settle();
          expect(a.state, const SyncState(SyncStatus.synced));
        }));
  });

  group('conflicts', () {
    test('rename vs move and delete vs move both survive', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final card = a.editor.addCard(columnId: a.editor.columns.first.id, title: 'K');
          final s = sticky(a, 'S');
          w.run(const Duration(seconds: 2));
          a.backend.online = false;
          b.backend.online = false;
          a.editor.updateCard(card, {F.title: 'Yeni ad'});
          a.editor.deleteItems({s});
          w.run(const Duration(seconds: 1));
          b.editor.moveCard(card, columnId: b.editor.columns[1].id, index: 0);
          b.editor.moveTo({s: const Offset(500, 500)}); // later than the delete
          heal(w, [a, b]);
          for (final c in [a, b]) {
            expect(c.editor.item(card)!.title, 'Yeni ad');
            expect(c.editor.columnOf(card), c.editor.columns[1].id);
            expect(c.editor.item(s)!.deleted, isTrue);
            expect(c.editor.item(s)!.x, 500);
          }
          expectConverged(w, id, [a, b]);
        }));

    test('a column deleted while a card moves into it: the card shows in the first column', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final card = a.editor.addCard(columnId: a.editor.columns.first.id, title: 'K');
          w.run(const Duration(seconds: 2));
          final mid = a.editor.columns[1].id;
          a.backend.online = false;
          b.backend.online = false;
          a.editor.deleteColumn(mid);
          b.editor.moveCard(card, columnId: mid, index: 0);
          heal(w, [a, b]);
          for (final c in [a, b]) {
            expect(c.editor.columns, hasLength(2));
            expect(c.editor.item(card)!.columnId, mid, reason: 'never written back');
            expect(c.editor.columnOf(card), c.editor.columns.first.id);
          }
          expectConverged(w, id, [a, b]);
        }));

    test('same user on two devices at identical wall ms converges', () => inFakeTime((async) {
          final w = World(async);
          final d1 = Device(w, userId: 'u-ada', name: 'Ada (iPad)').boot();
          final d2 = Device(w, userId: 'u-ada', name: 'Ada (Mac)').boot();
          final (id, code) = w.share(d1);
          w.join(d2, code);
          expect(d1.sync.peers.value.single.key, d2.clock.node, reason: 'two devices, two presences');
          final s = sticky(d1, 'ortak');
          w.run(const Duration(seconds: 1));
          d1.backend.online = false;
          d2.backend.online = false;
          d1.editor.updateSticky(s, text: 'iPad');
          d2.editor.updateSticky(s, text: 'Mac');
          d2.editor.updateSticky(s, colorIndex: 6);
          expect(d1.doc.items[s]!.h[F.text]!.substring(0, 21), d2.doc.items[s]!.h[F.text]!.substring(0, 21));
          heal(w, [d1, d2]);
          final winner = d1.clock.node.compareTo(d2.clock.node) > 0 ? 'iPad' : 'Mac';
          expect(d1.doc.items[s]!.text, winner);
          expect(d2.doc.items[s]!.text, winner);
          expect(d1.doc.items[s]!.colorIndex, 6);
          expectConverged(w, id, [d1, d2]);
        }));

    test('a newer value taken from an ack moves the clock, so the next edit wins', () => inFakeTime((async) {
          final w = World(async);
          final dev = Device(w, userId: 'u-ada', name: 'Ada', skewMs: -3600 * 1000);
          final a = dev.boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (id, code) = w.share(a);
          w.join(b, code);
          a.controller.clockOffsetMs = 0; // as if the measurement had failed
          final s = sticky(b, 'ilk');
          w.run(const Duration(seconds: 1));
          // Ada only learns of Bora's edit through her push's ack.
          a.backend
            ..online = false
            ..dropRate = 1
            ..fault = (call) => call == 'pullItems' ? const BackendUnavailable() : null;
          w.run(const Duration(minutes: 5));
          b.editor.updateSticky(s, text: 'Bora');
          w.run(const Duration(seconds: 1));
          a.editor.updateSticky(s, text: 'Ada eski');
          a.backend.online = true;
          w.run(const Duration(seconds: 2));
          expect(a.doc.items[s]!.text, 'Bora', reason: 'lost to the newer write');
          a.editor.updateSticky(s, text: 'Ada yeni');
          w.run(const Duration(seconds: 2));
          expect(w.server.boards[id]!.items[s]!.data[F.text], 'Ada yeni');
          expect(b.doc.items[s]!.text, 'Ada yeni');
        }));

    test('clock moved back 10 minutes plus a restart: the next edit still wins', () => inFakeTime((async) {
          final w = World(async);
          final dev = Device(w, userId: 'u-ada', name: 'Ada');
          var a = dev.boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (id, code) = w.share(a);
          w.join(b, code);
          final s = sticky(a, 'eins');
          w.run(const Duration(seconds: 2));
          final stored = a.doc.items[s]!.h[F.text]!;
          a.close();
          a = dev.boot()..backend.online = false; // no fresh offset measurement
          dev.skewMs = -10 * 60 * 1000;
          a.open(id);
          a.editor.updateSticky(s, text: 'zwei');
          expect(a.doc.items[s]!.h[F.text]!.compareTo(stored), greaterThan(0));
          a.backend.online = true;
          w.run(const Duration(seconds: 3));
          expect(b.doc.items[s]!.text, 'zwei');
          expectConverged(w, id, [a, b]);
        }));
  });

  group('ink', () {
    test('ink deleted at load and restored by a teammate gets its strokes back', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final ink = a.editor.addInk(origin: const Offset(5, 5), strokes: 'PINK1:çizgi');
          w.run(const Duration(seconds: 1));
          a.editor.deleteItems({ink});
          w.run(const Duration(seconds: 1));
          b.close();
          b.open(id); // deleted ink: strokes stay on disk
          expect(b.doc.items[ink]!.strokes, isNull);
          a.editor.undo();
          w.run(const Duration(seconds: 1));
          expect(b.editor.item(ink)!.deleted, isFalse);
          expect(b.editor.item(ink)!.strokes, 'PINK1:çizgi');
          expectConverged(w, id, [a, b]);
        }));
  });

  group('presence', () {
    test('peers are the others; activity is tracked; leaving removes them', () => inFakeTime((async) {
          final (w, a, b, _) = pair(async);
          expect(a.backend.lives.single.handlers.presenceKey, a.clock.node);
          final peer = a.sync.peers.value.single;
          expect(peer.key, b.clock.node);
          expect(peer.userId, 'u-bora');
          expect(peer.name, 'Bora');
          expect(peer.colorIndex, 4);
          expect(b.sync.peers.value.single.name, 'Ada');
          final card = a.editor.addCard(columnId: a.editor.columns.first.id, title: 'K');
          w.run(const Duration(seconds: 1));
          b.sync.setActivity(view: 'kanban', editing: card);
          w.settle();
          expect(a.sync.peers.value.single.view, 'kanban');
          expect(a.sync.peers.value.single.editing, card);
          b.close();
          w.settle();
          expect(a.sync.peers.value, isEmpty);
        }));

    test('presence is tracked again after the live channel reconnects', () => inFakeTime((async) {
          final (w, a, b, _) = pair(async);
          b.sync.setActivity(view: 'kanban');
          b.backend.online = false;
          w.settle();
          expect(a.sync.peers.value, isEmpty);
          expect(b.sync.peers.value, isEmpty);
          b.backend.online = true;
          w.run(const Duration(seconds: 1));
          expect(a.sync.peers.value.single.view, 'kanban');
          expect(b.sync.peers.value.single.name, 'Ada');
        }));

    test('cursors: only with company, ≤8 Hz, ≥2 units, trailing send, gone, not in the background', () => inFakeTime((async) {
          final w = World(async);
          final a = Device(w, userId: 'u-ada', name: 'Ada', colorIndex: 2).boot();
          final b = Device(w, userId: 'u-bora', name: 'Bora').boot();
          final (_, code) = w.share(a);
          a.sync.sendCursor(const Offset(1, 1));
          expect(a.backend.sentCursors, isEmpty, reason: 'alone');
          w.join(b, code);
          a.sync.sendCursor(const Offset(10, 10));
          expect(a.backend.sentCursors.single, {'key': a.clock.node, 'x': 10.0, 'y': 10.0});
          w.run(const Duration(milliseconds: 200));
          a.sync.sendCursor(const Offset(11, 10.5)); // < 2 units
          w.run(const Duration(milliseconds: 200));
          expect(a.backend.sentCursors, hasLength(1));
          // One second of fast movement.
          for (var i = 1; i <= 100; i++) {
            a.sync.sendCursor(Offset(10 + i * 3.0, 10));
            w.run(const Duration(milliseconds: 10));
          }
          w.run(const Duration(milliseconds: 200));
          final sent = a.backend.sentCursors.length - 1;
          expect(sent, inInclusiveRange(8, 9));
          expect(a.backend.sentCursors.last['x'], 310.0, reason: 'the last position goes out');
          final at = b.sync.cursors.value[a.clock.node]!;
          expect(at.position, const Offset(310, 10));
          expect(at.name, 'Ada');
          expect(at.colorIndex, 2);
          expect(at.pointer, isTrue);
          a.sync.sendCursor(const Offset(400, 10), pointer: false);
          w.settle();
          expect(b.sync.cursors.value[a.clock.node]!.pointer, isFalse);
          a.sync.sendCursor(null);
          w.settle();
          expect(a.backend.sentCursors.last, {'key': a.clock.node, 'gone': true});
          expect(b.sync.cursors.value, isEmpty);
          a.foreground.value = false;
          final n = a.backend.sentCursors.length;
          a.sync.sendCursor(const Offset(900, 900));
          expect(a.backend.sentCursors.length, n);
        }));

    test('incoming cursors fade out after 10 s and leave with their peer', () => inFakeTime((async) {
          final (w, a, b, _) = pair(async);
          a.sync.sendCursor(const Offset(5, 5));
          w.settle();
          expect(b.sync.cursors.value.keys, [a.clock.node]);
          w.run(const Duration(seconds: 9));
          a.sync.sendCursor(const Offset(50, 5));
          w.run(const Duration(seconds: 2));
          expect(b.sync.cursors.value, hasLength(1), reason: 'refreshed at 9 s');
          w.run(const Duration(seconds: 9));
          expect(b.sync.cursors.value, isEmpty);
          a.sync.sendCursor(const Offset(90, 5));
          w.settle();
          expect(b.sync.cursors.value, hasLength(1));
          a.close();
          w.settle();
          expect(b.sync.cursors.value, isEmpty);
        }));
  });

  group('close', () {
    test('flushes, removes channels and stops every timer', () => inFakeTime((async) {
          final (w, a, b, id) = pair(async);
          final s = sticky(a, 'son');
          a.close(); // before the 300 ms debounce
          expect(w.server.boards[id]!.items[s]!.data[F.text], 'son');
          expect(a.backend.channels, isEmpty);
          expect(a.backend.lives, isEmpty);
          final calls = a.backend.calls.length;
          w.run(const Duration(minutes: 10));
          expect(a.backend.calls.length, calls);
          expect(b.doc.items[s]!.text, 'son');
        }));

    test('a response after close is ignored and the edit stays dirty for next time', () => inFakeTime((async) {
          final (w, a, _, id) = pair(async);
          a.backend.latency = const Duration(seconds: 3);
          final s = sticky(a, 'yavaş');
          final board = a.board!;
          a.close(); // gives up after 5 s
          expect(board.doc.items[s]!.d, contains(F.text));
          final writes = a.store.writes;
          w.run(const Duration(seconds: 10));
          expect(board.doc.items[s]!.d, contains(F.text));
          expect(a.store.writes, writes);
          // Reopening pushes it again; the server already has it, so it just settles.
          a.backend.latency = Duration.zero;
          a.open(id);
          w.run(const Duration(seconds: 2));
          expect(a.doc.pendingCount, 0);
        }));

    test('refreshConnections replaces the engine cleanly', () => inFakeTime((async) {
          final (w, a, _, id) = pair(async);
          final old = a.sync;
          w.wait(a.controller.refreshConnections());
          w.run(const Duration(seconds: 1));
          expect(a.sync, isNot(same(old)));
          expect(a.backend.channels, hasLength(1));
          expect(a.sync.phase, SyncPhase.live);
          sticky(a, 'yeni motor');
          w.run(const Duration(seconds: 1));
          expectConverged(w, id, [a]);
        }));
  });
}
