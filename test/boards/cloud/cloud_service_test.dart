import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/cloud/cloud_api.dart';
import 'package:pamnot/boards/cloud/cloud_service.dart';
import 'package:pamnot/boards/cloud/supabase_cloud_api.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes.dart';

const url = 'https://abcdefghijklmnopqrst.supabase.co';
const host = 'abcdefghijklmnopqrst.supabase.co';
const key = 'sb_publishable_AbCdEf123456';

void main() {
  late MemoryStore store;
  late FakeCloudApi api;
  CloudService service({String defaultUrl = '', String defaultKey = ''}) =>
      CloudService(store: store, api: api, defaultUrl: defaultUrl, defaultKey: defaultKey);

  setUp(() {
    store = MemoryStore();
    api = FakeCloudApi();
  });

  group('CloudService', () {
    test('nothing saved: stays off and never starts a client', () async {
      final c = service();
      await c.start();
      expect(c.ready.value, isFalse);
      expect(c.backend, isNull);
      expect(c.account, isNull);
      expect(c.config, isNull);
      expect(api.calls, isEmpty);
    });

    test('connect runs the checks in order, signs in and saves the config', () async {
      final c = service();
      await c.start();
      final steps = <ConnectStep>[];
      await c.connect(url: '$url/rest/v1/', key: ' $key\n', name: ' Ayşe ', colorIndex: 4, onStep: steps.add);
      expect(steps, ConnectStep.values);
      expect(api.calls, ['start $url', 'probe', 'schema', 'signIn Ayşe', 'profile Ayşe 4']);
      expect(c.ready.value, isTrue);
      expect(c.account, const BoardAccount(host: host, userId: 'user-1'));
      expect(c.backend?.host, host);
      expect(c.displayName, 'Ayşe');
      expect(c.colorIndex, 4);
      final doc = jsonDecode(store.data[CloudService.docKey]!) as Map;
      expect(doc['url'], url);
      expect(doc['key'], key);
      expect(doc['name'], 'Ayşe');
      expect(doc['colorIndex'], 4);
    });

    test('a later start restores the session without any network call', () async {
      await service().connect(url: url, key: key, name: 'Ayşe', colorIndex: 1);
      api.calls.clear();
      final c = service();
      await c.start();
      expect(api.calls, ['start $url']);
      expect(c.ready.value, isTrue);
      expect(c.account?.userId, 'user-1');
    });

    test('a saved session is reused: connecting again does not make a new member', () async {
      final c = service();
      await c.connect(url: url, key: key, name: 'Ayşe', colorIndex: 1);
      await c.connect(url: url, key: key, name: 'Ayşe', colorIndex: 2);
      expect(api.calls.where((x) => x.startsWith('signIn')), hasLength(1));
      expect(c.account?.userId, 'user-1');
      expect(c.colorIndex, 2);
    });

    test('saved server without a session: not ready, server still known', () async {
      store.data[CloudService.docKey] = jsonEncode({'url': url, 'key': key, 'name': 'Ayşe', 'colorIndex': 2});
      final c = service();
      await c.start();
      expect(c.ready.value, isFalse);
      expect(c.server?.host, host);
      expect(c.displayName, 'Ayşe');
      await c.connect(url: c.server!.url, key: c.server!.key, name: 'Ayşe', colorIndex: 2);
      expect(c.ready.value, isTrue);
    });

    test('a failed check saves nothing and leaves no client running', () async {
      api.signInError = const CloudFailure(CloudProblem.anonymousDisabled);
      final c = service();
      await expectLater(
        c.connect(url: url, key: key, name: 'Ayşe', colorIndex: 1),
        throwsA(isA<CloudFailure>().having((e) => e.problem, 'problem', CloudProblem.anonymousDisabled)),
      );
      expect(c.ready.value, isFalse);
      expect(store.data.containsKey(CloudService.docKey), isFalse);
      expect(api.calls.last, 'stop');
      expect(api.started, isFalse);
    });

    test('each check reports its own problem', () async {
      final cases = <void Function(), CloudProblem>{
        () => api.probeError = const CloudFailure(CloudProblem.unreachable): CloudProblem.unreachable,
        () => api.probeError = const CloudFailure(CloudProblem.badKey): CloudProblem.badKey,
        () => api.schemaError = const CloudFailure(CloudProblem.sqlMissing): CloudProblem.sqlMissing,
        () => api.schema = 0: CloudProblem.sqlOutdated,
        () => api.signInError = const CloudFailure(CloudProblem.rateLimited): CloudProblem.rateLimited,
        () => api.profileError = const CloudFailure(CloudProblem.sqlMissing): CloudProblem.sqlMissing,
      };
      for (final e in cases.entries) {
        api = FakeCloudApi();
        e.key();
        final c = service();
        CloudProblem? got;
        try {
          await c.connect(url: url, key: key, name: 'A', colorIndex: 0);
        } on CloudFailure catch (f) {
          got = f.problem;
        }
        expect(got, e.value);
        expect(c.ready.value, isFalse);
      }
    });

    test('raw errors from the client are mapped too', () async {
      api.probeError = null;
      final c = CloudService(store: store, api: _ThrowingApi(const SocketException('no route')));
      await expectLater(
        c.connect(url: url, key: key, name: 'A', colorIndex: 0),
        throwsA(isA<CloudFailure>().having((e) => e.problem, 'problem', CloudProblem.unreachable)),
      );
    });

    test('bad input never reaches the network', () async {
      final c = service();
      await expectLater(c.connect(url: 'http://example.com', key: key, name: 'A', colorIndex: 0), throwsA(isA<CloudFailure>()));
      await expectLater(c.connect(url: url, key: 'sb_secret_abcdefghijkl', name: 'A', colorIndex: 0),
          throwsA(isA<CloudFailure>().having((e) => e.problem, 'problem', CloudProblem.badKey)));
      expect(api.calls, isEmpty);
    });

    test('switching servers requires disconnecting first', () async {
      final c = service();
      await c.connect(url: url, key: key, name: 'A', colorIndex: 0);
      await expectLater(
        c.connect(url: 'https://zyxwvutsrqponmlkjihg.supabase.co', key: key, name: 'A', colorIndex: 0),
        throwsA(isA<CloudFailure>().having((e) => e.problem, 'problem', CloudProblem.otherServer)),
      );
      expect(c.ready.value, isTrue, reason: 'the refused switch leaves the current server alone');
      await c.disconnect();
      expect(api.calls.last, 'stop signOut');
      expect(c.ready.value, isFalse);
      expect(c.config, isNull);
      expect(store.data.containsKey(CloudService.docKey), isFalse);
      await c.connect(url: 'https://zyxwvutsrqponmlkjihg.supabase.co', key: key, name: 'A', colorIndex: 0);
      expect(c.account?.host, 'zyxwvutsrqponmlkjihg.supabase.co');
      expect(c.account?.userId, 'user-2', reason: 'signing out ended the old identity');
    });

    test('a failed reconnect to the saved server keeps the old session syncing', () async {
      final c = service();
      await c.connect(url: url, key: key, name: 'A', colorIndex: 0);
      api.probeError = const CloudFailure(CloudProblem.unreachable);
      await expectLater(c.connect(url: url, key: key, name: 'B', colorIndex: 0), throwsA(isA<CloudFailure>()));
      expect(c.ready.value, isTrue);
      expect(c.displayName, 'A');
    });

    test('profile changes are saved locally and sent; offline ones wait for the next start', () async {
      final c = service();
      await c.connect(url: url, key: key, name: 'Ayşe', colorIndex: 1);
      await c.updateProfile(name: 'Ayşe K.');
      expect(api.profiles.last, ('Ayşe K.', 1));
      expect((jsonDecode(store.data[CloudService.docKey]!) as Map)['profilePending'], isNull);

      api.profileError = const CloudFailure(CloudProblem.unreachable);
      await c.updateProfile(colorIndex: 6);
      expect(c.colorIndex, 6);
      final saved = jsonDecode(store.data[CloudService.docKey]!) as Map;
      expect(saved['colorIndex'], 6);
      expect(saved['profilePending'], isTrue);

      api.profileError = null;
      final again = service();
      await again.start();
      await pumpEventQueue();
      expect(api.profiles.last, ('Ayşe K.', 6));
      expect((jsonDecode(store.data[CloudService.docKey]!) as Map)['profilePending'], isNull);
    });

    test('a session that ends by itself turns ready off', () async {
      final c = service();
      await c.connect(url: url, key: key, name: 'A', colorIndex: 0);
      api.endSession();
      expect(c.ready.value, isFalse);
      expect(c.backend, isNull);
      expect(c.config, isNotNull, reason: 'the server stays known for reconnecting');
    });

    test('--dart-define server is a preset, not a connection', () async {
      final c = service(defaultUrl: 'abcdefghijklmnopqrst', defaultKey: key);
      await c.start();
      expect(c.preset?.url, url);
      expect(c.server?.url, url);
      expect(c.config, isNull);
      expect(c.ready.value, isFalse);
      expect(service(defaultUrl: url, defaultKey: 'sb_secret_abcdefghijkl').preset, isNull);
      expect(service().preset, isNull);
    });

    test('attach wires the account, and disconnect removes this account’s shared copies only', () async {
      final boards = BoardsController(store: store, saveDelay: Duration.zero);
      await boards.load();
      final c = service();
      var made = 0;
      c.attach(boards, connections: (b, ctl) {
        made++;
        return LocalConnection();
      });
      await c.connect(url: url, key: key, name: 'A', colorIndex: 0);
      expect(boards.currentAccount(), c.account);
      final localId = await boards.createBoard(title: 'Yerel', colorIndex: 0, template: BoardTemplate.blank, strings: S.tr);
      await boards.addJoined(boardId: 'shared-1', title: 'Ortak', account: c.account!);
      await boards.addJoined(boardId: 'other-1', title: 'Başka', account: const BoardAccount(host: 'x.example', userId: 'u'));
      final open = await boards.open('shared-1');
      expect(made, 1, reason: 'a shared board of this account syncs');

      await c.disconnect();
      await boards.flush();
      expect(boards.summary(localId), isNotNull);
      expect(boards.summary('shared-1'), isNull);
      expect(boards.summary('other-1'), isNotNull, reason: 'boards of other servers are not ours to delete');
      expect(boards.currentAccount(), isNull);
      expect(open, isNotNull);
      boards.dispose();
    });
  });

  group('error mapping', () {
    CloudProblem p(Object e) => cloudFailureOf(e).problem;

    test('auth errors', () {
      expect(p(const AuthApiException('x', statusCode: '422', code: 'anonymous_provider_disabled')), CloudProblem.anonymousDisabled);
      expect(p(const AuthApiException('Anonymous sign-ins are disabled', statusCode: '422')), CloudProblem.anonymousDisabled);
      expect(p(const AuthApiException('x', statusCode: '422', code: 'signup_disabled')), CloudProblem.signupsDisabled);
      expect(p(const AuthApiException('x', statusCode: '429', code: 'over_request_rate_limit')), CloudProblem.rateLimited);
      expect(p(const AuthApiException('x', statusCode: '429')), CloudProblem.rateLimited);
      expect(p(const AuthApiException('Invalid API key', statusCode: '401')), CloudProblem.badKey);
      expect(p(AuthRetryableFetchException(message: 'SocketException')), CloudProblem.unreachable);
      expect(p(const AuthApiException('?', statusCode: '400')), CloudProblem.unknown);
    });

    test('PostgREST errors', () {
      expect(p(const PostgrestException(message: 'Could not find the function public.pamnot_info', code: 'PGRST202')),
          CloudProblem.sqlMissing);
      expect(p(const PostgrestException(message: 'relation does not exist', code: 'PGRST205')), CloudProblem.sqlMissing);
      expect(p(const PostgrestException(message: '{"message":"Invalid API key"}', code: '401')), CloudProblem.badKey);
      expect(p(const PostgrestException(message: '<html>', code: '503')), CloudProblem.unreachable);
      expect(p(const PostgrestException(message: 'x', code: 'P0001', hint: 'rate_limited')), CloudProblem.rateLimited);
      expect(p(const PostgrestException(message: 'x', code: '22023')), CloudProblem.unknown);
    });

    test('transport errors', () {
      expect(p(const SocketException('Failed host lookup')), CloudProblem.unreachable);
      expect(p(const HandshakeException('bad cert')), CloudProblem.unreachable);
      expect(p(Exception('timeout')), CloudProblem.unreachable);
      expect(p(const CloudFailure(CloudProblem.badKey)), CloudProblem.badKey);
    });

    test('the /auth/v1/settings probe', () {
      expect(probeProblem(200, jsonEncode({'external': {'anonymous_users': true, 'email': true}})), isNull);
      expect(probeProblem(200, jsonEncode({'external': {'email': true}})), isNull, reason: 'missing field is no verdict');
      expect(probeProblem(200, jsonEncode({'external': {'anonymous_users': false}})), CloudProblem.anonymousDisabled);
      expect(probeProblem(200, jsonEncode({'disable_signup': true, 'external': {}})), CloudProblem.signupsDisabled);
      expect(probeProblem(401, '{"message":"Invalid API key"}'), CloudProblem.badKey);
      expect(probeProblem(403, ''), CloudProblem.badKey);
      expect(probeProblem(429, ''), CloudProblem.rateLimited);
      expect(probeProblem(404, 'not found'), CloudProblem.unreachable);
      expect(probeProblem(502, '<html>'), CloudProblem.unreachable);
      expect(probeProblem(200, '<html>not json</html>'), CloudProblem.unreachable);
    });
  });
}

/// An API whose network calls throw a raw (unmapped) error.
class _ThrowingApi extends FakeCloudApi {
  _ThrowingApi(this.error);

  final Object error;

  @override
  Future<void> probe() async => throw error;
}
