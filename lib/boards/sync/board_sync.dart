import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;

import '../boards_controller.dart';
import '../connection.dart';
import '../model/board_doc.dart';
import '../model/board_item.dart';
import 'backend.dart';

/// Where the data channel is in its connect cycle (DESIGN.md §5).
enum SyncPhase { offline, joining, catchingUp, live }

/// True while the app is in the foreground. Follows [AppLifecycleListener];
/// tests pass a plain `ValueNotifier<bool>` to [BoardSync] instead.
class AppForeground extends ValueNotifier<bool> {
  AppForeground() : super(_resumed(WidgetsBinding.instance.lifecycleState)) {
    _listener = AppLifecycleListener(onStateChange: (s) => value = _resumed(s));
  }

  late final AppLifecycleListener _listener;

  static bool _resumed(AppLifecycleState? s) => s == null || s == AppLifecycleState.resumed;

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }
}

/// Live sync of one open shared board (DESIGN.md §3 and §5).
///
/// - Data: subscribe first, then a single-flight catch-up (with a rerun
///   flag) on every `subscribed`, every postgres_changes `ok`, app resume, a
///   rev gap and a 60 s foreground poll. The only cursor is the board's
///   gap-free `rev`; realtime rows move it only when they are the next one.
///   Every row is merged as it arrives: the per-field merge is idempotent,
///   so there is no buffering and no echo filtering.
/// - Push: the dirty fields in the document are the outbox. Debounced,
///   single flight, acknowledged field by field.
/// - Presence and cursors on a second channel, so recreating the data
///   channel never makes avatars flicker.
class BoardSync implements BoardConnection {
  BoardSync({
    required this.board,
    required this.controller,
    required this.backend,
    required this.session,
    ValueListenable<bool>? foreground,
    math.Random? random,
    DateTime Function()? now,
  })  : _random = random ?? math.Random(),
        _now = now ?? DateTime.now {
    final own = foreground == null ? AppForeground() : null;
    _ownForeground = own;
    _foreground = foreground ?? own!;
    _wasForeground = _foreground.value;
    _foreground.addListener(_onForeground);
    unawaited(_start());
  }

  final OpenBoard board;
  final BoardsController controller;
  final BoardBackend backend;
  final CloudSession session;
  final math.Random _random;
  final DateTime Function() _now;
  late final ValueListenable<bool> _foreground;
  AppForeground? _ownForeground;

  static const pushDebounce = Duration(milliseconds: 300);
  static const pushMaxDelay = Duration(seconds: 2);
  static const pollInterval = Duration(seconds: 60);
  static const gapDebounce = Duration(seconds: 1);
  static const watchdog = Duration(seconds: 15);
  static const maxChannelBackoff = Duration(seconds: 30);
  static const maxRetryBackoff = Duration(seconds: 60);
  static const cursorInterval = Duration(milliseconds: 125); // ≤ 8 Hz
  static const cursorMinMove = 2.0; // canvas units
  static const cursorFade = Duration(seconds: 10);
  static const closeTimeout = Duration(seconds: 5);
  static const pageSize = 500;

  final _state = ValueNotifier(const SyncState(SyncStatus.offline));
  final _peers = ValueNotifier<List<Peer>>(const []);
  final _cursors = ValueNotifier<Map<String, PeerCursor>>(const {});

  @override
  ValueListenable<SyncState> get state => _state;

  @override
  ValueListenable<List<Peer>> get peers => _peers;

  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => _cursors;

  SyncPhase _phase = SyncPhase.offline;

  @visibleForTesting
  SyncPhase get phase => _phase;

  /// Read through every time: an upload can re-mint the board id.
  BoardDoc get _doc => board.editor.doc;
  String get _node => board.editor.clock.node;

  /// The board exists on the server; channels, pulls and pushes may run.
  bool _ready = false;
  bool _closing = false;
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Deleted or revoked: syncing has stopped for good.
  BoardState? _ended;

  bool _netDown = false;
  bool _channelDown = false;
  bool _wasForeground = true;

  /// Unexpected failures by operation ('create', 'push', 'pull'); each is
  /// cleared by its own next success, so one working path does not hide
  /// another failing one.
  final Map<String, String> _errors = {};

  Timer? _poll;

  // ------------------------------------------------------------- start

  Future<void> _start() async {
    final doc = _doc;
    if (doc.readOnly) {
      _ended = doc.state;
      _publish();
      return;
    }
    if (!doc.isShared || doc.account == null || doc.account != session.account) {
      // Not this session's board: stay off the network.
      _channelDown = true;
      _publish();
      return;
    }
    _publish();
    unawaited(_measureClock());
    if (doc.state == BoardState.uploading && !await _createOnServer()) return;
    if (_closing || _ended != null) return;
    _ready = true;
    // Subscribe first, so nothing committed during the first pull is missed.
    _data.start();
    _live.start();
    _requestCatchUp();
    _poll = Timer.periodic(pollInterval, (_) {
      if (_foreground.value) _requestCatchUp();
    });
    _pushSoon(immediate: true);
  }

  /// `offset = s - (t0 + t1) / 2`, stored by the controller for every tick.
  Future<void> _measureClock() async {
    try {
      final t0 = _now().millisecondsSinceEpoch;
      final s = await backend.serverTimeMs();
      final t1 = _now().millisecondsSinceEpoch;
      // A very slow round trip says little about the offset.
      if (_closed || t1 - t0 > 5000) return;
      controller.clockOffsetMs = s - (t0 + t1) ~/ 2;
    } catch (_) {
      // Keep the stored offset.
    }
  }

  /// Registers a device-only board before anything is pushed. When the id
  /// already belongs to someone else, the board gets a new id here.
  Future<bool> _createOnServer() async {
    var attempt = 0;
    while (!_closing && _ended == null) {
      try {
        await backend.createBoard(_doc.id);
        if (_closing) return false;
        _netDown = false;
        _errors.remove('create');
        return true;
      } on BoardIdTaken {
        if (_closing) return false;
        final old = _doc.id;
        if (await controller.remint(old) == old) {
          _fail('create', 'board id could not be re-minted');
          await _sleep(_backoff(attempt++, maxRetryBackoff));
        }
      } on BackendUnavailable {
        _netDown = true;
        _publish();
        await _sleep(_backoff(attempt++, maxRetryBackoff));
      } catch (e) {
        _fail('create', e);
        await _sleep(_backoff(attempt++, maxRetryBackoff));
      }
    }
    return false;
  }

  Completer<void>? _wake;
  Timer? _sleepTimer;

  /// A wait that [retry], resume and [close] cut short.
  Future<void> _sleep(Duration d) {
    final c = _wake = Completer<void>();
    _sleepTimer = Timer(d, _wakeUp);
    return c.future;
  }

  void _wakeUp() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final c = _wake;
    _wake = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  // ------------------------------------------------------- data channel

  late final _data = _Keeper(open: _openData, backoff: (n) => _backoff(n, maxChannelBackoff), active: _wasForeground);

  Future<void> Function() _openData(int gen) {
    _phase = SyncPhase.joining;
    final link = backend.subscribe(
      _doc.id,
      RealtimeHandlers(
        onStatus: (s, e) => _onDataStatus(gen, s, e),
        onSystem: (e) => _onSystem(gen, e),
        onRow: (r) => _onRow(gen, r),
      ),
    );
    return link.close;
  }

  bool _isCurrent(_Keeper k, int gen) => k.current(gen) && !_closing && _ended == null;

  void _onDataStatus(int gen, SubscribeStatus status, Object? error) {
    if (!_isCurrent(_data, gen)) return;
    if (status == SubscribeStatus.subscribed) {
      // Repeats too: after a resume the client rejoins and reports
      // `subscribed` again without any error before it.
      _data.up(gen);
      _channelDown = false;
      _phase = SyncPhase.catchingUp;
      _requestCatchUp();
      // The network is back: do not wait out a push backoff.
      _pushSoon(immediate: _retryTimer != null);
      _publish();
      return;
    }
    _data.down(gen);
    _channelDown = true;
    _phase = SyncPhase.offline;
    _publish();
    // A removed member's channel fails authorization; the status check in
    // the catch-up tells that apart from an expired token.
    if ('$error'.toLowerCase().contains('unauthorized')) _requestCatchUp();
  }

  void _onSystem(int gen, Map<String, Object?> event) {
    if (!_isCurrent(_data, gen) || event['extension'] != 'postgres_changes') return;
    switch (event['status']) {
      case 'ok':
        // Replication is live only now; anything committed before it was
        // not delivered.
        _requestCatchUp();
      case 'error':
        _onDataStatus(gen, SubscribeStatus.channelError, event['message']);
    }
  }

  int _gapRev = 0;
  Timer? _gapTimer;

  void _onRow(int gen, RemoteRow? row) {
    if (!_isCurrent(_data, gen)) return;
    final rev = row?.rev;
    if (row == null || rev == null) {
      // Truncated or incomplete record: never merge it, read the row.
      _requestCatchUp();
      return;
    }
    final doc = _doc;
    if (_merge([row])) {
      _requestCatchUp();
      return;
    }
    if (rev == doc.cursor + 1) {
      doc.cursor = rev;
      controller.repo.saveBoard(doc);
    } else if (rev > doc.cursor + 1) {
      _gapRev = math.max(_gapRev, rev);
      _gapTimer ??= Timer(gapDebounce, () {
        _gapTimer = null;
        if (_doc.cursor < _gapRev) _requestCatchUp();
      });
    }
  }

  /// Merges through the editor (one notification and one save), skipping it
  /// when nothing would change: echoes of this device's own pushes are the
  /// common case and must stay cheap. Returns whether a field was newer but
  /// missing from the row.
  bool _merge(List<RemoteRow> rows) {
    if (!rows.any(_wouldChange)) return false;
    final r = board.editor.applyRemote(rows);
    _loadRestoredInk(r.changed);
    return r.incomplete;
  }

  /// Strokes of deleted ink stay on disk when a board opens. When a
  /// teammate restores such an item, its strokes come from the blob: the
  /// server's HLC equals ours, so no merge brings them.
  void _loadRestoredInk(Iterable<String> changed) {
    final ids = [
      for (final id in changed)
        if (_doc.items[id] case final it?
            when it.kind == ItemKind.ink && it.live && it.f[F.strokes] == null && it.h.containsKey(F.strokes))
          id,
    ];
    if (ids.isEmpty) return;
    unawaited(controller.repo.loadInk(ids).then((ink) {
      if (_closed) return;
      board.editor.attachStrokes({
        for (final e in ink.entries)
          if (_doc.items[e.key]?.f[F.strokes] == null) e.key: e.value,
      });
    }));
  }

  bool _wouldChange(RemoteRow r) {
    final it = _doc.items[r.id];
    if (it == null) return true;
    for (final e in r.fh.entries) {
      final lh = it.h[e.key];
      if (lh == null) return true;
      final c = e.value.compareTo(lh);
      if (c > 0 || (c == 0 && it.d.contains(e.key))) return true;
    }
    return false;
  }

  // ----------------------------------------------------------- catch-up

  bool _catching = false;
  bool _again = false;
  int _catchAttempt = 0;
  Timer? _catchRetry;

  void _requestCatchUp() {
    if (!_ready || _closing || _ended != null) return;
    if (_catching) {
      _again = true;
      return;
    }
    unawaited(_catchUp());
  }

  Future<void> _catchUp() async {
    _catching = true;
    _catchRetry?.cancel();
    _catchRetry = null;
    try {
      do {
        _again = false;
        _gapTimer?.cancel();
        _gapTimer = null;
        final status = await backend.boardStatus(_doc.id);
        if (_closed || _ended != null) return;
        if (status == null) {
          _end(BoardState.revoked);
          return;
        }
        if (status.deletedAt != null) {
          _end(BoardState.deleted);
          return;
        }
        while (true) {
          final doc = _doc;
          final rows = await backend.pullItems(doc.id, afterRev: doc.cursor, limit: pageSize);
          if (_closed || _ended != null) return;
          if (rows.isNotEmpty) {
            _merge(rows);
            final last = rows.last.rev ?? doc.cursor;
            if (last > doc.cursor) {
              doc.cursor = last;
              controller.repo.saveBoard(doc);
            }
          }
          if (rows.length < pageSize) break;
        }
      } while (_again && !_closing);
      _catchAttempt = 0;
      _netDown = false;
      _errors.remove('pull');
      if (_data.isUp) _phase = SyncPhase.live;
      _publish();
      // Fields that could not go out earlier (strokes still loading, a
      // failed push) get another chance.
      _pushSoon();
    } on AccessDenied {
      _end(BoardState.revoked);
    } on BackendUnavailable {
      _netDown = true;
      _retryCatchUpLater();
    } catch (e) {
      _fail('pull', e);
      _retryCatchUpLater();
    } finally {
      _catching = false;
    }
  }

  void _retryCatchUpLater() {
    if (_closing || _ended != null) return;
    _publish();
    _catchRetry?.cancel();
    _catchRetry = Timer(_backoff(_catchAttempt++, maxRetryBackoff), () {
      _catchRetry = null;
      _requestCatchUp();
    });
  }

  // --------------------------------------------------------------- push

  bool _pushing = false;
  bool _pushAgain = false;
  Future<void>? _pushDone;
  int _pushAttempt = 0;
  Timer? _debounce;
  Timer? _maxWait;
  Timer? _retryTimer;

  @override
  void kick() {
    if (_closing || _ended != null) return;
    _pushSoon();
    if (_state.value.status == SyncStatus.synced) _publish();
  }

  /// 300 ms after the last edit, at most 2 s after the first one. While a
  /// backoff runs, edits wait for it.
  void _pushSoon({bool immediate = false}) {
    if (!_ready || _closing || _ended != null) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    if (immediate) {
      _firePush();
      return;
    }
    if (_retryTimer != null) return;
    _debounce?.cancel();
    _debounce = Timer(pushDebounce, _firePush);
    _maxWait ??= Timer(pushMaxDelay, _firePush);
  }

  void _firePush() {
    _cancelPushTimers();
    unawaited(_push());
  }

  void _cancelPushTimers() {
    _debounce?.cancel();
    _maxWait?.cancel();
    _retryTimer?.cancel();
    _debounce = _maxWait = _retryTimer = null;
  }

  Future<void> _push() async {
    if (!_ready || _closed || _ended != null) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    _pushAgain = false;
    final done = Completer<void>();
    _pushDone = done.future;
    try {
      while (!_closed && _ended == null) {
        final doc = _doc;
        final sent = <String, Map<String, String>>{};
        final rows = doc.dirtyRows(sent);
        if (rows.isEmpty) break;
        _publish();
        final res = await backend.pushItems(doc.id, rows);
        if (_closed || _ended != null) return;
        _netDown = false;
        _errors.remove('push');
        _pushAttempt = 0;
        switch (res.status) {
          case PushStatus.boardDeleted:
            _end(BoardState.deleted);
            return;
          case PushStatus.forbidden:
            _end(BoardState.revoked);
            return;
          case PushStatus.ok:
            // Received HLCs move the clock too: an edit right after taking
            // a newer server value must sort after it.
            final clock = board.editor.clock;
            for (final a in res.acks) {
              a.fh.values.forEach(clock.observe);
            }
            _loadRestoredInk(board.editor.applyAcks(sent, res.acks));
            if (doc.state == BoardState.uploading) {
              doc.state = BoardState.shared;
              controller.stateChanged(doc);
            }
        }
        // Edits made during the flight are still dirty and go next round;
        // a batch the server took nothing from is not retried in a loop.
        if (!_progress(sent)) break;
      }
    } on AccessDenied {
      _end(BoardState.revoked);
    } on BackendUnavailable {
      _netDown = true;
      _retryPushLater();
    } catch (e) {
      _fail('push', e);
      _retryPushLater();
    } finally {
      _pushing = false;
      done.complete();
      if (!_closed) {
        _publish();
        if (_pushAgain) {
          _pushAgain = false;
          _pushSoon();
        }
      }
    }
  }

  /// True when the server settled at least one sent field, or one was
  /// edited again during the flight.
  bool _progress(Map<String, Map<String, String>> sent) {
    for (final e in sent.entries) {
      final it = _doc.items[e.key];
      if (it == null) return true;
      for (final f in e.value.entries) {
        if (!it.d.contains(f.key) || it.h[f.key] != f.value) return true;
      }
    }
    return false;
  }

  void _retryPushLater() {
    if (_closing || _ended != null) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff(_pushAttempt++, maxRetryBackoff), () {
      _retryTimer = null;
      unawaited(_push());
    });
  }

  // ----------------------------------------------------- state and end

  void _fail(String op, Object e) {
    debugPrint('Board sync ($op): $e');
    _errors[op] = '$e';
    _publish();
  }

  /// Deleted for everyone or access lost: read-only from here on, nothing
  /// left to push.
  void _end(BoardState state) {
    if (_ended != null || _closed) return;
    _ended = state;
    final doc = _doc;
    doc.state = state;
    doc.clearDirty();
    controller.stateChanged(doc);
    _phase = SyncPhase.offline;
    _cancelTimers();
    unawaited(_data.stop());
    unawaited(_live.stop());
    _liveLink = null;
    _setPeers(const []);
    _publish();
  }

  void _publish() {
    if (_closed) return;
    final ended = _ended;
    if (ended != null) {
      _state.value = SyncState(ended == BoardState.deleted ? SyncStatus.deleted : SyncStatus.revoked);
      return;
    }
    final pending = _doc.pendingCount;
    final error = _errors.values.firstOrNull;
    _state.value = error != null
        ? SyncState(SyncStatus.error, pending: pending, message: error)
        : _netDown || _channelDown
            ? SyncState(SyncStatus.offline, pending: pending)
            : pending > 0
                ? SyncState(SyncStatus.sending, pending: pending)
                : const SyncState(SyncStatus.synced);
  }

  Duration _backoff(int attempt, Duration cap) {
    final ms = math.min(cap.inMilliseconds, 1000 << math.min(attempt, 16));
    return Duration(milliseconds: ms + _random.nextInt(math.max(1, ms ~/ 5)));
  }

  void _cancelTimers() {
    _cancelPushTimers();
    for (final t in [_poll, _gapTimer, _catchRetry, _cursorGate, _sweep]) {
      t?.cancel();
    }
    _poll = _gapTimer = _catchRetry = _cursorGate = _sweep = null;
    _wakeUp();
  }

  // ---------------------------------------------------------- lifecycle

  void _onForeground() {
    final fg = _foreground.value;
    if (fg == _wasForeground || _closing) return;
    _wasForeground = fg;
    if (_ended != null) return;
    _data.setActive(fg);
    _live.setActive(fg);
    _wakeUp();
    if (fg) {
      _requestCatchUp();
    } else {
      _stopCursor();
    }
    // Going away: the OS may suspend or kill the app, send what is dirty
    // now. Coming back: send what piled up.
    _pushSoon(immediate: true);
  }

  @override
  Future<void> retry() async {
    if (_closing || _ended != null) return;
    _errors.clear();
    _pushAttempt = 0;
    _catchAttempt = 0;
    _wakeUp();
    _data.retryNow();
    _live.retryNow();
    _requestCatchUp();
    _pushSoon(immediate: true);
    _publish();
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    _foreground.removeListener(_onForeground);
    _ownForeground?.dispose();
    _ownForeground = null;
    _cancelTimers();
    final channels = Future.wait([_data.stop(), _live.stop()]);
    _liveLink = null;
    // Known to be offline: no point waiting. Whatever does not go out stays
    // dirty in the document for next time.
    if (_ready && _ended == null && !_netDown) {
      try {
        await _flushPush().timeout(closeTimeout);
      } catch (_) {}
    }
    try {
      await channels.timeout(closeTimeout);
    } catch (_) {}
    // From here on late results are dropped: the document may already be
    // open again in a new editor.
    _closed = true;
    _state.dispose();
    _peers.dispose();
    _cursors.dispose();
  }

  Future<void> _flushPush() async {
    while (_pushing && _pushDone != null) {
      await _pushDone;
    }
    await _push();
  }

  // ------------------------------------------------- presence & cursors

  late final _live = _Keeper(open: _openLive, backoff: (n) => _backoff(n, maxChannelBackoff), active: _wasForeground);
  LiveLink? _liveLink;
  Map<String, Peer> _peerByKey = const {};
  String _view = 'canvas';
  String? _editing;

  Future<void> Function() _openLive(int gen) {
    final link = backend.joinLive(
      _doc.id,
      LiveHandlers(
        onPresence: (p) => _onPresence(gen, p),
        onCursor: (p) => _onCursor(gen, p),
        onStatus: (s, e) => _onLiveStatus(gen, s, e),
        presenceKey: _node,
      ),
    );
    _liveLink = link;
    _track();
    return () {
      if (identical(_liveLink, link)) {
        _liveLink = null;
        // Whoever is here shows up again once the new channel joins.
        _setPeers(const []);
      }
      return link.close();
    };
  }

  void _onLiveStatus(int gen, SubscribeStatus status, Object? error) {
    if (!_isCurrent(_live, gen)) return;
    if (status == SubscribeStatus.subscribed) {
      _live.up(gen);
      // Presence lives with the socket connection; a rejoin starts empty.
      _track();
    } else {
      _live.down(gen);
      _setPeers(const []);
    }
  }

  void _track() {
    final link = _liveLink;
    if (link == null || _closing || _ended != null) return;
    link.track({
      'key': _node,
      'userId': session.account?.userId ?? backend.userId ?? '',
      'name': session.displayName,
      'colorIndex': session.colorIndex,
      'view': _view,
      'editing': _editing,
    });
  }

  @override
  void setActivity({required String view, String? editing}) {
    if (view == _view && editing == _editing) return;
    _view = view;
    _editing = editing;
    _track();
  }

  void _onPresence(int gen, List<Map<String, Object?>> presences) {
    if (!_isCurrent(_live, gen)) return;
    final byKey = <String, Peer>{};
    for (final p in presences) {
      final key = p['key'];
      // Keyed by HLC node, so the same user on two devices is two peers.
      if (key is! String || key == _node) continue;
      final userId = p['userId'], name = p['name'], color = p['colorIndex'], editing = p['editing'];
      byKey[key] = Peer(
        key: key,
        userId: userId is String ? userId : '',
        name: name is String ? name : '',
        colorIndex: color is num ? color.toInt() : 0,
        view: p['view'] == 'kanban' ? 'kanban' : 'canvas',
        editing: editing is String ? editing : null,
      );
    }
    final list = byKey.values.toList()
      ..sort((a, b) {
        final c = a.name.compareTo(b.name);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    _setPeers(list);
  }

  void _setPeers(List<Peer> peers) {
    if (_closed) return;
    _peerByKey = {for (final p in peers) p.key: p};
    if (peers.isEmpty && _peers.value.isEmpty) return;
    _peers.value = List.unmodifiable(peers);
    // A newcomer has not seen this device's pointer yet.
    if (peers.isEmpty) _lastCursor = null;
    final c = _cursors.value;
    if (c.keys.any((k) => !_peerByKey.containsKey(k))) {
      _cursors.value = {for (final e in c.entries) if (_peerByKey.containsKey(e.key)) e.key: e.value};
    }
  }

  Offset? _lastCursor;
  (Offset, bool)? _cursorPending;
  Timer? _cursorGate;

  bool get _cursorAllowed =>
      !_closing && _ended == null && _liveLink != null && _foreground.value && _peerByKey.isNotEmpty;

  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) {
    if (!_cursorAllowed) return;
    if (canvasPosition == null) {
      _stopCursor();
      return;
    }
    if (!canvasPosition.isFinite) return;
    _cursorPending = (canvasPosition, pointer);
    if (_cursorGate == null) _sendPendingCursor();
  }

  void _sendPendingCursor() {
    final pending = _cursorPending;
    _cursorPending = null;
    final link = _liveLink;
    if (pending == null || link == null) return;
    final (p, pointer) = pending;
    final last = _lastCursor;
    if (last != null && (p - last).distance < cursorMinMove) return;
    _lastCursor = p;
    link.sendCursor({'key': _node, 'x': p.dx, 'y': p.dy, if (!pointer) 'p': false});
    // Trailing send: the last position of a quick move still goes out.
    _cursorGate = Timer(cursorInterval, () {
      _cursorGate = null;
      if (_cursorAllowed) _sendPendingCursor();
    });
  }

  /// The pointer left the canvas or the app went to the background.
  void _stopCursor() {
    _cursorPending = null;
    _cursorGate?.cancel();
    _cursorGate = null;
    if (_lastCursor == null) return;
    _lastCursor = null;
    _liveLink?.sendCursor({'key': _node, 'gone': true});
  }

  Timer? _sweep;

  void _onCursor(int gen, Map<String, Object?> p) {
    if (!_isCurrent(_live, gen)) return;
    final key = p['key'];
    if (key is! String || key == _node) return;
    if (p['gone'] == true) {
      if (_cursors.value.containsKey(key)) _cursors.value = {..._cursors.value}..remove(key);
      return;
    }
    final peer = _peerByKey[key];
    final x = p['x'], y = p['y'];
    if (peer == null || x is! num || y is! num) return;
    final pos = Offset(x.toDouble(), y.toDouble());
    if (!pos.isFinite) return;
    _cursors.value = {
      ..._cursors.value,
      key: PeerCursor(
        key: key,
        name: peer.name,
        colorIndex: peer.colorIndex,
        position: pos,
        at: _now(),
        pointer: p['p'] != false,
      ),
    };
    _sweep ??= Timer(cursorFade, _sweepCursors);
  }

  /// Cursors fade out on the canvas from [PeerCursor.at]; after
  /// [cursorFade] they leave the map.
  void _sweepCursors() {
    _sweep = null;
    if (_closed) return;
    final now = _now();
    final c = _cursors.value;
    final keep = {for (final e in c.entries) if (now.difference(e.value.at) < cursorFade) e.key: e.value};
    if (keep.length != c.length) _cursors.value = keep;
    if (keep.isEmpty) return;
    final oldest = keep.values.map((v) => v.at).reduce((a, b) => a.isBefore(b) ? a : b);
    _sweep = Timer(cursorFade - now.difference(oldest) + const Duration(milliseconds: 1), _sweepCursors);
  }
}

/// Keeps one realtime channel open (DESIGN.md §5 step 5). After it goes
/// down, a 15 s watchdog; if it has not come back by then, remove it and
/// open a new one after a backoff of 1…30 s plus jitter. Callbacks carry
/// the generation they were opened with, so a removed channel changes
/// nothing. While the app is in the background it is left alone: the
/// client disconnects on purpose then, and rejoins on resume.
class _Keeper {
  _Keeper({required this.open, required this.backoff, required this.active});

  /// Opens a channel tagged with [gen] and returns how to remove it.
  final Future<void> Function() Function(int gen) open;
  final Duration Function(int attempt) backoff;
  bool active;

  int _gen = 0;
  bool _up = false;
  bool _started = false;
  bool _stopped = false;
  bool _reopening = false;
  int _attempt = 0;
  Future<void> Function()? _close;
  Timer? _watchdog;
  Timer? _reopen;

  bool get isUp => _up;

  bool current(int gen) => gen == _gen && !_stopped;

  void start() {
    if (_stopped || _started) return;
    _started = true;
    if (active) _openNow();
  }

  void _openNow() {
    _up = false;
    _close = open(++_gen);
    // Also covers a channel that never reports anything.
    _arm();
  }

  void up(int gen) {
    if (!current(gen)) return;
    _up = true;
    _attempt = 0;
    _watchdog?.cancel();
    _watchdog = null;
  }

  void down(int gen) {
    if (!current(gen)) return;
    _up = false;
    _arm();
  }

  /// Only the first failure starts the watchdog: a channel erroring every
  /// few seconds must not keep postponing it.
  void _arm() {
    if (!active || _stopped || _up || _reopening || _watchdog != null) return;
    _watchdog = Timer(BoardSync.watchdog, () {
      _watchdog = null;
      if (!_up) unawaited(_recreate(backoff(_attempt++)));
    });
  }

  Future<void> _recreate(Duration delay) async {
    if (_stopped || _reopening) return;
    _reopening = true;
    _watchdog?.cancel();
    _watchdog = null;
    final close = _close;
    _close = null;
    _gen++;
    try {
      await close?.call();
    } catch (_) {}
    if (_stopped) return;
    _reopen = Timer(delay, () {
      _reopen = null;
      _reopening = false;
      if (!_stopped && active) _openNow();
    });
  }

  void setActive(bool value) {
    active = value;
    if (_stopped || !_started) return;
    if (!value) {
      _watchdog?.cancel();
      _watchdog = null;
      if (_reopen != null) {
        _reopen!.cancel();
        _reopen = null;
        _reopening = false;
      }
    } else if (_close == null && !_reopening) {
      _openNow();
    } else {
      _arm();
    }
  }

  /// The user tapped retry: replace a channel that is down right away.
  void retryNow() {
    if (_stopped || !_started || _up) return;
    _attempt = 0;
    if (_reopen != null) {
      _reopen!.cancel();
      _reopen = null;
      _reopening = false;
      if (active) _openNow();
    } else if (_close != null && !_reopening) {
      unawaited(_recreate(Duration.zero));
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _watchdog?.cancel();
    _reopen?.cancel();
    _gen++;
    final close = _close;
    _close = null;
    try {
      await close?.call();
    } catch (_) {}
  }
}
