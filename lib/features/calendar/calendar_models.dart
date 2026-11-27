import '../../models/reminder.dart' show Repeat;
import '../../state/app_controller.dart' show AgendaKind;

/// What the calendar page shows: one day, a week (3 days on narrow screens)
/// or a month grid.
enum CalendarViewMode { day, week, month }

/// A task box is always this long, whatever the task.
const taskBoxMinutes = 30;

/// Dragging snaps the start to this step.
const snapStepMinutes = 15;

/// Overlapping items share at most this many columns; the rest become "+n".
const maxColumns = 3;

/// A month cell shows at most this many dots.
const maxMonthDots = 3;

/// One task, reminder or calendar event placed on the calendar.
class DayItem {
  const DayItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.colorIndex = 0,
    this.argb,
    this.icon = 'list',
    this.done = false,
    this.repeat = Repeat.none,
  });

  final String id;
  final AgendaKind kind;
  final String title;

  /// For tasks and reminders [end] is [start] + [taskBoxMinutes].
  final DateTime start, end;
  final bool allDay, done;

  /// The list's pastel index (tasks and reminders).
  final int colorIndex;

  /// The calendar's colour (ARGB); only for events.
  final int? argb;

  /// Tasks: the list's icon key; reminders: 'alarm'; events: 'event'.
  final String icon;
  final Repeat repeat;

  /// Events are read-only and all-day items have no time to change.
  bool get draggable => kind != AgendaKind.event && !allDay;
}
