import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/cloud/server_config.dart';

import 'fakes.dart';

void main() {
  group('checkServerUrl', () {
    const ref = 'abcdefghijklmnopqrst';
    const ok = 'https://$ref.supabase.co';
    final cases = <String, Object>{
      ok: ok,
      '$ok/': ok,
      '$ok/rest/v1': ok,
      '$ok/rest/v1/': ok,
      '  $ok  \n': ok,
      'https://ABCDEFGHIJKLMNOPQRST.Supabase.co': ok,
      '$ref.supabase.co': ok,
      ref: ok,
      ref.toUpperCase(): ok,
      'https://supabase.com/dashboard/project/$ref': ok,
      'https://supabase.com/dashboard/project/$ref/settings/api': ok,
      'supabase.com/dashboard/project/$ref/editor': ok,
      'https://app.supabase.com/project/$ref': ok,
      'https://my.server.example:8443/': 'https://my.server.example:8443',
      'https://my.server.example:443': 'https://my.server.example',
      'http://localhost:54321': 'http://localhost:54321',
      'localhost:54321': 'http://localhost:54321',
      'http://127.0.0.1:54321/rest/v1': 'http://127.0.0.1:54321',
      'http://10.0.2.2:54321': 'http://10.0.2.2:54321',
      'https://localhost:54321': 'https://localhost:54321',
      '': UrlProblem.empty,
      '   ': UrlProblem.empty,
      'http://$ref.supabase.co': UrlProblem.insecure,
      'http://example.com': UrlProblem.insecure,
      'ftp://$ref.supabase.co': UrlProblem.invalid,
      'not a url': UrlProblem.invalid,
      'abc': UrlProblem.invalid,
      'https://supabase.com': UrlProblem.dashboard,
      'https://supabase.com/dashboard/projects': UrlProblem.dashboard,
      'supabase.com/dashboard/project/short': UrlProblem.dashboard,
    };
    for (final e in cases.entries) {
      test('"${e.key.replaceAll('\n', r'\n')}" → ${e.value}', () {
        final r = checkServerUrl(e.key);
        if (e.value is String) {
          expect(r.url, e.value);
          expect(r.problem, isNull);
        } else {
          expect(r.url, isNull);
          expect(r.problem, e.value);
        }
      });
    }

    test('serverHost keeps a non-default port', () {
      expect(serverHost(ok), '$ref.supabase.co');
      expect(serverHost('http://localhost:54321'), 'localhost:54321');
      expect(serverHost('https://x.example:443'), 'x.example');
    });
  });

  group('checkPublishableKey', () {
    final cases = <String, KeyProblem?>{
      'sb_publishable_AbCdEf123456': null,
      '  sb_publishable_AbCdEf123456\n': null,
      'sb_publishable_': KeyProblem.unrecognized,
      'sb_secret_AbCdEf123456': KeyProblem.secret,
      jwt({'role': 'anon', 'iss': 'supabase'}): null,
      jwt({'role': 'service_role'}): KeyProblem.secret,
      jwt({'role': 'authenticated'}): KeyProblem.wrongRole,
      jwt({'iss': 'supabase'}): KeyProblem.unrecognized,
      'a.b.c': KeyProblem.unrecognized,
      'hello': KeyProblem.unrecognized,
      '': KeyProblem.empty,
      ' \n ': KeyProblem.empty,
    };
    var i = 0;
    for (final e in cases.entries) {
      test('key #${i++} → ${e.value}', () => expect(checkPublishableKey(e.key), e.value));
    }

    test('a JWT pasted across lines is still recognised', () {
      final k = jwt({'role': 'anon'});
      expect(checkPublishableKey('${k.substring(0, 20)}\n${k.substring(20)}'), isNull);
      expect(cleanKey(' a b\nc '), 'abc');
    });
  });

  group('CloudConfig', () {
    test('json round trip', () {
      const c = CloudConfig(url: 'https://abcdefghijklmnopqrst.supabase.co', key: 'sb_publishable_AbCdEf123456', name: 'Ayşe', colorIndex: 3, profilePending: true);
      final back = CloudConfig.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
      expect(back.url, c.url);
      expect(back.key, c.key);
      expect(back.name, 'Ayşe');
      expect(back.colorIndex, 3);
      expect(back.profilePending, isTrue);
      expect(back.host, 'abcdefghijklmnopqrst.supabase.co');
    });

    test('a stored secret key or bad url is not loaded', () {
      expect(CloudConfig.fromJson({'url': 'https://x.supabase.co', 'key': 'sb_secret_abcdefghijklmnop'}), isNull);
      expect(CloudConfig.fromJson({'url': 'http://x.example.com', 'key': 'sb_publishable_AbCdEf123456'}), isNull);
      expect(CloudConfig.fromJson('garbage'), isNull);
      expect(CloudConfig.fromJson({'url': 1}), isNull);
    });
  });
}
