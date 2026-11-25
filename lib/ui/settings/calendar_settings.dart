import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/calendar/calendar_source.dart';
import '../../services/links.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/soft.dart';

/// Settings > "Calendar": the switch that shows device calendar events in
/// Plan (turning it on asks for access the first time), why events are
/// missing when access was refused, and which calendars to show. Only shown
/// when [AppController.calendar] is supported.
class CalendarSettingsGroup extends StatefulWidget {
  const CalendarSettingsGroup({super.key, required this.app});

  final AppController app;

  @override
  State<CalendarSettingsGroup> createState() => _CalendarSettingsGroupState();
}

class _CalendarSettingsGroupState extends State<CalendarSettingsGroup> {
  @override
  void initState() {
    super.initState();
    // The calendar list and the access may have changed since the last look;
    // reading them never prompts.
    if (widget.app.settings.showCalendar) unawaited(widget.app.refreshCalendar());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.settings, Slice.calendar});
    final s = S.of(context);
    final t = Theme.of(context);
    final st = app.settings;
    final denied = app.calendarAccess == CalendarAccess.denied;
    final on = st.showCalendar && !denied;
    final hidden = st.hiddenCalendarIds.toSet();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(s.calendarSection),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.event_rounded),
                  title: Text(s.calendarEvents),
                  subtitle: Text(s.calendarEventsSub),
                  value: on,
                  onChanged: (v) {
                    if (v) {
                      unawaited(app.enableCalendar());
                    } else {
                      app.updateSettings(app.settings.copyWith(showCalendar: false));
                    }
                  },
                ),
                if (denied)
                  ListTile(
                    leading: const Icon(Icons.event_busy_rounded),
                    title: Text(s.calendarDenied),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                    onTap: openAppSettings,
                  ),
                if (on && app.deviceCalendars.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      s.calendarsToShow,
                      style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  for (final cal in app.deviceCalendars)
                    CheckboxListTile(
                      key: Key('calendar-${cal.id}'),
                      secondary: ExcludeSemantics(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cal.color == null ? t.colorScheme.primary : Color(cal.color!),
                            shape: BoxShape.circle,
                            border: Border.all(color: t.colorScheme.outline),
                          ),
                        ),
                      ),
                      title: Text(cal.name),
                      subtitle: cal.account == null || cal.account!.isEmpty ? null : Text(cal.account!),
                      value: !hidden.contains(cal.id),
                      onChanged: (v) => app.setCalendarHidden(cal.id, v == false),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    s.calendarOutlookHint,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
