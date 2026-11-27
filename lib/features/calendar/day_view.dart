import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart' show Repeat;
import '../../state/app_controller.dart' show AgendaKind;
import '../../theme/pamnot_theme.dart';
import '../../ui/common/format.dart';
import '../../ui/common/soft.dart';
import '../../ui/matrix/list_icons.dart';
import 'calendar_item_card.dart';
import 'calendar_layout.dart';
import 'calendar_models.dart';
import 'calendar_view_controller.dart';
import 'hour_grid_painter.dart';

/// One day on a 00–24 time grid, with the all-day items in a strip on top.
///
/// Opens at the current hour when [day] is today, at 08:00 otherwise. Tasks
/// and reminders move by long press and drag; events open on tap.
class DayView extends StatelessWidget {
  const DayView({super.key, required this.controller, required this.day, required this.onOpen});

  final CalendarViewController controller;
  final DateTime day;
  final ValueChanged<DayItem> onOpen;

  @override
  Widget build(BuildContext context) => _DayBody(
        key: ValueKey(dateOnly(day)),
        controller: controller,
        day: dateOnly(day),
        onOpen: onOpen,
      );
}

class _DayBody extends StatefulWidget {
  const _DayBody({super.key, required this.controller, required this.day, required this.onOpen});

  final CalendarViewController controller;
  final DateTime day;
  final ValueChanged<DayItem> onOpen;

  @override
  State<_DayBody> createState() => _DayBodyState();
}

class _DayBodyState extends State<_DayBody> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.ensureRange());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final now = c.app.now();
          final today = isSameDay(now, widget.day);
          final allDay = c.allDayOn(widget.day);
          final placed = layoutDay(c.timedOn(widget.day), widget.day);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (allDay.isNotEmpty) AllDayStrip(day: widget.day, items: allDay, onOpen: widget.onOpen),
              Expanded(
                child: TimeGrid(
                  clock: c.app.now,
                  showNow: today,
                  openAtMinute: today ? now.hour * 60.0 + now.minute - 60 : 8 * 60.0,
                  columnsBuilder: (context, window, hourHeight, inset) => CalendarDayColumn(
                    placed: placed,
                    window: window,
                    hourHeight: hourHeight,
                    inset: inset,
                    onOpen: widget.onOpen,
                    onMove: (item, start) => moveWithUndo(context, c, item, start),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// Moves [item] through [controller] and offers to undo it.
void moveWithUndo(BuildContext context, CalendarViewController controller, DayItem item, DateTime start) {
  final undo = controller.move(item, start);
  if (undo == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final s = S.of(context);
  final time = hhmm(start);
  final series = item.kind == AgendaKind.reminder && item.repeat != Repeat.none;
  showUndoSnack(messenger, series ? s.seriesMoved(time) : s.itemMoved(time), undo, s.undo);
}

/// Builds the cards of a grid for the minute [window].
typedef GridColumnsBuilder = Widget Function(
    BuildContext context, (double, double) window, double hourHeight, double inset);

/// The vertically scrolling 00–24 grid: one [HourGridPainter] layer under
/// the cards from [columnsBuilder], which are rebuilt only when the card
/// window (what shows ± 2 hours, in whole hours) changes.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.clock,
    required this.showNow,
    required this.openAtMinute,
    required this.columnsBuilder,
  });

  final DateTime Function() clock;

  /// Draws the "now" line (the grid shows today).
  final bool showNow;

  /// The minute at the top when the grid first opens.
  final double openAtMinute;
  final GridColumnsBuilder columnsBuilder;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  ScrollController? _scroll;
  (double, double)? _window;
  double _viewport = 0, _hourHeight = 0, _inset = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(TimeGrid old) {
    super.didUpdateWidget(old);
    if (old.showNow != widget.showNow) _syncTick();
  }

  /// Moves the "now" line once a minute while today shows.
  void _syncTick() {
    _tick?.cancel();
    _tick = widget.showNow ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {})) : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final sc = _scroll;
    if (sc == null || !sc.hasClients) return;
    final w = cardWindow(offset: sc.offset, viewport: _viewport, hourHeight: _hourHeight, inset: _inset);
    if (w != _window) setState(() => _window = w);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final hh = hourHeightFor(context);
    final style = hourLabelStyle(context, t.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
        .copyWith(color: c.onSurfaceVariant);
    final m = HourGridPainter.metrics(hourLabels, style);
    final total = 2 * m.inset + 24 * hh;
    final now = widget.clock();
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = box.maxHeight;
        _hourHeight = hh;
        _inset = m.inset;
        final sc = _scroll ??= ScrollController(
          initialScrollOffset: initialGridOffset(
            minute: widget.openAtMinute,
            hourHeight: hh,
            inset: m.inset,
            viewport: box.maxHeight,
          ),
        )..addListener(_onScroll);
        final offset = sc.hasClients ? sc.offset : sc.initialScrollOffset;
        final window = _window = cardWindow(offset: offset, viewport: box.maxHeight, hourHeight: hh, inset: m.inset);
        return SingleChildScrollView(
          controller: sc,
          child: SizedBox(
            height: total,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: HourGridPainter(
                        hourHeight: hh,
                        lineColor: c.outlineVariant,
                        labelStyle: style,
                        labels: hourLabels,
                        nowMinute: widget.showNow ? now.hour * 60.0 + now.minute : null,
                        nowColor: c.error,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: m.gutter,
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: widget.columnsBuilder(context, window, hh, m.inset),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The all-day items of a day: up to three chips, then "+n" that lists all.
class AllDayStrip extends StatelessWidget {
  const AllDayStrip({super.key, required this.day, required this.items, required this.onOpen});

  final DateTime day;
  final List<DayItem> items;
  final ValueChanged<DayItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final shown = items.length > maxColumns ? items.sublist(0, maxColumns) : items;
    final more = items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(s.allDay, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          for (final it in shown) AllDayChip(item: it, onTap: () => onOpen(it)),
          if (more > 0)
            Semantics(
              button: true,
              label: s.moreItemsLabel(more),
              excludeSemantics: true,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(minTouchTarget, minTouchTarget)),
                onPressed: () => showAllDaySheet(context, day, items, onOpen),
                child: Text(s.moreItems(more)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One all-day item: stripe, icon and title, at least 44 pt tall.
class AllDayChip extends StatelessWidget {
  const AllDayChip({super.key, required this.item, required this.onTap, this.maxWidth = 220});

  final DayItem item;
  final VoidCallback onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final isEvent = item.kind == AgendaKind.event;
    final title = item.title.trim().isEmpty && isEvent ? s.untitledEvent : item.title;
    final label = switch (item.kind) {
      AgendaKind.task => s.taskAt(title, s.allDay),
      AgendaKind.reminder => s.reminderAt(title, s.allDay),
      AgendaKind.event => s.eventAt(title, s.allDay),
    };
    final stripe = isEvent ? (item.argb == null ? c.primary : Color(item.argb!)) : pastelAt(item.colorIndex).accent;
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minTouchTarget, maxWidth: maxWidth),
        child: Material(
          color: cardBackground(t, item),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: c.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: stripe),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(isEvent ? Icons.event_rounded : listIconOf(item.icon), size: 16, color: c.onSurfaceVariant),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.labelMedium?.copyWith(color: cardInk(t, item)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every all-day item of [day] in a sheet; tapping one opens it.
Future<void> showAllDaySheet(
  BuildContext context,
  DateTime day,
  List<DayItem> items,
  ValueChanged<DayItem> onOpen,
) {
  final s = S.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${s.allDay} · ${longDate(s, day)}', style: Theme.of(sheet).textTheme.titleMedium),
          ),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AllDayChip(
                item: it,
                maxWidth: double.infinity,
                onTap: () {
                  Navigator.of(sheet).pop();
                  onOpen(it);
                },
              ),
            ),
        ],
      ),
    ),
  );
}
