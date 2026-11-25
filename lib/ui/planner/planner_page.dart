import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../common/format.dart';
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

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});

  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  DateTime? _selected;
  DateTime? _anchor;
  bool _month = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlanSection>(
        valueListenable: planSection,
        builder: (context, section, _) => _build(context, section),
      );

  Widget _build(BuildContext context, PlanSection section) {
    final app = AppScope.of(context, {Slice.tasks, Slice.reminders, Slice.settings});
    final s = S.of(context);
    final today = dateOnly(app.now());
    final mondayFirst = app.settings.mondayFirst;
    final selected = _selected ?? today;
    final anchor = _anchor ?? (_month ? DateTime(selected.year, selected.month) : startOfWeek(selected, mondayFirst: mondayFirst));
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final pad = wide ? 28.0 : 16.0;
    final agenda = app.agenda(selected);
    final reminders = section == PlanSection.reminders;

    void shift(int dir) => setState(() {
          _anchor = _month ? DateTime(anchor.year, anchor.month + dir) : addDays(anchor, 7 * dir);
        });

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
              onPressed: () => _addFor(context, app, selected),
              icon: const Icon(Icons.add_rounded),
              label: Text(s.add),
            ),
      body: CustomScrollView(
        slivers: [
          PageHeader(
            title: s.planner,
            subtitle: reminders
                ? null
                : toBeginningOfSentenceCase(DateFormat('MMMM y', s.locale).format(_month ? anchor : addDays(anchor, 3))),
            actions: [
              if (!reminders)
                IconButton(
                  tooltip: s.goToToday,
                  onPressed: () => setState(() {
                    _selected = today;
                    _anchor = null;
                  }),
                  icon: const Icon(Icons.today_rounded),
                ),
            ],
          ),
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
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: s.previous,
                            onPressed: () => shift(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Center(
                              child: SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(value: false, label: Text(s.week)),
                                  ButtonSegment(value: true, label: Text(s.month)),
                                ],
                                selected: {_month},
                                onSelectionChanged: (v) => setState(() {
                                  _month = v.first;
                                  _anchor = null;
                                }),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: s.next,
                            onPressed: () => shift(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: motion(context, const Duration(milliseconds: 220)),
                        child: _month
                            ? _MonthGrid(
                                key: ValueKey('m${anchor.year}-${anchor.month}'),
                                app: app,
                                month: anchor,
                                selected: selected,
                                today: today,
                                mondayFirst: mondayFirst,
                                onPick: (d) => setState(() => _selected = d),
                              )
                            : _WeekStrip(
                                key: ValueKey('w${dayKey(anchor)}'),
                                app: app,
                                start: anchor,
                                selected: selected,
                                today: today,
                                onPick: (d) => setState(() => _selected = d),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(
                  child: SectionHeader(
                    toBeginningOfSentenceCase(longDate(s, selected)),
                    icon: Icons.wb_sunny_outlined,
                  ),
                ),
              ),
            ),
            if (agenda.isEmpty)
              SliverToBoxAdapter(child: EmptyState(emoji: '☁️', text: s.emptyDay))
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverList.separated(
                  itemCount: agenda.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => ContentWidth(child: AgendaRow(app: app, entry: agenda[i])),
                ),
              ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: scrollEndSpace(context))),
        ],
      ),
    );
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

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({super.key, required this.app, required this.start, required this.selected, required this.today, required this.onPick});

  final AppController app;
  final DateTime start;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final busy = app.busyDays(start, 7);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _DayCell(
              day: addDays(start, i),
              selected: selected,
              today: today,
              count: busy[dayKey(addDays(start, i))] ?? 0,
              onTap: onPick,
              showWeekday: true,
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.app,
    required this.month,
    required this.selected,
    required this.today,
    required this.mondayFirst,
    required this.onPick,
  });

  final AppController app;
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final bool mondayFirst;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final first = startOfWeek(month, mondayFirst: mondayFirst);
    final weeks = ((DateTime(month.year, month.month + 1, 1).difference(first).inHours / 24) / 7).ceil();
    final busy = app.busyDays(first, weeks * 7);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat('E', s.locale).format(addDays(first, i)),
                    style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < weeks; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Opacity(
                    opacity: addDays(first, w * 7 + i).month == month.month ? 1 : 0.35,
                    child: _DayCell(
                      day: addDays(first, w * 7 + i),
                      selected: selected,
                      today: today,
                      count: busy[dayKey(addDays(first, w * 7 + i))] ?? 0,
                      onTap: onPick,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.count,
    required this.onTap,
    this.showWeekday = false,
  });

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final int count;
  final ValueChanged<DateTime> onTap;
  final bool showWeekday;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final isSel = isSameDay(day, selected);
    final isToday = isSameDay(day, today);
    final fg = isSel ? c.onPrimary : (isToday ? c.primary : c.onSurface);
    // Read as the full date ("Salı 27 Ekim") instead of "Sal" and "27".
    return Semantics(
      container: true,
      button: true,
      selected: isSel,
      label: DateFormat('EEEE d MMMM', S.of(context).locale).format(day),
      onTap: () => onTap(day),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onTap(day),
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 200)),
          margin: const EdgeInsets.all(3),
          padding: EdgeInsets.symmetric(vertical: showWeekday ? 10 : 6),
          decoration: BoxDecoration(
            color: isSel ? c.primary : (isToday ? c.primaryContainer : Colors.transparent),
            borderRadius: BorderRadius.circular(showWeekday ? 18 : 14),
          ),
          child: Column(
            children: [
              if (showWeekday)
                Text(
                  DateFormat('E', S.of(context).locale).format(day),
                  style: t.textTheme.labelSmall?.copyWith(color: isSel ? c.onPrimary : c.onSurfaceVariant),
                ),
              Text('${day.day}', style: t.textTheme.titleMedium?.copyWith(color: fg)),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count.clamp(0, 3); i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: isSel ? c.onPrimary.withValues(alpha: 0.8) : c.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (count == 0) const SizedBox(height: 5),
                ],
              ),
            ],
          ),
        ),
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
