import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../features/calendar/calendar_layout.dart';
import '../../features/calendar/calendar_view.dart';
import '../../features/calendar/calendar_view_controller.dart';
import '../../features/features.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart';
import '../../services/calendar/calendar_source.dart';
import '../../services/links.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../common/glass_nav_bar.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import '../reminders/reminder_editor.dart';
import '../reminders/reminders_page.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_tile.dart';

/// The two sections of Plan: the calendar agenda and every reminder.
enum PlanSection { agenda, reminders }

/// The section Plan shows. HomeShell writes it (a tapped reminder
/// notification opens [PlanSection.reminders]); [PlannerPage] listens and
/// writes it back when the user switches.
final planSection = ValueNotifier<PlanSection>(PlanSection.agenda);

/// The calendar never gets shorter than this; the page scrolls instead.
const minCalendarHeight = 440.0;

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  /// The calendar range last asked for, so a rebuild does not ask again.
  String? _rangeKey;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlanSection>(
        valueListenable: planSection,
        builder: (context, section, _) => _build(context, section),
      );

  Widget _build(BuildContext context, PlanSection section) {
    final app = AppScope.of(context, {Slice.tasks, Slice.reminders, Slice.settings, Slice.calendar});
    final calendar = Features.of(context).calendar;
    final s = S.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final pad = wide ? 28.0 : 16.0;
    final reminders = section == PlanSection.reminders;
    if (!reminders) _ensureRange(app, calendar);

    return Scaffold(
      floatingActionButton: reminders
          ? FloatingActionButton.extended(
              heroTag: 'plan-fab',
              onPressed: () => showReminderEditor(context, app, app.draftReminder(), isNew: true),
              icon: const Icon(Icons.add_alert_rounded),
              label: Text(s.newReminder),
            )
          : FloatingActionButton.extended(
              heroTag: 'plan-fab',
              onPressed: () => _addFor(context, app, calendar.anchor),
              icon: const Icon(Icons.add_rounded),
              label: Text(s.add),
            ),
      body: CustomScrollView(
        slivers: [
          PageHeader(title: s.planner),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                child: Center(
                  child: SegmentedButton<PlanSection>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: PlanSection.agenda,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(s.planAgendaTab),
                      ),
                      ButtonSegment(
                        value: PlanSection.reminders,
                        icon: const Icon(Icons.notifications_none_rounded),
                        label: Text(s.reminders),
                      ),
                    ],
                    selected: {section},
                    onSelectionChanged: (v) => planSection.value = v.first,
                  ),
                ),
              ),
            ),
          ),
          if (reminders)
            RemindersList(app: app)
          else ...[
            if (app.calendar.isSupported)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverToBoxAdapter(child: ContentWidth(child: _CalendarPrompt(app: app))),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  // Fills the screen above the tab bar; on a short screen
                  // (large text) keeps a usable height and the page scrolls.
                  final rest = constraints.viewportMainAxisExtent -
                      constraints.precedingScrollExtent -
                      scrollEndSpace(context);
                  return SliverToBoxAdapter(
                    child: ContentWidth(
                      child: SizedBox(height: math.max(minCalendarHeight, rest), child: const CalendarView()),
                    ),
                  );
                },
              ),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: scrollEndSpace(context))),
        ],
      ),
    );
  }

  /// Loads the events of the visible range when the view, its range or the
  /// calendar's state changed; [CalendarViewController.goTo] loads by itself.
  void _ensureRange(AppController app, CalendarViewController calendar) {
    final range = visibleRange(calendar.mode, calendar.anchor, mondayFirst: app.settings.mondayFirst);
    final key = '${dayKey(range.from)}|${dayKey(range.to)}|${app.settings.showCalendar}|${app.calendarAccess.name}';
    if (key == _rangeKey) return;
    _rangeKey = key;
    // Not during build: a finished load notifies listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(calendar.ensureRange());
    });
  }

  Future<void> _addFor(BuildContext context, AppController app, DateTime day) async {
    final s = S.of(context);
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(s.task),
                onTap: () => Navigator.pop(sheet, 'task'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: Text(s.reminder),
                onTap: () => Navigator.pop(sheet, 'reminder'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (kind == 'task') {
      await showTaskEditor(context, app, app.draftTask(due: day), isNew: true);
    } else if (kind == 'reminder') {
      final now = app.now();
      final at = isSameDay(day, now)
          ? DateTime(day.year, day.month, day.day, now.hour + 1)
          : DateTime(day.year, day.month, day.day, 9);
      await showReminderEditor(context, app, app.draftReminder(at: at), isNew: true);
    }
  }
}

/// Above the calendar: "Show calendar" until the user turns the calendar
/// on (the first tap asks for access) or while access was never decided,
/// or why events are missing when access was refused.
class _CalendarPrompt extends StatelessWidget {
  const _CalendarPrompt({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (app.calendarAccess == CalendarAccess.denied) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ListTile(
          key: const Key('calendar-denied'),
          leading: const Icon(Icons.event_busy_rounded),
          title: Text(s.calendarDenied),
          trailing: const Icon(Icons.open_in_new_rounded, size: 20),
          onTap: openAppSettings,
        ),
      );
    }
    // On, and access granted or not read yet: nothing to offer. On while the
    // system never asked (settings restored to a new device): offer it again.
    if (app.settings.showCalendar && !app.calendarNeedsAccess) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        key: const Key('show-calendar'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        onPressed: app.enableCalendar,
        icon: const Icon(Icons.event_rounded),
        label: Text(s.showCalendar),
      ),
    );
  }
}

/// One line of a day's agenda: a time on the left, a soft card on the right.
class AgendaRow extends StatelessWidget {
  const AgendaRow({super.key, required this.app, required this.entry});

  final AppController app;
  final AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    if (entry.kind == AgendaKind.event) return _EventRow(entry: entry);
    final p = pastelAt(entry.colorIndex);
    final isTask = entry.kind == AgendaKind.task;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Wide enough for "18:00" on one line at any text size.
          width: MediaQuery.textScalerOf(context).scale(58),
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              entry.time == null ? s.allDay : hhmm(entry.time!),
              style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: SoftCard(
            color: p.paper(t.brightness),
            shadow: false,
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            onTap: () {
              if (isTask) {
                final task = app.tasks.where((x) => x.id == entry.id).firstOrNull;
                if (task != null) showTaskEditor(context, app, task);
              } else {
                final r = app.reminders.where((x) => x.id == entry.id).firstOrNull;
                if (r != null) showReminderEditor(context, app, r);
              }
            },
            child: Row(
              children: [
                if (isTask)
                  SoftCheck(
                    done: entry.done,
                    label: entry.title,
                    colorIndex: entry.colorIndex,
                    onTap: () => app.toggleTask(entry.id),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(Icons.notifications_active_outlined, color: p.accent, size: 22),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      entry.title,
                      style: t.textTheme.titleSmall?.copyWith(
                        decoration: entry.done ? TextDecoration.lineThrough : null,
                        color: entry.done ? c.onSurfaceVariant : c.onSurface,
                      ),
                    ),
                  ),
                ),
                if (entry.repeat != Repeat.none)
                  Icon(Icons.repeat_rounded, size: 16, color: c.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A calendar event in the agenda: read-only, so no check box and no tap.
/// The time range (or "All day") on the left, a flat card with a stripe in
/// the calendar's colour on the right.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.entry});

  final AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final title = entry.title.trim().isEmpty ? s.untitledEvent : entry.title;
    final start = entry.time;
    final end = entry.end;
    final when = start == null ? s.allDay : (end == null ? hhmm(start) : '${hhmm(start)}–${hhmm(end)}');
    final label = t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${s.calendarEventLabel}: $title, $when',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(58),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: start == null
                  ? Text(s.allDay, style: label)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hhmm(start), style: label),
                        if (end != null) Text(hhmm(end), style: t.textTheme.labelSmall?.copyWith(color: c.onSurfaceVariant)),
                      ],
                    ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: c.surfaceContainerLow,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        key: Key('event-stripe-${entry.id}'),
                        width: 4,
                        color: entry.color == null ? c.primary : Color(entry.color!),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(11, 15, 6, 15),
                        child: Icon(Icons.event_rounded, size: 22, color: c.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
                          child: Text(title, style: t.textTheme.titleSmall?.copyWith(color: c.onSurface)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
