import 'dart:math' as math;
import 'dart:ui';

/// The lane block: the board's columns side by side at the board's lane
/// origin, cards stacked by order. Card positions are derived here and never
/// stored.
abstract final class LaneMetrics {
  static const width = 300.0;
  static const gap = 24.0;
  static const header = 52.0;
  static const padding = 12.0;
  static const cardGap = 12.0;
  static const minHeight = 420.0;
  static const radius = 22.0;
  static const cardWidth = width - 2 * padding;
  static const pitch = width + gap;
}

/// The card face drawn on the canvas (same proportions as the Kanban card).
abstract final class CardGeometry {
  static const radius = 14.0;
  static const padLeft = 18.0;
  static const padRight = 12.0;
  static const padV = 12.0;
  static const titleSize = 15.0;
  static const titleLines = 3;
  static const metaHeight = 22.0;
  static const metaGap = 8.0;
  static const doneIcon = 18.0;
  static const minHeight = 48.0;

  static double titleWidth(bool done) => LaneMetrics.cardWidth - padLeft - padRight - (done ? doneIcon + 6 : 0);

  static double height(double titleHeight, bool hasMeta) =>
      math.max(minHeight, padV + titleHeight + (hasMeta ? metaGap + metaHeight : 0) + padV);
}

class LaneCard {
  const LaneCard(this.id, this.rect);

  final String id;
  final Rect rect;
}

class Lane {
  Lane(this.columnId, this.index, this.rect, this.cards);

  final String columnId;
  final int index;
  final Rect rect;
  final List<LaneCard> cards;

  Rect get header => Rect.fromLTWH(rect.left, rect.top, rect.width, LaneMetrics.header);
}

/// Where a dropped card goes: [index] among the column's other cards.
typedef LaneDrop = ({String columnId, int index});

class LaneLayout {
  LaneLayout._(this.origin, this.lanes, this._cards, this.bounds);

  static final empty = LaneLayout._(Offset.zero, const [], const {}, Rect.zero);

  /// Lays out [columns] (`(columnId, [(cardId, height)])` in order) at
  /// [origin]. All lanes share the tallest lane's height so the block reads
  /// as one board.
  factory LaneLayout.compute(Offset origin, List<(String, List<(String, double)>)> columns) {
    if (columns.isEmpty) return LaneLayout._(origin, const [], const {}, Rect.zero);
    var tallest = LaneMetrics.minHeight;
    for (final (_, cards) in columns) {
      var h = LaneMetrics.header;
      for (final (_, ch) in cards) {
        h += ch + LaneMetrics.cardGap;
      }
      if (cards.isNotEmpty) h -= LaneMetrics.cardGap;
      tallest = math.max(tallest, h + LaneMetrics.padding);
    }
    final lanes = <Lane>[];
    final byId = <String, (int, int)>{};
    for (var i = 0; i < columns.length; i++) {
      final (colId, cards) = columns[i];
      final left = origin.dx + i * LaneMetrics.pitch;
      var y = origin.dy + LaneMetrics.header;
      final placed = <LaneCard>[];
      for (final (id, h) in cards) {
        placed.add(LaneCard(id, Rect.fromLTWH(left + LaneMetrics.padding, y, LaneMetrics.cardWidth, h)));
        byId[id] = (i, placed.length - 1);
        y += h + LaneMetrics.cardGap;
      }
      lanes.add(Lane(colId, i, Rect.fromLTWH(left, origin.dy, LaneMetrics.width, tallest), placed));
    }
    final bounds = Rect.fromLTRB(lanes.first.rect.left, origin.dy, lanes.last.rect.right, origin.dy + tallest);
    return LaneLayout._(origin, lanes, byId, bounds);
  }

  final Offset origin;
  final List<Lane> lanes;
  final Map<String, (int, int)> _cards;

  /// The whole block (Rect.zero when there are no columns).
  final Rect bounds;

  bool get isEmpty => lanes.isEmpty;

  Rect? cardRect(String id) {
    final at = _cards[id];
    return at == null ? null : lanes[at.$1].cards[at.$2].rect;
  }

  Lane? laneOfCard(String id) {
    final at = _cards[id];
    return at == null ? null : lanes[at.$1];
  }

  Lane? laneById(String columnId) {
    for (final l in lanes) {
      if (l.columnId == columnId) return l;
    }
    return null;
  }

  /// The lane whose rect contains [p] (lanes are a row, so this is O(1)).
  Lane? laneAt(Offset p) {
    if (lanes.isEmpty) return null;
    final i = ((p.dx - origin.dx) / LaneMetrics.pitch).floor();
    if (i < 0 || i >= lanes.length) return null;
    final l = lanes[i];
    return l.rect.contains(p) ? l : null;
  }

  /// The lane whose header strip contains [p].
  Lane? headerAt(Offset p) {
    final l = laneAt(p);
    return l != null && p.dy < l.rect.top + LaneMetrics.header ? l : null;
  }

  LaneCard? cardAt(Offset p, {double slop = 0}) {
    if (lanes.isEmpty) return null;
    final i = ((p.dx - origin.dx) / LaneMetrics.pitch).floor();
    if (i < 0 || i >= lanes.length) return null;
    for (final c in lanes[i].cards) {
      if (c.rect.top - slop > p.dy) break;
      if (c.rect.inflate(slop).contains(p)) return c;
    }
    return null;
  }

  /// Index among the lane's cards other than [exclude] for a card whose
  /// centre is at height [y].
  int insertIndex(Lane lane, double y, {String? exclude}) {
    var i = 0;
    for (final c in lane.cards) {
      if (c.id == exclude) continue;
      if (c.rect.center.dy < y) {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  /// Column and index for a card dropped with its centre at [centre], or
  /// null when the centre is outside every lane.
  LaneDrop? dropTarget(Offset centre, {String? exclude}) {
    final lane = laneAt(centre);
    if (lane == null) return null;
    return (columnId: lane.columnId, index: insertIndex(lane, centre.dy, exclude: exclude));
  }

  /// Height of the insertion line for [index] among the other cards.
  double insertionY(Lane lane, int index, {String? exclude}) {
    final others = [
      for (final c in lane.cards)
        if (c.id != exclude) c,
    ];
    if (others.isEmpty) return lane.rect.top + LaneMetrics.header + LaneMetrics.cardGap / 2;
    if (index <= 0) return others.first.rect.top - LaneMetrics.cardGap / 2;
    if (index >= others.length) return others.last.rect.bottom + LaneMetrics.cardGap / 2;
    return (others[index - 1].rect.bottom + others[index].rect.top) / 2;
  }
}
