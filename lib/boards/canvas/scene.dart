import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../models/ink.dart';
import '../board_editor.dart';
import '../model/board_item.dart';
import 'board_text.dart';
import 'lanes.dart';

/// The render model of one item: its live [BoardItem] plus what painting and
/// hit-testing need (bounds, decoded stroke, fitted text size).
class SceneItem {
  SceneItem(this.item);

  BoardItem item;
  String get id => item.id;
  ItemKind get kind => item.kind;

  /// Canvas bounds.
  Rect bounds = Rect.zero;
  double z = 0;

  // Ink: the one stroke, points relative to (item.x, item.y).
  InkStroke? stroke;
  String? _src;

  /// x, y pairs for the polyline drawn until the outline is built.
  Float32List? polyline;

  // Sticky: fitted font size for [fitText] (0 = not fitted yet).
  double fit = 0;
  String? fitText;

  // Card.
  String? columnId;
  bool done = false;
  bool hasMeta = false;

  /// Title line widths, for greek bars at overview zoom.
  List<double> lines = const [];

  Offset get origin => Offset(item.x, item.y);
}

enum HitKind { none, free, card, laneHeader }

class SceneHit {
  const SceneHit(this.kind, {this.id, this.columnId});

  static const none = SceneHit(HitKind.none);

  final HitKind kind;

  /// Item id for [HitKind.free] and [HitKind.card].
  final String? id;

  /// Column of a card or lane header.
  final String? columnId;

  bool get isItem => kind == HitKind.free || kind == HitKind.card;

  bool sameTarget(SceneHit o) => o.kind == kind && o.id == id && o.columnId == columnId;
}

class _CardMeasure {
  const _CardMeasure(this.title, this.done, this.meta, this.color, this.height, this.lines);

  final String title;
  final bool done;
  final bool meta;
  final Color color;
  final double height;
  final List<double> lines;
}

/// The canvas' derived view of a board, kept in step with [BoardEditor]
/// incrementally: each editor notification touches only the items in
/// [BoardEditor.lastChanged] (the lane block is re-laid out from cached card
/// heights when a card, column or the board origin changed).
class BoardScene extends ChangeNotifier {
  BoardScene(this.editor, {required this.text, this.placeholder = ''});

  final BoardEditor editor;
  final BoardTextCache text;

  /// Shown (and measured) for a card with no title.
  String placeholder;

  /// Card title colours (theme); the measured painters are reused for
  /// painting, so they are laid out in the colour they are drawn in.
  Color textColor = const Color(0xFF3E3A4A);
  Color mutedColor = const Color(0xFF7A7488);

  int _revision = 0;
  LaneLayout _lanes = LaneLayout.empty;
  final Map<String, SceneItem> _cards = {};
  final Map<String, SceneItem> _free = {};
  List<SceneItem> _ordered = const [];
  final Map<String, _CardMeasure> _measures = {};
  Rect? _bounds;

  /// Bumped once per applied change.
  int get revision => _revision;
  LaneLayout get lanes => _lanes;

  /// Stickies and ink, back to front.
  List<SceneItem> get free => _ordered;
  Iterable<SceneItem> get cards => _cards.values;
  int get itemCount => _cards.length + _free.length;
  bool get isEmpty => _lanes.isEmpty && _free.isEmpty;

  SceneItem? byId(String id) => _free[id] ?? _cards[id];

  /// Union of the lane block and every sticky and stroke.
  Rect get contentBounds {
    final cached = _bounds;
    if (cached != null) return cached;
    Rect? r = _lanes.isEmpty ? null : _lanes.bounds;
    for (final si in _ordered) {
      r = r == null ? si.bounds : r.expandToInclude(si.bounds);
    }
    return _bounds = r ?? Rect.zero;
  }

  /// Builds everything from the editor (first open, or an unknown change).
  void rebuild() {
    _free.clear();
    for (final it in editor.canvasItems) {
      _free[it.id] = _makeFree(it);
    }
    _ordered = [for (final it in editor.canvasItems) _free[it.id]!];
    _layoutLanes();
    _bounds = null;
    _revision++;
    notifyListeners();
  }

  /// Applies the editor's latest change.
  void sync() {
    final changed = editor.lastChanged;
    if (changed.isEmpty) {
      // touch(): state or id changed outside an edit.
      rebuild();
      return;
    }
    var lanesDirty = false, orderDirty = false;
    for (final id in changed) {
      final it = editor.item(id);
      if (it == null) {
        if (_free.remove(id) != null) orderDirty = true;
        if (_cards.containsKey(id)) lanesDirty = true;
        continue;
      }
      switch (it.kind) {
        case ItemKind.meta || ItemKind.column || ItemKind.card:
          lanesDirty = true;
        case ItemKind.sticky || ItemKind.ink:
          final existing = _free[id];
          if (it.deleted) {
            if (existing != null) {
              _free.remove(id);
              orderDirty = true;
            }
          } else if (existing == null) {
            _free[id] = _makeFree(it);
            orderDirty = true;
          } else {
            if (existing.z != it.z) orderDirty = true;
            _updateFree(existing, it);
          }
      }
    }
    if (lanesDirty) _layoutLanes();
    if (orderDirty) _ordered = [for (final it in editor.canvasItems) ?_free[it.id]];
    _bounds = null;
    _revision++;
    notifyListeners();
  }

  SceneItem _makeFree(BoardItem it) {
    final si = SceneItem(it);
    _updateFree(si, it);
    return si;
  }

  void _updateFree(SceneItem si, BoardItem it) {
    si.item = it;
    si.z = it.z;
    if (it.kind == ItemKind.ink) {
      final src = it.strokes;
      if (src != si._src) {
        si._src = src;
        final strokes = src == null ? const <InkStroke>[] : InkCodec.decode(src);
        final s = strokes.isEmpty ? null : strokes.first;
        si.stroke = s;
        if (s != null) {
          final xy = Float32List(s.length * 2);
          for (var i = 0; i < s.length; i++) {
            xy[i * 2] = s.x(i);
            xy[i * 2 + 1] = s.y(i);
          }
          si.polyline = xy;
        } else {
          si.polyline = null;
        }
      }
      // Strokes load after the document: until then a dot holds the place.
      final b = si.stroke?.bounds ?? const Rect.fromLTWH(0, 0, 1, 1);
      si.bounds = b.shift(Offset(it.x, it.y));
    } else {
      si.bounds = Rect.fromLTWH(it.x, it.y, StickyMetrics.size, StickyMetrics.size);
    }
  }

  void _layoutLanes() {
    final data = <(String, List<(String, double)>)>[];
    final seen = <String>{};
    for (final col in editor.columns) {
      final done = col.isDone;
      final list = <(String, double)>[];
      for (final card in editor.cardsIn(col.id)) {
        final m = _measure(card, done);
        list.add((card.id, m.height));
        final si = _cards[card.id] ??= SceneItem(card);
        si
          ..item = card
          ..columnId = col.id
          ..done = done
          ..hasMeta = m.meta
          ..lines = m.lines;
        seen.add(card.id);
      }
      data.add((col.id, list));
    }
    _cards.removeWhere((id, _) => !seen.contains(id));
    _measures.removeWhere((id, _) => !seen.contains(id));
    _lanes = LaneLayout.compute(editor.laneOrigin, data);
    for (final si in _cards.values) {
      si.bounds = _lanes.cardRect(si.id) ?? Rect.zero;
    }
  }

  static bool cardHasMeta(BoardItem card) =>
      card.due != null ||
      card.notes.isNotEmpty ||
      card.assigneeId != null ||
      (card.f[F.subtasks] is List && (card.f[F.subtasks] as List).isNotEmpty);

  /// Card height from its title at the canvas title style (max 3 lines);
  /// re-measured only when the title, done state or meta row changes.
  _CardMeasure _measure(BoardItem card, bool done) {
    final title = card.title.isEmpty ? placeholder : card.title;
    final meta = cardHasMeta(card);
    final color = done || card.title.isEmpty ? mutedColor : textColor;
    final m = _measures[card.id];
    if (m != null && m.title == title && m.done == done && m.meta == meta && m.color == color) return m;
    final tp = boardPainter(title, cardTitleStyle(color), maxLines: CardGeometry.titleLines)
      ..layout(maxWidth: CardGeometry.titleWidth(done));
    final lines = [for (final l in tp.computeLineMetrics()) l.width];
    // Painting reuses this layout.
    text.put('c:${card.id}', title, CardGeometry.titleSize, color, tp);
    return _measures[card.id] = _CardMeasure(title, done, meta, color, CardGeometry.height(tp.height, meta), lines);
  }

  /// The top item under [p] (canvas units; [slop] in canvas units too):
  /// stickies and ink top-first, then cards, then a lane header strip. A
  /// lane's body is empty space.
  SceneHit hitTest(Offset p, {required double slop, Set<String> exclude = const {}}) {
    for (var i = _ordered.length - 1; i >= 0; i--) {
      final si = _ordered[i];
      if (!si.bounds.inflate(slop).contains(p) || exclude.contains(si.id)) continue;
      if (si.kind == ItemKind.ink) {
        final s = si.stroke;
        if (s == null || !s.hitTest(p - si.origin, slop)) continue;
      }
      return SceneHit(HitKind.free, id: si.id);
    }
    final c = _lanes.cardAt(p, slop: slop);
    if (c != null && !exclude.contains(c.id)) {
      return SceneHit(HitKind.card, id: c.id, columnId: _cards[c.id]?.columnId);
    }
    final lane = _lanes.headerAt(p);
    if (lane != null) return SceneHit(HitKind.laneHeader, columnId: lane.columnId);
    return SceneHit.none;
  }

  /// Ink strokes touched by a circle (the eraser).
  List<String> inkAt(Offset p, double radius, {Set<String> exclude = const {}}) {
    final out = <String>[];
    for (final si in _ordered) {
      if (si.kind != ItemKind.ink || exclude.contains(si.id)) continue;
      if (!si.bounds.inflate(radius).contains(p)) continue;
      final s = si.stroke;
      if (s != null && s.hitTest(p - si.origin, radius)) out.add(si.id);
    }
    return out;
  }

  /// Items whose bounds overlap [r] (marquee).
  Set<String> query(Rect r) => {
    for (final si in _cards.values)
      if (si.bounds.overlaps(r)) si.id,
    for (final si in _ordered)
      if (si.bounds.overlaps(r)) si.id,
  };
}

TextStyle cardTitleStyle(Color c) => boardText(CardGeometry.titleSize, c, weight: FontWeight.w700);
