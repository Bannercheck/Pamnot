import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/store.dart';
import '../l10n/strings.dart';
import 'board_editor.dart';
import 'boards_repository.dart';
import 'connection.dart';
import 'model/board_doc.dart';
import 'model/board_item.dart';
import 'model/hlc.dart';

enum BoardTemplate {
  /// Yapılacak · Yapılıyor · Bitti.
  tasks,

  /// No columns: a free canvas.
  blank,
}

/// An open board: its editor and its live connection.
class OpenBoard {
  OpenBoard(this.editor, this.connection);

  final BoardEditor editor;
  BoardConnection connection;
  int _refs = 0;

  String get id => editor.doc.id;
  BoardDoc get doc => editor.doc;
}

/// Creates the live connection for a shared board whose account matches the
/// current session (wired up in main.dart with BoardSync).
typedef BoardConnectionFactory = BoardConnection Function(OpenBoard board, BoardsController controller);

/// The list of boards plus opening, creating, seeding and persisting them.
/// Board content changes go through [BoardEditor]; this class persists them
/// and keeps the list summaries fresh.
class BoardsController extends ChangeNotifier {
  BoardsController({
    required KeyValueStore store,
    HlcClock? clock,
    String Function()? newId,
    DateTime Function()? now,
    Duration saveDelay = const Duration(milliseconds: 400),
  })  : repo = BoardsRepository(store, saveDelay: saveDelay),
        clock = clock ?? HlcClock(),
        _newId = newId ?? const Uuid().v4,
        _now = now ?? DateTime.now;

  final BoardsRepository repo;
  final HlcClock clock;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Set by the cloud wiring; null while collaboration is off.
  BoardConnectionFactory? connectionFactory;

  /// The signed-in collaboration account, or null.
  BoardAccount? Function() currentAccount = () => null;

  final Map<String, BoardSummary> _summaries = {};
  final Map<String, OpenBoard> _open = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Boards to list: device-only ones and shared ones of the current account,
  /// most recently changed first.
  List<BoardSummary> get boards {
    final acc = currentAccount();
    final list = _summaries.values.where((b) => b.account == null || b.account == acc).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  BoardSummary? summary(String id) => _summaries[id];

  int get clockOffsetMs => clock.offsetMs;

  set clockOffsetMs(int v) {
    if (v == clock.offsetMs) return;
    clock.offsetMs = v;
    _saveIndex();
  }

  Future<void> load() async {
    final (list, offset) = await repo.loadIndex();
    clock.offsetMs = offset;
    _summaries
      ..clear()
      ..addEntries(list.map((b) => MapEntry(b.id, b)));
    _loaded = true;
    notifyListeners();
  }

  void _saveIndex() => repo.saveIndex(_summaries.values.toList(), clock.offsetMs);

  Timer? _notifyTimer;

  void _summarize(BoardDoc doc) {
    _summaries[doc.id] = BoardSummary.of(doc, _now());
    _saveIndex();
    // Edits can arrive many times a second (ink, remote rows); the list only
    // needs to catch up a few times a second.
    _notifyTimer ??= Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  /// Persists a board after a change.
  void persist(BoardDoc doc) {
    repo.saveBoard(doc);
    _summarize(doc);
  }

  // ------------------------------------------------------------- creating

  Future<String> createBoard({
    required String title,
    required int colorIndex,
    required BoardTemplate template,
    required S strings,
  }) async {
    final id = _newId();
    final doc = BoardDoc(id: id);
    final editor = BoardEditor(doc: doc, clock: clock, newId: _newId);
    editor.initialize(
      title: title,
      colorIndex: colorIndex,
      columns: template == BoardTemplate.tasks ? defaultColumns(strings) : const [],
    );
    persist(doc);
    await repo.flush();
    return id;
  }

  static List<(String, int, bool)> defaultColumns(S s) => [
        (s.pick('Yapılacak', 'To do'), 3, false),
        (s.pick('Yapılıyor', 'Doing'), 5, false),
        (s.pick('Bitti', 'Done'), 2, true),
      ];

  /// The first-run example board. Device-only, never uploaded by itself.
  Future<String> seedSample(S s) async {
    final id = _newId();
    final doc = BoardDoc(id: id);
    final e = BoardEditor(doc: doc, clock: clock, newId: _newId);
    e.initialize(title: s.pick('İlk panom 🌷', 'My first board 🌷'), colorIndex: 3, columns: defaultColumns(s));
    final cols = e.columns;
    e.addCard(columnId: cols[0].id, title: s.pick('Bu kartı Yapılıyor sütununa taşı', 'Move this card to Doing'));
    final c2 = e.addCard(
      columnId: cols[0].id,
      title: s.pick('Karta dokun: tarih ve alt görev ekle', 'Tap a card to add a date and subtasks'),
      due: dueKey(_now().add(const Duration(days: 1))),
      colorIndex: 1,
    );
    e.updateCard(c2, {
      F.subtasks: [
        CardSubtask(id: _newId(), title: s.pick('Tarih seç', 'Pick a date')).toJson(),
        CardSubtask(id: _newId(), title: s.pick('Renk değiştir', 'Change the colour')).toJson(),
      ],
    });
    e.addCard(columnId: cols[1].id, title: s.pick('Tuval ile Kanban arasında geçiş yap', 'Switch between Canvas and Kanban'), colorIndex: 4);
    e.addCard(columnId: cols[2].id, title: s.pick('Panoyu aç ✓', 'Open the board ✓'), colorIndex: 2);
    // Lanes start at (0, 0) and are 3 × 300 + 2 × 24 = 948 wide.
    e.addSticky(at: const Offset(1010, 0), text: s.pick('Fikirlerini yapışkan notlara yaz 💡', 'Write ideas on sticky notes 💡'), colorIndex: 5);
    e.addSticky(at: const Offset(1010, 230), text: s.pick('Apple Pencil ile çiz, ok çek, daire içine al ✏️', 'Draw with Apple Pencil: arrows, circles ✏️'), colorIndex: 1);
    e.addSticky(at: const Offset(1240, 115), text: s.pick('Hazır olunca bu örnek panoyu silebilirsin 🌸', 'Delete this sample board when you are ready 🌸'), colorIndex: 4);
    doc.clearDirty();
    persist(doc);
    await repo.flush();
    return id;
  }

  // -------------------------------------------------------------- opening

  /// Opens a board (or returns the already-open one). Pair with [release].
  Future<OpenBoard?> open(String id) async {
    final existing = _open[id];
    if (existing != null) {
      existing._refs++;
      return existing;
    }
    final doc = await repo.loadBoard(id);
    if (doc == null) return null;
    doc.observeAll(clock);
    final editor = BoardEditor(doc: doc, clock: clock, newId: _newId);
    final board = OpenBoard(editor, LocalConnection()).._refs = 1;
    editor.onLocalChange = () {
      persist(doc);
      board.connection.kick();
    };
    editor.onRemoteChange = () => persist(doc);
    _open[id] = board;
    final placeholder = board.connection;
    board.connection = _connectionFor(board);
    if (!identical(placeholder, board.connection)) unawaited(placeholder.close());
    // Deleted ink is not drawn, but strokes that were never pushed must
    // still be loaded or they could never leave the outbox.
    final inkIds = [
      for (final it in doc.items.values)
        if (it.kind == ItemKind.ink && (!it.deleted || it.d.contains(F.strokes))) it.id,
    ];
    if (inkIds.isNotEmpty) {
      unawaited(repo.loadInk(inkIds).then((ink) {
        if (_open[board.id] == board) editor.attachStrokes(ink);
      }));
    }
    return board;
  }

  OpenBoard? openBoard(String id) => _open[id];

  Future<void> release(OpenBoard board) async {
    if (--board._refs > 0) return;
    _open.remove(board.id);
    await board.connection.close();
    await repo.flush();
  }

  BoardConnection _connectionFor(OpenBoard board) {
    final f = connectionFactory;
    final acc = currentAccount();
    if (f != null && board.doc.isShared && acc != null && board.doc.account == acc) return f(board, this);
    return LocalConnection();
  }

  /// Re-creates connections after sign-in, sign-out or a server change.
  Future<void> refreshConnections() async {
    for (final b in _open.values) {
      final old = b.connection;
      await old.close();
      b.connection = _connectionFor(b);
      b.editor.touch();
    }
    notifyListeners();
  }

  // ---------------------------------------------------- sharing lifecycle

  /// Marks a device-only board for upload under [account] (one atomic
  /// write); the sync engine then creates it on the server and pushes.
  Future<void> beginUpload(String id, BoardAccount account) async {
    final board = await open(id);
    if (board == null) return;
    try {
      board.doc.prepareUpload(account);
      persist(board.doc);
      await repo.flush();
      await refreshConnections();
    } finally {
      await release(board);
    }
  }

  /// Gives a board a new id after an id collision on upload.
  Future<String> remint(String oldId) async {
    final newId = _newId();
    final board = _open.remove(oldId);
    final doc = board?.doc ?? await repo.loadBoard(oldId);
    if (doc == null) return oldId;
    final view = await repo.loadView(oldId);
    doc.remint(newId);
    _summaries.remove(oldId);
    if (view != null) repo.saveView(newId, view);
    if (board != null) _open[newId] = board;
    persist(doc);
    // The new document is on disk before the old one goes, so a crash in
    // between keeps the board.
    await repo.flush();
    await repo.deleteBoard(oldId, const []);
    board?.editor.touch();
    return newId;
  }

  /// Adds a board this device just joined (server data arrives by sync).
  Future<void> addJoined({required String boardId, required String title, required BoardAccount account}) async {
    if (_summaries.containsKey(boardId)) return;
    final doc = BoardDoc(id: boardId, state: BoardState.shared, account: account);
    // Title placeholder until the meta row arrives; not dirty, so it is
    // never pushed.
    doc.items[boardId] = BoardItem(id: boardId, kind: ItemKind.meta, f: {F.title: title});
    persist(doc);
    await repo.flush();
  }

  /// Sync moved the board to deleted / revoked / shared.
  void stateChanged(BoardDoc doc) {
    persist(doc);
    _open[doc.id]?.editor.touch();
  }

  /// Keeps a device-only copy of a deleted or revoked shared board.
  Future<String?> saveLocalCopy(String id) async {
    final doc = await repo.loadBoard(id);
    if (doc == null) return null;
    final copy = BoardDoc(id: _newId());
    for (final it in doc.items.values) {
      if (it.deleted) continue;
      final nid = it.kind == ItemKind.meta ? copy.id : it.id;
      copy.items[nid] = BoardItem(id: nid, kind: it.kind, f: {...it.f}, h: {...it.h});
    }
    final ink = await repo.loadInk([for (final it in copy.items.values) if (it.kind == ItemKind.ink) it.id]);
    for (final e in ink.entries) {
      copy.items[e.key]?.f[F.strokes] = e.value;
    }
    persist(copy);
    await repo.flush();
    return copy.id;
  }

  /// Removes a board from this device only.
  Future<void> removeLocal(String id) async {
    final board = _open.remove(id);
    await board?.connection.close();
    final doc = board?.doc ?? await repo.loadBoard(id);
    final inkIds = [if (doc != null) for (final it in doc.items.values) if (it.kind == ItemKind.ink) it.id];
    _summaries.remove(id);
    await repo.deleteBoard(id, inkIds);
    _saveIndex();
    notifyListeners();
  }

  Future<BoardViewState?> loadView(String id) => repo.loadView(id);

  void saveView(String id, BoardViewState v) => repo.saveView(id, v);

  Future<void> flush() => repo.flush();

  @override
  void dispose() {
    _notifyTimer?.cancel();
    repo.dispose();
    super.dispose();
  }
}
