import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../ui/common/glass.dart';
import 'calendar_item_card.dart' show minTouchTarget;
import 'calendar_models.dart';
import 'calendar_view_controller.dart';

/// The bar over the calendar, on glass: the month and year with the previous
/// and next arrows, the "Pamnot tasks" switch, Today, and Day · Week · Month.
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({super.key, required this.controller});

  final CalendarViewController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final s = S.of(context);
          final t = Theme.of(context);
          final c = t.colorScheme;
          final anchor = controller.anchor;
          final title = toBeginningOfSentenceCase(DateFormat('MMMM y', s.locale).format(anchor));
          // onSurface keeps 4.5:1 on the glass fill and on the plain surface.
          final ink = ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(c.onSurface),
            minimumSize: const WidgetStatePropertyAll(Size(minTouchTarget, minTouchTarget)),
          );
          return GlassPanel(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: s.previous,
                      color: c.onSurface,
                      style: IconButton.styleFrom(minimumSize: const Size(minTouchTarget, minTouchTarget)),
                      onPressed: () => controller.shift(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: t.textTheme.titleMedium?.copyWith(color: c.onSurface, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: s.next,
                      color: c.onSurface,
                      style: IconButton.styleFrom(minimumSize: const Size(minTouchTarget, minTouchTarget)),
                      onPressed: () => controller.shift(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _PamnotToggle(controller: controller, style: ink),
                    TextButton.icon(
                      key: const Key('calendar-today'),
                      style: ink,
                      onPressed: controller.goToday,
                      icon: const Icon(Icons.today_rounded),
                      label: Text(s.today),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Center(
                  child: SegmentedButton<CalendarViewMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(minTouchTarget, minTouchTarget)),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    segments: [
                      ButtonSegment(value: CalendarViewMode.day, label: Text(s.day)),
                      ButtonSegment(value: CalendarViewMode.week, label: Text(s.week)),
                      ButtonSegment(value: CalendarViewMode.month, label: Text(s.month)),
                    ],
                    selected: {controller.mode},
                    onSelectionChanged: (v) => controller.mode = v.first,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Shows or hides the Pamnot tasks and reminders. The icon changes with the
/// state (not only the colour) and VoiceOver reads it as a switch.
class _PamnotToggle extends StatelessWidget {
  const _PamnotToggle({required this.controller, required this.style});

  final CalendarViewController controller;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = Theme.of(context).colorScheme;
    final on = controller.showPamnot;
    void toggle() => controller.showPamnot = !on;
    return Semantics(
      key: const Key('calendar-pamnot-toggle'),
      container: true,
      button: true,
      toggled: on,
      label: s.calendarPamnotToggle,
      value: on ? s.calendarPamnotOn : s.calendarPamnotOff,
      onTap: toggle,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        style: style.copyWith(
          backgroundColor: WidgetStatePropertyAll(on ? c.secondaryContainer : Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(on ? c.onSecondaryContainer : c.onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
        ),
        onPressed: toggle,
        icon: Icon(on ? Icons.visibility_rounded : Icons.visibility_off_rounded),
        label: Text(s.calendarPamnotToggle),
      ),
    );
  }
}
