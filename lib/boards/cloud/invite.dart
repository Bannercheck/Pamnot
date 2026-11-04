import 'dart:convert';

import 'server_config.dart';

/// The one text a teammate pastes to join a board: server, publishable key,
/// invite code and title, as `PMN1.` + base64url(JSON) without padding
/// (docs/boards/DESIGN.md §7).
class Invite {
  const Invite({required this.url, required this.key, required this.code, required this.title});

  /// Normalised server origin.
  final String url;
  final String key;

  /// 10 Crockford base32 characters.
  final String code;
  final String title;

  String get host => serverHost(url);

  static const prefix = 'PMN1.';

  /// Finds the token anywhere in a pasted message.
  static final pattern = RegExp(r'PMN1\.[A-Za-z0-9_-]{16,}');

  String encode() {
    final json = jsonEncode({'u': url, 'k': key, 'c': code, 't': title});
    return prefix + base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// The first valid invite in [text] (a whole chat message is fine), or null.
  static Invite? find(String text) {
    for (final m in pattern.allMatches(text)) {
      final inv = decode(m.group(0)!);
      if (inv != null) return inv;
    }
    return null;
  }

  /// Decodes one token. Null when it is malformed or carries anything an app
  /// must not use: a non-https remote server or a secret key.
  static Invite? decode(String token) {
    if (!token.startsWith(prefix)) return null;
    final body = token.substring(prefix.length);
    if (body.length % 4 == 1) return null;
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body))));
      if (j is! Map) return null;
      final u = j['u'], k = j['k'], c = j['c'], t = j['t'];
      if (u is! String || k is! String || c is! String) return null;
      final url = checkServerUrl(u);
      if (!url.isOk || checkPublishableKey(k) != null) return null;
      final code = c.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
      if (code.isEmpty) return null;
      return Invite(url: url.url!, key: cleanKey(k), code: code, title: t is String ? t : '');
    } catch (_) {
      return null;
    }
  }
}
