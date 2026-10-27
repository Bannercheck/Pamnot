import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamuk_theme.dart';
import '../common/format.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import '../notes/note_card.dart';
import '../notes/note_editor_page.dart';
import '../planner/planner_page.dart';
import '../reminders/reminder_editor.dart';
import '../tasks/habits_view.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_tile.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, Slice.values.toSet());
    final s = S.of(context);
    final now = app.now();
    final today = dateOnly(now);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width >= 560 ? 28.0 : 16.0;
    final twoColumns = width >= 1000;

    final overdue = app.overdueTasks();
    final todays = app.tasksDueOn(today);
    final reminders = app.agenda(today).where((e) => e.kind == AgendaKind.reminder).toList();
    final upcoming = app.upcomingReminders(limit: 4).where((e) => !isSameDay(e.$2, today)).toList();
    final pinned = app.sortedNotes().where((n) => n.pinned).take(6).toList();
    final recent = pinned.isEmpty ? app.sortedNotes().take(4).toList() : pinned;

    final plan = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProgressCard(app: app),
        const SizedBox(height: 14),
        QuickAddField(app: app, hint: s.quickCapture),
        SectionHeader(s.todaysPlan, icon: Icons.wb_sunny_outlined),
        if (overdue.isEmpty && todays.isEmpty && reminders.isEmpty)
          SoftCard(child: Text(s.nothingToday, style: Theme.of(context).textTheme.bodyLarge))
        else ...[
          for (final t in overdue) ...[TaskTile(app: app, task: t), const SizedBox(height: 8)],
          for (final t in todays) ...[TaskTile(app: app, task: t, showDate: false), const SizedBox(height: 8)],
          for (final e in reminders) ...[AgendaRow(app: app, entry: e), const SizedBox(height: 8)],
        ],
        if (upcoming.isNotEmpty) ...[
          SectionHeader(s.upcoming, icon: Icons.notifications_none_rounded),
          for (final (r, at) in upcoming) ...[
            SoftCard(
              shadow: false,
              color: pastelAt(r.colorIndex).paper(Theme.of(context).brightness),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              onTap: () => showReminderEditor(context, app, r),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined, color: pastelAt(r.colorIndex).accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(r.title, style: Theme.of(context).textTheme.titleSmall)),
                Text(formatWhen(s, at, now: now), style: Theme.of(context).textTheme.labelMedium),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app.habits.isNotEmpty) ...[
          SectionHeader(s.habits, icon: Icons.spa_outlined),
          for (final h in app.habits.take(3)) ...[
            HabitCard(app: app, habit: h, compact: true),
            const SizedBox(height: 10),
          ],
        ],
        SectionHeader(pinned.isEmpty ? s.recentNotes : s.pinnedNotes, icon: Icons.push_pin_outlined),
        if (recent.isEmpty)
          SoftCard(child: Text(s.noNotes))
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 200,
                child: NoteCard(
                  note: recent[i],
                  now: now,
                  compact: true,
                  onTap: () => NoteEditorPage.open(context, recent[i]),
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          PageHeader(
            title: s.greeting(now.hour),
            subtitle: toBeginningOfSentenceCase(longDate(s, now), s.locale),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 120),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                maxWidth: twoColumns ? 1180 : 820,
                child: twoColumns
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: plan),
                          const SizedBox(width: 28),
                          Expanded(flex: 2, child: side),
                        ],
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [plan, side]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final (done, total) = app.progressOn(app.now());
    final value = total == 0 ? 0.0 : done / total;
    final dark = t.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF3A3358), const Color(0xFF4A3530)]
              : [const Color(0xFFE9E3FB), const Color(0xFFFDE5DA)],
        ),
        boxShadow: softShadow(context),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: value),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      color: c.primary,
                      backgroundColor: c.surfaceContainerLowest.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Text(total == 0 ? '☁️' : '$done/$total', style: t.textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.todaysPlan, style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  total == 0 ? s.nothingToday : (done == total ? s.allDone : s.progressLabel(done, total)),
                  style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: s.newTask,
            onPressed: () => showTaskEditor(context, app, app.draftTask(due: dateOnly(app.now())), isNew: true),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
