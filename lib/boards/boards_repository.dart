import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'model/board_doc.dart';
import 'model/board_item.dart';

/// List entry for a board, kept in `boards_index` so the list never loads
/// whole boards.
class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.title,
    required this.colorIndex,
    required this.state,
    required this.updatedAt,
    this.account,
    this.columns = const [],
    this.cardCount = 0,
    this.doneCount = 0,
    this.canvasCount = 0,
  });

  final String id;
  final String title;
  final int colorIndex;
  final BoardState state;
  final DateTime updatedAt;
  final BoardAccount? account;

  /// (title, colorIndex, cards, isDone) for the first columns.
  final List<(String, int, int, bool)> columns;
  final int cardCount;
  final int doneCount;

  /// Stickies and ink.
  final int canvasCount;

  bool get shared => state != BoardState.local;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'color': colorIndex,
        'state': state.name,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        if (account != null) 'account': account!.toJson(),
        'columns': [for (final (t, c, n, d) in columns) [t, c, n, d]],
        'cards': cardCount,
        'done': doneCount,
        'canvas': canvasCount,
      };

  static BoardSummary? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return BoardSummary(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      colorIndex: (j['color'] as num?)?.toInt() ?? 0,
      state: boardStateFromName(j['state'] as String?),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((j['updatedAt'] as num?)?.toInt() ?? 0),
      account: BoardAccount.fromJson(j['account']),
      columns: [
        for (final c in ((j['columns'] as List?) ?? const []))
          if (c is List && c.length == 4)
            ((c[0] as String?) ?? '', (c[1] as num?)?.toInt() ?? 0, (c[2] as num?)?.toInt() ?? 0, c[3] == true),
      ],
      cardCount: (j['cards'] as num?)?.toInt() ?? 0,
      doneCount: (j['done'] as num?)?.toInt() ?? 0,
      canvasCount: (j['canvas'] as num?)?.toInt() ?? 0,
    );
  }

  static BoardSummary of(BoardDoc doc, DateTime now) {
    final cols = [
      for (final it in doc.items.values)
        if (it.kind == ItemKind.column && !it.deleted) it,
    ]..sort((a, b) {
        final c = a.order.compareTo(b.order);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final colIds = {for (final c in cols) c.id};
    final counts = <String, int>{for (final c in cols) c.id: 0};
    var cards = 0, canvas = 0;
    for (final it in doc.items.values) {
      if (it.deleted) continue;
      if (it.kind == ItemKind.card) {
        cards++;
        final col = colIds.contains(it.columnId) ? it.columnId! : (cols.isEmpty ? null : cols.first.id);
        if (col != null) counts[col] = counts[col]! + 1;
      } else if (it.kind == ItemKind.sticky || it.kind == ItemKind.ink) {
        canvas++;
      }
    }
    final done = cols.where((c) => c.isDone).fold(0, (n, c) => n + counts[c.id]!);
    return BoardSummary(
      id: doc.id,
      title: doc.meta?.title ?? '',
      colorIndex: doc.meta?.colorIndex ?? 0,
      state: doc.state,
      updatedAt: now,
      account: doc.account,
      columns: [for (final c in cols.take(6)) (c.title, c.colorIndex, counts[c.id]!, c.isDone)],
      cardCount: cards,
      doneCount: done,
      canvasCount: canvas,
    );
  }
}

/// This device's way of looking at a board; never synced.
class BoardViewState {
  const BoardViewState({required this.view, this.offset = Offset.zero, this.scale = 1, this.fitted = false});

  /// 'canvas' or 'kanban'.
  final String view;
  final Offset offset;
  final double scale;

  /// The canvas was zoomed to fit once already.
  final bool fitted;

  BoardViewState copyWith({String? view, Offset? offset, double? scale, bool? fitted}) => BoardViewState(
        view: view ?? this.view,
        offset: offset ?? this.offset,
        scale: scale ?? this.scale,
        fitted: fitted ?? this.fitted,
      );

  Map<String, Object?> toJson() => {'view': view, 'ox': offset.dx, 'oy': offset.dy, 'scale': scale, 'fitted': fitted};

  static BoardViewState? fromJson(Object? j) {
    if (j is! Map) return null;
    return BoardViewState(
      view: j['view'] == 'kanban' ? 'kanban' : 'canvas',
      offset: Offset((j['ox'] as num?)?.toDouble() ?? 0, (j['oy'] as num?)?.toDouble() ?? 0),
      scale: (j['scale'] as num?)?.toDouble() ?? 1,
      fitted: j['fitted'] == true,
    );
  }
}

/// Reads and writes boards in the KeyValueStore:
/// `boards_index`, `board_<id>`, `boardink_<itemId>`, `board_view_<id>`.
class BoardsRepository {
  BoardsRepository(this.store, {this.saveDelay = const Duration(milliseconds: 400)});

  final KeyValueStore store;
  final Duration saveDelay;

  static String docKey(String id) => 'board_$id';
  static String inkKey(String itemId) => 'boardink_$itemId';
  static String viewKey(String id) => 'board_view_$id';
  static const indexKey = 'boards_index';

  /// Ink blobs already on disk, so each is written once.
  final Set<String> _inkWritten = {};
  final Map<String, BoardDoc> _pendingDocs = {};
  final Map<String, BoardViewState> _pendingViews = {};
  Map<String, Object?>? _pendingIndex;
  Timer? _timer;
  Timer? _maxTimer;
  Future<void>? _writing;

  Future<(List<BoardSummary>, int)> loadIndex() async {
    final raw = await store.read(indexKey);
    if (raw == null) return (const <BoardSummary>[], 0);
    try {
      final j = jsonDecode(raw) as Map;
      return (
        [for (final b in ((j['boards'] as List?) ?? const [])) ?BoardSummary.fromJson(b)],
        (j['clockOffsetMs'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('boards_index unreadable: $e');
      return (const <BoardSummary>[], 0);
    }
  }

  void saveIndex(List<BoardSummary> boards, int clockOffsetMs) {
    _pendingIndex = {'v': 1, 'clockOffsetMs': clockOffsetMs, 'boards': [for (final b in boards) b.toJson()]};
    _schedule();
  }

  Future<BoardDoc?> loadBoard(String id) async {
    final raw = await store.read(docKey(id));
    if (raw == null) return null;
    try {
      return BoardDoc.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('Board $id unreadable: $e');
      return null;
    }
  }

  /// Loads the strokes of every ink item, in parallel batches.
  Future<Map<String, String>> loadInk(Iterable<String> itemIds) async {
    final out = <String, String>{};
    final ids = itemIds.toList();
    for (var i = 0; i < ids.length; i += 64) {
      final chunk = ids.sublist(i, i + 64 > ids.length ? ids.length : i + 64);
      final values = await Future.wait(chunk.map((id) => store.read(inkKey(id))));
      for (var k = 0; k < chunk.length; k++) {
        final v = values[k];
        if (v != null) {
          out[chunk[k]] = v;
          _inkWritten.add(chunk[k]);
        }
      }
    }
    return out;
  }

  Future<BoardViewState?> loadView(String id) async {
    final raw = await store.read(viewKey(id));
    if (raw == null) return null;
    try {
      return BoardViewState.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void saveView(String id, BoardViewState v) {
    _pendingViews[id] = v;
    _schedule();
  }

  void saveBoard(BoardDoc doc) {
    _pendingDocs[doc.id] = doc;
    _schedule();
  }

  Future<void> deleteBoard(String id, Iterable<String> inkIds) async {
    _pendingDocs.remove(id);
    _pendingViews.remove(id);
    await store.delete(docKey(id));
    await store.delete(viewKey(id));
    for (final i in inkIds) {
      await store.delete(inkKey(i));
      _inkWritten.remove(i);
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(flush()));
    // A steady stream of changes (a teammate drawing, a burst of realtime
    // rows) must not postpone the save forever.
    _maxTimer ??= Timer(saveDelay * 5, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    _maxTimer?.cancel();
    _maxTimer = null;
    while (_writing != null) {
      await _writing;
    }
    if (_pendingDocs.isEmpty && _pendingViews.isEmpty && _pendingIndex == null) return;
    final docs = {..._pendingDocs};
    final views = {..._pendingViews};
    final index = _pendingIndex;
    _pendingDocs.clear();
    _pendingViews.clear();
    _pendingIndex = null;
    final done = Completer<void>();
    _writing = done.future;
    try {
      for (final doc in docs.values) {
        // Ink first: a document never points at strokes that are not on disk.
        for (final it in doc.items.values) {
          if (it.kind != ItemKind.ink || _inkWritten.contains(it.id)) continue;
          final s = it.strokes;
          if (s == null) continue;
          await store.write(inkKey(it.id), s);
          _inkWritten.add(it.id);
        }
        await store.write(docKey(doc.id), jsonEncode(doc.toJson()));
      }
      for (final e in views.entries) {
        await store.write(viewKey(e.key), jsonEncode(e.value.toJson()));
      }
      if (index != null) await store.write(indexKey, jsonEncode(index));
    } catch (e) {
      debugPrint('Board save failed, retrying: $e');
      for (final d in docs.values) {
        _pendingDocs.putIfAbsent(d.id, () => d);
      }
      for (final e in views.entries) {
        _pendingViews.putIfAbsent(e.key, () => e.value);
      }
      _pendingIndex ??= index;
      _timer = Timer(const Duration(seconds: 3), () => unawaited(flush()));
    } finally {
      _writing = null;
      done.complete();
    }
  }

  void dispose() {
    _timer?.cancel();
    _maxTimer?.cancel();
  }
}

