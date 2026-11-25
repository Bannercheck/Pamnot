import 'package:pamnot/services/calendar/calendar_source.dart';

/// A calendar the test controls.
class FakeCalendarSource implements CalendarSource {
  /// What [access] answers; [request] sets it to [onRequest].
  CalendarAccess state = CalendarAccess.notAsked;

  /// What [request] answers.
  CalendarAccess onRequest = CalendarAccess.granted;

  /// What [calendars] answers.
  List<DeviceCalendarInfo> calendarsList = const [];

  /// What [events] answers (unfiltered).
  List<CalendarEvent> eventsList = const [];

  /// [events] throws instead of answering.
  bool throwOnEvents = false;

  /// Every range passed to [events], in order.
  final List<(DateTime, DateTime)> eventsCalls = [];

  /// How many times [request] was called.
  int requests = 0;

  @override
  bool get isSupported => true;

  @override
  Future<CalendarAccess> access() async => state;

  @override
  Future<CalendarAccess> request() async {
    requests++;
    return state = onRequest;
  }

  @override
  Future<List<DeviceCalendarInfo>> calendars() async => List.of(calendarsList);

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) async {
    eventsCalls.add((from, to));
    if (throwOnEvents) throw StateError('calendar failed');
    return List.of(eventsList);
  }
}
