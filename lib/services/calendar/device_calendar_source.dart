import 'package:device_calendar_plus/device_calendar_plus.dart' as dcp;
import 'package:flutter/foundation.dart';

import 'calendar_source.dart';

/// The calendar for this platform: the device calendar on iOS, none elsewhere.
/// Building it asks for nothing and does not call the plugin.
CalendarSource createCalendarSource() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? DeviceCalendarSource() : NoCalendarSource();

/// The part of `device_calendar_plus` Pamnot uses; tests implement it.
abstract class DeviceCalendarApi {
  Future<dcp.CalendarPermissionStatus> hasPermissions();
  Future<dcp.CalendarPermissionStatus> requestPermissions();
  Future<List<dcp.Calendar>> listCalendars();
  Future<List<dcp.Event>> listEvents(DateTime start, DateTime end);
}

/// [DeviceCalendarApi] over `DeviceCalendar.instance`. `autoPermissions` stays
/// off, so the plugin never prompts on its own: only [CalendarSource.request]
/// asks.
class _PluginDeviceCalendarApi implements DeviceCalendarApi {
  dcp.DeviceCalendar get _plugin => dcp.DeviceCalendar.instance;

  @override
  Future<dcp.CalendarPermissionStatus> hasPermissions() => _plugin.hasPermissions();

  @override
  Future<dcp.CalendarPermissionStatus> requestPermissions() => _plugin.requestPermissions();

  @override
  Future<List<dcp.Calendar>> listCalendars() => _plugin.listCalendars();

  @override
  Future<List<dcp.Event>> listEvents(DateTime start, DateTime end) => _plugin.listEvents(start, end);
}

final _hexColor = RegExp(r'^#([0-9a-fA-F]{6})$');

/// `#RRGGBB` as an opaque ARGB int; null for anything else.
int? argbFromHex(String? hex) {
  final match = hex == null ? null : _hexColor.firstMatch(hex);
  if (match == null) return null;
  return 0xFF000000 | int.parse(match.group(1)!, radix: 16);
}

/// Reads the iOS calendar through `device_calendar_plus`, read-only
/// (design §9). Every plugin failure is logged and answered as no access or
/// an empty list, never thrown.
class DeviceCalendarSource implements CalendarSource {
  DeviceCalendarSource({DeviceCalendarApi? api}) : _api = api ?? _PluginDeviceCalendarApi();

  final DeviceCalendarApi _api;

  @override
  bool get isSupported => true;

  @override
  Future<CalendarAccess> access() => _status('access', _api.hasPermissions);

  @override
  Future<CalendarAccess> request() => _status('request', _api.requestPermissions);

  @override
  Future<List<DeviceCalendarInfo>> calendars() async {
    try {
      return [
        for (final c in await _api.listCalendars())
          if (!c.hidden)
            DeviceCalendarInfo(id: c.id, name: c.name, color: argbFromHex(c.colorHex), account: c.accountName),
      ];
    } catch (e) {
      debugPrint('Calendar list failed: $e');
      return const [];
    }
  }

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    try {
      // Calendar colors for events without their own; hidden calendars stay hidden.
      final calendars = await _api.listCalendars();
      final hidden = {
        for (final c in calendars)
          if (c.hidden) c.id,
      };
      final colors = {for (final c in calendars) c.id: argbFromHex(c.colorHex)};
      return [
        for (final e in await _api.listEvents(from, to))
          if (!hidden.contains(e.calendarId))
            CalendarEvent(
              id: e.instanceId,
              calendarId: e.calendarId,
              title: e.title,
              start: e.startDate,
              end: e.endDate,
              allDay: e.isAllDay,
              color: argbFromHex(e.colorHex) ?? colors[e.calendarId],
            ),
      ];
    } catch (e) {
      debugPrint('Calendar events failed: $e');
      return const [];
    }
  }

  Future<CalendarAccess> _status(String what, Future<dcp.CalendarPermissionStatus> Function() call) async {
    try {
      return switch (await call()) {
        dcp.CalendarPermissionStatus.granted => CalendarAccess.granted,
        dcp.CalendarPermissionStatus.notDetermined => CalendarAccess.notAsked,
        dcp.CalendarPermissionStatus.denied ||
        dcp.CalendarPermissionStatus.restricted ||
        dcp.CalendarPermissionStatus.writeOnly => CalendarAccess.denied,
      };
    } catch (e) {
      debugPrint('Calendar $what failed: $e');
      return CalendarAccess.denied;
    }
  }
}
