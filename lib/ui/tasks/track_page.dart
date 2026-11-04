import 'package:flutter/material.dart';

import '../../boards/ui/board_list.dart';
import '../../boards/ui/new_board_sheet.dart';
import '../../core/dates.dart';
import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../models/settings.dart';
import '../../models/task.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/page_header.dart';
import '../common/soft.dart';
import 'habits_view.dart';
import 'task_editor.dart';
import 'task_tile.dart';

enum _Filter { all, today, upcoming, done }

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.tasks, Slice.habits, Slice.settings});
    final s = S.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final pad = wide ? 28.0 : 16.0;
    // Remembered across launches; a task notification switches back to tasks.
    final segment = app.settings.trackSegment;
    // Three labels with icons get clipped on a 360 dp phone.
    final icons = width >= 420;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'track-fab',
        onPressed: () => switch (segment) {
          TrackSegment.tasks => showTaskEditor(context, app, app.draftTask(), isNew: true),
          TrackSegment.habits => showHabitEditor(context, app, null),
          TrackSegment.boards => showNewBoardSheet(context),
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(switch (segment) {
          TrackSegment.tasks => s.newTask,
          TrackSegment.habits => s.newHabit,
          TrackSegment.boards => s.newBoard,
        }),
      ),
      body: CustomScrollView(
        slivers: [
          PageHeader(
            title: s.tasks,
            actions: [
              if (segment == TrackSegment.boards)
                IconButton(
                  tooltip: s.joinInvite,
                  onPressed: () => joinBoardFromInvite(context),
                  icon: const Icon(Icons.group_add_outlined),
                ),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            sliver: SliverToBoxAdapter(
              child: ContentWidth(
                child: SegmentedButton<TrackSegment>(
                  showSelectedIcon: false,
                  segments: [
                    for (final (v, label, icon) in [
                      (TrackSegment.tasks, s.tasksTab, Icons.check_circle_outline_rounded),
                      (TrackSegment.habits, s.habits, Icons.spa_outlined),
                      (TrackSegment.boards, s.boards, Icons.dashboard_outlined),
                    ])
                      ButtonSegment(value: v, label: Text(label, maxLines: 1), icon: icons ? Icon(icon) : null),
                  ],
                  selected: {segment},
                  onSelectionChanged: (v) => app.updateSettings(app.settings.copyWith(trackSegment: v.first)),
                ),
              ),
            ),
          ),
          if (segment == TrackSegment.habits)
            HabitsSliver(app: app, padding: pad)
          else if (segment == TrackSegment.boards)
            BoardsSliver(padding: pad)
          else ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 4),
              sliver: SliverToBoxAdapter(child: ContentWidth(child: QuickAddField(app: app))),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 6, pad, 0),
              sliver: SliverToBoxAdapter(
                child: ContentWidth(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final (f, label) in [
                        (_Filter.all, s.filterAll),
                        (_Filter.today, s.filterToday),
                        (_Filter.upcoming, s.filterUpcoming),
                        (_Filter.done, s.filterDone),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ..._taskSlivers(context, app, pad),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<Widget> _taskSlivers(BuildContext context, AppController app, double pad) {
    final s = S.of(context);
    final today = dateOnly(app.now());
    final tomorrow = addDays(today, 1);
    final open = app.tasks.where((t) => !t.done).toList();
    final groups = <(String, List<TaskItem>)>[];
    // By day; within a day timed tasks first (like the agenda), then priority.
    List<TaskItem> sorted(Iterable<TaskItem> l) => l.toList()
      ..sort((a, b) {
        if (a.due == null || b.due == null) return a.createdAt.compareTo(b.createdAt);
        var c = dateOnly(a.due!).compareTo(dateOnly(b.due!));
        if (c != 0) return c;
        if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
        c = a.due!.compareTo(b.due!);
        return c != 0 ? c : b.priority.index.compareTo(a.priority.index);
      });
    bool on(TaskItem t, DateTime d) => t.due != null && isSameDay(t.due!, d);

    switch (_filter) {
      case _Filter.all:
        groups.addAll([
          (s.overdue, sorted(open.where((t) => t.due != null && dateOnly(t.due!).isBefore(today)))),
          (s.today, sorted(app.tasksDueOn(today))),
          (s.tomorrow, sorted(open.where((t) => on(t, tomorrow)))),
          (s.later, sorted(open.where((t) => t.due != null && dateOnly(t.due!).isAfter(tomorrow)))),
          (s.someday, sorted(open.where((t) => t.due == null))),
        ]);
      case _Filter.today:
        groups.addAll([
          (s.overdue, sorted(open.where((t) => t.due != null && dateOnly(t.due!).isBefore(today)))),
          (s.today, sorted(app.tasksDueOn(today))),
        ]);
      case _Filter.upcoming:
        groups.add((s.upcoming, sorted(open.where((t) => t.due != null && dateOnly(t.due!).isAfter(today)))));
      case _Filter.done:
        final done = app.tasks.where((t) => t.done).toList()
          ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
        groups.add((s.completed, done));
    }
    final visible = groups.where((g) => g.$2.isNotEmpty).toList();
    if (visible.isEmpty) {
      return [SliverToBoxAdapter(child: EmptyState(emoji: '🌸', text: s.noTasks))];
    }
    return [
      for (final (title, list) in visible) ...[
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverToBoxAdapter(
            child: ContentWidth(child: SectionHeader('$title · ${list.length}')),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => ContentWidth(
              child: TaskTile(
                key: ValueKey(list[i].id),
                app: app,
                task: list[i],
                showDate: title != s.today && title != s.tomorrow,
              ),
            ),
          ),
        ),
      ],
    ];
  }
}
