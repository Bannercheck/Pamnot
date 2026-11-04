import 'dart:convert';

import 'package:pamnot/boards/cloud/cloud_api.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/sync/backend.dart';

/// An unsigned JWT with [payload], like Supabase's legacy anon key.
String jwt(Map<String, Object?> payload) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.c2lnbmF0dXJl';
}

/// A Supabase stand-in for CloudService: sessions survive stop() unless
/// signed out, like the real per-host session storage.
class FakeCloudApi implements CloudApi {
  final calls = <String>[];

  /// Saved sessions by server url ("on this device").
  final sessions = <String, String>{};
  CloudFailure? probeError, schemaError, signInError, profileError, startError;
  int schema = 1;
  int _nextUser = 1;
  String? _url;
  void Function()? _signedOut;
  FakeBackend? lastBackend;
  final profiles = <(String, int)>[];

  bool get started => _url != null;

  @override
  set onSignedOut(void Function()? callback) => _signedOut = callback;

  void endSession() {
    sessions.remove(_url);
    _signedOut?.call();
  }

  @override
  Future<void> start(String url, String key) async {
    calls.add('start $url');
    if (startError != null) throw startError!;
    _url = url;
  }

  @override
  Future<void> stop({required bool signOut}) async {
    calls.add('stop${signOut ? ' signOut' : ''}');
    if (signOut) sessions.remove(_url);
    _url = null;
  }

  @override
  String? get userId => _url == null ? null : sessions[_url];

  @override
  Future<void> probe() async {
    calls.add('probe');
    if (probeError != null) throw probeError!;
  }

  @override
  Future<int> schemaVersion() async {
    calls.add('schema');
    if (schemaError != null) throw schemaError!;
    return schema;
  }

  @override
  Future<String> signInAnonymously(String name) async {
    calls.add('signIn $name');
    if (signInError != null) throw signInError!;
    final id = 'user-${_nextUser++}';
    sessions[_url!] = id;
    return id;
  }

  @override
  Future<void> saveProfile(String name, int colorIndex) async {
    calls.add('profile $name $colorIndex');
    if (profileError != null) throw profileError!;
    profiles.add((name, colorIndex));
  }

  /// One backend per host, so a test can set its answers up front.
  @override
  BoardBackend backend(String host) {
    if (lastBackend?.host != host) lastBackend = FakeBackend(host: host, user: () => userId);
    return lastBackend!;
  }
}

/// Records calls; answers are set per test.
class FakeBackend implements BoardBackend {
  FakeBackend({required this.host, String? Function()? user}) : _user = user ?? (() => 'me');

  @override
  final String host;
  final String? Function() _user;
  final calls = <String>[];

  JoinResult? Function(String code) onJoin = (_) => null;
  BoardStatusInfo? status;
  Exception? statusError;
  Exception? joinError;
  Exception? writeError;
  String invite = 'ABCDEFGHJK';
  List<BoardMember> memberList = const [];

  @override
  String? get userId => _user();

  @override
  Future<int> serverTimeMs() async => 0;

  @override
  Future<String> createBoard(String boardId) async {
    calls.add('create $boardId');
    return invite;
  }

  @override
  Future<PushResult> pushItems(String boardId, List<Map<String, Object?>> rows) async =>
      const PushResult(PushStatus.ok);

  @override
  Future<List<RemoteRow>> pullItems(String boardId, {required int afterRev, int limit = 500}) async => const [];

  @override
  Future<BoardStatusInfo?> boardStatus(String boardId) async {
    calls.add('status $boardId');
    if (statusError != null) throw statusError!;
    return status;
  }

  @override
  Future<JoinResult?> joinBoard(String code) async {
    calls.add('join $code');
    if (joinError != null) throw joinError!;
    return onJoin(code);
  }

  @override
  Future<void> leaveBoard(String boardId) async {
    calls.add('leave $boardId');
    if (writeError != null) throw writeError!;
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    calls.add('delete $boardId');
    if (writeError != null) throw writeError!;
  }

  @override
  Future<String?> getInvite(String boardId) async {
    calls.add('invite $boardId');
    return invite;
  }

  @override
  Future<String> rotateInvite(String boardId) async {
    calls.add('rotate $boardId');
    return invite = 'NEWC0DE123';
  }

  @override
  Future<String> removeMember(String boardId, String userId) async {
    calls.add('remove $boardId $userId');
    return invite = 'REM0VED123';
  }

  @override
  Future<List<BoardMember>> members(String boardId) async {
    calls.add('members $boardId');
    return memberList;
  }

  @override
  RealtimeLink subscribe(String boardId, RealtimeHandlers handlers) => _Link();

  @override
  LiveLink joinLive(String boardId, LiveHandlers handlers) => _Live();
}

class _Link implements RealtimeLink {
  @override
  Future<void> close() async {}
}

class _Live implements LiveLink {
  @override
  void track(Map<String, Object?> presence) {}

  @override
  void sendCursor(Map<String, Object?> payload) {}

  @override
  Future<void> close() async {}
}
