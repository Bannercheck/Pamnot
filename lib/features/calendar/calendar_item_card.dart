import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart' show AgendaKind;
import '../../theme/pamnot_theme.dart';
import '../../ui/common/soft.dart';
import '../../ui/matrix/list_icons.dart';
import 'calendar_layout.dart';
import 'calendar_models.dart';
import 'hour_grid_painter.dart';

/// Smallest touch target, whatever the box's height.
const minTouchTarget = 44.0;

/// One timed item on a time grid: a colour stripe, an icon (list icon,
/// alarm or calendar, so colour is never the only cue) and the title.
///
/// The drawn box is as tall as the item; the touch area below it is at least
/// [minTouchTarget]. A draggable item moves after a long press, in
/// [snapStepMinutes] steps; on release [onMoved] gets the new start.
class CalendarItemCard extends StatelessWidget {
  const CalendarItemCard({super.key, required this.placed, required this.onTap, this.onMoved});

  final Placed placed;
  final VoidCallback onTap;

  /// Only for a draggable item.
  final ValueChanged<DateTime>? onMoved;

  @override
  Widget build(BuildContext context) => _DraggableCard(placed: placed, onTap: onTap, onMoved: onMoved);
}

class _DraggableCard extends StatefulWidget {
  const _DraggableCard({required this.placed, required this.onTap, this.onMoved});

  final Placed placed;
  final VoidCallback onTap;
  final ValueChanged<DateTime>? onMoved;

  @override
  State<_DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<_DraggableCard> with SingleTickerProviderStateMixin {
  /// The card's offset from its slot while dragging, in points.
  late final AnimationController _dy = AnimationController.unbounded(vsync: this);

  /// The snapped start minute under the finger; null when not dragging.
  int? _target;
  bool _dropping = false;
  TickerFuture? _step;

  bool get _canDrag => widget.onMoved != null && widget.placed.item.draggable;

  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  void _start(LongPressStartDetails _) {
    if (!_canDrag) return;
    setState(() => _target = widget.placed.startMinute.round());
  }

  void _update(LongPressMoveUpdateDetails d) {
    if (_target == null || _dropping) return;
    final hh = hourHeightFor(context);
    final p = widget.placed;
    final target = snapMinute(p.startMinute + d.offsetFromOrigin.dy / hh * 60);
    if (target == _target) return;
    _target = target;
    final dy = (target - p.startMinute) / 60 * hh;
    final duration = motion(context, const Duration(milliseconds: 120));
    if (duration == Duration.zero) {
      _dy.value = dy;
    } else {
      _step = _dy.animateTo(dy, duration: duration, curve: Curves.easeOut);
    }
  }

  void _end(LongPressEndDetails _) {
    final target = _target;
    if (target == null || _dropping) return;
    final step = _step;
    if (step == null || !_dy.isAnimating) return _drop(target);
    // Lets the card settle on its step first.
    _dropping = true;
    step.whenCompleteOrCancel(() {
      if (mounted) _drop(target);
    });
  }

  void _drop(int target) {
    final item = widget.placed.item;
    final moved = target != widget.placed.startMinute.round();
    _dropping = false;
    _step = null;
    _dy.value = 0;
    setState(() => _target = null);
    if (moved) widget.onMoved?.call(snappedStart(dateOnly(item.start), target.toDouble()));
  }

  void _cancel() {
    if (_target == null) return;
    _dropping = false;
    _step = null;
    _dy.value = 0;
    setState(() => _target = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final item = widget.placed.item;
    final title = item.title.trim().isEmpty && item.kind == AgendaKind.event ? s.untitledEvent : item.title;
    final time = item.kind == AgendaKind.event && item.end.isAfter(item.start)
        ? '${hhmm(item.start)}–${hhmm(item.end)}'
        : hhmm(item.start);
    final label = switch (item.kind) {
      AgendaKind.task => s.taskAt(title, time),
      AgendaKind.reminder => s.reminderAt(title, time),
      AgendaKind.event => s.eventAt(title, time),
    };
    final hidden = widget.placed.hidden;
    final hh = hourHeightFor(context);
    final boxHeight = (widget.placed.endMinute - widget.placed.startMinute) / 60 * hh;
    final dragging = _target != null;
    return Semantics(
      container: true,
      button: true,
      label: hidden > 0 ? '$label, ${s.moreItemsLabel(hidden)}' : label,
      hint: _canDrag ? s.dragHint : null,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _dy,
        builder: (context, child) => Transform.translate(offset: Offset(0, _dy.value), child: child),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPressStart: _canDrag ? _start : null,
          onLongPressMoveUpdate: _canDrag ? _update : null,
          onLongPressEnd: _canDrag ? _end : null,
          onLongPressCancel: _canDrag ? _cancel : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minTouchTarget),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: Key('calendar-box-${item.kind.name}-${item.id}'),
                height: boxHeight,
                width: double.infinity,
                child: _CardFace(item: item, title: title, hidden: hidden, lifted: dragging),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawn box: stripe, icon, title and "+n".
class _CardFace extends StatelessWidget {
  const _CardFace({required this.item, required this.title, required this.hidden, required this.lifted});

  final DayItem item;
  final String title;
  final int hidden;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final isEvent = item.kind == AgendaKind.event;
    final stripe = isEvent ? (item.argb == null ? c.primary : Color(item.argb!)) : pastelAt(item.colorIndex).accent;
    final background = cardBackground(t, item);
    final ink = cardInk(t, item);
    final icon = switch (item.kind) {
      AgendaKind.event => Icons.event_rounded,
      AgendaKind.reminder => Icons.notifications_active_outlined,
      AgendaKind.task => listIconOf(item.icon),
    };
    return DecoratedBox(
      key: Key('calendar-face-${item.kind.name}-${item.id}'),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.outlineVariant),
        boxShadow: lifted ? [BoxShadow(color: c.shadow.withValues(alpha: 0.25), blurRadius: 8)] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, box) {
            final roomy = box.maxWidth >= 40;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 4, color: stripe),
                if (roomy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 2, 0),
                    child: Icon(icon, size: 16, color: c.onSurfaceVariant),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 4, 0),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelMedium?.copyWith(
                        color: ink,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 4, 0),
                    child: Text(s.moreItems(hidden), style: t.textTheme.labelSmall?.copyWith(color: ink)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The box colour: the list's paper for tasks and reminders, a neutral
/// surface for events (their calendar colour is the stripe).
Color cardBackground(ThemeData t, DayItem item) =>
    item.kind == AgendaKind.event ? t.colorScheme.surfaceContainerHigh : pastelAt(item.colorIndex).paper(t.brightness);

/// The title colour on [cardBackground].
Color cardInk(ThemeData t, DayItem item) => t.colorScheme.onSurface;

/// The cards of one day column: only those touching [window] (minutes) are
/// built. Overlapping items share the width in columns.
class CalendarDayColumn extends StatelessWidget {
  const CalendarDayColumn({
    super.key,
    required this.placed,
    required this.window,
    required this.hourHeight,
    required this.inset,
    required this.onOpen,
    required this.onMove,
  });

  final List<Placed> placed;
  final (double, double) window;
  final double hourHeight, inset;
  final ValueChanged<DayItem> onOpen;
  final void Function(DayItem item, DateTime newStart) onMove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final (from, to) = window;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final p in placed)
                if (p.endMinute > from && p.startMinute < to)
                  Positioned(
                    key: ValueKey('${p.item.kind.name}:${p.item.id}'),
                    left: box.maxWidth * p.column / p.columns,
                    width: box.maxWidth / p.columns - 2,
                    top: inset + p.startMinute / 60 * hourHeight,
                    child: CalendarItemCard(
                      placed: p,
                      onTap: () => onOpen(p.item),
                      onMoved: p.item.draggable ? (start) => onMove(p.item, start) : null,
                    ),
                  ),
            ],
          );
        },
      );
}
