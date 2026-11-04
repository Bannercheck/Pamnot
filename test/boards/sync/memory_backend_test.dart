import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/hlc.dart';
import 'package:pamnot/boards/sync/backend.dart';
import 'package:pamnot/boards/sync/memory_backend.dart';

import 'harness.dart';

const board = '00000000-0000-4000-8000-0000000000b0';
const item = '00000000-0000-4000-8000-0000000000a1';
const item2 = '00000000-0000-4000-8000-0000000000a2';

String h(int ms, [int c = 0, String node = '000000000000000a']) => HlcClock.format(ms, c, node);

Map<String, Object?> row(String id, Map<String, Object?> data, Map<String, String> fh, {String kind = 'sticky'}) =>
    {'id': id, 'kind': kind, 'data': data, 'fh': fh};

void main() {
  group('push_items', () {
    late MemoryServer s;
    setUp(() {
      s = MemoryServer(nowMs: () => baseMs, random: math.Random(1));
      s.createBoard('owner', board);
    });

    test('merges field by field by HLC string order and reports lost fields', () {
      var r = s.pushItems('owner', board, [
        row(item, {'text': 'a', 'x': 1}, {'text': h(10), 'x': h(10)}),
      ]);
      expect(r.status, PushStatus.ok);
      expect(r.acks.single.fh, {'text': h(10), 'x': h(10)});
      // Newer text, older x.
      r = s.pushItems('owner', board, [
        row(item, {'text': 'b', 'x': 2}, {'text': h(11), 'x': h(9)}),
      ]);
      final it = s.boards[board]!.items[item]!;
      expect(it.data, {'text': 'b', 'x': 1});
      expect(it.fh, {'text': h(11), 'x': h(10)});
      expect(r.acks.single.lost, {'x': 1});
      // Equal HLCs: no change, nothing lost.
      r = s.pushItems('owner', board, [row(item, {'text': 'zzz'}, {'text': h(11)})]);
      expect(it.rev, 2);
      expect(r.acks.single.lost, isEmpty);
      expect(s.boards[board]!.items[item]!.data['text'], 'b');
      // The counter and node compare as plain strings too.
      s.pushItems('owner', board, [row(item, {'text': 'c'}, {'text': h(11, 0, '000000000000000b')})]);
      expect(s.boards[board]!.items[item]!.data['text'], 'c');
    });

    test('rev is per board, gap-free and bumped only for rows that changed', () {
      s.createBoard('owner', item2); // another board
      s.pushItems('owner', board, [
        row(item, {'text': 'a'}, {'text': h(10)}),
        row(item2, {'text': 'b'}, {'text': h(10)}),
      ]);
      s.pushItems('owner', board, [row(item, {'text': 'old'}, {'text': h(5)})]); // stale
      s.pushItems('owner', item2, [row(item, {'text': 'x'}, {'text': h(5)})]);
      s.pushItems('owner', board, [row(item2, {'text': 'c'}, {'text': h(20)})]);
      expect(s.boards[board]!.revLog, [1, 2, 3]);
      expect(s.boards[board]!.rev, 3);
      expect(s.boards[board]!.items[item]!.rev, 1);
      expect(s.boards[board]!.items[item2]!.rev, 3);
      expect(s.boards[item2]!.revLog, [1]);
    });

    test('invalid rows are skipped without failing the batch', () {
      final r = s.pushItems('owner', board, [
        row('not-a-uuid', {'text': 'a'}, {'text': h(10)}),
        row(item, {'text': 'a'}, {'text': h(10)}, kind: 'connector'),
        row(item2, {'text': 'ok', 'bad': 1, 'nodata': 2}, {'text': h(10), 'bad': 'garbage', 'missing': h(10)}),
        'not even a map',
      ]);
      expect(r.status, PushStatus.ok);
      expect(r.acks.map((a) => a.id), [item, item2]);
      expect(r.acks.first.invalid, isTrue);
      expect(s.boards[board]!.items.keys, [item2]);
      expect(s.boards[board]!.items[item2]!.data, {'text': 'ok'});
      expect(r.acks.last.fh, {'text': h(10)});
    });

    test('statuses instead of exceptions', () {
      expect(s.pushItems('stranger', board, [row(item, {'text': 'a'}, {'text': h(1)})]).status, PushStatus.forbidden);
      expect(s.pushItems('owner', item2, const []).status, PushStatus.forbidden); // no such board
      s.deleteBoard('stranger', board); // not the owner: no effect
      expect(s.boards[board]!.deletedAt, isNull);
      s.deleteBoard('owner', board);
      expect(s.pushItems('owner', board, const []).status, PushStatus.boardDeleted);
      expect(s.boardStatus('owner', board)!.deletedAt, isNotNull);
    });

    test('createBoard is idempotent for the owner and taken for anyone else', () {
      final code = s.createBoard('owner', board);
      expect(s.createBoard('owner', board), code);
      expect(() => s.createBoard('other', board), throwsA(isA<BoardIdTaken>()));
      expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{10}$')));
    });

    test('join, members, leave, remove and invites', () {
      s.setProfile('owner', 'Ada', 2);
      s.setProfile('bora', 'Bora', 4);
      final code = s.boards[board]!.code;
      expect(s.joinBoard('bora', 'nope'), isNull);
      final j = s.joinBoard('bora', '${code.substring(0, 5).toLowerCase()}-${code.substring(5)}')!;
      expect(j.boardId, board);
      expect(s.members('bora', board).map((m) => (m.displayName, m.role)), [('Ada', 'owner'), ('Bora', 'editor')]);
      expect(s.members('stranger', board), isEmpty);
      expect(s.getInvite('bora', board), isNull);
      expect(() => s.rotateInvite('bora', board), throwsA(isA<AccessDenied>()));
      final rotated = s.rotateInvite('owner', board);
      expect(rotated, isNot(code));
      expect(s.joinBoard('carl', code), isNull);
      s.leaveBoard('bora', board);
      expect(s.boardStatus('bora', board), isNull);
      expect(() => s.leaveBoard('owner', board), throwsA(isA<AccessDenied>()));
      s.joinBoard('bora', rotated);
      final next = s.removeMember('owner', board, 'bora');
      expect(next, isNot(rotated));
      expect(s.pullItems('bora', board, 0, 500), isEmpty);
    });

    test('wrong codes are rate limited', () {
      for (var i = 0; i < 10; i++) {
        expect(s.joinBoard('bora', 'WRONG$i'), isNull);
      }
      expect(() => s.joinBoard('bora', s.boards[board]!.code), throwsA(isA<RateLimited>()));
    });

    test('pull pages in rev order', () {
      for (var i = 0; i < 7; i++) {
        s.pushItems('owner', board, [row('00000000-0000-4000-8000-00000000000$i', {'text': '$i'}, {'text': h(10 + i)})]);
      }
      // Re-edit the first: it moves to the end.
      s.pushItems('owner', board, [row('00000000-0000-4000-8000-000000000000', {'text': 'z'}, {'text': h(99)})]);
      final p1 = s.pullItems('owner', board, 0, 3);
      expect(p1.map((r) => r.rev), [2, 3, 4]);
      final p2 = s.pullItems('owner', board, 4, 500);
      expect(p2.map((r) => r.rev), [5, 6, 7, 8]);
      expect(p2.last.data['text'], 'z');
    });
  });

  group('MemoryBackend', () {
    test('wire copies, offline, lost responses and faults', () => inFakeTime((async) {
          final w = World(async);
          final b = MemoryBackend(w.server, userId: 'owner', random: math.Random(2))..latency = const Duration(milliseconds: 50);
          w.wait(b.createBoard(board));
          final data = <String, Object?>{'subtasks': [<String, Object?>{'id': 's', 'title': 't', 'done': false}]};
          w.wait(b.pushItems(board, [row(item, data, {'subtasks': h(5)})]));
          ((data['subtasks'] as List).first as Map)['title'] = 'mutated';
          expect(w.wait(b.pullItems(board, afterRev: 0)).single.data['subtasks'], [
            {'id': 's', 'title': 't', 'done': false},
          ]);
          b.online = false;
          expect(() => w.wait(b.serverTimeMs()), throwsA(isA<BackendUnavailable>()));
          b.online = true;
          b.lossRate = 1;
          expect(() => w.wait(b.pushItems(board, [row(item2, {'text': 'x'}, {'text': h(6)})])),
              throwsA(isA<BackendUnavailable>()));
          // Applied even though the answer was lost.
          expect(w.server.boards[board]!.items.containsKey(item2), isTrue);
          b.lossRate = 0;
          b.fault = (call) => call == 'boardStatus' ? const AccessDenied() : null;
          expect(() => w.wait(b.boardStatus(board)), throwsA(isA<AccessDenied>()));
          expect(b.calls, containsAllInOrder(['createBoard', 'pushItems', 'pullItems', 'serverTimeMs']));
        }));

    test('realtime: replication starts after subscribed; faults drop, duplicate and truncate', () => inFakeTime((async) {
          final w = World(async);
          final owner = MemoryBackend(w.server, userId: 'owner', random: math.Random(3));
          final viewer = MemoryBackend(w.server, userId: 'owner', random: math.Random(4))
            ..replicationDelay = const Duration(milliseconds: 500);
          w.wait(owner.createBoard(board));
          final statuses = <SubscribeStatus>[];
          final system = <Map<String, Object?>>[];
          final rows = <RemoteRow?>[];
          viewer.subscribe(
            board,
            RealtimeHandlers(onStatus: (s, _) => statuses.add(s), onSystem: system.add, onRow: rows.add),
          );
          w.settle();
          expect(statuses, [SubscribeStatus.subscribed]);
          w.wait(owner.pushItems(board, [row(item, {'text': 'early'}, {'text': h(1)})]));
          w.run(const Duration(milliseconds: 600));
          expect(rows, isEmpty, reason: 'committed before replication was live');
          expect(system.single['status'], 'ok');
          w.wait(owner.pushItems(board, [row(item, {'text': 'live'}, {'text': h(2)})]));
          w.settle();
          expect(rows.single!.data['text'], 'live');
          viewer.duplicateRate = 1;
          w.wait(owner.pushItems(board, [row(item, {'text': 'twice'}, {'text': h(3)})]));
          w.settle();
          expect(rows.length, 3);
          viewer
            ..duplicateRate = 0
            ..truncateRate = 1;
          w.wait(owner.pushItems(board, [row(item, {'text': 'cut'}, {'text': h(4)})]));
          w.settle();
          expect(rows.last, isNull);
          viewer
            ..truncateRate = 0
            ..dropRate = 1;
          w.wait(owner.pushItems(board, [row(item, {'text': 'gone'}, {'text': h(5)})]));
          w.settle();
          expect(rows.length, 4);
          // Pause and resume: silence, then `subscribed` again.
          viewer
            ..dropRate = 0
            ..suspend();
          w.wait(owner.pushItems(board, [row(item, {'text': 'missed'}, {'text': h(6)})]));
          viewer.resumeSocket();
          w.run(const Duration(seconds: 1));
          expect(rows.length, 4);
          expect(statuses, [SubscribeStatus.subscribed, SubscribeStatus.subscribed]);
          viewer.channels.single.failReplication();
          w.settle();
          expect(statuses.last, SubscribeStatus.channelError);
          expect(system.last['status'], 'error');
          w.wait(owner.pushItems(board, [row(item, {'text': 'dead'}, {'text': h(7)})]));
          w.settle();
          expect(rows.length, 4);
        }));

    test('presence and cursors', () => inFakeTime((async) {
          final w = World(async);
          final a = MemoryBackend(w.server, userId: 'owner');
          final b = MemoryBackend(w.server, userId: 'bora');
          final code = w.wait(a.createBoard(board));
          w.wait(b.joinBoard(code));
          final seenByA = <List<Map<String, Object?>>>[];
          final cursorsAtB = <Map<String, Object?>>[];
          final la = a.joinLive(board, LiveHandlers(onPresence: seenByA.add, onCursor: (_) {}));
          final lb = b.joinLive(board, LiveHandlers(onPresence: (_) {}, onCursor: cursorsAtB.add));
          la.track({'key': 'na'});
          lb.track({'key': 'nb'});
          w.settle();
          expect(seenByA.last.map((p) => p['key']).toSet(), {'na', 'nb'});
          la.sendCursor({'key': 'na', 'x': 1, 'y': 2});
          w.settle();
          expect(cursorsAtB.single['x'], 1);
          b.online = false;
          w.settle();
          expect(seenByA.last.map((p) => p['key']), ['na']);
          b.online = true;
          w.settle();
          expect(seenByA.last.map((p) => p['key']), ['na'], reason: 'a rejoin starts untracked');
          lb.track({'key': 'nb'});
          w.settle();
          expect(seenByA.last.length, 2);
          b.kill();
          w.settle();
          expect(seenByA.last.map((p) => p['key']), ['na']);
        }));
  });

  test('BoardState names stay stable', () {
    expect(BoardState.values.map((s) => s.name), ['local', 'uploading', 'shared', 'deleted', 'revoked']);
  });
}
