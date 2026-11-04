import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

enum SyncStatus {
  /// Device-only board.
  local,
  synced,
  sending,
  offline,
  error,

  /// The owner deleted the board for everyone.
  deleted,

  /// This device lost access (removed from the board).
  revoked,
}

class SyncState {
  const SyncState(this.status, {this.pending = 0, this.message});

  final SyncStatus status;

  /// Items with changes not yet confirmed by the server.
  final int pending;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is SyncState && other.status == status && other.pending == pending && other.message == message;

  @override
  int get hashCode => Object.hash(status, pending, message);
}

/// Someone else on the board right now.
class Peer {
  const Peer({
    required this.key,
    required this.userId,
    required this.name,
    required this.colorIndex,
    this.view = 'canvas',
    this.editing,
  });

  /// Presence key (one per device and app launch).
  final String key;
  final String userId;
  final String name;
  final int colorIndex;

  /// 'canvas' or 'kanban'.
  final String view;

  /// Item the peer is editing (card sheet or sticky), if any.
  final String? editing;
}

/// Latest known pointer of a peer, in canvas units.
class PeerCursor {
  const PeerCursor({
    required this.key,
    required this.name,
    required this.colorIndex,
    required this.position,
    required this.at,
    this.pointer = true,
  });

  final String key;
  final String name;
  final int colorIndex;
  final Offset position;
  final DateTime at;

  /// Mouse or stylus hover (arrow); false for touch (dot).
  final bool pointer;
}

/// The live link of an open board: sync state, presence and cursors. A
/// device-only board gets [LocalConnection].
abstract class BoardConnection {
  ValueListenable<SyncState> get state;

  /// Others on the board, not including this device.
  ValueListenable<List<Peer>> get peers;

  /// Peers' cursors keyed by presence key.
  ValueListenable<Map<String, PeerCursor>> get cursors;

  /// This device's pointer on the canvas (null when it leaves). Throttled
  /// and sent only while someone else is here.
  void sendCursor(Offset? canvasPosition, {bool pointer = true});

  /// What this device shows and edits, for others' presence UI.
  void setActivity({required String view, String? editing});

  /// A local edit happened: push soon.
  void kick();

  /// Retry after an error (tap on the sync icon).
  Future<void> retry();

  Future<void> close();
}

class LocalConnection implements BoardConnection {
  LocalConnection();

  final _state = ValueNotifier(const SyncState(SyncStatus.local));
  final _peers = ValueNotifier<List<Peer>>(const []);
  final _cursors = ValueNotifier<Map<String, PeerCursor>>(const {});

  @override
  ValueListenable<SyncState> get state => _state;

  @override
  ValueListenable<List<Peer>> get peers => _peers;

  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => _cursors;

  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) {}

  @override
  void setActivity({required String view, String? editing}) {}

  @override
  void kick() {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> close() async {
    _state.dispose();
    _peers.dispose();
    _cursors.dispose();
  }
}
