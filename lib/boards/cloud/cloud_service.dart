import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../boards_controller.dart';
import '../model/board_doc.dart';
import '../sync/backend.dart';
import 'cloud_api.dart';
import 'server_config.dart';
import 'supabase_cloud_api.dart';

/// The checks Bağlan runs, in order (docs/boards/DESIGN.md §7).
enum ConnectStep { reach, checkSetup, signIn, profile, done }

/// Owns the collaboration server: its configuration (KeyValueStore doc
/// `cloud`), the Supabase client and the anonymous identity.
///
/// Start-up never needs the network: a stored configuration with a saved
/// session is [ready] at once and sync catches up when it can.
class CloudService extends ChangeNotifier implements CloudSession {
  CloudService({
    required this.store,
    CloudApi? api,
    this.defaultUrl = const String.fromEnvironment('PAMNOT_SUPABASE_URL'),
    this.defaultKey = const String.fromEnvironment('PAMNOT_SUPABASE_KEY'),
  }) : api = api ?? SupabaseCloudApi() {
    this.api.onSignedOut = _sessionLost;
  }

  static const docKey = 'cloud';

  final KeyValueStore store;
  final CloudApi api;

  /// Build-time server (`--dart-define`), used until one is saved.
  final String defaultUrl;
  final String defaultKey;

  final ValueNotifier<bool> _ready = ValueNotifier(false);
  CloudConfig? _config;
  BoardBackend? _backend;
  BoardAccount? _account;
  bool _started = false;
  Future<void>? _busy;
  BoardsController? _boards;

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  BoardBackend? get backend => _ready.value ? _backend : null;

  @override
  BoardAccount? get account => _ready.value ? _account : null;

  /// The saved configuration (set once a connect succeeded), or null.
  CloudConfig? get config => _config;

  @override
  String get displayName => _config?.name ?? '';

  @override
  int get colorIndex => _config?.colorIndex ?? 0;

  /// Server set at build time with `--dart-define`; the wizard then skips
  /// steps 1–4.
  CloudConfig? get preset {
    final u = checkServerUrl(defaultUrl);
    if (!u.isOk || checkPublishableKey(defaultKey) != null) return null;
    return CloudConfig(url: u.url!, key: cleanKey(defaultKey));
  }

  /// The server this device uses or will use: the saved one, else the preset.
  CloudConfig? get server => _config ?? preset;

  /// `host[:port]` of [server].
  String? get host => server?.host;

  /// Loads the saved configuration and, if there is one, starts the client
  /// and restores the session. Safe to call more than once.
  Future<void> start() => _serial(() async {
        if (_started) return;
        _started = true;
        _config = await _load();
        final cfg = _config;
        if (cfg == null) {
          notifyListeners();
          return;
        }
        try {
          await api.start(cfg.url, cfg.key);
        } catch (e) {
          debugPrint('Collaboration client did not start: $e');
          notifyListeners();
          return;
        }
        final uid = api.userId;
        if (uid != null) {
          _becomeReady(cfg, uid);
          if (cfg.profilePending) unawaited(_sendProfile());
        } else {
          notifyListeners();
        }
      });

  /// Wires the boards to this service: their account, their connections, and
  /// a refresh whenever the session comes or goes.
  void attach(BoardsController boards, {required BoardConnectionFactory connections}) {
    _boards = boards;
    boards.currentAccount = () => account;
    boards.connectionFactory = connections;
    _ready.addListener(() => unawaited(boards.refreshConnections()));
  }

  /// Sets up (or re-joins) a server: validates, starts the client, checks the
  /// server, signs in anonymously and saves the profile, reporting each
  /// [ConnectStep]. Throws [CloudFailure]; nothing is saved unless it all
  /// works. A different server than the current one is only allowed after
  /// [disconnect].
  Future<void> connect({
    required String url,
    required String key,
    required String name,
    required int colorIndex,
    void Function(ConnectStep step)? onStep,
  }) =>
      _serial(() async {
        final u = checkServerUrl(url);
        if (!u.isOk) throw const CloudFailure(CloudProblem.unknown, 'url');
        if (checkPublishableKey(key) != null) throw const CloudFailure(CloudProblem.badKey);
        final next = CloudConfig(url: u.url!, key: cleanKey(key), name: name.trim(), colorIndex: colorIndex);
        final current = _config;
        if (current != null && current.host != next.host) {
          throw const CloudFailure(CloudProblem.otherServer);
        }
        _started = true;
        _setReady(false);
        try {
          await api.start(next.url, next.key);
          onStep?.call(ConnectStep.reach);
          await api.probe();
          onStep?.call(ConnectStep.checkSetup);
          final schema = await api.schemaVersion();
          if (schema < 1) throw const CloudFailure(CloudProblem.sqlOutdated);
          onStep?.call(ConnectStep.signIn);
          // A session saved for this server is kept: signing in again would
          // make this device a new member everywhere.
          final uid = api.userId ?? await api.signInAnonymously(next.name);
          onStep?.call(ConnectStep.profile);
          await api.saveProfile(next.name, next.colorIndex);
          _config = next;
          await _save();
          _becomeReady(next, uid);
          onStep?.call(ConnectStep.done);
        } catch (e) {
          // A stored server keeps its client (its session still syncs);
          // otherwise nothing is left half set up.
          final uid = current == null ? null : api.userId;
          if (current == null) {
            await api.stop(signOut: false);
          } else if (uid != null) {
            _becomeReady(current, uid);
          }
          throw cloudFailureOf(e);
        }
      });

  /// Changes how others see this device. Saved at once, sent when possible.
  Future<void> updateProfile({String? name, int? colorIndex}) async {
    final cfg = _config;
    if (cfg == null) return;
    _config = cfg.copyWith(name: name?.trim(), colorIndex: colorIndex, profilePending: true);
    notifyListeners();
    await _save();
    await _sendProfile();
  }

  Future<void> _sendProfile() async {
    final cfg = _config;
    if (cfg == null || !_ready.value) return;
    try {
      await api.saveProfile(cfg.name, cfg.colorIndex);
      if (identical(_config, cfg)) {
        _config = cfg.copyWith(profilePending: false);
        await _save();
      }
    } catch (e) {
      debugPrint('Profile not sent yet: $e');
    }
  }

  /// "Bu cihazın bağlantısını kaldır": closes every connection, removes this
  /// device's copies of the server's shared boards (the anonymous identity
  /// ends here, so they could never sync again), signs out and forgets the
  /// server. Device-only boards stay.
  Future<void> disconnect() => _serial(() async {
        final acc = account;
        final boards = _boards;
        // Listed while still signed in: the list shows this account's boards.
        final shared = [if (boards != null && acc != null) for (final b in boards.boards) if (b.account == acc) b.id];
        _setReady(false);
        if (boards != null) {
          await boards.refreshConnections();
          for (final id in shared) {
            await boards.removeLocal(id);
          }
        }
        await api.stop(signOut: true);
        _config = null;
        _account = null;
        _backend = null;
        await store.delete(docKey);
        notifyListeners();
      });

  void _sessionLost() {
    if (!_ready.value) return;
    debugPrint('Collaboration session ended');
    _setReady(false);
  }

  void _becomeReady(CloudConfig cfg, String uid) {
    _account = BoardAccount(host: cfg.host, userId: uid);
    _backend = api.backend(cfg.host);
    _setReady(true);
    notifyListeners();
  }

  void _setReady(bool v) {
    if (_ready.value == v) return;
    _ready.value = v;
    notifyListeners();
  }

  Future<CloudConfig?> _load() async {
    try {
      final raw = await store.read(docKey);
      return raw == null ? null : CloudConfig.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('cloud config unreadable: $e');
      return null;
    }
  }

  Future<void> _save() async {
    final cfg = _config;
    if (cfg == null) return;
    await store.write(docKey, jsonEncode(cfg.toJson()));
  }

  /// One configuration change at a time.
  Future<T> _serial<T>(Future<T> Function() f) async {
    while (_busy != null) {
      try {
        await _busy;
      } catch (_) {}
    }
    final c = Completer<void>();
    _busy = c.future;
    try {
      return await f();
    } finally {
      _busy = null;
      c.complete();
    }
  }

  @override
  void dispose() {
    _ready.dispose();
    super.dispose();
  }
}
