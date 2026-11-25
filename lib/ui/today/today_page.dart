import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamnot_theme.dart';
import '../common/format.dart';
import '../common/glass_nav_bar.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import '../guide/shortcut_guide_page.dart';
import '../notes/note_card.dart';
import '../notes/note_editor_page.dart';
import '../notes/notes_page.dart';
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
        // Adds to the last used list (AppController.currentListId).
        QuickAddField(app: app, hint: s.quickCapture),
        // Once, after the first save by voice (design §10).
        if (app.speech.isSupported && app.settings.voiceUsed && !app.settings.guideCardDismissed) ...[
          const SizedBox(height: 12),
          _GuideCard(app: app),
        ],
        SectionHeader(s.todaysPlan, icon: Icons.wb_sunny_outlined),
        if (overdue.isEmpty && todays.isEmpty && reminders.isEmpty)
          SoftCard(child: Text(s.nothingToday, style: Theme.of(context).textTheme.bodyLarge))
        else ...[
          // Today mixes every list; each row shows its list's dot.
          for (final t in overdue) ...[TaskTile(app: app, task: t, showList: true), const SizedBox(height: 8)],
          for (final t in todays) ...[
            TaskTile(app: app, task: t, showDate: false, showList: true),
            const SizedBox(height: 8),
          ],
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
            // Grows with the system text size so the cards' text fits.
            height: MediaQuery.textScalerOf(context).scale(196),
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
                  onLongPress: () => showNoteActions(context, app, recent[i]),
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
            padding: EdgeInsets.fromLTRB(pad, 8, pad, scrollEndSpace(context)),
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

/// The one-time card that points to the "Shortcuts & Siri" guide. Opening
/// the guide closes it for good, the same as its close button.
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.app});

  final AppController app;

  void _dismiss() => app.updateSettings(app.settings.copyWith(guideCardDismissed: true));

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: t.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(s.guideCardTitle, style: t.textTheme.titleMedium)),
              IconButton(
                key: const Key('guide-card-close'),
                tooltip: s.close,
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(s.guideCardBody, style: t.textTheme.bodyMedium),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('guide-card-open'),
            onPressed: () {
              _dismiss();
              ShortcutGuidePage.open(context);
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(s.guideOpen),
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
    // The ring grows with the system text size so the count inside fits.
    // When it gets that big the text moves below it instead of being
    // squeezed beside it.
    final ring = MediaQuery.textScalerOf(context).scale(74);
    final stacked = ring > 100;
    final progress = SizedBox(
      width: ring,
      height: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: value),
              duration: motion(context, const Duration(milliseconds: 650)),
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
          // The cloud is decoration; the text beside it says there is nothing today.
          total == 0
              ? ExcludeSemantics(child: Text('☁️', style: t.textTheme.titleMedium))
              : Text('$done/$total', style: t.textTheme.titleMedium),
        ],
      ),
    );
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.todaysPlan, style: t.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          total == 0 ? s.nothingToday : (done == total ? s.allDone : s.progressLabel(done, total)),
          style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
    final add = IconButton.filledTonal(
      tooltip: s.newTask,
      onPressed: () => showTaskEditor(context, app, app.draftTask(due: dateOnly(app.now())), isNew: true),
      icon: const Icon(Icons.add_rounded),
    );
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
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [progress, const Spacer(), add]),
                const SizedBox(height: 14),
                summary,
              ],
            )
          : Row(
              children: [
                progress,
                const SizedBox(width: 18),
                Expanded(child: summary),
                add,
              ],
            ),
    );
  }
}
