/// Whether Pamnot may read the device calendar (design §9, read-only).
enum CalendarAccess {
  /// This platform has no calendar support (everything but iOS).
  unsupported,

  /// The user has not been asked yet.
  notAsked,

  /// The user said no, or access is restricted.
  denied,

  /// Full read access.
  granted,
}

/// One calendar on the device (iCloud, Google, Outlook, …).
class DeviceCalendarInfo {
  const DeviceCalendarInfo({required this.id, required this.name, this.color, this.account});

  final String id, name;

  /// ARGB.
  final int? color;

  /// The account the calendar belongs to, e.g. "iCloud".
  final String? account;
}

/// One event, as read from the device calendar. Never written back.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.color,
  });

  final String id, calendarId, title;
  final DateTime start, end;
  final bool allDay;

  /// ARGB.
  final int? color;

  /// Etkinlik [day] gününe değiyor mu (çok günlü ve tüm gün etkinlikler dahil;
  /// bitişi 00:00 olan gün sayılmaz).
  ///
  /// The time of [day] is ignored. An event that lasts no time at all touches
  /// the day it starts on.
  bool occursOn(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    if (!end.isAfter(start)) return !start.isBefore(dayStart) && start.isBefore(dayEnd);
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }
}

/// Reads the device calendar. Asking for access happens only through
/// [request], and only when the user turns the calendar on (design §9).
abstract class CalendarSource {
  /// Whether this platform can show calendar events at all. Never touches
  /// the plugin.
  bool get isSupported;

  /// The current access; never shows a prompt.
  Future<CalendarAccess> access();

  /// Asks for full (read) access and answers the result.
  Future<CalendarAccess> request();

  /// The calendars on the device; empty without access.
  Future<List<DeviceCalendarInfo>> calendars();

  /// The events that overlap [from, to); empty without access.
  Future<List<CalendarEvent>> events(DateTime from, DateTime to);
}

/// No calendar (every platform but iOS, and tests that do not care).
class NoCalendarSource implements CalendarSource {
  @override
  bool get isSupported => false;

  @override
  Future<CalendarAccess> access() async => CalendarAccess.unsupported;

  @override
  Future<CalendarAccess> request() async => CalendarAccess.unsupported;

  @override
  Future<List<DeviceCalendarInfo>> calendars() async => const [];

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async => const [];
}
