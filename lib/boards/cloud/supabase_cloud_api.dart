import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/backend.dart';
import '../sync/supabase_backend.dart';
import 'cloud_api.dart';

/// [CloudApi] on supabase_flutter. `Supabase.instance` is touched only
/// between [start] and [stop]; a server change goes through [stop] first,
/// because `Supabase.initialize` ignores a second call.
class SupabaseCloudApi implements CloudApi {
  SupabaseCloudApi({http.Client? httpClient, this.timeout = const Duration(seconds: 15)}) : _http = httpClient;

  final http.Client? _http;
  final Duration timeout;

  String? _url;
  String? _key;
  bool _started = false;
  StreamSubscription<AuthState>? _auth;
  void Function()? _onSignedOut;
  bool _stopping = false;

  SupabaseClient get _client {
    assert(_started, 'SupabaseCloudApi used before start()');
    return Supabase.instance.client;
  }

  @override
  set onSignedOut(void Function()? callback) => _onSignedOut = callback;

  @override
  Future<void> start(String url, String key) async {
    if (_started) {
      await stop(signOut: false);
    } else if (Supabase.instance.isInitialized) {
      // Left over from a start that failed half way: initialize() would
      // silently keep it.
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
    }
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        httpClient: _http,
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        realtimeLifecycleOptions: const RealtimeLifecycleOptions(disconnectAfterPause: Duration(seconds: 30)),
        postgrestOptions: PostgrestClientOptions(requestTimeout: timeout),
      );
    } catch (e) {
      throw CloudFailure(CloudProblem.unknown, e);
    }
    _url = url;
    _key = key;
    _started = true;
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut && !_stopping) _onSignedOut?.call();
    }, onError: (Object _) {});
  }

  @override
  Future<void> stop({required bool signOut}) async {
    if (!_started) return;
    _stopping = true;
    try {
      final c = Supabase.instance.client;
      await _auth?.cancel();
      _auth = null;
      try {
        await c.removeAllChannels();
      } catch (_) {}
      if (signOut) {
        try {
          // Clears the local session first, then revokes it on the server
          // (which may fail offline; the session is gone here either way).
          await c.auth.signOut();
        } catch (e) {
          debugPrint('Sign-out on the server failed: $e');
        }
      }
      await Supabase.instance.dispose();
    } finally {
      _started = false;
      _stopping = false;
      _url = null;
      _key = null;
    }
  }

  @override
  String? get userId => _started ? _client.auth.currentUser?.id : null;

  @override
  Future<void> probe() async {
    final url = _url, key = _key;
    if (url == null || key == null) throw const CloudFailure(CloudProblem.unknown);
    final http.Response res;
    try {
      final uri = Uri.parse('$url/auth/v1/settings');
      final headers = {'apikey': key};
      res = await (_http?.get(uri, headers: headers) ?? http.get(uri, headers: headers)).timeout(timeout);
    } catch (e) {
      throw CloudFailure(CloudProblem.unreachable, e);
    }
    final problem = probeProblem(res.statusCode, res.body);
    if (problem != null) throw CloudFailure(problem, 'HTTP ${res.statusCode}');
  }

  @override
  Future<int> schemaVersion() async {
    try {
      final r = await _client.rpc('pamnot_info').timeout(timeout);
      final v = r is Map ? r['schema'] : null;
      if (v is num) return v.toInt();
      throw const CloudFailure(CloudProblem.sqlOutdated);
    } catch (e) {
      throw cloudFailureOf(e);
    }
  }

  @override
  Future<String> signInAnonymously(String name) async {
    try {
      final r = await _client.auth.signInAnonymously(data: {'display_name': name}).timeout(timeout);
      final id = r.user?.id ?? _client.auth.currentUser?.id;
      if (id == null) throw const CloudFailure(CloudProblem.unknown, 'no user');
      return id;
    } catch (e) {
      throw cloudFailureOf(e);
    }
  }

  @override
  Future<void> saveProfile(String name, int colorIndex) async {
    final id = userId;
    if (id == null) throw const CloudFailure(CloudProblem.unknown, 'signed out');
    try {
      await _client
          .from('profiles')
          .upsert({'id': id, 'display_name': name, 'color_index': colorIndex})
          .timeout(timeout);
    } catch (e) {
      throw cloudFailureOf(e);
    }
  }

  @override
  BoardBackend backend(String host) => SupabaseBoardBackend(_client, host: host);
}

/// What the `/auth/v1/settings` answer says about the setup, or null if fine.
CloudProblem? probeProblem(int status, String body) {
  if (status == 401 || status == 403) return CloudProblem.badKey;
  if (status == 429) return CloudProblem.rateLimited;
  if (status < 200 || status >= 300) return CloudProblem.unreachable;
  try {
    final j = jsonDecode(body);
    final external = j is Map ? j['external'] : null;
    // Present on current servers; a missing field is not a verdict.
    if (external is Map && external['anonymous_users'] == false) return CloudProblem.anonymousDisabled;
    if (j is Map && j['disable_signup'] == true) return CloudProblem.signupsDisabled;
  } catch (_) {
    return CloudProblem.unreachable;
  }
  return null;
}

/// Maps Supabase errors to the wizard's vocabulary.
CloudFailure cloudFailureOf(Object e) {
  if (e is CloudFailure) return e;
  if (e is AuthRetryableFetchException) return CloudFailure(CloudProblem.unreachable, e);
  if (e is AuthException) {
    final code = e.code;
    if (code == 'anonymous_provider_disabled') return CloudFailure(CloudProblem.anonymousDisabled, e);
    if (code == 'signup_disabled') return CloudFailure(CloudProblem.signupsDisabled, e);
    if (code == 'over_request_rate_limit' || e.statusCode == '429') return CloudFailure(CloudProblem.rateLimited, e);
    if (e.statusCode == '401' || e.statusCode == '403') return CloudFailure(CloudProblem.badKey, e);
    // Servers from before error codes say it in words.
    if (e.message.toLowerCase().contains('anonymous sign-ins are disabled')) {
      return CloudFailure(CloudProblem.anonymousDisabled, e);
    }
    return CloudFailure(CloudProblem.unknown, e);
  }
  if (e is PostgrestException) {
    final code = e.code ?? '';
    // Function or table not in the schema cache: the SQL was not run.
    if (code == 'PGRST202' || code == 'PGRST205' || code == '42883' || code == '42P01') {
      return CloudFailure(CloudProblem.sqlMissing, e);
    }
    if (e.hint == 'rate_limited' || code == '429') return CloudFailure(CloudProblem.rateLimited, e);
    if (code == '401' || code == '403' || e.message.contains('Invalid API key')) {
      return CloudFailure(CloudProblem.badKey, e);
    }
    if (code.startsWith('5')) return CloudFailure(CloudProblem.unreachable, e);
    return CloudFailure(CloudProblem.unknown, e);
  }
  // SocketException, http ClientException, TimeoutException, TLS errors.
  return CloudFailure(CloudProblem.unreachable, e);
}
