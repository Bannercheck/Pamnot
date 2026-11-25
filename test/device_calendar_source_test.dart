import 'package:device_calendar_plus/device_calendar_plus.dart' as dcp;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/services/calendar/device_calendar_source.dart';

/// A scripted plugin: answers what the test sets, or throws [error].
class FakeApi implements DeviceCalendarApi {
  dcp.CalendarPermissionStatus status = dcp.CalendarPermissionStatus.notDetermined;
  dcp.CalendarPermissionStatus requestAnswer = dcp.CalendarPermissionStatus.granted;
  List<dcp.Calendar> cals = [];
  List<dcp.Event> evs = [];
  Object? error;
  int requests = 0;
  final List<(DateTime, DateTime)> queries = [];

  void _maybeThrow() {
    if (error != null) throw error!;
  }

  @override
  Future<dcp.CalendarPermissionStatus> hasPermissions() async {
    _maybeThrow();
    return status;
  }

  @override
  Future<dcp.CalendarPermissionStatus> requestPermissions() async {
    requests++;
    _maybeThrow();
    return requestAnswer;
  }

  @override
  Future<List<dcp.Calendar>> listCalendars() async {
    _maybeThrow();
    return cals;
  }

  @override
  Future<List<dcp.Event>> listEvents(DateTime start, DateTime end) async {
    queries.add((start, end));
    _maybeThrow();
    return evs;
  }
}

dcp.Calendar cal(String id, {String name = 'Cal', String? colorHex, bool hidden = false, String? account}) =>
    dcp.Calendar(id: id, name: name, colorHex: colorHex, readOnly: false, hidden: hidden, accountName: account);

dcp.Event event({
  String eventId = 'ev',
  String instanceId = 'ev@1',
  String calendarId = 'c1',
  String title = 'Toplantı',
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String? colorHex,
}) => dcp.Event(
  eventId: eventId,
  instanceId: instanceId,
  calendarId: calendarId,
  title: title,
  startDate: start,
  endDate: end,
  isAllDay: allDay,
  availability: dcp.EventAvailability.busy,
  status: dcp.EventStatus.confirmed,
  isRecurring: false,
  colorHex: colorHex,
);

void main() {
  late FakeApi api;
  late DeviceCalendarSource source;

  setUp(() {
    api = FakeApi();
    source = DeviceCalendarSource(api: api);
  });

  test('isSupported: true', () {
    expect(source.isSupported, isTrue);
  });

  group('izin durumu eşlemesi', () {
    const expected = {
      dcp.CalendarPermissionStatus.granted: CalendarAccess.granted,
      dcp.CalendarPermissionStatus.notDetermined: CalendarAccess.notAsked,
      dcp.CalendarPermissionStatus.denied: CalendarAccess.denied,
      dcp.CalendarPermissionStatus.restricted: CalendarAccess.denied,
      dcp.CalendarPermissionStatus.writeOnly: CalendarAccess.denied,
    };

    test('access(): beş durum, istek yapılmaz', () async {
      for (final entry in expected.entries) {
        api.status = entry.key;
        expect(await source.access(), entry.value, reason: '${entry.key}');
      }
      expect(api.requests, 0);
    });

    test('request(): beş durum', () async {
      for (final entry in expected.entries) {
        api.requestAnswer = entry.key;
        expect(await source.request(), entry.value, reason: '${entry.key}');
      }
      expect(api.requests, expected.length);
    });
  });

  test('gizli takvimler listelenmez; ad, hesap ve renk geçer', () async {
    api.cals = [
      cal('c1', name: 'iCloud', colorHex: '#86B4DE', account: 'iCloud'),
      cal('c2', name: 'Gizli', hidden: true),
      cal('c3', name: 'Outlook'),
    ];
    final list = await source.calendars();
    expect(list.map((c) => c.id), ['c1', 'c3']);
    expect(list[0].name, 'iCloud');
    expect(list[0].account, 'iCloud');
    expect(list[0].color, 0xFF86B4DE);
    expect(list[1].color, isNull);
  });

  group('argbFromHex', () {
    test('#RRGGBB → opak ARGB', () {
      expect(argbFromHex('#86B4DE'), 0xFF86B4DE);
      expect(argbFromHex('#86b4de'), 0xFF86B4DE);
      expect(argbFromHex('#000000'), 0xFF000000);
    });

    test('bozuk ya da eksik metin → null', () {
      for (final bad in [null, '', '#', 'zzzzzz', '#12345', '#1234567', '#GGHHII', '86B4DE#', '#86B4DE00']) {
        expect(argbFromHex(bad), isNull, reason: '$bad');
      }
    });
  });

  test('etkinlik eşlemesi: instanceId → id, tüm gün bayrağı, renk ve boş başlık', () async {
    api.cals = [cal('c1', colorHex: '#86B4DE'), cal('c2', colorHex: '#112233')];
    api.evs = [
      event(
        instanceId: 'a@1',
        calendarId: 'c1',
        title: 'Diş hekimi',
        start: DateTime(2026, 11, 25, 10),
        end: DateTime(2026, 11, 25, 11),
      ),
      event(
        instanceId: 'b@2',
        calendarId: 'c2',
        title: '',
        start: DateTime(2026, 11, 26),
        end: DateTime(2026, 11, 27),
        allDay: true,
        colorHex: '#FF0000',
      ),
    ];
    final from = DateTime(2026, 11, 23), to = DateTime(2026, 11, 30);
    final list = await source.events(from, to);
    expect(api.queries, [(from, to)]);
    expect(list, hasLength(2));

    final a = list[0];
    expect(a.id, 'a@1');
    expect(a.calendarId, 'c1');
    expect(a.title, 'Diş hekimi');
    expect(a.start, DateTime(2026, 11, 25, 10));
    expect(a.end, DateTime(2026, 11, 25, 11));
    expect(a.allDay, isFalse);
    expect(a.color, 0xFF86B4DE, reason: 'etkinlik rengi yoksa takviminki');

    final b = list[1];
    expect(b.id, 'b@2');
    expect(b.title, '', reason: 'boş başlık olduğu gibi geçer');
    expect(b.allDay, isTrue);
    expect(b.color, 0xFFFF0000, reason: 'etkinliğin kendi rengi önce gelir');
  });

  test('gizli takvimin etkinlikleri gösterilmez', () async {
    api.cals = [cal('c1'), cal('c2', hidden: true)];
    api.evs = [
      event(instanceId: 'a', calendarId: 'c1', start: DateTime(2026, 11, 25, 9), end: DateTime(2026, 11, 25, 10)),
      event(instanceId: 'b', calendarId: 'c2', start: DateTime(2026, 11, 25, 9), end: DateTime(2026, 11, 25, 10)),
    ];
    final list = await source.events(DateTime(2026, 11, 23), DateTime(2026, 11, 30));
    expect(list.map((e) => e.id), ['a']);
  });

  group('eklenti hata fırlatınca çökme yok', () {
    late List<String?> logs;
    late DebugPrintCallback original;

    setUp(() {
      logs = [];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logs.add(message);
    });

    tearDown(() => debugPrint = original);

    for (final error in <Object>[
      const dcp.DeviceCalendarException(errorCode: dcp.DeviceCalendarError.permissionDenied, message: 'no'),
      StateError('boom'),
    ]) {
      test('${error.runtimeType}: boş listeler, denied, hata yazılır', () async {
        api.error = error;
        expect(await source.calendars(), isEmpty);
        expect(await source.events(DateTime(2026, 11, 23), DateTime(2026, 11, 30)), isEmpty);
        expect(await source.access(), CalendarAccess.denied);
        expect(await source.request(), CalendarAccess.denied);
        expect(logs, hasLength(4));
      });
    }
  });

  group('createCalendarSource', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('test ortamında (iOS olmayan) NoCalendarSource', () {
      expect(createCalendarSource(), isA<NoCalendarSource>());
      for (final p in [TargetPlatform.android, TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = p;
        expect(createCalendarSource(), isA<NoCalendarSource>(), reason: '$p');
      }
    });

    test('iOS: DeviceCalendarSource (kurmak eklentiyi çağırmaz)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(createCalendarSource(), isA<DeviceCalendarSource>());
    });
  });
}
