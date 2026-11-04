import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/dates.dart';
import '../../l10n/board_strings.dart';
import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../model/board_item.dart';
import 'board_widgets.dart';

/// Who a card is assigned to, as far as this device knows.
class CardAssignee {
  const CardAssignee({required this.label, this.avatarName, this.colorIndex = 3});

  /// Read out by screen readers ("Ayşe", "Ben", "Biri").
  final String label;

  /// Initials source; null shows a person icon.
  final String? avatarName;
  final int colorIndex;
}

/// One card as Kanban (and the drag feedback) shows it: colour stripe,
/// title, then a meta row with the due date, subtasks, a notes mark and
/// the assignee (docs/boards/DESIGN.md §9, ux_specs §6).
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.card,
    required this.columnTitle,
    required this.now,
    this.done = false,
    this.assignee,
    this.onTap,
    this.actions = const {},
    this.lifted = false,
  });

  final BoardItem card;

  /// The column the card shows in (for the screen reader label).
  final String columnTitle;
  final DateTime now;

  /// The card sits in a done column.
  final bool done;

  /// Only on shared boards.
  final CardAssignee? assignee;
  final VoidCallback? onTap;

  /// Screen reader moves (next/previous column, up/down).
  final Map<CustomSemanticsAction, VoidCallback> actions;

  /// Drawn as drag feedback: a deeper shadow.
  final bool lifted;

  /// The same card as drag feedback (no tap, no actions).
  CardFace asFeedback() => CardFace(
        card: card,
        columnTitle: columnTitle,
        now: now,
        done: done,
        assignee: assignee,
        lifted: true,
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final accent = pastelAt(card.colorIndex).accent;
    final due = card.dueDate;
    final overdue = !done && due != null && due.isBefore(dateOnly(now));
    final dueText = due == null ? null : dueLabel(s, due, now);
    final subs = card.subtasks;
    final subsDone = subs.where((x) => x.done).length;
    final title = card.title.trim().isEmpty ? s.untitled : card.title;
    final muted = c.onSurfaceVariant;

    final meta = <Widget>[
      if (dueText != null)
        _DueChip(text: overdue ? s.overdueOn(dueText) : dueText, overdue: overdue),
      if (subs.isNotEmpty)
        _Meta(
          icon: subsDone == subs.length ? Icons.check_box_rounded : Icons.check_box_outlined,
          text: '$subsDone/${subs.length}',
        ),
      if (card.notes.trim().isNotEmpty) Icon(Icons.notes_rounded, size: 15, color: muted),
    ];
    final person = assignee;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (done) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.check_circle_rounded, size: 18, color: c.tertiary),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleSmall?.copyWith(color: done ? muted : c.onSurface, height: 1.3),
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty || person != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: meta,
                  ),
                ),
                if (person != null) PersonAvatar(name: person.avatarName, colorIndex: person.colorIndex, size: 22),
              ],
            ),
          ],
        ],
      ),
    );

    final radius = BorderRadius.circular(16);
    return Semantics(
      container: true,
      button: onTap != null,
      excludeSemantics: true,
      label: s.cardSemantics(
        title: title,
        column: columnTitle,
        due: dueText == null ? null : (overdue ? s.overdueOn(dueText) : dueText),
        assignee: person?.label,
        subtasksDone: subsDone,
        subtasks: subs.length,
        done: done,
      ),
      onTap: onTap,
      customSemanticsActions: actions.isEmpty ? null : actions,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: softShadow(context, strength: lifted ? 2.2 : 0.7),
        ),
        // No clip layer per card: the stripe is a pill inside the card and
        // the ink splash is clipped by the InkWell's own radius.
        child: Material(
          color: c.surfaceContainerLowest,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Stack(
              children: [
                body,
                Positioned(
                  left: 6,
                  top: 10,
                  bottom: 10,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DueChip extends StatelessWidget {
  const _DueChip({required this.text, required this.overdue});

  final String text;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final fg = overdue ? c.onErrorContainer : c.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: overdue ? c.errorContainer : c.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(overdue ? Icons.event_busy_rounded : Icons.event_rounded, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(text, style: t.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final col = t.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: col),
        const SizedBox(width: 3),
        Text(text, style: t.textTheme.labelMedium?.copyWith(color: col)),
      ],
    );
  }
}
