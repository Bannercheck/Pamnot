// Simulated devices, processes and a shared in-memory server for the sync
// tests. Everything runs in fake time (FakeAsync), so minutes of backoffs,
// polls and watchdogs take milliseconds.

import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/board_editor.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/model/hlc.dart';
import 'package:pamnot/boards/sync/board_sync.dart';
import 'package:pamnot/boards/sync/memory_backend.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';

/// Fake wall time starts here (November 2026).
const baseMs = 1793000000000;

/// Runs [body] in fake time without timer stack traces (they are slow).
void inFakeTime(void Function(FakeAsync async) body) =>
    FakeAsync(includeTimerStackTrace: false).run(body);

/// A device's storage as one app process sees it. After [dead] (a crash),
/// nothing more reaches the disk. Every write is atomic, like FileStore's
/// temp file and rename.
class CrashStore implements KeyValueStore {
  CrashStore(this.disk);

  final MemoryStore disk;
  bool dead = false;

  /// Writes and deletes that reached the disk.
  int writes = 0;

  /// The process dies right after this many writes.
  int? crashAfterWrites;

  /// Called when the process dies at [crashAfterWrites].
  void Function()? onCrash;

  void _wrote() {
    writes++;
    if (writes == crashAfterWrites) {
      dead = true;
      onCrash?.call();
    }
  }

  @override
  Future<String?> read(String key) => dead ? Completer<String?>().future : disk.read(key);

  @override
  Future<void> write(String key, String value) {
    if (dead) return Completer<void>().future;
    disk.data[key] = value;
    _wrote();
    return Future.value();
  }

  @override
  Future<void> delete(String key) {
    if (dead) return Completer<void>().future;
    disk.data.remove(key);
    _wrote();
    return Future.value();
  }
}

class World {
  World(this.async, {int seed = 1}) : random = math.Random(seed) {
    server = MemoryServer(nowMs: () => baseMs + async.elapsed.inMilliseconds, random: math.Random(seed * 31 + 7));
  }

  final FakeAsync async;
  final math.Random random;
  late final MemoryServer server;
  int _ids = 0;

  /// Unique uuid-shaped ids across every device and process.
  String newId() => '00000000-0000-4000-8000-${(_ids++).toRadixString(16).padLeft(12, '0')}';

  String node() => List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();

  void run(Duration d) => async.elapse(d);

  /// Lets zero-delay timers and microtasks run.
  void settle() => async.elapse(const Duration(milliseconds: 1));

  /// Advances fake time until [f] completes.
  T wait<T>(Future<T> f, {Duration max = const Duration(minutes: 10)}) {
    var done = false;
    T? value;
    Object? error;
    StackTrace? stack;
    f.then((v) {
      value = v;
      done = true;
    }, onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    });
    async.flushMicrotasks();
    var spent = Duration.zero;
    while (!done) {
      if (spent > max) throw StateError('future did not complete in $max of fake time');
      async.elapse(const Duration(milliseconds: 5));
      spent += const Duration(milliseconds: 5);
    }
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return value as T;
  }

  /// A board created on [owner], shared and uploaded. Returns its id and
  /// invite code.
  (String, String) share(Client owner, {BoardTemplate template = BoardTemplate.tasks, String title = 'Ekip'}) {
    final id = wait(owner.controller.createBoard(title: title, colorIndex: 2, template: template, strings: S.tr));
    owner.open(id);
    wait(owner.controller.beginUpload(id, owner.session.account!));
    run(const Duration(seconds: 3));
    final bid = owner.board!.id;
    return (bid, server.boards[bid]!.code);
  }

  /// [c] joins with an invite code and opens the board.
  String join(Client c, String code) {
    final r = wait(c.backend.joinBoard(code))!;
    wait(c.controller.addJoined(boardId: r.boardId, title: r.title, account: c.session.account!));
    c.open(r.boardId);
    run(const Duration(seconds: 2));
    return r.boardId;
  }
}

/// A phone or computer: its disk survives crashes, its processes do not.
class Device {
  Device(this.world, {required this.userId, required this.name, this.colorIndex = 1, this.skewMs = 0}) {
    world.server.setProfile(userId, name, colorIndex);
  }

  final World world;
  final String userId;
  final String name;
  final int colorIndex;

  /// Device clock minus true time.
  int skewMs;
  final disk = MemoryStore();

  /// Starts a new app process.
  Client boot() => Client._(this).._boot();
}

/// One app process on a [Device].
class Client {
  Client._(this.device)
      : store = CrashStore(device.disk),
        clock = HlcClock(
          node: device.world.node(),
          wallMs: () => baseMs + device.world.async.elapsed.inMilliseconds + device.skewMs,
        ),
        backend = MemoryBackend(device.world.server,
            userId: device.userId, random: math.Random(device.world.random.nextInt(1 << 30))) {
    // A dead process sends nothing more either.
    store.onCrash = backend.kill;
  }

  final Device device;
  final CrashStore store;
  final HlcClock clock;
  final MemoryBackend backend;
  late final MemorySession session = MemorySession(backend, displayName: device.name, colorIndex: device.colorIndex);
  final foreground = ValueNotifier(true);
  late final BoardsController controller;
  OpenBoard? board;

  World get world => device.world;

  DateTime now() => DateTime.fromMillisecondsSinceEpoch(baseMs + world.async.elapsed.inMilliseconds + device.skewMs);

  void _boot() {
    controller = BoardsController(store: store, clock: clock, newId: world.newId, now: now);
    controller.currentAccount = () => session.account;
    controller.connectionFactory = (b, c) => BoardSync(
          board: b,
          controller: c,
          backend: backend,
          session: session,
          foreground: foreground,
          random: math.Random(world.random.nextInt(1 << 30)),
          now: now,
        );
    world.wait(controller.load());
  }

  BoardSync get sync => board!.connection as BoardSync;
  BoardEditor get editor => board!.editor;
  BoardDoc get doc => board!.doc;
  SyncState get state => board!.connection.state.value;

  /// The current data channel on the fake server.
  MemoryChannel get channel => backend.channels.last;

  OpenBoard open(String id) {
    board = world.wait(controller.open(id))!;
    world.settle();
    return board!;
  }

  void close() {
    world.wait(controller.release(board!));
    board = null;
  }

  /// The process dies: no more writes, no more network.
  void crash() {
    store.dead = true;
    backend.kill();
    board = null;
  }

  /// The app goes to the background and the socket drops.
  void pause() {
    foreground.value = false;
    backend.suspend();
  }

  void resume() {
    backend.resumeSocket();
    foreground.value = true;
  }

  int count(String call) => backend.calls.where((c) => c == call).length;
}

/// Every client's `(f, h)` equals the server's `(data, fh)`, nothing is
/// pending, every cursor is at the board's rev, and revs have no gaps.
void expectConverged(World w, String boardId, List<Client> clients) {
  final b = w.server.boards[boardId]!;
  expect(b.revLog, List.generate(b.revLog.length, (i) => i + 1), reason: 'revs are gap-free');
  for (final c in clients) {
    final who = '${c.device.name} (${c.clock.node})';
    final doc = c.doc;
    expect(doc.pendingCount, 0, reason: '$who has nothing pending');
    expect(doc.cursor, b.rev, reason: '$who cursor');
    expect(doc.items.keys.toSet(), b.items.keys.toSet(), reason: '$who items');
    for (final e in b.items.entries) {
      final it = doc.items[e.key]!;
      expect(it.kind.name, e.value.kind, reason: '$who ${e.key} kind');
      expect(it.h, e.value.fh, reason: '$who ${e.key} hlcs');
      for (final k in it.f.keys) {
        expect(e.value.fh.containsKey(k), isTrue, reason: '$who ${e.key}.$k has no server hlc');
      }
      for (final k in e.value.fh.keys) {
        // Strokes of deleted ink are not loaded into memory.
        if (k == F.strokes && it.deleted && !it.f.containsKey(k)) continue;
        expect(it.f[k], equals(e.value.data[k]), reason: '$who ${e.key}.$k');
      }
    }
  }
}

/// Turns every fault off and lets the clients heal on their own.
void heal(World w, List<Client> clients, {Duration time = const Duration(minutes: 4)}) {
  for (final c in clients) {
    c.backend
      ..fault = null
      ..lossRate = 0
      ..dropRate = 0
      ..duplicateRate = 0
      ..truncateRate = 0
      ..partialRate = 0
      ..minDelay = Duration.zero
      ..maxDelay = Duration.zero
      ..online = true;
    c.resume();
  }
  w.run(time);
}

T pick<T>(List<T> list, math.Random r) => list[r.nextInt(list.length)];

/// One random edit through the editor, as a user would make it.
void randomEdit(BoardEditor e, math.Random r) {
  final cols = e.columns;
  final cards = [for (final c in cols) ...e.cardsIn(c.id)];
  final canvas = e.canvasItems;
  Offset spot() => Offset(r.nextDouble() * 3000, r.nextDouble() * 2000);
  switch (r.nextInt(16)) {
    case 0 || 1:
      if (cols.isNotEmpty) e.addCard(columnId: pick(cols, r).id, title: 'Kart ${r.nextInt(999)}', top: r.nextBool());
    case 2 || 3:
      if (cards.isNotEmpty && cols.isNotEmpty) {
        e.moveCard(pick(cards, r).id, columnId: pick(cols, r).id, index: r.nextInt(cards.length + 1));
      }
    case 4:
      if (cards.isNotEmpty) {
        e.updateCard(pick(cards, r).id, {
          F.title: 'Başlık ${r.nextInt(999)}',
          if (r.nextBool()) F.notes: 'Not ${r.nextInt(99)}',
          if (r.nextBool()) F.due: '2026-11-${(r.nextInt(28) + 1).toString().padLeft(2, '0')}',
          if (r.nextBool()) F.subtasks: [CardSubtask(id: 's${r.nextInt(9)}', title: 'Alt', done: r.nextBool()).toJson()],
        });
      }
    case 5:
      e.addSticky(at: spot(), text: 'Not ${r.nextInt(99)}', colorIndex: r.nextInt(8));
    case 6:
      if (canvas.isNotEmpty) e.moveTo({pick(canvas, r).id: spot()});
    case 7:
      if (canvas.isNotEmpty) e.updateSticky(pick(canvas, r).id, text: 'Metin ${r.nextInt(99)}');
    case 8:
      if (canvas.isNotEmpty) e.deleteItems({pick(canvas, r).id});
    case 9:
      if (cards.isNotEmpty) e.deleteItems({pick(cards, r).id});
    case 10:
      e.undo();
    case 11:
      e.redo();
    case 12:
      if (cols.length < 6) e.addColumn(title: 'Sütun ${r.nextInt(99)}');
      if (cols.length > 1 && r.nextBool()) e.deleteColumn(pick(cols, r).id);
    case 13:
      e.addInk(origin: spot(), strokes: 'PINK1:${r.nextInt(1 << 20).toRadixString(36)}');
    case 14:
      if (canvas.isNotEmpty) r.nextBool() ? e.bringToFront({pick(canvas, r).id}) : e.sendToBack({pick(canvas, r).id});
    default:
      e.setTitle('Pano ${r.nextInt(99)}');
  }
}

/// A server row stamped far in the future, for direct handler tests.
String futureHlc([int c = 0]) => HlcClock.format(baseMs + 10 * 365 * 86400000, c, 'ffffffffffffffff');
