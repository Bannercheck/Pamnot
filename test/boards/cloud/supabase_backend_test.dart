import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/sync/backend.dart';
import 'package:pamnot/boards/sync/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const board = '11111111-1111-4111-8111-111111111111';
const h1 = '000001760000000-00000-1111111111111111';
const h2 = '000001760000001-00000-2222222222222222';

/// One canned answer per request; the requests are kept for inspection.
class Server {
  final requests = <http.Request>[];
  http.Response Function(http.Request r) answer = (_) => http.Response('null', 200);

  http.Client get client => MockClient((r) async {
        requests.add(r);
        final a = answer(r);
        // PostgREST reads the request back from the response.
        return http.Response.bytes(a.bodyBytes, a.statusCode, headers: a.headers, request: r);
      });

  static http.Response json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  static http.Response error(int status, String code, {String? hint, String message = 'boom'}) =>
      json({'code': code, 'message': message, 'details': null, 'hint': hint}, status);
}

void main() {
  late Server server;
  late SupabaseClient client;
  late SupabaseBoardBackend backend;
  var signedIn = true;

  setUp(() {
    server = Server();
    signedIn = true;
    client = SupabaseClient(
      'https://abcdefghijklmnopqrst.supabase.co',
      'sb_publishable_test_key',
      httpClient: server.client,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    backend = SupabaseBoardBackend(client, host: 'abcdefghijklmnopqrst.supabase.co', signedIn: () => signedIn);
  });

  tearDown(() => client.dispose());

  group('RPCs', () {
    test('push_items: request shape and per-row acks', () async {
      server.answer = (_) => Server.json({
            'status': 'ok',
            'items': [
              {'id': 'a', 'fh': {'title': h2}, 'lost': {'title': 'server'}},
              {'id': 'b', 'fh': {'x': h1, 'y': h1}, 'lost': {}},
              {'id': 'bad', 'status': 'invalid'},
            ],
          });
      final rows = [
        {'id': 'a', 'kind': 'card', 'data': {'title': 'mine'}, 'fh': {'title': h1}},
      ];
      final r = await backend.pushItems(board, rows);
      final req = server.requests.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/rest/v1/rpc/push_items');
      expect(jsonDecode(req.body), {'p_board': board, 'p_items': rows});
      expect(req.headers['apikey'], 'sb_publishable_test_key');
      expect(r.status, PushStatus.ok);
      expect(r.acks, hasLength(3));
      expect(r.acks[0].fh, {'title': h2});
      expect(r.acks[0].lost, {'title': 'server'});
      expect(r.acks[1].fh, {'x': h1, 'y': h1});
      expect(r.acks[2].invalid, isTrue);
    });

    test('push_items: board_deleted and forbidden are statuses, not errors', () async {
      server.answer = (_) => Server.json({'status': 'board_deleted'});
      expect((await backend.pushItems(board, const [])).status, PushStatus.boardDeleted);
      server.answer = (_) => Server.json({'status': 'forbidden'});
      expect((await backend.pushItems(board, const [])).status, PushStatus.forbidden);
      server.answer = (_) => Server.json({'status': 'weird'});
      await expectLater(backend.pushItems(board, const []), throwsA(isA<BackendUnavailable>()));
    });

    test('42501 is AccessDenied while signed in, BackendUnavailable without a session', () async {
      server.answer = (_) => Server.error(403, '42501', message: 'permission denied for function push_items');
      await expectLater(backend.pushItems(board, const []), throwsA(isA<AccessDenied>()));
      signedIn = false;
      await expectLater(backend.pushItems(board, const []), throwsA(isA<BackendUnavailable>()));
    });

    test('rate_limited hint from join_board is RateLimited', () async {
      server.answer = (_) => Server.error(400, 'P0001', hint: 'rate_limited', message: 'too many wrong codes');
      await expectLater(backend.joinBoard('ZZZZZZZZZZ'), throwsA(isA<RateLimited>()));
    });

    test('join_board: null for a wrong code, the board for a right one', () async {
      server.answer = (_) => Server.json(null);
      expect(await backend.joinBoard('ZZZZZZZZZZ'), isNull);
      server.answer = (_) => Server.json({'board_id': board, 'title': 'Pano'});
      final j = await backend.joinBoard('K7Q2M9XDAB');
      expect(j?.boardId, board);
      expect(j?.title, 'Pano');
      expect(jsonDecode(server.requests.last.body), {'p_code': 'K7Q2M9XDAB'});
    });

    test('create_board: code back, 23505 is BoardIdTaken (and only there)', () async {
      server.answer = (_) => Server.json('K7Q2M9XDAB');
      expect(await backend.createBoard(board), 'K7Q2M9XDAB');
      expect(jsonDecode(server.requests.last.body), {'p_id': board});
      server.answer = (_) => Server.error(409, '23505', message: 'board id already in use');
      await expectLater(backend.createBoard(board), throwsA(isA<BoardIdTaken>()));
      await expectLater(backend.rotateInvite(board), throwsA(isA<BackendUnavailable>()));
    });

    // POSTs only: the library retries GETs on network errors and 5xx with
    // seconds of delay, which this file does not need to sit through.
    test('network failures and gateway pages are BackendUnavailable', () async {
      server.answer = (_) => throw http.ClientException('Connection refused');
      await expectLater(backend.serverTimeMs(), throwsA(isA<BackendUnavailable>()));
      server.answer = (_) => throw const SocketException('Failed host lookup');
      await expectLater(backend.pushItems(board, const []), throwsA(isA<BackendUnavailable>()));
      server.answer = (_) => http.Response('<html>502 Bad Gateway</html>', 502);
      await expectLater(backend.joinBoard('K7Q2M9XDAB'), throwsA(isA<BackendUnavailable>()));
      server.answer = (_) => http.Response('<html>oops</html>', 200);
      await expectLater(backend.createBoard(board), throwsA(isA<BackendUnavailable>()));
      server.answer = (_) => Server.error(401, 'PGRST301', message: 'JWT expired');
      await expectLater(backend.members(board), throwsA(isA<BackendUnavailable>()));
    });

    test('a call that hangs times out as BackendUnavailable', () async {
      final hanging = SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k',
          httpClient: MockClient((_) => Completer<http.Response>().future),
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(hanging.dispose);
      final b = SupabaseBoardBackend(hanging, host: 'h', timeout: const Duration(milliseconds: 50));
      await expectLater(b.pullItems(board, afterRev: 0), throwsA(isA<BackendUnavailable>()));
    });

    test('small RPCs send the right parameters', () async {
      server.answer = (_) => Server.json(1762000000123);
      expect(await backend.serverTimeMs(), 1762000000123);
      server.answer = (_) => Server.json(null);
      await backend.leaveBoard(board);
      expect(server.requests.last.url.path, '/rest/v1/rpc/leave_board');
      expect(jsonDecode(server.requests.last.body), {'p_board': board});
      await backend.deleteBoard(board);
      expect(server.requests.last.url.path, '/rest/v1/rpc/delete_board');
      expect(await backend.getInvite(board), isNull);
      server.answer = (_) => Server.json('NEWC0DE123');
      expect(await backend.getInvite(board), 'NEWC0DE123');
      expect(await backend.rotateInvite(board), 'NEWC0DE123');
      expect(await backend.removeMember(board, 'u2'), 'NEWC0DE123');
      expect(server.requests.last.url.path, '/rest/v1/rpc/remove_member');
      expect(jsonDecode(server.requests.last.body), {'p_board': board, 'p_user': 'u2'});
    });
  });

  group('queries', () {
    test('pull: rev cursor, rev order, limit and parsed rows', () async {
      server.answer = (_) => Server.json([
            {
              'id': 'c1',
              'kind': 'card',
              'data': {'title': 'Kart'},
              'fh': {'title': h1},
              'rev': 41,
              'updated_by': 'u1',
              'updated_at': '2026-11-04T10:00:00.123456+00:00',
            },
            {'id': 'c2', 'kind': 'card', 'data': {'title': 'x'}, 'fh': {'title': h2}, 'rev': 42, 'updated_by': 'u2', 'updated_at': null},
          ]);
      final rows = await backend.pullItems(board, afterRev: 40, limit: 500);
      final q = server.requests.single.url.queryParameters;
      expect(server.requests.single.url.path, '/rest/v1/board_items');
      expect(q['select'], 'id,kind,data,fh,rev,updated_by,updated_at');
      expect(q['board_id'], 'eq.$board');
      expect(q['rev'], 'gt.40');
      expect(q['order'], startsWith('rev.asc'));
      expect(q['limit'], '500');
      expect(rows.map((r) => r.rev), [41, 42]);
      expect(rows.first.data, {'title': 'Kart'});
      expect(rows.first.fh, {'title': h1});
      expect(rows.first.updatedBy, 'u1');
      expect(rows.first.updatedAt, DateTime.utc(2026, 11, 4, 10, 0, 0, 123, 456));
    });

    test('pull: a row without data keeps its place as an empty row; one without rev fails', () async {
      server.answer = (_) => Server.json([
            {'id': 'c1', 'kind': 'card', 'data': null, 'fh': {'title': h1}, 'rev': 7},
          ]);
      final rows = await backend.pullItems(board, afterRev: 6);
      expect(rows.single.rev, 7);
      expect(rows.single.fh, isEmpty, reason: 'merging it changes nothing');
      server.answer = (_) => Server.json([
            {'id': 'c1', 'kind': 'card', 'data': {}, 'fh': {}},
          ]);
      await expectLater(backend.pullItems(board, afterRev: 6), throwsA(isA<BackendUnavailable>()));
    });

    test('status: missing row is null (revoked), deleted_at is read', () async {
      server.answer = (_) => Server.json([]);
      expect(await backend.boardStatus(board), isNull);
      final q = server.requests.last.url.queryParameters;
      expect(q['select'], 'owner_id,deleted_at');
      expect(q['id'], 'eq.$board');
      server.answer = (_) => Server.json([
            {'owner_id': 'u1', 'deleted_at': '2026-11-04T10:00:00+00:00'},
          ]);
      final s = await backend.boardStatus(board);
      expect(s?.ownerId, 'u1');
      expect(s?.deletedAt, DateTime.utc(2026, 11, 4, 10));
      server.answer = (_) => Server.json([
            {'owner_id': 'u1', 'deleted_at': null},
          ]);
      expect((await backend.boardStatus(board))?.deletedAt, isNull);
    });

    test('members: membership joined with profiles, owner first', () async {
      server.answer = (r) => r.url.path.endsWith('/board_members')
          ? Server.json([
              {'user_id': 'u3', 'role': 'editor'},
              {'user_id': 'u2', 'role': 'editor'},
              {'user_id': 'u1', 'role': 'owner'},
            ])
          : Server.json([
              {'id': 'u1', 'display_name': 'Zeynep', 'color_index': 2},
              {'id': 'u2', 'display_name': 'ayşe', 'color_index': 5},
            ]);
      final m = await backend.members(board);
      expect(m.map((x) => x.userId), ['u1', 'u3', 'u2'], reason: 'owner, then by name ("" before "ayşe")');
      expect(m.first.role, 'owner');
      expect(m.first.displayName, 'Zeynep');
      expect(m.last.colorIndex, 5);
      expect(m[1].displayName, '', reason: 'no profile yet');
      expect(server.requests.last.url.queryParameters['id'], 'in.("u3","u2","u1")');
    });
  });

  group('payload helpers', () {
    PostgresChangePayload change(Map<String, Object?> record, {Object? errors}) => PostgresChangePayload.fromPayload({
          'schema': 'public',
          'table': 'board_items',
          'commit_timestamp': '2026-11-04T10:00:00Z',
          'eventType': 'UPDATE',
          'new': record,
          'old': <String, Object?>{},
          'errors': errors,
        });

    test('realtime rows: complete, truncated, with errors, other board', () {
      final full = {'board_id': board, 'id': 'c1', 'kind': 'card', 'data': {'title': 'x'}, 'fh': {'title': h1}, 'rev': 3};
      final (d1, r1) = realtimeRow(change(full), board);
      expect(d1, isTrue);
      expect(r1?.rev, 3);
      final (d2, r2) = realtimeRow(change({...full}..remove('data')), board);
      expect((d2, r2), (true, null), reason: 'truncated: ask for a catch-up');
      final (d3, r3) = realtimeRow(change(full, errors: ['Error 413: Payload Too Large']), board);
      expect((d3, r3), (true, null));
      final (d4, _) = realtimeRow(change({...full, 'board_id': '22222222-2222-4222-8222-222222222222'}), board);
      expect(d4, isFalse);
      final (d5, r5) = realtimeRow(change({...full}..remove('rev')), board);
      expect((d5, r5), (true, null));
    });

    test('presence state is flattened with its key', () {
      final state = [
        SinglePresenceState(key: 'node-a', presences: [
          Presence.fromJson({'presence_ref': 'r1', 'userId': 'u1', 'name': 'Ayşe', 'colorIndex': 3, 'view': 'canvas'}),
        ]),
        SinglePresenceState(key: 'node-b', presences: [
          Presence.fromJson({'presence_ref': 'r2', 'userId': 'u2', 'name': 'Mert'}),
        ]),
      ];
      final p = presencesOf(state);
      expect(p, hasLength(2));
      expect(p.first, {'userId': 'u1', 'name': 'Ayşe', 'colorIndex': 3, 'view': 'canvas', 'key': 'node-a'});
      expect(p.last['key'], 'node-b');
    });

    test('cursor broadcasts carry their payload inside', () {
      expect(broadcastPayload({'type': 'broadcast', 'event': 'cursor', 'payload': {'x': 1, 'y': 2}}), {'x': 1, 'y': 2});
      expect(broadcastPayload({'type': 'broadcast', 'event': 'cursor'}), isNull);
    });

    test('status mapping and error mapping', () {
      expect(RealtimeSubscribeStatus.values.map(subscribeStatusOf).toSet(), SubscribeStatus.values.toSet());
      expect(mapBackendError(const AccessDenied()), isA<AccessDenied>());
      expect(mapBackendError(const PostgrestException(message: 'x', code: '23505')), isA<BackendUnavailable>());
      expect(mapBackendError(const PostgrestException(message: 'x', code: '23505'), creating: true), isA<BoardIdTaken>());
      expect(mapBackendError(AuthRetryableFetchException()), isA<BackendUnavailable>());
      expect(mapBackendError(const FormatException('x')), isA<BackendUnavailable>());
    });

    test('membersOf survives odd rows', () {
      final m = membersOf([
        {'user_id': 5},
        {'user_id': 'u1', 'role': 'admin'},
      ], [
        {'id': 'u1', 'display_name': null},
      ]);
      expect(m.single.role, 'editor');
      expect(m.single.displayName, '');
    });

    test('pulledRow requires id, kind and rev', () {
      expect(pulledRow({'id': 'a', 'kind': 'card', 'data': {}, 'fh': {}, 'rev': 1}).rev, 1);
      expect(() => pulledRow({'id': 'a', 'rev': 1}), throwsFormatException);
      expect(RemoteRow.tryParse({'id': 'a', 'kind': 'card', 'data': {}, 'fh': {}}), isNull);
    });
  });
}
