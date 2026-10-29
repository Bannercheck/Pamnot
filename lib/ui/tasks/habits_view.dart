import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/habit.dart';
import '../../state/app_controller.dart';
import '../../theme/pamnot_theme.dart';
import '../common/soft.dart';

class HabitsSliver extends StatelessWidget {
  const HabitsSliver({super.key, required this.app, required this.padding});

  final AppController app;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final habits = app.habits;
    if (habits.isEmpty) {
      return SliverToBoxAdapter(child: EmptyState(emoji: '🌱', text: s.noHabits));
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 0),
      sliver: SliverList.separated(
        itemCount: habits.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => ContentWidth(child: HabitCard(app: app, habit: habits[i])),
      ),
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({super.key, required this.app, required this.habit, this.compact = false});

  final AppController app;
  final Habit habit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final p = pastelAt(habit.colorIndex);
    final today = dateOnly(app.now());
    final weekStart = startOfWeek(today, mondayFirst: app.settings.mondayFirst);
    final count = habit.countInWeek(weekStart);
    final streak = habit.streak(today);
    final progress = (count / habit.targetPerWeek).clamp(0.0, 1.0);
    return SoftCard(
      onLongPress: () => showHabitEditor(context, app, habit),
      onTap: compact ? null : () => showHabitEditor(context, app, habit),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        color: p.accent,
                        backgroundColor: p.paper(t.brightness),
                      ),
                    ),
                    Text(habit.emoji, style: const TextStyle(fontSize: 20)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(habit.name, style: t.textTheme.titleMedium),
                    Text(
                      '${s.timesAWeek(habit.targetPerWeek)} · $count/${habit.targetPerWeek}',
                      style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (streak > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text('🔥 ${s.streakDays(streak)}',
                      style: t.textTheme.labelMedium?.copyWith(color: c.onSecondaryContainer)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++) _DayBubble(app: app, habit: habit, day: addDays(weekStart, i), today: today),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayBubble extends StatelessWidget {
  const _DayBubble({required this.app, required this.habit, required this.day, required this.today});

  final AppController app;
  final Habit habit;
  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final p = pastelAt(habit.colorIndex);
    final done = habit.doneOn(day);
    final future = day.isAfter(today);
    final isToday = isSameDay(day, today);
    final label = DateFormat('E', S.of(context).locale).format(day);
    return Column(
      children: [
        Text(label.substring(0, label.length.clamp(0, 3)),
            style: t.textTheme.labelSmall?.copyWith(
              color: isToday ? c.primary : c.onSurfaceVariant,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            )),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: future ? null : () => app.toggleHabit(habit.id, day),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? p.accent : (future ? Colors.transparent : p.paper(t.brightness)),
              border: Border.all(
                color: isToday ? p.accent : (future ? c.outlineVariant : Colors.transparent),
                width: isToday ? 2 : 1,
              ),
            ),
            child: done ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
          ),
        ),
      ],
    );
  }
}

const _emojis = ['🌿', '💧', '📖', '🚶', '🧘', '🏃', '🍎', '😴', '✍️', '🎨', '🎵', '🧹', '💊', '🌞', '🫶', '📵'];

Future<void> showHabitEditor(BuildContext context, AppController app, Habit? habit) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => _HabitEditor(app: app, habit: habit),
    );

class _HabitEditor extends StatefulWidget {
  const _HabitEditor({required this.app, required this.habit});

  final AppController app;
  final Habit? habit;

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final _name = TextEditingController(text: widget.habit?.name ?? '');
  late String _emoji = widget.habit?.emoji ?? _emojis.first;
  late int _color = widget.habit?.colorIndex ?? 2;
  late int _target = widget.habit?.targetPerWeek ?? 7;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) {
      final base = widget.habit ?? Habit(id: widget.app.newId(), name: name, createdAt: widget.app.now());
      widget.app.upsertHabit(base.copyWith(name: name, emoji: _emoji, colorIndex: _color, targetPerWeek: _target));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.habit == null ? s.newHabit : s.edit, style: t.textTheme.titleLarge)),
                if (widget.habit != null)
                  IconButton(
                    tooltip: s.delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () {
                      final messenger = ScaffoldMessenger.of(context);
                      final removed = widget.app.deleteHabit(widget.habit!.id);
                      Navigator.pop(context);
                      if (removed != null) {
                        showUndoSnack(messenger, s.deleted, () => widget.app.restoreHabit(removed), s.undo);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.habit == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: s.habitNameHint),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: e == _emoji ? c.primaryContainer : c.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PastelPicker(selected: _color, onChanged: (i) => setState(() => _color = i)),
            const SizedBox(height: 16),
            Text('${s.perWeek}: ${s.timesAWeek(_target)}', style: t.textTheme.labelLarge),
            Slider(
              value: _target.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_target',
              onChanged: (v) => setState(() => _target = v.round()),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _save, child: Text(s.save)),
          ],
        ),
      ),
    );
  }
}
