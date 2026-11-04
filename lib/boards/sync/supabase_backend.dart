import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../model/board_doc.dart';
import 'backend.dart';

/// [BoardBackend] on a Supabase project running supabase/schema.sql
/// (docs/boards/DESIGN.md §5–6). Every write goes through an RPC; reads are
/// plain PostgREST queries that RLS limits to the caller's boards.
class SupabaseBoardBackend implements BoardBackend {
  SupabaseBoardBackend(
    this.client, {
    required this.host,
    bool Function()? signedIn,
    this.timeout = const Duration(seconds: 30),
  }) : _signedIn = signedIn ?? (() => client.auth.currentSession != null);

  final SupabaseClient client;

  @override
  final String host;

  final bool Function() _signedIn;

  /// Upper bound for one call. Table queries do not get the client's request
  /// timeout (and GETs retry three times inside the library), so every call
  /// is bounded here.
  final Duration timeout;

  @override
  String? get userId => client.auth.currentUser?.id;

  Future<T> _guard<T>(Future<T> Function() call, {bool creating = false}) async {
    try {
      return await call().timeout(timeout);
    } catch (e) {
      throw mapBackendError(e, creating: creating, signedIn: _signedIn());
    }
  }

  @override
  Future<int> serverTimeMs() => _guard(() async {
        final v = await client.rpc('server_time_ms');
        if (v is num) return v.toInt();
        throw const FormatException('server_time_ms');
      });

  @override
  Future<String> createBoard(String boardId) => _guard(creating: true, () async {
        final code = await client.rpc('create_board', params: {'p_id': boardId});
        if (code is String) return code;
        throw const FormatException('create_board');
      });

  @override
  Future<PushResult> pushItems(String boardId, List<Map<String, Object?>> rows) => _guard(() async {
        final res = await client.rpc('push_items', params: {'p_board': boardId, 'p_items': rows});
        return parsePushResult(res);
      });

  @override
  Future<List<RemoteRow>> pullItems(String boardId, {required int afterRev, int limit = 500}) => _guard(() async {
        final rows = await client
            .from('board_items')
            .select('id,kind,data,fh,rev,updated_by,updated_at')
            .eq('board_id', boardId)
            .gt('rev', afterRev)
            .order('rev', ascending: true)
            .limit(limit);
        return [for (final r in rows) pulledRow(r)];
      });

  @override
  Future<BoardStatusInfo?> boardStatus(String boardId) => _guard(() async {
        final r = await client.from('boards').select('owner_id,deleted_at').eq('id', boardId).maybeSingle();
        if (r == null) return null;
        final owner = r['owner_id'];
        if (owner is! String) throw const FormatException('boards.owner_id');
        final del = r['deleted_at'];
        return BoardStatusInfo(ownerId: owner, deletedAt: del is String ? DateTime.tryParse(del) : null);
      });

  @override
  Future<JoinResult?> joinBoard(String code) => _guard(() async {
        final r = await client.rpc('join_board', params: {'p_code': code});
        if (r == null) return null;
        if (r is Map && r['board_id'] is String) {
          return JoinResult(boardId: r['board_id'] as String, title: (r['title'] as String?) ?? '');
        }
        throw const FormatException('join_board');
      });

  @override
  Future<void> leaveBoard(String boardId) => _guard(() => client.rpc('leave_board', params: {'p_board': boardId}));

  @override
  Future<void> deleteBoard(String boardId) => _guard(() => client.rpc('delete_board', params: {'p_board': boardId}));

  @override
  Future<String?> getInvite(String boardId) => _guard(() async {
        final code = await client.rpc('get_invite', params: {'p_board': boardId});
        return code is String ? code : null;
      });

  @override
  Future<String> rotateInvite(String boardId) => _guard(() async {
        final code = await client.rpc('rotate_invite', params: {'p_board': boardId});
        if (code is String) return code;
        throw const FormatException('rotate_invite');
      });

  @override
  Future<String> removeMember(String boardId, String userId) => _guard(() async {
        final code = await client.rpc('remove_member', params: {'p_board': boardId, 'p_user': userId});
        if (code is String) return code;
        throw const FormatException('remove_member');
      });

  @override
  Future<List<BoardMember>> members(String boardId) => _guard(() async {
        final rows = await client.from('board_members').select('user_id,role').eq('board_id', boardId);
        final ids = [for (final r in rows) if (r['user_id'] is String) r['user_id'] as String];
        final profiles = ids.isEmpty
            ? const <Map<String, dynamic>>[]
            : await client.from('profiles').select('id,display_name,color_index').inFilter('id', ids);
        return membersOf(rows, profiles);
      });

  @override
  RealtimeLink subscribe(String boardId, RealtimeHandlers handlers) {
    final ch = client.channel('board-data:$boardId', opts: const RealtimeChannelConfig(private: true));
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'board_id', value: boardId);
    // INSERT and UPDATE only: DELETE events are neither filtered nor checked
    // against RLS, and the app never deletes rows.
    for (final event in const [PostgresChangeEvent.insert, PostgresChangeEvent.update]) {
      ch.onPostgresChanges(
        event: event,
        schema: 'public',
        table: 'board_items',
        filter: filter,
        callback: (p) {
          final (deliver, row) = realtimeRow(p, boardId);
          if (deliver) handlers.onRow(row);
        },
      );
    }
    ch.onSystemEvents((p) => handlers.onSystem(p is Map ? p.cast<String, Object?>() : const {}));
    ch.subscribe((status, error) => handlers.onStatus(subscribeStatusOf(status), error));
    return _DataLink(client, ch);
  }

  @override
  LiveLink joinLive(String boardId, LiveHandlers handlers) {
    final ch = client.channel(
      'board-live:$boardId',
      opts: RealtimeChannelConfig(private: true, key: handlers.presenceKey ?? ''),
    );
    final link = _LiveLink(client, ch);
    ch.onPresenceSync((_) => handlers.onPresence(presencesOf(ch.presenceState())));
    ch.onBroadcast(event: 'cursor', callback: (m) {
      final p = broadcastPayload(m);
      if (p != null) handlers.onCursor(p);
    });
    ch.subscribe((status, error) {
      link._joined = status == RealtimeSubscribeStatus.subscribed;
      // Presence is per connection: track again after every (re)join.
      if (link._joined) link._sendTrack();
      handlers.onStatus?.call(subscribeStatusOf(status), error);
    });
    return link;
  }
}

class _DataLink implements RealtimeLink {
  _DataLink(this._client, this._ch);

  final SupabaseClient _client;
  final RealtimeChannel _ch;

  @override
  Future<void> close() async {
    try {
      await _client.removeChannel(_ch);
    } catch (_) {
      // Already gone with the socket.
    }
  }
}

class _LiveLink implements LiveLink {
  _LiveLink(this._client, this._ch);

  final SupabaseClient _client;
  final RealtimeChannel _ch;
  bool _joined = false;
  bool _closed = false;
  Map<String, Object?>? _presence;

  void _sendTrack() {
    final p = _presence;
    if (p == null || !_joined || _closed) return;
    unawaited(_ch.track({...p}).catchError((Object _) => ChannelResponse.error));
  }

  @override
  void track(Map<String, Object?> presence) {
    _presence = presence;
    _sendTrack();
  }

  @override
  void sendCursor(Map<String, Object?> payload) {
    // Only over the socket: while not joined the client would fall back to
    // one REST call per cursor sample.
    if (!_joined || _closed) return;
    unawaited(_ch
        .sendBroadcastMessage(event: 'cursor', payload: {'payload': payload})
        .catchError((Object _) => ChannelResponse.error));
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      await _client.removeChannel(_ch);
    } catch (_) {
      // Already gone with the socket.
    }
  }
}

/// Maps whatever a Supabase call threw onto the [BoardBackend] contract.
/// 42501 means access is gone, but only while signed in: without a session
/// the request ran as `anon` and is denied for that reason alone.
Exception mapBackendError(Object e, {bool creating = false, bool signedIn = true}) {
  if (e is BackendUnavailable || e is AccessDenied || e is RateLimited || e is BoardIdTaken) return e as Exception;
  if (e is PostgrestException) {
    if (e.hint == 'rate_limited') return const RateLimited();
    if (creating && e.code == '23505') return const BoardIdTaken();
    if (e.code == '42501' && signedIn) return AccessDenied(e);
    return BackendUnavailable(e);
  }
  // Sockets, http ClientException, timeouts, auth refresh failures, odd bodies.
  return BackendUnavailable(e);
}

SubscribeStatus subscribeStatusOf(RealtimeSubscribeStatus s) => switch (s) {
      RealtimeSubscribeStatus.subscribed => SubscribeStatus.subscribed,
      RealtimeSubscribeStatus.channelError => SubscribeStatus.channelError,
      RealtimeSubscribeStatus.timedOut => SubscribeStatus.timedOut,
      RealtimeSubscribeStatus.closed => SubscribeStatus.closed,
    };

/// The `push_items` answer as a [PushResult].
PushResult parsePushResult(Object? res) {
  if (res is! Map) throw const FormatException('push_items');
  switch (res['status']) {
    case 'board_deleted':
      return const PushResult(PushStatus.boardDeleted);
    case 'forbidden':
      return const PushResult(PushStatus.forbidden);
    case 'ok':
      break;
    default:
      throw FormatException('push_items status ${res['status']}');
  }
  final acks = <PushAck>[];
  for (final it in (res['items'] as List?) ?? const []) {
    if (it is! Map || it['id'] is! String) continue;
    final id = it['id'] as String;
    if (it['status'] == 'invalid') {
      acks.add(PushAck(id: id, fh: const {}, invalid: true));
      continue;
    }
    final fh = it['fh'], lost = it['lost'];
    acks.add(PushAck(
      id: id,
      fh: {if (fh is Map) for (final e in fh.entries) if (e.value is String) e.key as String: e.value as String},
      lost: lost is Map ? lost.cast<String, Object?>() : const {},
    ));
  }
  return PushResult(PushStatus.ok, acks);
}

/// A postgres_changes event as `(deliver, row)`: rows of other boards are
/// dropped; a record with errors (e.g. too large) or without data, fh or rev
/// is delivered as null, which asks the engine for a catch-up.
(bool, RemoteRow?) realtimeRow(PostgresChangePayload p, String boardId) {
  final record = p.newRecord;
  final board = record['board_id'];
  if (board is String && board != boardId) return (false, null);
  if (p.errors != null) return (true, null);
  return (true, RemoteRow.tryParse(record.cast<String, Object?>()));
}

/// A pulled row. Server rows always carry data, fh and rev; if one ever does
/// not, it becomes an empty row with its rev so the page keeps its length
/// (a short page ends the catch-up) and the cursor still moves past it.
RemoteRow pulledRow(Map<String, dynamic> r) {
  final row = RemoteRow.tryParse(r.cast<String, Object?>());
  if (row != null) return row;
  final id = r['id'], kind = r['kind'], rev = r['rev'];
  if (id is! String || kind is! String || rev is! num) throw FormatException('board_items row $id');
  return RemoteRow(id: id, kind: kind, data: const {}, fh: const {}, rev: rev.toInt());
}

/// Joins membership rows with profiles: owner first, then by name.
List<BoardMember> membersOf(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> profiles) {
  final byId = {for (final p in profiles) if (p['id'] is String) p['id'] as String: p};
  final out = [
    for (final r in rows)
      if (r['user_id'] is String)
        BoardMember(
          userId: r['user_id'] as String,
          role: r['role'] == 'owner' ? 'owner' : 'editor',
          displayName: (byId[r['user_id']]?['display_name'] as String?) ?? '',
          colorIndex: (byId[r['user_id']]?['color_index'] as num?)?.toInt() ?? 0,
        ),
  ]..sort((a, b) {
      if (a.role != b.role) return a.role == 'owner' ? -1 : 1;
      final c = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      return c != 0 ? c : a.userId.compareTo(b.userId);
    });
  return out;
}

/// Flattens presence state: one payload per device, with its key.
List<Map<String, Object?>> presencesOf(List<SinglePresenceState> state) => [
      for (final s in state)
        for (final p in s.presences) {...p.payload.cast<String, Object?>(), 'key': s.key},
    ];

/// Cursor messages are sent as `{payload: {...}}` inside the broadcast.
Map<String, Object?>? broadcastPayload(Map<String, dynamic> message) {
  final inner = message['payload'];
  if (inner is Map) return inner.cast<String, Object?>();
  return null;
}
