import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../ui/common/format.dart';
import '../../ui/common/soft.dart';
import 'calendar_item_card.dart';
import 'calendar_layout.dart';
import 'calendar_models.dart';
import 'calendar_view_controller.dart';
import 'day_view.dart';
import 'hour_grid_painter.dart';

/// At least this wide, the week shows all seven days side by side.
const wideWeekWidth = 700.0;

/// Days visible at once on a narrow screen; the rest scroll sideways.
const narrowWeekDays = 3;

/// The week of [CalendarViewController.anchor] on a time grid, one column
/// per day. On a narrow screen three columns show and only the column area
/// scrolls sideways, settling on a column; the hour labels stay put. Items
/// move only vertically here (their day does not change).
class WeekView extends StatelessWidget {
  const WeekView({super.key, required this.controller, required this.onOpen});

  final CalendarViewController controller;
  final ValueChanged<DayItem> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final range = visibleRange(
            CalendarViewMode.week,
            controller.anchor,
            mondayFirst: controller.app.settings.mondayFirst,
          );
          return _WeekBody(key: ValueKey(range.from), controller: controller, from: range.from, onOpen: onOpen);
        },
      );
}

class _WeekBody extends StatefulWidget {
  const _WeekBody({super.key, required this.controller, required this.from, required this.onOpen});

  final CalendarViewController controller;
  final DateTime from;
  final ValueChanged<DayItem> onOpen;

  @override
  State<_WeekBody> createState() => _WeekBodyState();
}

class _WeekBodyState extends State<_WeekBody> {
  /// The column area's sideways scroll; the header follows it.
  ScrollController? _columns, _header;
  double _columnWidth = 0;

  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(widget.from, i)];

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.ensureRange());
  }

  @override
  void dispose() {
    _columns?.dispose();
    _header?.dispose();
    super.dispose();
  }

  void _syncHeader() {
    final c = _columns, h = _header;
    if (c == null || h == null || !c.hasClients || !h.hasClients) return;
    if (h.offset != c.offset) h.jumpTo(c.offset.clamp(0, h.position.maxScrollExtent));
  }

  /// Settles the column area on the nearest column.
  bool _settle(ScrollEndNotification n) {
    final c = _columns;
    if (n.metrics.axis != Axis.horizontal || c == null || !c.hasClients || _columnWidth <= 0) return false;
    final target = ((c.offset / _columnWidth).round() * _columnWidth).clamp(0.0, c.position.maxScrollExtent);
    if ((target - c.offset).abs() < 0.5) return false;
    final duration = motion(context, const Duration(milliseconds: 200));
    // After this frame: the scroll that just ended is still finishing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !c.hasClients) return;
      if (duration == Duration.zero) {
        c.jumpTo(target);
      } else {
        unawaited(c.animateTo(target, duration: duration, curve: Curves.easeOut));
      }
    });
    return false;
  }

  ScrollController _columnsFor(double width) {
    final existing = _columns;
    if (existing != null) return existing;
    // Opens with the anchor day in the first visible column.
    final anchorIndex =
        (widget.controller.anchor.difference(widget.from).inHours / 24).round().clamp(0, 7 - narrowWeekDays);
    _header = ScrollController(initialScrollOffset: anchorIndex * width);
    return _columns = ScrollController(initialScrollOffset: anchorIndex * width)..addListener(_syncHeader);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final t = Theme.of(context);
          final now = c.app.now();
          final days = _days;
          final todayInWeek = days.any((d) => isSameDay(d, now));
          final style = hourLabelStyle(context, t.textTheme.labelSmall ?? const TextStyle(fontSize: 11));
          final gutter = HourGridPainter.metrics(hourLabels, style).gutter;
          final timed = [for (final d in days) c.timedOn(d)];
          final allDay = [for (final d in days) c.allDayOn(d)];
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= wideWeekWidth;
              final colW = (box.maxWidth - gutter - 4) / (wide ? 7 : narrowWeekDays);
              _columnWidth = colW;
              // Overlapping cards share colW; never narrower than minCardWidth.
              final limit = columnsFitting(colW);
              final placed = [for (var i = 0; i < 7; i++) layoutDay(timed[i], days[i], columnLimit: limit)];
              final columns = wide ? null : _columnsFor(colW);
              Widget row(List<Widget> children) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final w in children) SizedBox(width: colW, child: w)],
                  );
              final header = row([
                for (var i = 0; i < 7; i++)
                  _DayHeader(day: days[i], today: isSameDay(days[i], now), allDay: allDay[i], onOpen: widget.onOpen),
              ]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: gutter, right: 4),
                    child: wide
                        ? header
                        : SingleChildScrollView(
                            controller: _header,
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: header,
                          ),
                  ),
                  Expanded(
                    child: TimeGrid(
                      clock: c.app.now,
                      showNow: todayInWeek,
                      openAtMinute: todayInWeek ? now.hour * 60.0 + now.minute - 60 : 8 * 60.0,
                      columnsBuilder: (context, window, hourHeight, inset) {
                        final grid = row([
                          for (var i = 0; i < 7; i++)
                            CalendarDayColumn(
                              placed: placed[i],
                              window: window,
                              hourHeight: hourHeight,
                              inset: inset,
                              onOpen: widget.onOpen,
                              onMove: (item, start) => moveWithUndo(context, c, item, start),
                            ),
                        ]);
                        if (columns == null) return grid;
                        return NotificationListener<ScrollEndNotification>(
                          onNotification: _settle,
                          child: SingleChildScrollView(
                            controller: columns,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(height: 2 * inset + 24 * hourHeight, child: grid),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
}

/// A week column's header: weekday and date; below it, the day's all-day
/// items as one button that lists them.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today, required this.allDay, required this.onOpen});

  final DateTime day;
  final bool today;
  final List<DayItem> allDay;
  final ValueChanged<DayItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Column(
      key: Key('week-day-${dayKey(day)}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          label: today ? '${longDate(s, day)}, ${s.today}' : longDate(s, day),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              DateFormat('E d', s.locale).format(day),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelLarge?.copyWith(
                color: today ? c.primary : c.onSurfaceVariant,
                // Today is bold and underlined, not only coloured.
                fontWeight: today ? FontWeight.w800 : null,
                decoration: today ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: allDay.length == 1
                ? AllDayChip(item: allDay.first, maxWidth: double.infinity, onTap: () => onOpen(allDay.first))
                : Semantics(
                    button: true,
                    label: '${s.allDay}: ${s.moreItemsLabel(allDay.length)}',
                    excludeSemantics: true,
                    child: TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(minTouchTarget, minTouchTarget)),
                      onPressed: () => showAllDaySheet(context, day, allDay, onOpen),
                      child: Text(s.moreItems(allDay.length), maxLines: 1),
                    ),
                  ),
          ),
      ],
    );
  }
}
