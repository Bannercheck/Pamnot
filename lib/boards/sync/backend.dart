import 'package:flutter/foundation.dart';

import '../model/board_doc.dart';

/// What the sync engine needs from a server. Implemented by
/// SupabaseBoardBackend (production) and an in-memory fake (tests).
///
/// Methods throw [BackendUnavailable] for network failures,
/// [AccessDenied] when this user may not touch the board, [RateLimited]
/// for too many wrong invite codes and [BoardIdTaken] when a board id
/// already belongs to someone else.
abstract class BoardBackend {
  /// `host` of the server (for scoping local data).
  String get host;

  /// The signed-in user, or null.
  String? get userId;

  Future<int> serverTimeMs();

  /// Registers a device-only board on the server with this user as owner
  /// and returns its invite code. Idempotent for the same owner.
  Future<String> createBoard(String boardId);

  /// `push_items`: rows are `{id, kind, data, fh}` with dirty fields only.
  Future<PushResult> pushItems(String boardId, List<Map<String, Object?>> rows);

  /// Rows with `rev > afterRev` in rev order, at most [limit].
  Future<List<RemoteRow>> pullItems(String boardId, {required int afterRev, int limit = 500});

  /// Null when the board is gone for this user (revoked or never shared).
  Future<BoardStatusInfo?> boardStatus(String boardId);

  /// Null for a wrong code.
  Future<JoinResult?> joinBoard(String code);

  Future<void> leaveBoard(String boardId);
  Future<void> deleteBoard(String boardId);
  Future<String?> getInvite(String boardId);
  Future<String> rotateInvite(String boardId);

  /// Removes a member and returns the new invite code.
  Future<String> removeMember(String boardId, String userId);

  Future<List<BoardMember>> members(String boardId);

  /// Data channel: postgres_changes for the board's items.
  RealtimeLink subscribe(String boardId, RealtimeHandlers handlers);

  /// Presence and cursors.
  LiveLink joinLive(String boardId, LiveHandlers handlers);
}

enum SubscribeStatus { subscribed, channelError, timedOut, closed }

class RealtimeHandlers {
  const RealtimeHandlers({required this.onStatus, required this.onSystem, required this.onRow});

  final void Function(SubscribeStatus status, Object? error) onStatus;

  /// System events (`extension`, `status`, `message`).
  final void Function(Map<String, Object?> event) onSystem;

  /// A changed row; null when the record was truncated or incomplete.
  final void Function(RemoteRow? row) onRow;
}

abstract class RealtimeLink {
  Future<void> close();
}

class LiveHandlers {
  const LiveHandlers({required this.onPresence, required this.onCursor, this.onStatus, this.presenceKey});

  /// This device's presence key (its HLC node), for the channel config.
  /// Every tracked payload also carries it as `key`. Null lets the server
  /// pick one per connection.
  final String? presenceKey;

  /// Current presence payloads of everyone on the channel (including self).
  /// Each payload also carries its presence key under `key`.
  final void Function(List<Map<String, Object?>> presences) onPresence;

  final void Function(Map<String, Object?> payload) onCursor;
  final void Function(SubscribeStatus status, Object? error)? onStatus;
}

abstract class LiveLink {
  void track(Map<String, Object?> presence);
  void sendCursor(Map<String, Object?> payload);
  Future<void> close();
}

enum PushStatus { ok, boardDeleted, forbidden }

class PushResult {
  const PushResult(this.status, [this.acks = const []]);

  final PushStatus status;
  final List<PushAck> acks;
}

class BoardStatusInfo {
  const BoardStatusInfo({required this.ownerId, this.deletedAt});

  final String ownerId;
  final DateTime? deletedAt;
}

class JoinResult {
  const JoinResult({required this.boardId, required this.title});

  final String boardId;
  final String title;
}

class BoardMember {
  const BoardMember({required this.userId, required this.role, required this.displayName, required this.colorIndex});

  final String userId;

  /// 'owner' or 'editor'.
  final String role;
  final String displayName;
  final int colorIndex;
}

class BackendUnavailable implements Exception {
  const BackendUnavailable([this.cause]);

  final Object? cause;

  @override
  String toString() => 'BackendUnavailable($cause)';
}

class AccessDenied implements Exception {
  const AccessDenied([this.cause]);

  final Object? cause;

  @override
  String toString() => 'AccessDenied($cause)';
}

class RateLimited implements Exception {
  const RateLimited();
}

class BoardIdTaken implements Exception {
  const BoardIdTaken();
}

/// The app's link to the collaboration server, as the rest of the app
/// needs it. Implemented by CloudService.
abstract class CloudSession {
  /// True once configured and signed in.
  ValueListenable<bool> get ready;

  /// Null until [ready].
  BoardBackend? get backend;

  BoardAccount? get account;
  String get displayName;
  int get colorIndex;
}
