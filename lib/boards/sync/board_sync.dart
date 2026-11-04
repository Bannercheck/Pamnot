import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../boards_controller.dart';
import '../connection.dart';
import 'backend.dart';

/// Live sync of one open shared board (docs/boards/DESIGN.md §5).
///
/// STUB: the sync engine replaces this body; the constructor is the
/// contract main.dart wires up.
class BoardSync implements BoardConnection {
  BoardSync({
    required this.board,
    required this.controller,
    required this.backend,
    required this.session,
  });

  final OpenBoard board;
  final BoardsController controller;
  final BoardBackend backend;
  final CloudSession session;

  final _state = ValueNotifier(const SyncState(SyncStatus.offline));
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
  Future<void> close() async {}
}
