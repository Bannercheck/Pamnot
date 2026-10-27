import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../../theme/pamuk_theme.dart';
import '../common/format.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import 'reminder_editor.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.reminders, Slice.settings});
    final s = S.of(context);
    final now = app.now();
    final today = dateOnly(now);
    final wide = MediaQuery.sizeOf(context).width >= 560;
    final pad = wide ? 28.0 : 16.0;

    final withNext = [
      for (final r in app.reminders) (r, r.nextOccurrence(now)),
    ];
    int byNext((Reminder, DateTime?) a, (Reminder, DateTime?) b) =>
        (a.$2 ?? a.$1.at).compareTo(b.$2 ?? b.$1.at);
    final todayList = withNext.where((e) => e.$2 != null && isSameDay(e.$2!, today) && e.$1.repeat == Repeat.none).toList()..sort(byNext);
    final upcoming = withNext.where((e) => e.$2 != null && !isSameDay(e.$2!, today) && e.$1.repeat == Repeat.none).toList()..sort(byNext);
    final recurring = withNext.where((e) => e.$1.repeat != Repeat.none).toList()..sort(byNext);
    final past = withNext.where((e) => e.$1.repeat == Repeat.none && (e.$2 == null)).toList()
      ..sort((a, b) => b.$1.at.compareTo(a.$1.at));

    final groups = [
      (s.today, todayList),
      (s.upcoming, upcoming),
      (s.recurring, recurring),
      (s.past, past),
    ].where((g) => g.$2.isNotEmpty).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'rem-fab',
        onPressed: () => showReminderEditor(context, app, app.draftReminder(), isNew: true),
        icon: const Icon(Icons.add_alert_rounded),
        label: Text(s.newReminder),
      ),
      body: CustomScrollView(
        slivers: [
          PageHeader(title: s.reminders),
          if (!app.scheduler.schedulesInBackground)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(
                  child: SoftCard(
                    shadow: false,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.notificationsUnsupported)),
                    ]),
                  ),
                ),
              ),
            ),
          if (groups.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: EmptyState(emoji: '🔔', text: s.noReminders))
          else
            for (final (title, list) in groups) ...[
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverToBoxAdapter(child: ContentWidth(child: SectionHeader(title))),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => ContentWidth(
                    child: ReminderTile(app: app, reminder: list[i].$1, next: list[i].$2),
                  ),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.app, required this.reminder, required this.next});

  final AppController app;
  final Reminder reminder;
  final DateTime? next;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final p = pastelAt(reminder.colorIndex);
    final when = next ?? reminder.at;
    final subtitle = [
      formatWhen(s, when, now: app.now()),
      if (reminder.repeat != Repeat.none) repeatLabel(s, reminder.repeat),
      if (reminder.note.isNotEmpty) reminder.note,
    ].join(' · ');
    return Opacity(
      opacity: reminder.enabled ? 1 : 0.6,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        onTap: () => showReminderEditor(context, app, reminder),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.paper(t.brightness), borderRadius: BorderRadius.circular(15)),
              child: Icon(
                reminder.repeat == Repeat.none ? Icons.notifications_none_rounded : Icons.repeat_rounded,
                color: p.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.title, style: t.textTheme.titleSmall?.copyWith(fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Switch(value: reminder.enabled, onChanged: (_) => app.toggleReminder(reminder.id)),
          ],
        ),
      ),
    );
  }
}
