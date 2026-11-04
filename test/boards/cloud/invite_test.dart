import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/cloud/invite.dart';

import 'fakes.dart';

void main() {
  const invite = Invite(
    url: 'https://abcdefghijklmnopqrst.supabase.co',
    key: 'sb_publishable_AbCdEf123456_xyz',
    code: 'K7Q2M9XDAB',
    title: 'İlk panom 🌷 · Ürün “lansman”',
  );

  group('Invite codec', () {
    test('round trip keeps every field, unicode included', () {
      final token = invite.encode();
      expect(token, startsWith('PMN1.'));
      expect(token.contains('='), isFalse, reason: 'no padding');
      expect(RegExp(r'^PMN1\.[A-Za-z0-9_-]+$').hasMatch(token), isTrue);
      final back = Invite.decode(token)!;
      expect(back.url, invite.url);
      expect(back.key, invite.key);
      expect(back.code, invite.code);
      expect(back.title, invite.title);
      expect(back.host, 'abcdefghijklmnopqrst.supabase.co');
    });

    test('round trips for every padding length', () {
      for (var n = 0; n < 6; n++) {
        final i = Invite(url: invite.url, key: invite.key, code: invite.code, title: 'x' * n);
        expect(Invite.decode(i.encode())?.title, 'x' * n);
      }
    });

    test('found inside a whole pasted chat message', () {
      final message = '[12:04] Ayşe: Pamnot’ta «İlk panom 🌷» panosuna katıl 🌸\n'
          '1. Pamnot’u aç → Takip → Panolar → Davete katıl\n'
          '2. Bu metnin tamamını yapıştır:\n'
          '${invite.encode()}\n'
          '[12:05] Ayşe: 👍';
      final found = Invite.find(message);
      expect(found?.code, invite.code);
      expect(found?.title, invite.title);
    });

    test('a token followed by punctuation still decodes', () {
      expect(Invite.find('davet: ${invite.encode()}. teşekkürler!')?.code, invite.code);
      expect(Invite.find('(${invite.encode()})')?.code, invite.code);
    });

    test('a broken token is skipped for the next good one', () {
      final text = 'PMN1.AAAAAAAAAAAAAAAAAAAAAAAA ve sonra ${invite.encode()}';
      expect(Invite.find(text)?.code, invite.code);
    });

    test('nothing to find', () {
      expect(Invite.find(''), isNull);
      expect(Invite.find('merhaba, bu bir davet değil'), isNull);
      expect(Invite.find('PMN1.short'), isNull);
      expect(Invite.decode('PMN2.${invite.encode().substring(5)}'), isNull);
      expect(Invite.decode('PMN1.${base64Url.encode(utf8.encode('[1,2,3]'))}'), isNull);
    });

    test('a legacy anon JWT is accepted as the key', () {
      final i = Invite(url: invite.url, key: jwt({'role': 'anon', 'ref': 'abcdefghijklmnopqrst'}), code: 'ABCDEFGHJK', title: 't');
      expect(Invite.decode(i.encode())?.key, i.key);
    });

    String raw(Map<String, Object?> j) => 'PMN1.${base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '')}';

    test('refuses a secret key or a service_role JWT', () {
      expect(Invite.decode(raw({'u': invite.url, 'k': 'sb_secret_abcdefghijklmnop', 'c': 'ABCDEFGHJK', 't': 'x'})), isNull);
      expect(Invite.decode(raw({'u': invite.url, 'k': jwt({'role': 'service_role'}), 'c': 'ABCDEFGHJK', 't': 'x'})), isNull);
    });

    test('refuses plain http to a remote server, accepts localhost', () {
      expect(Invite.decode(raw({'u': 'http://evil.example.com', 'k': invite.key, 'c': 'ABCDEFGHJK', 't': 'x'})), isNull);
      expect(Invite.decode(raw({'u': 'http://127.0.0.1:54321', 'k': invite.key, 'c': 'ABCDEFGHJK', 't': 'x'}))?.host,
          '127.0.0.1:54321');
    });

    test('normalises the url and code it carries', () {
      final i = Invite.decode(raw({
        'u': 'https://ABCDEFGHIJKLMNOPQRST.supabase.co/rest/v1/',
        'k': ' ${invite.key}\n',
        'c': 'k7q2-m9xd ab',
        't': 'x',
      }))!;
      expect(i.url, 'https://abcdefghijklmnopqrst.supabase.co');
      expect(i.key, invite.key);
      expect(i.code, 'K7Q2M9XDAB');
    });

    test('missing title is empty, missing code is invalid', () {
      expect(Invite.decode(raw({'u': invite.url, 'k': invite.key, 'c': 'ABCDEFGHJK'}))?.title, '');
      expect(Invite.decode(raw({'u': invite.url, 'k': invite.key, 't': 'x'})), isNull);
    });
  });
}
