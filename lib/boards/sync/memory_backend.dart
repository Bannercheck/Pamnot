/// An in-memory stand-in for the Supabase project, for tests and demos.
///
/// [MemoryServer] reproduces the server side of DESIGN.md §5–6: the
/// `push_items` per-field merge by HLC string comparison, a gap-free
/// per-board `rev` bumped only for rows that changed, `board_deleted` /
/// `forbidden` statuses instead of exceptions, invites, members and
/// row-level visibility. Each simulated device talks to it through its own
/// [MemoryBackend], whose network and realtime can misbehave on purpose:
/// go offline, lose responses, and drop, delay, duplicate, reorder or
/// truncate change events, repeat `subscribed`, or fail replication.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/board_doc.dart';
import '../model/board_item.dart';
import '../model/hlc.dart';
import 'backend.dart';

/// The current version of a row on the server.
class MemoryRow {
  MemoryRow({
    required this.kind,
    required this.data,
    required this.fh,
    required this.rev,
    required this.updatedBy,
    required this.updatedAt,
  });

  final String kind;
  final Map<String, Object?> data;
  final Map<String, String> fh;
  final int rev;
  final String updatedBy;
  final DateTime updatedAt;

  /// The record as postgres_changes delivers it.
  Map<String, Object?> record(String boardId, String id) => {
        'board_id': boardId,
        'id': id,
        'kind': kind,
        'data': data,
        'fh': fh,
        'rev': rev,
        'updated_by': updatedBy,
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// A `boards` row with its members, invite and items.
class MemoryBoard {
  MemoryBoard({required this.id, required this.ownerId, required this.code});

  final String id;
  final String ownerId;
  String code;
  DateTime? deletedAt;
  int rev = 0;

  /// userId → 'owner' | 'editor'.
  final Map<String, String> roles = {};
  final Map<String, MemoryRow> items = {};

  /// Every rev handed out, in order (tests check it has no gaps).
  final List<int> revLog = [];

  String get title => (items[id]?.data[F.title] as String?) ?? '';
}

class MemoryServer {
  MemoryServer({int Function()? nowMs, math.Random? random})
      : nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        random = random ?? math.Random();

  final int Function() nowMs;
  final math.Random random;
  final Map<String, MemoryBoard> boards = {};
  final Map<String, (String, int)> profiles = {};
  final List<MemoryBackend> _clients = [];

  /// Wrong invite codes per user, for the join rate limit.
  final Map<String, List<int>> _joinFailures = {};

  static final uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _kinds = {for (final k in ItemKind.values) k.name};
  static const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  DateTime get now => DateTime.fromMillisecondsSinceEpoch(nowMs(), isUtc: true);

  void setProfile(String userId, String name, int colorIndex) => profiles[userId] = (name, colorIndex);

  bool isMember(String boardId, String? userId) =>
      userId != null && (boards[boardId]?.roles.containsKey(userId) ?? false);

  String _newCode() => String.fromCharCodes(
      List.generate(10, (_) => _crockford.codeUnitAt(random.nextInt(_crockford.length))));

  static String normalizeCode(String code) => code
      .toUpperCase()
      .replaceAll(RegExp(r'[^0-9A-Z]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');

  // ----------------------------------------------------------- RPCs

  String createBoard(String uid, String boardId) {
    final b = boards[boardId];
    if (b != null) {
      if (b.ownerId == uid) return b.code;
      throw const BoardIdTaken();
    }
    if (!uuidPattern.hasMatch(boardId)) throw FormatException('invalid uuid', boardId);
    final nb = MemoryBoard(id: boardId, ownerId: uid, code: _newCode());
    nb.roles[uid] = 'owner';
    boards[boardId] = nb;
    return nb.code;
  }

  /// `push_items(p_board, p_items)`.
  PushResult pushItems(String uid, String boardId, List<Object?> rows) {
    final b = boards[boardId];
    if (b == null) return const PushResult(PushStatus.forbidden);
    if (b.deletedAt != null) return const PushResult(PushStatus.boardDeleted);
    if (!b.roles.containsKey(uid)) return const PushResult(PushStatus.forbidden);
    final acks = <PushAck>[];
    final changed = <String>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final id = raw['id'];
      // Not a uuid: skipped without an answer.
      if (id is! String || !uuidPattern.hasMatch(id)) continue;
      final cur = b.items[id];
      final kind = raw['kind'];
      if (cur == null && (kind is! String || !_kinds.contains(kind))) {
        acks.add(PushAck(id: id, fh: const {}, invalid: true));
        continue;
      }
      final data = <String, Object?>{...?cur?.data};
      final fh = <String, String>{...?cur?.fh};
      final lost = <String, Object?>{};
      var chg = false;
      final inData = raw['data'];
      final inFh = raw['fh'];
      if (inFh is Map) {
        for (final e in inFh.entries) {
          final k = e.key, ih = e.value;
          if (k is! String || ih is! String || !HlcClock.isValid(ih)) continue;
          if (inData is! Map || !inData.containsKey(k)) continue;
          final ch = fh[k];
          if (ch == null || ih.compareTo(ch) > 0) {
            data[k] = inData[k];
            fh[k] = ih;
            chg = true;
          } else if (ih.compareTo(ch) < 0) {
            lost[k] = data[k];
          }
        }
      }
      if (chg) {
        b.rev++;
        b.revLog.add(b.rev);
        b.items[id] = MemoryRow(
          kind: cur?.kind ?? kind as String,
          data: data,
          fh: fh,
          rev: b.rev,
          updatedBy: uid,
          updatedAt: now,
        );
        changed.add(id);
      }
      acks.add(PushAck(id: id, fh: {...fh}, lost: lost));
    }
    // Replication reads the log after the transaction commits.
    for (final id in changed) {
      _replicate(b, b.items[id]!.record(b.id, id));
    }
    return PushResult(PushStatus.ok, acks);
  }

  /// Rows visible to [uid] (RLS: nothing for non-members).
  List<RemoteRow> pullItems(String uid, String boardId, int afterRev, int limit) {
    final b = boards[boardId];
    if (b == null || !b.roles.containsKey(uid)) return const [];
    final rows = [for (final e in b.items.entries) if (e.value.rev > afterRev) e]
      ..sort((x, y) => x.value.rev.compareTo(y.value.rev));
    return [
      for (final e in rows.take(limit))
        RemoteRow(
          id: e.key,
          kind: e.value.kind,
          data: e.value.data,
          fh: e.value.fh,
          rev: e.value.rev,
          updatedBy: e.value.updatedBy,
          updatedAt: e.value.updatedAt,
        ),
    ];
  }

  BoardStatusInfo? boardStatus(String uid, String boardId) {
    final b = boards[boardId];
    if (b == null || !b.roles.containsKey(uid)) return null;
    return BoardStatusInfo(ownerId: b.ownerId, deletedAt: b.deletedAt);
  }

  JoinResult? joinBoard(String uid, String code) {
    final t = nowMs();
    final fails = _joinFailures.putIfAbsent(uid, () => [])..removeWhere((f) => t - f > const Duration(days: 1).inMilliseconds);
    final recent = fails.where((f) => t - f <= const Duration(minutes: 15).inMilliseconds).length;
    if (recent >= 10 || fails.length >= 50) throw const RateLimited();
    final c = normalizeCode(code);
    MemoryBoard? b;
    for (final x in boards.values) {
      if (x.code == c && x.deletedAt == null) b = x;
    }
    if (b == null) {
      fails.add(t);
      return null;
    }
    b.roles.putIfAbsent(uid, () => 'editor');
    return JoinResult(boardId: b.id, title: b.title);
  }

  void leaveBoard(String uid, String boardId) {
    final b = boards[boardId];
    if (b == null || !b.roles.containsKey(uid)) return;
    if (b.ownerId == uid) throw const AccessDenied('the owner cannot leave');
    b.roles.remove(uid);
    _presenceChanged(boardId);
  }

  /// Absorbing: a deleted board never comes back.
  void deleteBoard(String uid, String boardId) {
    final b = boards[boardId];
    if (b == null || b.ownerId != uid) return;
    b.deletedAt ??= now;
  }

  String? getInvite(String uid, String boardId) {
    final b = boards[boardId];
    return b != null && b.ownerId == uid ? b.code : null;
  }

  String rotateInvite(String uid, String boardId) {
    final b = boards[boardId];
    if (b == null || b.ownerId != uid) throw const AccessDenied('owner only');
    return b.code = _newCode();
  }

  String removeMember(String uid, String boardId, String userId) {
    final b = boards[boardId];
    if (b == null || b.ownerId != uid) throw const AccessDenied('owner only');
    if (userId == b.ownerId) throw const AccessDenied('the owner cannot be removed');
    b.roles.remove(userId);
    _presenceChanged(boardId);
    return b.code = _newCode();
  }

  List<BoardMember> members(String uid, String boardId) {
    final b = boards[boardId];
    if (b == null || !b.roles.containsKey(uid)) return const [];
    return [
      for (final e in b.roles.entries)
        BoardMember(
          userId: e.key,
          role: e.value,
          displayName: profiles[e.key]?.$1 ?? '',
          colorIndex: profiles[e.key]?.$2 ?? 0,
        ),
    ];
  }

  // -------------------------------------------------------- realtime

  void _replicate(MemoryBoard b, Map<String, Object?> record) {
    for (final client in _clients) {
      for (final ch in [...client._channels]) {
        if (ch.boardId == b.id) ch._deliver(record);
      }
    }
  }

  Iterable<MemoryLive> _livesOn(String boardId) sync* {
    for (final client in _clients) {
      for (final l in client._lives) {
        if (l.boardId == boardId) yield l;
      }
    }
  }

  void _presenceChanged(String boardId) {
    final present = [
      for (final l in _livesOn(boardId))
        if (l._present) l._presence!,
    ];
    for (final l in _livesOn(boardId)) {
      if (l._joined && l._reachable) l._later(() => l.handlers.onPresence([for (final p in present) _wire(p)]));
    }
  }

  void _broadcastCursor(MemoryLive from, Map<String, Object?> payload) {
    for (final l in _livesOn(from.boardId)) {
      // Broadcast does not echo to the sender.
      if (identical(l, from) || !l._joined || !l._reachable) continue;
      l._later(() => l.handlers.onCursor(_wire(payload)));
    }
  }
}

/// Deep copy through JSON, as on the wire: nothing is shared between a
/// client's document and the server's rows.
T _wire<T>(T value) => jsonDecode(jsonEncode(value)) as T;

/// One device's connection to a [MemoryServer].
class MemoryBackend implements BoardBackend {
  MemoryBackend(
    this.server, {
    required this.userId,
    this.host = 'memory.local',
    math.Random? random,
  }) : random = random ?? math.Random() {
    server._clients.add(this);
  }

  final MemoryServer server;
  final math.Random random;

  @override
  final String host;

  @override
  final String? userId;

  /// Each way, for every call.
  Duration latency = Duration.zero;

  /// Chance that a call's response is lost after the server applied it.
  double lossRate = 0;

  /// Throws the returned exception instead of running the call (by name:
  /// `pushItems`, `pullItems`, `boardStatus`, …).
  Object? Function(String call)? fault;

  // Realtime faults, applied per delivered event.
  double dropRate = 0;
  double duplicateRate = 0;

  /// Delivers the record without `data` (the backend then reports null).
  double truncateRate = 0;

  /// Delivers `data` with one field missing while `fh` still has it.
  double partialRate = 0;
  Duration minDelay = Duration.zero;
  Duration maxDelay = Duration.zero;

  /// From the join request to `subscribed`.
  Duration joinDelay = Duration.zero;

  /// From `subscribed` to replication being live (and the system `ok`).
  /// Rows committed in between are not delivered.
  Duration replicationDelay = Duration.zero;

  /// Send the system `ok` event when replication goes live.
  bool systemOk = true;

  /// After the network comes back, channels rejoin by themselves.
  bool autoRejoin = true;

  /// Names of every call, in order.
  final List<String> calls = [];

  /// Every cursor payload this device sent.
  final List<Map<String, Object?>> sentCursors = [];

  /// Row count of every pushItems call.
  final List<int> pushedRows = [];

  final List<MemoryChannel> _channels = [];
  final List<MemoryLive> _lives = [];
  bool _online = true;
  bool _suspended = false;
  bool _killed = false;

  List<MemoryChannel> get channels => List.unmodifiable(_channels);
  List<MemoryLive> get lives => List.unmodifiable(_lives);

  bool get online => _online;
  bool get killed => _killed;
  bool get _reachable => _online && !_suspended && !_killed;

  /// Network partition. Going offline errors every channel; coming back
  /// rejoins them (`subscribed` again) unless [autoRejoin] is off.
  set online(bool value) {
    if (value == _online || _killed) return;
    _online = value;
    if (!value) {
      for (final c in [..._channels]) {
        c._lost(SubscribeStatus.channelError, 'socket closed');
      }
      for (final l in [..._lives]) {
        l._lost(SubscribeStatus.channelError);
      }
    } else if (autoRejoin && !_suspended) {
      _rejoinAll();
    }
  }

  /// The app went to the background and the client dropped the socket:
  /// nothing is reported, events are missed.
  void suspend() {
    if (_suspended || _killed) return;
    _suspended = true;
    for (final c in [..._channels]) {
      c._lost(null, null);
    }
    for (final l in [..._lives]) {
      l._lost(null);
    }
  }

  /// Back in the foreground: the client rejoins every channel, which
  /// reports `subscribed` again with no error before it.
  void resumeSocket() {
    if (!_suspended || _killed) return;
    _suspended = false;
    if (_online) _rejoinAll();
  }

  void _rejoinAll() {
    for (final c in [..._channels]) {
      if (!c._joined && !c._failed) c._join();
    }
    for (final l in [..._lives]) {
      if (!l._joined) l._join();
    }
  }

  /// The app process died: calls never return, channels vanish.
  void kill() {
    if (_killed) return;
    _killed = true;
    final boards = {for (final l in _lives) l.boardId};
    for (final c in _channels) {
      c._removed = true;
    }
    for (final l in _lives) {
      l._removed = true;
    }
    _channels.clear();
    _lives.clear();
    server._clients.remove(this);
    boards.forEach(server._presenceChanged);
  }

  Duration _eventDelay() {
    final lo = minDelay.inMicroseconds, hi = maxDelay.inMicroseconds;
    if (hi <= lo) return minDelay;
    return Duration(microseconds: lo + random.nextInt(hi - lo + 1));
  }

  Future<T> _call<T>(String name, T Function(String uid) op) async {
    calls.add(name);
    if (_killed) return Completer<T>().future;
    await _hop();
    if (_killed) return Completer<T>().future;
    if (!_online) throw const BackendUnavailable('offline');
    final f = fault?.call(name);
    if (f != null) throw f;
    final uid = userId;
    if (uid == null) throw const AccessDenied('not signed in');
    late final T out;
    Object? error;
    try {
      // Runs atomically, like one transaction.
      out = _wireCopy(op(uid));
    } catch (e) {
      error = e;
    }
    await _hop();
    if (_killed) return Completer<T>().future;
    if (!_online || (lossRate > 0 && random.nextDouble() < lossRate)) {
      throw const BackendUnavailable('response lost');
    }
    if (error != null) throw error;
    return out;
  }

  /// One trip over the network.
  Future<void> _hop() => latency == Duration.zero ? Future<void>.value() : Future<void>.delayed(latency);

  static T _wireCopy<T>(T v) {
    if (v is List<RemoteRow>) {
      return [
        for (final r in v)
          RemoteRow(
            id: r.id,
            kind: r.kind,
            data: _wire(r.data),
            fh: {...r.fh},
            rev: r.rev,
            updatedBy: r.updatedBy,
            updatedAt: r.updatedAt,
          ),
      ] as T;
    }
    if (v is PushResult) {
      return PushResult(v.status, [
        for (final a in v.acks) PushAck(id: a.id, fh: {...a.fh}, lost: _wire(a.lost), invalid: a.invalid),
      ]) as T;
    }
    return v;
  }

  @override
  Future<int> serverTimeMs() => _call('serverTimeMs', (_) => server.nowMs());

  @override
  Future<String> createBoard(String boardId) => _call('createBoard', (uid) => server.createBoard(uid, boardId));

  @override
  Future<PushResult> pushItems(String boardId, List<Map<String, Object?>> rows) {
    final payload = jsonDecode(jsonEncode(rows)) as List;
    pushedRows.add(rows.length);
    return _call('pushItems', (uid) => server.pushItems(uid, boardId, payload));
  }

  @override
  Future<List<RemoteRow>> pullItems(String boardId, {required int afterRev, int limit = 500}) =>
      _call('pullItems', (uid) => server.pullItems(uid, boardId, afterRev, limit));

  @override
  Future<BoardStatusInfo?> boardStatus(String boardId) => _call('boardStatus', (uid) => server.boardStatus(uid, boardId));

  @override
  Future<JoinResult?> joinBoard(String code) => _call('joinBoard', (uid) => server.joinBoard(uid, code));

  @override
  Future<void> leaveBoard(String boardId) => _call('leaveBoard', (uid) => server.leaveBoard(uid, boardId));

  @override
  Future<void> deleteBoard(String boardId) => _call('deleteBoard', (uid) => server.deleteBoard(uid, boardId));

  @override
  Future<String?> getInvite(String boardId) => _call('getInvite', (uid) => server.getInvite(uid, boardId));

  @override
  Future<String> rotateInvite(String boardId) => _call('rotateInvite', (uid) => server.rotateInvite(uid, boardId));

  @override
  Future<String> removeMember(String boardId, String userId) =>
      _call('removeMember', (uid) => server.removeMember(uid, boardId, userId));

  @override
  Future<List<BoardMember>> members(String boardId) => _call('members', (uid) => server.members(uid, boardId));

  @override
  RealtimeLink subscribe(String boardId, RealtimeHandlers handlers) {
    calls.add('subscribe');
    final c = MemoryChannel._(this, boardId, handlers);
    if (_killed) return c.._removed = true;
    _channels.add(c);
    c._join();
    return c;
  }

  @override
  LiveLink joinLive(String boardId, LiveHandlers handlers) {
    calls.add('joinLive');
    final l = MemoryLive._(this, boardId, handlers);
    if (_killed) return l.._removed = true;
    _lives.add(l);
    l._join();
    return l;
  }
}

/// A `board-data:<id>` channel.
class MemoryChannel implements RealtimeLink {
  MemoryChannel._(this.backend, this.boardId, this.handlers);

  final MemoryBackend backend;
  final String boardId;
  final RealtimeHandlers handlers;

  bool _joined = false;
  bool _replicating = false;
  bool _removed = false;

  /// Replication failed: the channel stays joined and delivers nothing,
  /// and the client schedules no rejoin.
  bool _failed = false;
  int _joinGen = 0;

  bool get joined => _joined;
  bool get replicating => _replicating;
  bool get removed => _removed;

  /// Rows delivered to the handlers (after faults).
  int delivered = 0;

  void _later(void Function() fn, [Duration delay = Duration.zero]) => Timer(delay, () {
        if (!_removed) fn();
      });

  void _status(SubscribeStatus s, [Object? error]) => _later(() => handlers.onStatus(s, error));

  void _join() {
    final gen = ++_joinGen;
    _failed = false;
    if (!backend._reachable) {
      // The join push times out; the client retries when the socket is back.
      _later(() {
        if (gen == _joinGen && !_joined && !backend._suspended) handlers.onStatus(SubscribeStatus.timedOut, null);
      }, const Duration(seconds: 10));
      return;
    }
    _later(() {
      if (gen != _joinGen || !backend._reachable) return;
      if (!backend.server.isMember(boardId, backend.userId)) {
        handlers.onStatus(
            SubscribeStatus.channelError, 'Unauthorized: You do not have permissions to read from this Channel topic');
        return;
      }
      _joined = true;
      handlers.onStatus(SubscribeStatus.subscribed, null);
      _later(() {
        if (gen != _joinGen || !_joined || _failed) return;
        _replicating = true;
        if (backend.systemOk) {
          handlers.onSystem({
            'extension': 'postgres_changes',
            'status': 'ok',
            'message': 'Subscribed to PostgreSQL',
            'channel': 'board-data:$boardId',
          });
        }
      }, backend.replicationDelay);
    }, backend.joinDelay);
  }

  /// The socket dropped. [status] null: silently (app paused).
  void _lost(SubscribeStatus? status, Object? error) {
    _joinGen++;
    final was = _joined;
    _joined = false;
    _replicating = false;
    if (status != null && was) _status(status, error);
  }

  void _deliver(Map<String, Object?> record) {
    if (!_replicating || _failed || _removed || !backend._reachable) return;
    if (!backend.server.isMember(boardId, backend.userId)) return;
    final r = backend.random;
    if (r.nextDouble() < backend.dropRate) return;
    final copies = r.nextDouble() < backend.duplicateRate ? 2 : 1;
    final gen = _joinGen;
    for (var i = 0; i < copies; i++) {
      final rec = _wire(record);
      if (r.nextDouble() < backend.truncateRate) {
        rec.remove('data');
      } else if (r.nextDouble() < backend.partialRate) {
        final data = rec['data'] as Map;
        if (data.isNotEmpty) data.remove(data.keys.elementAt(r.nextInt(data.length)));
      }
      _later(() {
        // In flight when the socket dropped: lost.
        if (gen != _joinGen || !_replicating || !backend._reachable) return;
        delivered++;
        handlers.onRow(RemoteRow.tryParse(rec));
      }, backend._eventDelay());
    }
  }

  // ------------------------------------------------------ test hooks

  void emitStatus(SubscribeStatus status, [Object? error]) => _status(status, error);

  void emitSystem(Map<String, Object?> event) => _later(() => handlers.onSystem(event));

  /// A postgres_changes setup failure after `subscribed` (an expired token,
  /// an RLS denial): a system error, reported as `channelError`, and then
  /// a channel that looks joined but delivers nothing, forever.
  void failReplication([String message = 'postgres_changes subscription failed']) {
    _failed = true;
    _replicating = false;
    emitSystem({'extension': 'postgres_changes', 'status': 'error', 'message': message});
    _status(SubscribeStatus.channelError, message);
  }

  /// What the client does on resume (`forceRejoin`): `subscribed` again.
  void rejoin() {
    _lost(null, null);
    _join();
  }

  @override
  Future<void> close() async {
    if (_removed) return;
    _removed = true;
    _joined = false;
    _replicating = false;
    backend._channels.remove(this);
    // removeChannel reports `closed` to the subscribe callback.
    Timer(Duration.zero, () => handlers.onStatus(SubscribeStatus.closed, null));
  }
}

/// A `board-live:<id>` channel: presence and cursor broadcast.
class MemoryLive implements LiveLink {
  MemoryLive._(this.backend, this.boardId, this.handlers);

  final MemoryBackend backend;
  final String boardId;
  final LiveHandlers handlers;

  bool _joined = false;
  bool _removed = false;
  int _joinGen = 0;
  Map<String, Object?>? _presence;

  /// Tracked before the join completed; sent once it does.
  Map<String, Object?>? _pending;

  bool get joined => _joined;
  bool get removed => _removed;
  Map<String, Object?>? get presence => _presence;

  bool get _reachable => backend._reachable && backend.server.isMember(boardId, backend.userId);
  bool get _present => _joined && _presence != null && _reachable && !_removed;

  void _later(void Function() fn) => Timer(Duration.zero, () {
        if (!_removed) fn();
      });

  void _join() {
    final gen = ++_joinGen;
    // Presence belongs to the connection: a rejoin starts untracked.
    _presence = null;
    if (!backend._reachable) return;
    Timer(backend.joinDelay, () {
      if (gen != _joinGen || _removed || !backend._reachable) return;
      if (!backend.server.isMember(boardId, backend.userId)) {
        handlers.onStatus?.call(SubscribeStatus.channelError, 'Unauthorized');
        return;
      }
      _joined = true;
      if (_pending != null) {
        _presence = _pending;
        _pending = null;
      }
      handlers.onStatus?.call(SubscribeStatus.subscribed, null);
      backend.server._presenceChanged(boardId);
    });
  }

  void _lost(SubscribeStatus? status) {
    _joinGen++;
    final was = _joined;
    _joined = false;
    _presence = null;
    if (status != null && was) _later(() => handlers.onStatus?.call(status, null));
    backend.server._presenceChanged(boardId);
  }

  @override
  void track(Map<String, Object?> presence) {
    if (_removed) return;
    if (!_joined) {
      // Buffered until the join completes, like the client's push buffer.
      _pending = _wire(presence);
      return;
    }
    _presence = _wire(presence);
    backend.server._presenceChanged(boardId);
  }

  @override
  void sendCursor(Map<String, Object?> payload) {
    if (_removed || !_joined || !_reachable) return;
    backend.sentCursors.add(_wire(payload));
    backend.server._broadcastCursor(this, payload);
  }

  @override
  Future<void> close() async {
    if (_removed) return;
    _removed = true;
    _joined = false;
    _presence = null;
    backend._lives.remove(this);
    backend.server._presenceChanged(boardId);
  }
}

/// A signed-in [CloudSession] over a [MemoryBackend].
class MemorySession implements CloudSession {
  MemorySession(this.memory, {this.displayName = 'Deniz', this.colorIndex = 3});

  final MemoryBackend memory;

  @override
  final String displayName;

  @override
  final int colorIndex;

  final _ready = ValueNotifier(true);

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  BoardBackend? get backend => memory;

  @override
  BoardAccount? get account {
    final uid = memory.userId;
    return uid == null ? null : BoardAccount(host: memory.host, userId: uid);
  }
}
