/// What the owner types into the setup wizard, checked before anything is
/// sent anywhere (docs/boards/DESIGN.md §7).
library;

import 'dart:convert';

enum UrlProblem {
  empty,

  /// Not something we can turn into a server address.
  invalid,

  /// The supabase.com website or dashboard root rather than a project.
  dashboard,

  /// Plain http to a remote host.
  insecure,
}

class UrlCheck {
  const UrlCheck.ok(String this.url) : problem = null;
  const UrlCheck.bad(UrlProblem this.problem) : url = null;

  /// Normalised origin (`https://<ref>.supabase.co`), or null.
  final String? url;
  final UrlProblem? problem;

  bool get isOk => url != null;
}

final _dashboardProject =
    RegExp(r'supabase\.com/(?:dashboard/)?project/([a-z0-9]{20})(?:[/?#]|$)', caseSensitive: false);
final _projectRef = RegExp(r'^[a-z0-9]{20}$', caseSensitive: false);
const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
const _siteHosts = {'supabase.com', 'www.supabase.com', 'app.supabase.com', 'supabase.co'};

/// Turns what people paste as the "Project URL" into the server origin:
/// a dashboard URL or a bare project ref becomes `https://<ref>.supabase.co`;
/// paths such as `/rest/v1` and trailing slashes go. Only https, except for
/// a server on this machine (or the Android emulator's host).
UrlCheck checkServerUrl(String input) {
  var s = input.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return const UrlCheck.bad(UrlProblem.empty);
  final dash = _dashboardProject.firstMatch(s);
  if (dash != null) return UrlCheck.ok('https://${dash[1]!.toLowerCase()}.supabase.co');
  if (_projectRef.hasMatch(s)) return UrlCheck.ok('https://${s.toLowerCase()}.supabase.co');
  if (!s.contains('://')) {
    final bareHost = s.split(RegExp(r'[/:?#]')).first.toLowerCase();
    s = '${_localHosts.contains(bareHost) ? 'http' : 'https'}://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return const UrlCheck.bad(UrlProblem.invalid);
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return const UrlCheck.bad(UrlProblem.invalid);
  final local = _localHosts.contains(host);
  if (!local && !host.contains('.')) return const UrlCheck.bad(UrlProblem.invalid);
  if (_siteHosts.contains(host)) return const UrlCheck.bad(UrlProblem.dashboard);
  if (scheme == 'http' && !local) return const UrlCheck.bad(UrlProblem.insecure);
  final port = uri.hasPort && uri.port != (scheme == 'https' ? 443 : 80) ? ':${uri.port}' : '';
  final h = host.contains(':') ? '[$host]' : host;
  return UrlCheck.ok('$scheme://$h$port');
}

/// The part of a server origin that scopes local data: `host[:port]`.
String serverHost(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  final port = u.hasPort && u.port != (u.scheme == 'https' ? 443 : 80) ? ':${u.port}' : '';
  return '${u.host.toLowerCase()}$port';
}

enum KeyProblem {
  empty,

  /// `sb_secret_…` or a service_role JWT: never put it in an app.
  secret,

  /// A JWT for some other role.
  wrongRole,

  /// Neither a publishable key nor a JWT.
  unrecognized,
}

/// Removes the spaces and line breaks pasting tends to add.
String cleanKey(String input) => input.replaceAll(RegExp(r'\s'), '');

/// Accepts `sb_publishable_…` keys and legacy anon JWTs, nothing else. The
/// key ends up in every invite text, so a secret key must never pass.
KeyProblem? checkPublishableKey(String input) {
  final k = cleanKey(input);
  if (k.isEmpty) return KeyProblem.empty;
  if (k.startsWith('sb_secret_')) return KeyProblem.secret;
  if (k.startsWith('sb_publishable_')) {
    return k.length >= 'sb_publishable_'.length + 8 ? null : KeyProblem.unrecognized;
  }
  final parts = k.split('.');
  if (parts.length != 3) return KeyProblem.unrecognized;
  final role = _jwtRole(parts[1]);
  if (role == null) return KeyProblem.unrecognized;
  if (role == 'anon') return null;
  if (role == 'service_role') return KeyProblem.secret;
  return KeyProblem.wrongRole;
}

String? _jwtRole(String part) {
  try {
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))));
    final role = json is Map ? json['role'] : null;
    return role is String ? role : null;
  } catch (_) {
    return null;
  }
}

/// The collaboration settings this device keeps in the `cloud` document.
class CloudConfig {
  const CloudConfig({required this.url, required this.key, this.name = '', this.colorIndex = 0, this.profilePending = false});

  /// Normalised server origin.
  final String url;
  final String key;
  final String name;
  final int colorIndex;

  /// The name or colour changed while offline; sent on the next start.
  final bool profilePending;

  String get host => serverHost(url);

  CloudConfig copyWith({String? name, int? colorIndex, bool? profilePending}) => CloudConfig(
        url: url,
        key: key,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        profilePending: profilePending ?? this.profilePending,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'url': url,
        'key': key,
        'name': name,
        'colorIndex': colorIndex,
        if (profilePending) 'profilePending': true,
      };

  /// Null unless the stored address and key still pass the checks.
  static CloudConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = j['url'], key = j['key'];
    if (url is! String || key is! String) return null;
    final u = checkServerUrl(url);
    if (!u.isOk || checkPublishableKey(key) != null) return null;
    return CloudConfig(
      url: u.url!,
      key: cleanKey(key),
      name: (j['name'] as String?) ?? '',
      colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
      profilePending: j['profilePending'] == true,
    );
  }
}
