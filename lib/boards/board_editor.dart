import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'model/board_doc.dart';
import 'model/board_item.dart';
import 'model/hlc.dart';
import 'model/order.dart';

class _FieldUndo {
  _FieldUndo(this.before, this.afterHlc);

  final Object? before;

  /// The HLC this field had right after the edit. Undo applies only while
  /// the field still has it, so teammates' later edits are never reverted.
  String afterHlc;
}

class _UndoEntry {
  final Map<String, Map<String, _FieldUndo>> fields = {};
  final Map<String, ItemKind> kinds = {};

  bool get isEmpty => fields.isEmpty;
}

/// Result of an undo or redo.
class UndoOutcome {
  const UndoOutcome({required this.applied, required this.skipped});

  final bool applied;

  /// Some fields were changed by someone else since, and were left alone.
  final bool skipped;
}

/// All edits to one board go through here: views call the operations below,
/// sync calls [applyRemote] / [applyAcks]. Each operation is one HLC-stamped
/// write group and one undo step, and ends in a single notification.
class BoardEditor extends ChangeNotifier {
  BoardEditor({
    required this.doc,
    required this.clock,
    this.onLocalChange,
    this.onRemoteChange,
    String Function()? newId,
    this.undoLimit = 100,
  }) : _newId = newId ?? const Uuid().v4;

  final BoardDoc doc;
  final HlcClock clock;

  /// Local edit made: persist and push.
  VoidCallback? onLocalChange;

  /// Server data merged: persist only.
  VoidCallback? onRemoteChange;

  final String Function() _newId;
  final int undoLimit;

  String get id => doc.id;
  bool get readOnly => doc.readOnly;

  int _rev = 0;

  /// Bumped on every visible change; derived views and painters key on it.
  int get revision => _rev;

  Set<String> _lastChanged = const {};

  /// Item ids changed by the latest notification (for incremental scenes).
  Set<String> get lastChanged => _lastChanged;

  // ------------------------------------------------------------- batching

  int _depth = 0;
  _UndoEntry? _entry;
  final Set<String> _changed = {};
  bool _local = false;
  bool _remote = false;
  final List<_UndoEntry> _undo = [];
  final List<_UndoEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Runs [fn] as one undo step with one notification.
  T batch<T>(T Function() fn) {
    _depth++;
    try {
      return fn();
    } finally {
      if (--_depth == 0) _commit();
    }
  }

  void _commit() {
    final e = _entry;
    _entry = null;
    if (e != null && !e.isEmpty) {
      _undo.add(e);
      if (_undo.length > undoLimit) _undo.removeAt(0);
      _redo.clear();
    }
    if (_changed.isNotEmpty) {
      _rev++;
      _lastChanged = {..._changed};
      _changed.clear();
      notifyListeners();
    }
    if (_local) {
      _local = false;
      onLocalChange?.call();
    }
    if (_remote) {
      _remote = false;
      onRemoteChange?.call();
    }
  }

  void _write(String id, ItemKind kind, Map<String, Object?> fields, {bool record = true}) {
    if (doc.readOnly || fields.isEmpty) return;
    final existing = doc.items[id];
    final hlc = clock.tick();
    if (record) {
      final entry = _entry ??= _UndoEntry();
      final m = entry.fields.putIfAbsent(id, () => {});
      entry.kinds[id] = kind;
      if (existing == null) {
        // Undoing a creation deletes the item.
        m.putIfAbsent(F.deleted, () => _FieldUndo(true, hlc)).afterHlc = hlc;
      } else {
        for (final k in fields.keys) {
          final prior = m[k];
          if (prior == null) {
            m[k] = _FieldUndo(_clone(existing.f[k]), hlc);
          } else {
            prior.afterHlc = hlc;
          }
        }
      }
    }
    doc.write(id, kind, fields, hlc);
    _changed.add(id);
    _local = true;
  }

  static Object? _clone(Object? v) {
    if (v is List) return [for (final e in v) _clone(e)];
    if (v is Map) return {for (final e in v.entries) e.key: _clone(e.value)};
    return v;
  }

  UndoOutcome undo() => _replay(_undo, _redo);

  UndoOutcome redo() => _replay(_redo, _undo);

  UndoOutcome _replay(List<_UndoEntry> from, List<_UndoEntry> to) {
    if (from.isEmpty || doc.readOnly) return const UndoOutcome(applied: false, skipped: false);
    final e = from.removeLast();
    final back = _UndoEntry();
    var skipped = false;
    for (final MapEntry(key: id, value: fields) in e.fields.entries) {
      final it = doc.items[id];
      if (it == null) continue;
      final changes = <String, Object?>{};
      final befores = <String, Object?>{};
      for (final MapEntry(key: k, value: u) in fields.entries) {
        if (it.h[k] != u.afterHlc) {
          skipped = true;
          continue;
        }
        befores[k] = _clone(it.f[k]);
        changes[k] = _clone(u.before);
      }
      if (changes.isEmpty) continue;
      final hlc = clock.tick();
      doc.write(id, it.kind, changes, hlc);
      back.fields[id] = {for (final k in changes.keys) k: _FieldUndo(befores[k], hlc)};
      back.kinds[id] = it.kind;
      _changed.add(id);
      _local = true;
    }
    if (!back.isEmpty) to.add(back);
    final applied = _changed.isNotEmpty;
    _commitWithoutUndo();
    return UndoOutcome(applied: applied, skipped: skipped);
  }

  void _commitWithoutUndo() {
    if (_changed.isNotEmpty) {
      _rev++;
      _lastChanged = {..._changed};
      _changed.clear();
      notifyListeners();
    }
    if (_local) {
      _local = false;
      onLocalChange?.call();
    }
  }

  // ------------------------------------------------------- remote input

  /// Merges server rows (pull, realtime). Returns whether a field was newer
  /// but missing, in which case the caller should catch up.
  MergeResult applyRemote(Iterable<RemoteRow> rows) {
    final r = doc.merge(rows, clock);
    _changed.addAll(r.changed);
    _remote = true;
    if (_depth == 0) _commit();
    return r;
  }

  Set<String> applyAcks(Map<String, Map<String, String>> sent, Iterable<PushAck> acks) {
    final changed = doc.applyAcks(sent, acks);
    _changed.addAll(changed);
    _remote = true;
    if (_depth == 0) _commit();
    return changed;
  }

  /// Ink stroke blobs arrive after the document loads.
  void attachStrokes(Map<String, String> byItem) {
    for (final e in byItem.entries) {
      final it = doc.items[e.key];
      if (it == null || it.kind != ItemKind.ink) continue;
      it.f[F.strokes] = e.value;
      _changed.add(e.key);
    }
    if (_depth == 0) _commitWithoutUndo();
  }

  /// The document's state or id changed outside an edit (sync transitions).
  void touch() {
    _rev++;
    _lastChanged = const {};
    notifyListeners();
  }

  // --------------------------------------------------------- derived views

  int _viewRev = -1;
  List<BoardItem> _columns = const [];
  Map<String, List<BoardItem>> _byColumn = const {};
  List<BoardItem> _canvas = const [];
  int _cardCount = 0;
  int _doneCount = 0;

  void _derive() {
    if (_viewRev == _rev) return;
    _viewRev = _rev;
    final cols = <BoardItem>[];
    final cards = <BoardItem>[];
    final canvas = <BoardItem>[];
    for (final it in doc.items.values) {
      if (it.deleted) continue;
      switch (it.kind) {
        case ItemKind.column:
          cols.add(it);
        case ItemKind.card:
          cards.add(it);
        case ItemKind.sticky || ItemKind.ink:
          canvas.add(it);
        case ItemKind.meta:
          break;
      }
    }
    int byOrder(BoardItem a, BoardItem b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    cols.sort(byOrder);
    final by = <String, List<BoardItem>>{for (final c in cols) c.id: []};
    final first = cols.isEmpty ? null : cols.first.id;
    var done = 0;
    for (final c in cards) {
      final col = by.containsKey(c.columnId) ? c.columnId! : first;
      if (col == null) continue;
      by[col]!.add(c);
    }
    for (final e in by.entries) {
      e.value.sort(byOrder);
    }
    for (final c in cols) {
      if (c.isDone) done += by[c.id]!.length;
    }
    canvas.sort((a, b) {
      final c = a.z.compareTo(b.z);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    _columns = List.unmodifiable(cols);
    _byColumn = {for (final e in by.entries) e.key: List.unmodifiable(e.value)};
    _canvas = List.unmodifiable(canvas);
    _cardCount = by.values.fold(0, (n, l) => n + l.length);
    _doneCount = done;
  }

  BoardItem? item(String id) => doc.items[id];

  String get title => doc.meta?.title ?? '';
  int get colorIndex => doc.meta?.colorIndex ?? 0;
  Offset get laneOrigin => Offset(doc.meta?.laneX ?? 0, doc.meta?.laneY ?? 0);

  /// Live columns in order.
  List<BoardItem> get columns {
    _derive();
    return _columns;
  }

  /// Live cards of a column in order. Cards whose column is gone show in the
  /// first column (render rule only).
  List<BoardItem> cardsIn(String columnId) {
    _derive();
    return _byColumn[columnId] ?? const [];
  }

  /// The column a card is shown in.
  String? columnOf(String cardId) {
    _derive();
    for (final e in _byColumn.entries) {
      if (e.value.any((c) => c.id == cardId)) return e.key;
    }
    return null;
  }

  bool isDoneColumn(String? columnId) => columnId != null && (doc.items[columnId]?.isDone ?? false);

  /// Live stickies and ink, back to front.
  List<BoardItem> get canvasItems {
    _derive();
    return _canvas;
  }

  int get cardCount {
    _derive();
    return _cardCount;
  }

  int get doneCount {
    _derive();
    return _doneCount;
  }

  double get _maxZ => canvasItems.isEmpty ? 0 : canvasItems.last.z;
  double get _minZ => canvasItems.isEmpty ? 0 : canvasItems.first.z;

  // ----------------------------------------------------------- board meta

  void setTitle(String title) => batch(() {
        if (title != this.title) _write(doc.id, ItemKind.meta, {F.title: title});
      });

  void setColor(int colorIndex) => batch(() {
        if (colorIndex != this.colorIndex) _write(doc.id, ItemKind.meta, {F.colorIndex: colorIndex});
      });

  void setLaneOrigin(Offset o) =>
      batch(() => _write(doc.id, ItemKind.meta, {F.laneX: _clampWorld(o.dx), F.laneY: _clampWorld(o.dy)}));

  static double _clampWorld(double v) => v.clamp(-100000.0, 100000.0);

  // -------------------------------------------------------------- columns

  String addColumn({required String title, int colorIndex = 3, bool isDone = false, String? afterId}) =>
      batch(() {
        final cols = columns;
        final i = afterId == null ? cols.length - 1 : cols.indexWhere((c) => c.id == afterId);
        final before = i >= 0 && i < cols.length ? cols[i].order : null;
        final after = i + 1 < cols.length && i + 1 >= 0 ? cols[i + 1].order : null;
        final id = _newId();
        _write(id, ItemKind.column, {
          F.title: title,
          F.colorIndex: colorIndex,
          F.isDone: isDone,
          F.order: FractionalOrder.between(before, after),
          F.deleted: false,
        });
        return id;
      });

  void updateColumn(String id, {String? title, int? colorIndex, bool? isDone}) => batch(() {
        final c = doc.items[id];
        if (c == null || c.kind != ItemKind.column) return;
        final ch = <String, Object?>{
          if (title != null && title != c.title) F.title: title,
          if (colorIndex != null && colorIndex != c.colorIndex) F.colorIndex: colorIndex,
          if (isDone != null && isDone != c.isDone) F.isDone: isDone,
        };
        _write(id, ItemKind.column, ch);
      });

  /// Moves a column one place left (-1) or right (+1).
  void moveColumn(String id, int direction) => batch(() {
        final cols = columns;
        final i = cols.indexWhere((c) => c.id == id);
        final j = i + direction;
        if (i < 0 || j < 0 || j >= cols.length) return;
        final others = [...cols]..removeAt(i);
        final insertAt = j;
        final before = insertAt - 1 >= 0 ? others[insertAt - 1].order : null;
        final after = insertAt < others.length ? others[insertAt].order : null;
        _placeInSequence(id, ItemKind.column, others, insertAt, before, after);
      });

  /// Deletes a column. Its cards move to the neighbouring column (or are
  /// deleted too when [deleteCards] or when it is the last column).
  void deleteColumn(String id, {bool deleteCards = false}) => batch(() {
        final cols = columns;
        final i = cols.indexWhere((c) => c.id == id);
        if (i < 0) return;
        final cards = cardsIn(id);
        final target = cols.length > 1 ? cols[i == 0 ? 1 : i - 1] : null;
        if (deleteCards || target == null) {
          for (final c in cards) {
            _write(c.id, ItemKind.card, {F.deleted: true});
          }
        } else {
          var last = cardsIn(target.id).isEmpty ? null : cardsIn(target.id).last.order;
          for (final c in cards) {
            final o = FractionalOrder.between(last, null);
            _write(c.id, ItemKind.card, {F.columnId: target.id, F.order: o});
            last = o;
          }
        }
        _write(id, ItemKind.column, {F.deleted: true});
      });

  // ---------------------------------------------------------------- cards

  String addCard({
    required String columnId,
    required String title,
    String notes = '',
    String? due,
    int colorIndex = 3,
    bool top = false,
  }) =>
      batch(() {
        final list = cardsIn(columnId);
        final order = list.isEmpty
            ? FractionalOrder.step
            : top
                ? FractionalOrder.between(null, list.first.order)
                : FractionalOrder.between(list.last.order, null);
        final id = _newId();
        _write(id, ItemKind.card, {
          F.title: title,
          F.notes: notes,
          F.columnId: columnId,
          F.order: order,
          F.due: due,
          F.subtasks: const <Object?>[],
          F.colorIndex: colorIndex,
          F.assigneeId: null,
          F.deleted: false,
        });
        return id;
      });

  /// Moves a card to [index] in [columnId] (index among the other cards).
  void moveCard(String id, {required String columnId, required int index}) => batch(() {
        final card = doc.items[id];
        if (card == null || card.kind != ItemKind.card || doc.items[columnId]?.kind != ItemKind.column) return;
        final others = [for (final c in cardsIn(columnId)) if (c.id != id) c];
        final at = index.clamp(0, others.length);
        final before = at - 1 >= 0 ? others[at - 1].order : null;
        final after = at < others.length ? others[at].order : null;
        final sameColumn = columnOf(id) == columnId && card.columnId == columnId;
        if (sameColumn) {
          final cur = cardsIn(columnId);
          final curIndex = cur.indexWhere((c) => c.id == id);
          if (curIndex == at) return;
        }
        _placeInSequence(id, ItemKind.card, others, at, before, after,
            extra: sameColumn ? const {} : {F.columnId: columnId});
      });

  /// Writes an order between [before] and [after], renormalising the
  /// sequence first when there is no room left.
  void _placeInSequence(String id, ItemKind kind, List<BoardItem> others, int at, double? before, double? after,
      {Map<String, Object?> extra = const {}}) {
    if (before != null && after != null && FractionalOrder.exhausted(before, after)) {
      final spaced = FractionalOrder.spaced(others.length + 1);
      var k = 0;
      for (var i = 0; i < others.length; i++) {
        if (i == at) k++;
        _write(others[i].id, kind, {F.order: spaced[k++]});
      }
      before = at - 1 >= 0 ? spaced[at - 1] : null;
      after = at < others.length ? spaced[at + 1] : null;
    }
    _write(id, kind, {...extra, F.order: FractionalOrder.between(before, after)});
  }

  /// Saves the card sheet: only fields that changed, in one write.
  void updateCard(String id, Map<String, Object?> fields) => batch(() {
        final c = doc.items[id];
        if (c == null || c.kind != ItemKind.card) return;
        final ch = <String, Object?>{
          for (final e in fields.entries)
            if (!_same(c.f[e.key], e.value)) e.key: e.value,
        };
        _write(id, ItemKind.card, ch);
      });

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_same(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is num && b is num) return a == b;
    return a == b;
  }

  // ------------------------------------------------------ stickies & ink

  String addSticky({required Offset at, String text = '', int colorIndex = 5}) => batch(() {
        final id = _newId();
        _write(id, ItemKind.sticky, {
          F.x: _clampWorld(at.dx),
          F.y: _clampWorld(at.dy),
          F.z: _maxZ + 1,
          F.text: text,
          F.colorIndex: colorIndex,
          F.deleted: false,
        });
        return id;
      });

  void updateSticky(String id, {String? text, int? colorIndex}) => batch(() {
        final s = doc.items[id];
        if (s == null || s.kind != ItemKind.sticky) return;
        _write(id, ItemKind.sticky, {
          if (text != null && text != s.text) F.text: text,
          if (colorIndex != null && colorIndex != s.colorIndex) F.colorIndex: colorIndex,
        });
      });

  /// Adds one pen stroke. [strokes] is an InkCodec string whose points are
  /// relative to [origin].
  String addInk({required Offset origin, required String strokes}) => batch(() {
        final id = _newId();
        _write(id, ItemKind.ink, {
          F.x: _clampWorld(origin.dx),
          F.y: _clampWorld(origin.dy),
          F.z: _maxZ + 1,
          F.strokes: strokes,
          F.deleted: false,
        });
        return id;
      });

  /// Sets absolute positions of stickies and ink (cards are laid out).
  void moveTo(Map<String, Offset> positions) => batch(() {
        for (final e in positions.entries) {
          final it = doc.items[e.key];
          if (it == null || (it.kind != ItemKind.sticky && it.kind != ItemKind.ink)) continue;
          final x = _clampWorld(e.value.dx), y = _clampWorld(e.value.dy);
          if (x == it.x && y == it.y) continue;
          _write(e.key, it.kind, {F.x: x, F.y: y});
        }
      });

  void setColorOf(Set<String> ids, int colorIndex) => batch(() {
        for (final id in ids) {
          final it = doc.items[id];
          if (it == null || it.kind == ItemKind.meta || it.colorIndex == colorIndex) continue;
          _write(id, it.kind, {F.colorIndex: colorIndex});
        }
      });

  void bringToFront(Set<String> ids) => batch(() {
        var z = _maxZ;
        for (final it in canvasItems.where((i) => ids.contains(i.id)).toList()) {
          _write(it.id, it.kind, {F.z: ++z});
        }
      });

  void sendToBack(Set<String> ids) => batch(() {
        var z = _minZ;
        for (final it in canvasItems.where((i) => ids.contains(i.id)).toList().reversed) {
          _write(it.id, it.kind, {F.z: --z});
        }
      });

  void deleteItems(Set<String> ids) => batch(() {
        for (final id in ids) {
          final it = doc.items[id];
          if (it == null || it.kind == ItemKind.meta || it.deleted) continue;
          if (it.kind == ItemKind.column) {
            deleteColumn(id);
          } else {
            _write(id, it.kind, {F.deleted: true});
          }
        }
      });

  /// Copies stickies and ink 24 units down-right; returns the new ids.
  List<String> duplicate(Set<String> ids) => batch(() {
        final out = <String>[];
        for (final it in canvasItems.where((i) => ids.contains(i.id)).toList()) {
          final at = Offset(it.x + 24, it.y + 24);
          if (it.kind == ItemKind.sticky) {
            out.add(addSticky(at: at, text: it.text, colorIndex: it.colorIndex));
          } else if (it.kind == ItemKind.ink && it.strokes != null) {
            out.add(addInk(origin: at, strokes: it.strokes!));
          }
        }
        return out;
      });

  /// Turns a sticky into a card in [columnId]: first line is the title, the
  /// rest the description. One undo step.
  String? stickyToCard(String stickyId, String columnId) => batch(() {
        final s = doc.items[stickyId];
        if (s == null || s.kind != ItemKind.sticky) return null;
        final lines = s.text.trim().split('\n');
        final id = addCard(
          columnId: columnId,
          title: lines.first.trim(),
          notes: lines.skip(1).join('\n').trim(),
          colorIndex: s.colorIndex,
        );
        _write(stickyId, ItemKind.sticky, {F.deleted: true});
        return id;
      });

  // -------------------------------------------------------------- creation

  /// Fills a brand-new board document (meta and default columns). Not
  /// undoable.
  void initialize({required String title, required int colorIndex, List<(String, int, bool)> columns = const []}) {
    var order = 0.0;
    final hlc = clock.tick();
    doc.write(doc.id, ItemKind.meta, {F.title: title, F.colorIndex: colorIndex, F.laneX: 0.0, F.laneY: 0.0}, hlc);
    for (final (t, c, done) in columns) {
      order += FractionalOrder.step;
      doc.write(_newId(), ItemKind.column,
          {F.title: t, F.colorIndex: c, F.isDone: done, F.order: order, F.deleted: false}, clock.tick());
    }
    _rev++;
    _lastChanged = {for (final id in doc.items.keys) id};
  }
}
