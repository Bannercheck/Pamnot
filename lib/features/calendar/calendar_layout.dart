/// Pure calendar geometry: overlapping items in columns, 15 minute snapping
/// and the days each view mode shows. No Flutter, no state.
library;

import '../../core/dates.dart';
import 'calendar_models.dart';

const _minutesPerDay = 24 * 60;

/// One timed item placed on a day's time grid.
class Placed {
  const Placed({
    required this.item,
    required this.column,
    required this.columns,
    required this.startMinute,
    required this.endMinute,
    this.hidden = 0,
  });

  final DayItem item;

  /// Zero-based column and how many columns its overlap group uses.
  final int column, columns;

  /// Clipped to the day (0..1440) and at least [snapStepMinutes] tall.
  final double startMinute, endMinute;

  /// Items not drawn in place of this box; when > 0 the box shows "+n".
  final int hidden;
}

/// Minutes since the start of [dayStart], wall clock, clipped to 0..1440.
double _minuteOn(DateTime t, DateTime dayStart, DateTime nextDay) {
  if (!t.isAfter(dayStart)) return 0;
  if (!t.isBefore(nextDay)) return _minutesPerDay.toDouble();
  return t.hour * 60 + t.minute + t.second / 60;
}

class _Span {
  _Span(this.item, this.start, this.end);
  final DayItem item;
  final double start, end;
  int column = 0;
  int hidden = 0;
}

/// How many columns a day column [width] wide holds with every card at least
/// [minCardWidth] wide: at least 1, at most [maxColumns].
int columnsFitting(double width) => (width / (minCardWidth + cardGap)).floor().clamp(1, maxColumns);

/// Lays out the [timed] items of [day] in at most [columnLimit] columns
/// (clamped to 1..[maxColumns]).
///
/// Items are sorted by start, then longest first; items that overlap in time
/// form a group; each goes into the first free column. Items that fit in no
/// column are not drawn: the box occupying the last column at that time
/// counts them in [Placed.hidden]. Items not touching [day] are skipped.
List<Placed> layoutDay(List<DayItem> timed, DateTime day, {int columnLimit = maxColumns}) {
  final limit = columnLimit.clamp(1, maxColumns);
  final dayStart = dateOnly(day);
  final nextDay = addDays(dayStart, 1);
  final spans = <_Span>[];
  for (final it in timed) {
    final end = it.end.isBefore(it.start) ? it.start : it.end;
    // A zero-length item belongs to the day its start is on.
    final touches = it.start.isBefore(nextDay) &&
        (end.isAfter(dayStart) || (end == it.start && !it.start.isBefore(dayStart)));
    if (!touches) continue;
    var s = _minuteOn(it.start, dayStart, nextDay);
    var e = _minuteOn(end, dayStart, nextDay);
    if (e - s < snapStepMinutes) {
      e = s + snapStepMinutes;
      if (e > _minutesPerDay) {
        e = _minutesPerDay.toDouble();
        s = e - snapStepMinutes;
      }
    }
    spans.add(_Span(it, s, e));
  }
  spans.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : (b.end - b.start).compareTo(a.end - a.start);
  });

  final out = <Placed>[];
  final group = <_Span>[];
  final columnEnds = <double>[];
  final occupants = <_Span>[];
  var groupEnd = double.negativeInfinity;

  void flush() {
    final columns = columnEnds.length;
    for (final sp in group) {
      out.add(Placed(
        item: sp.item,
        column: sp.column,
        columns: columns,
        startMinute: sp.start,
        endMinute: sp.end,
        hidden: sp.hidden,
      ));
    }
    group.clear();
    columnEnds.clear();
    occupants.clear();
  }

  for (final sp in spans) {
    if (sp.start >= groupEnd) flush();
    if (sp.end > groupEnd || group.isEmpty) groupEnd = sp.end;
    var col = -1;
    for (var c = 0; c < columnEnds.length; c++) {
      if (columnEnds[c] <= sp.start) {
        col = c;
        break;
      }
    }
    if (col < 0 && columnEnds.length < limit) {
      col = columnEnds.length;
      columnEnds.add(sp.end);
      occupants.add(sp);
    }
    if (col < 0) {
      occupants[limit - 1].hidden++;
      continue;
    }
    sp.column = col;
    columnEnds[col] = sp.end;
    occupants[col] = sp;
    group.add(sp);
  }
  flush();
  return out;
}

/// Rounds to the nearest [snapStepMinutes] and keeps the start inside the day.
int snapMinute(double minute) {
  final snapped = (minute / snapStepMinutes).round() * snapStepMinutes;
  return snapped.clamp(0, _minutesPerDay - snapStepMinutes);
}

/// The start time on [day] for a drop at [minute].
DateTime snappedStart(DateTime day, double minute) {
  final m = snapMinute(minute);
  return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
}

/// The 42 days (6 weeks) of the month grid containing [month].
List<DateTime> monthCells(DateTime month, {required bool mondayFirst}) {
  final first = startOfWeek(DateTime(month.year, month.month), mondayFirst: mondayFirst);
  return [for (var i = 0; i < 42; i++) addDays(first, i)];
}

/// The days [mode] shows around [anchor]: from inclusive, to exclusive.
({DateTime from, DateTime to}) visibleRange(
  CalendarViewMode mode,
  DateTime anchor, {
  required bool mondayFirst,
}) {
  final (from, days) = switch (mode) {
    CalendarViewMode.day => (dateOnly(anchor), 1),
    CalendarViewMode.week => (startOfWeek(anchor, mondayFirst: mondayFirst), 7),
    CalendarViewMode.month =>
      (startOfWeek(DateTime(anchor.year, anchor.month), mondayFirst: mondayFirst), 42),
  };
  return (from: from, to: addDays(from, days));
}

/// [anchor] moved one day, week or month in [direction] (±1). In month mode
/// the result is the first day of the month.
DateTime shifted(CalendarViewMode mode, DateTime anchor, int direction) => switch (mode) {
      CalendarViewMode.day => addDays(dateOnly(anchor), direction),
      CalendarViewMode.week => addDays(dateOnly(anchor), 7 * direction),
      CalendarViewMode.month => DateTime(anchor.year, anchor.month + direction),
    };
