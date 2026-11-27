import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../ui/common/format.dart';
import 'calendar_models.dart';

/// A calendar event, read-only: title, date and time range, the calendar's
/// name and why it cannot be changed here. There is nothing to edit.
Future<void> showEventDetail(BuildContext context, DayItem event, {String? calendarName}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _EventDetail(event: event, calendarName: calendarName),
        ),
      ),
    );

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event, this.calendarName});

  final DayItem event;
  final String? calendarName;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final title = event.title.trim().isEmpty ? s.untitledEvent : event.title;
    final when = event.allDay
        ? '${longDate(s, event.start)} · ${s.allDay}'
        : '${longDate(s, event.start)} · ${hhmm(event.start)}–${hhmm(event.end)}';
    final name = calendarName?.trim();
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: c.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: t.textTheme.bodyLarge?.copyWith(color: c.onSurface))),
            ],
          ),
        );
    return Column(
      key: const Key('event-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.eventDetails, style: t.textTheme.labelLarge?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: event.argb == null ? c.primary : Color(event.argb!)),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: t.textTheme.titleLarge?.copyWith(color: c.onSurface))),
              ],
            ),
          ),
        ),
        line(Icons.schedule_rounded, when),
        if (name != null && name.isNotEmpty) line(Icons.event_rounded, '${s.eventCalendar}: $name'),
        line(Icons.lock_outline_rounded, s.eventReadOnly),
      ],
    );
  }
}
