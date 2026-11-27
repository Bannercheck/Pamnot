import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/dates.dart';
import '../../models/reminder.dart';
import '../../models/task.dart';
import '../../services/calendar/calendar_source.dart';
import '../../state/app_controller.dart';
import 'calendar_models.dart';

/// The calendar page's state: view mode, anchor day, loaded events and
/// moving items.
///
/// Tasks and reminders are read from [app] on every call; only the events of
/// the visible range are kept here (never stored).
class CalendarViewController extends ChangeNotifier {
  CalendarViewController(this.app)
      : _anchor = dateOnly(app.now()),
        _revs = app.revisions {
    app.addListener(_onApp);
  }

  final AppController app;

  /// The slices whose change redraws the calendar.
  static const _watched = {Slice.tasks, Slice.reminders, Slice.settings, Slice.lists, Slice.calendar};

  DateTime _anchor;
  Map<Slice, int> _revs;
  bool _disposed = false;

  /// Events of [_loaded]; empty when the calendar is not shown.
  List<CalendarEvent> _events = const [];
  (DateTime, DateTime)? _loaded;
  (DateTime, DateTime)? _loading;
  Future<void>? _load;

  /// Bumped by every load and every drop; an older load's answer is ignored.
  int _generation = 0;
  Future<void>? _accessRead;

  // ------------------------------------------------------------- view state

  CalendarViewMode get mode => app.settings.calendarView;
  set mode(CalendarViewMode m) {
    if (m == mode) return;
    app.updateSettings(app.settings.copyWith(calendarView: m));
  }

  bool get showPamnot => app.settings.calendarShowPamnot;
  set showPamnot(bool v) {
    if (v == showPamnot) return;
    app.updateSettings(app.settings.copyWith(calendarShowPamnot: v));
  }

  DateTime get anchor => _anchor;

  void goTo(DateTime day) {
    final d = dateOnly(day);
    if (d == _anchor) return;
    _anchor = d;
    notifyListeners();
    unawaited(ensureRange());
  }

  /// One day, week or month forward (positive) or back (negative).
  void shift(int direction) {
    if (direction == 0) return;
    goTo(switch (mode) {
      CalendarViewMode.day => addDays(_anchor, direction),
      CalendarViewMode.week => addDays(_anchor, 7 * direction),
      CalendarViewMode.month => _monthShifted(direction),
    });
  }

  void goToday() => goTo(app.now());

  DateTime _monthShifted(int direction) {
    final first = DateTime(_anchor.year, _anchor.month + direction);
    final day = _anchor.day.clamp(1, daysInMonth(first.year, first.month));
    return DateTime(first.year, first.month, day);
  }

  /// [from, to) of what the current mode shows: the day, the week, or the
  /// 6×7 month grid.
  (DateTime, DateTime) get _range {
    final mondayFirst = app.settings.mondayFirst;
    switch (mode) {
      case CalendarViewMode.day:
        return (_anchor, addDays(_anchor, 1));
      case CalendarViewMode.week:
        final s = startOfWeek(_anchor, mondayFirst: mondayFirst);
        return (s, addDays(s, 7));
      case CalendarViewMode.month:
        final s = startOfWeek(DateTime(_anchor.year, _anchor.month), mondayFirst: mondayFirst);
        return (s, addDays(s, 42));
    }
  }

  // ----------------------------------------------------------------- events

  bool get _eventsShown => app.settings.showCalendar && app.calendarAccess == CalendarAccess.granted;

  /// The calendar is on but the system access was never read (cold start).
  bool get _accessUnread =>
      app.settings.showCalendar &&
      app.calendar.isSupported &&
      app.calendarAccess == CalendarAccess.notAsked &&
      !app.calendarNeedsAccess;

  /// Loads the events of the visible range, once per range. A failing
  /// calendar means no events.
  Future<void> ensureRange() async {
    if (_accessUnread) {
      // Reads the access without prompting; loads no events by itself.
      await (_accessRead ??= app.refreshCalendar());
      if (_disposed) return;
    }
    if (!_eventsShown) {
      _dropEvents();
      return;
    }
    final range = _range;
    if (range == _loaded) return;
    final inFlight = _load;
    if (range == _loading && inFlight != null) return inFlight;
    _loading = range;
    final load = _fetch(range, ++_generation);
    _load = load;
    try {
      await load;
    } finally {
      if (identical(_load, load)) {
        _load = null;
        _loading = null;
      }
    }
  }

  Future<void> _fetch((DateTime, DateTime) range, int generation) async {
    List<CalendarEvent> events;
    try {
      events = await app.calendar.events(range.$1, range.$2);
    } catch (e) {
      // No event text in the log.
      debugPrint('Calendar range failed: ${e.runtimeType}');
      events = const [];
    }
    if (_disposed || generation != _generation || !_eventsShown) return;
    _events = List.unmodifiable(events);
    _loaded = range;
    notifyListeners();
  }

  void _dropEvents() {
    if (_loaded == null && _load == null && _events.isEmpty) return;
    _generation++;
    _loaded = null;
    _loading = null;
    _load = null;
    final hadEvents = _events.isNotEmpty;
    _events = const [];
    if (hadEvents) notifyListeners();
  }

  void _onApp() {
    final now = app.revisions;
    final changed = _watched.any((s) => now[s] != _revs[s]);
    final calendarChanged = now[Slice.calendar] != _revs[Slice.calendar];
    _revs = now;
    if (!changed) return;
    if (calendarChanged) {
      // Read the range again; the loaded events stay until the new ones come.
      _loaded = null;
      _loading = null;
      _load = null;
    }
    notifyListeners();
    unawaited(ensureRange());
  }

  List<CalendarEvent> _eventsOn(DateTime day) {
    if (!_eventsShown || _events.isEmpty) return const [];
    final hidden = app.settings.hiddenCalendarIds.toSet();
    return [
      for (final e in _events)
        if (!hidden.contains(e.calendarId) && e.occursOn(day)) e,
    ];
  }

  // ------------------------------------------------------------------ items

  /// Timed tasks (30-minute boxes), reminder occurrences and timed events on
  /// [day], by start. Events crossing midnight are cut to the day.
  List<DayItem> timedOn(DateTime day) {
    final d = dateOnly(day);
    final next = addDays(d, 1);
    return [
      if (showPamnot) ...[
        for (final t in app.tasksDueOn(d))
          if (t.hasTime) _taskItem(t, t.due!, allDay: false),
        for (final r in app.reminders)
          if (r.enabled)
            if (r.occurrenceOn(d) case final at?) _reminderItem(r, at),
      ],
      for (final e in _eventsOn(d))
        if (!e.allDay) _eventItem(e, e.start.isBefore(d) ? d : e.start, e.end.isAfter(next) ? next : e.end),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// All-day events, then date-only tasks on [day].
  List<DayItem> allDayOn(DateTime day) {
    final d = dateOnly(day);
    return [
      for (final e in _eventsOn(d))
        if (e.allDay) _eventItem(e, d, addDays(d, 1), allDay: true),
      if (showPamnot)
        for (final t in app.tasksDueOn(d))
          if (!t.hasTime) _taskItem(t, d, allDay: true),
    ];
  }

  /// At most [maxMonthDots] dots and how many more there are.
  ({List<DayItem> dots, int more}) dotsOn(DateTime day) {
    final all = [...allDayOn(day), ...timedOn(day)];
    if (all.length <= maxMonthDots) return (dots: all, more: 0);
    return (dots: all.sublist(0, maxMonthDots), more: all.length - maxMonthDots);
  }

  DayItem _taskItem(TaskItem t, DateTime start, {required bool allDay}) {
    final list = app.listById(t.listId);
    return DayItem(
      id: t.id,
      kind: AgendaKind.task,
      title: t.title,
      start: start,
      end: allDay ? addDays(start, 1) : start.add(const Duration(minutes: taskBoxMinutes)),
      allDay: allDay,
      colorIndex: list.colorIndex,
      icon: list.icon,
      done: t.done,
    );
  }

  DayItem _reminderItem(Reminder r, DateTime at) => DayItem(
        id: r.id,
        kind: AgendaKind.reminder,
        title: r.title,
        start: at,
        end: at.add(const Duration(minutes: taskBoxMinutes)),
        colorIndex: r.colorIndex,
        icon: 'alarm',
        repeat: r.repeat,
      );

  DayItem _eventItem(CalendarEvent e, DateTime start, DateTime end, {bool allDay = false}) => DayItem(
        id: e.id,
        kind: AgendaKind.event,
        title: e.title,
        start: start,
        end: end,
        allDay: allDay,
        argb: e.color,
        icon: 'event',
      );

  // ------------------------------------------------------------------- move

  /// Moves [item] to [newStart]; returns the undo, or null when it cannot move.
  ///
  /// A timed task gets `due = newStart` and its reminder keeps its distance;
  /// a one-off reminder fires at [newStart]; a repeating reminder keeps its
  /// series' first day and takes only the new time. Alerts are rebuilt by the
  /// `upsert*` calls.
  VoidCallback? move(DayItem item, DateTime newStart) {
    if (!item.draggable) return null;
    switch (item.kind) {
      case AgendaKind.task:
        final i = app.tasks.indexWhere((t) => t.id == item.id);
        if (i < 0) return null;
        final old = app.tasks[i];
        final due = old.due;
        if (due == null || !old.hasTime) return null;
        final shift = newStart.difference(due);
        final remindAt = old.remindAt;
        app.upsertTask(old.copyWith(
          due: () => newStart,
          remindAt: remindAt == null ? null : () => remindAt.add(shift),
        ));
        return () => app.upsertTask(old);
      case AgendaKind.reminder:
        final i = app.reminders.indexWhere((r) => r.id == item.id);
        if (i < 0) return null;
        final old = app.reminders[i];
        final at = old.repeat == Repeat.none
            ? newStart
            : DateTime(old.at.year, old.at.month, old.at.day, newStart.hour, newStart.minute);
        app.upsertReminder(old.copyWith(at: at));
        return () => app.upsertReminder(old);
      case AgendaKind.event:
        return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    app.removeListener(_onApp);
    super.dispose();
  }
}
