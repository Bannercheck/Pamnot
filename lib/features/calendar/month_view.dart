import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart' show AgendaKind;
import '../../theme/pamnot_theme.dart';
import '../../ui/common/format.dart';
import 'calendar_item_card.dart' show minTouchTarget;
import 'calendar_layout.dart';
import 'calendar_models.dart';
import 'calendar_view_controller.dart';

/// The month of [CalendarViewController.anchor] as 6×7 cells. A cell shows
/// the day and up to [maxMonthDots] dots (a Pamnot item is a filled dot, an
/// event a ring) and "+n"; tapping it opens that day in the Day view.
class MonthView extends StatelessWidget {
  const MonthView({super.key, required this.controller});

  final CalendarViewController controller;

  void _open(DateTime day) {
    controller.goTo(day);
    controller.mode = CalendarViewMode.day;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final s = S.of(context);
          final t = Theme.of(context);
          final anchor = controller.anchor;
          final cells = monthCells(anchor, mondayFirst: controller.app.settings.mondayFirst);
          final today = dateOnly(controller.app.now());
          final scaler = MediaQuery.textScalerOf(context);
          // Day number, dots and "+n" at the current text size, never under 44 pt.
          final minCell = math.max(minTouchTarget, scaler.scale(18) + scaler.scale(12) + 14);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            DateFormat('E', s.locale).format(cells[i]),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final rowHeight = math.max(minCell, box.maxHeight / 6);
                    final grid = Column(
                      children: [
                        for (var w = 0; w < 6; w++)
                          SizedBox(
                            height: rowHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < 7; i++)
                                  Expanded(
                                    child: _MonthCell(
                                      day: cells[w * 7 + i],
                                      inMonth: cells[w * 7 + i].month == anchor.month,
                                      today: cells[w * 7 + i] == today,
                                      anchor: cells[w * 7 + i] == anchor,
                                      dots: controller.dotsOn(cells[w * 7 + i]),
                                      onTap: _open,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                    // Large text: the rows keep their height and scroll.
                    return rowHeight * 6 > box.maxHeight + 0.5 ? SingleChildScrollView(child: grid) : grid;
                  },
                ),
              ),
            ],
          );
        },
      );
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.anchor,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth, today, anchor;
  final ({List<DayItem> dots, int more}) dots;
  final ValueChanged<DateTime> onTap;

  String _label(S s) {
    String itemLabel(DayItem it) {
      final isEvent = it.kind == AgendaKind.event;
      final title = it.title.trim().isEmpty && isEvent ? s.untitledEvent : it.title;
      final time = it.allDay ? s.allDay : hhmm(it.start);
      return switch (it.kind) {
        AgendaKind.task => s.taskAt(title, time),
        AgendaKind.reminder => s.reminderAt(title, time),
        AgendaKind.event => s.eventAt(title, time),
      };
    }

    return [
      longDate(s, day),
      if (today) s.today,
      for (final it in dots.dots) itemLabel(it),
      if (dots.more > 0) s.moreItemsLabel(dots.more),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final key = dayKey(day);
    final number = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: today ? c.primary : null,
        borderRadius: BorderRadius.circular(12),
        border: anchor && !today ? Border.all(color: c.outline, width: 1.5) : null,
      ),
      child: Text(
        '${day.day}',
        style: t.textTheme.labelLarge?.copyWith(
          color: today ? c.onPrimary : (inMonth ? c.onSurface : c.onSurfaceVariant),
          // Today is bold as well as filled.
          fontWeight: today ? FontWeight.w800 : null,
        ),
      ),
    );
    return Semantics(
      key: Key('month-day-$key'),
      container: true,
      button: true,
      selected: anchor,
      label: _label(s),
      onTap: () => onTap(day),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(day),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                number,
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, it) in dots.dots.indexed) _Dot(dotKey: Key('month-dot-$key-$i'), item: it),
                    if (dots.dots.isEmpty) const SizedBox(height: 7),
                  ],
                ),
                if (dots.more > 0)
                  Text(
                    s.moreItems(dots.more),
                    style: t.textTheme.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Pamnot item is a filled dot in its list's colour; an event is a ring in
/// its calendar's colour, so the shape tells them apart too.
class _Dot extends StatelessWidget {
  const _Dot({required this.dotKey, required this.item});

  final Key dotKey;
  final DayItem item;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final isEvent = item.kind == AgendaKind.event;
    final color = isEvent ? (item.argb == null ? c.primary : Color(item.argb!)) : pastelAt(item.colorIndex).accent;
    return Container(
      key: dotKey,
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: isEvent
          ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.5))
          : BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
