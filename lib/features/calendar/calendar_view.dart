import 'package:flutter/material.dart';

import '../../state/app_controller.dart' show AgendaKind;
import '../../ui/reminders/reminder_editor.dart';
import '../../ui/tasks/task_editor.dart';
import '../features.dart';
import 'calendar_header.dart';
import 'calendar_models.dart';
import 'calendar_view_controller.dart';
import 'day_view.dart';
import 'event_detail_sheet.dart';
import 'month_view.dart';
import 'week_view.dart';

/// A sideways fling at least this fast (px/s) moves one day, week or month.
const calendarSwipeVelocity = 300.0;

/// Plan's calendar: [CalendarHeader] over the selected Day, Week or Month
/// view. A sideways swipe moves back or forward; in the Week view the day
/// columns keep their own sideways scroll, so there only the bar swipes.
class CalendarView extends StatelessWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Features.of(context).calendar;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        void open(DayItem item) => openCalendarItem(context, controller, item);
        final mode = controller.mode;
        final body = switch (mode) {
          CalendarViewMode.day => DayView(controller: controller, day: controller.anchor, onOpen: open),
          CalendarViewMode.week => WeekView(controller: controller, onOpen: open),
          CalendarViewMode.month => MonthView(controller: controller),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Swipe(controller: controller, child: CalendarHeader(controller: controller)),
            const SizedBox(height: 8),
            Expanded(
              child: KeyedSubtree(
                key: const Key('calendar-body'),
                child: mode == CalendarViewMode.week ? body : _Swipe(controller: controller, child: body),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Moves [controller] one step on a fast enough sideways fling.
class _Swipe extends StatelessWidget {
  const _Swipe({required this.controller, required this.child});

  final CalendarViewController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < calendarSwipeVelocity) return;
          // A fling to the left shows what comes next.
          controller.shift(v < 0 ? 1 : -1);
        },
        child: child,
      );
}

/// Opens [item]: a task or reminder in its editor (the agenda row's path), an
/// event in the read-only detail sheet.
void openCalendarItem(BuildContext context, CalendarViewController controller, DayItem item) {
  final app = controller.app;
  switch (item.kind) {
    case AgendaKind.task:
      final task = app.tasks.where((x) => x.id == item.id).firstOrNull;
      if (task != null) showTaskEditor(context, app, task);
    case AgendaKind.reminder:
      final r = app.reminders.where((x) => x.id == item.id).firstOrNull;
      if (r != null) showReminderEditor(context, app, r);
    case AgendaKind.event:
      final calendarId = controller.eventById(item.id)?.calendarId;
      final name = app.deviceCalendars.where((k) => k.id == calendarId).firstOrNull?.name;
      showEventDetail(context, item, calendarName: name);
  }
}
