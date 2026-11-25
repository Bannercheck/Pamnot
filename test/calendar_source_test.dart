import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';

import 'support/fake_calendar_source.dart';

void main() {
  CalendarEvent ev(DateTime start, DateTime end, {bool allDay = false}) =>
      CalendarEvent(id: 'e', calendarId: 'c', title: 'T', start: start, end: end, allDay: allDay);

  group('CalendarEvent.occursOn', () {
    test('tek günlük etkinlik yalnız kendi gününe değer', () {
      final e = ev(DateTime(2026, 11, 25, 10), DateTime(2026, 11, 25, 11));
      expect(e.occursOn(DateTime(2026, 11, 24)), isFalse);
      expect(e.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 25, 18, 30)), isTrue, reason: 'günün saati önemsiz');
      expect(e.occursOn(DateTime(2026, 11, 26)), isFalse);
    });

    test('23:00–01:00 iki güne değer', () {
      final e = ev(DateTime(2026, 11, 25, 23), DateTime(2026, 11, 26, 1));
      expect(e.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 26)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 27)), isFalse);
    });

    test('tüm gün 25–27 Kasım üç güne değer; bitişi 28 Kasım 00:00 olan 28\'e değmez', () {
      final e = ev(DateTime(2026, 11, 25), DateTime(2026, 11, 28), allDay: true);
      expect(e.occursOn(DateTime(2026, 11, 24)), isFalse);
      expect(e.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 26)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 27)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 28)), isFalse);
    });

    test('ay ve yıl sınırını geçen etkinlik', () {
      final e = ev(DateTime(2026, 12, 31, 22), DateTime(2027, 1, 1, 2));
      expect(e.occursOn(DateTime(2026, 12, 31)), isTrue);
      expect(e.occursOn(DateTime(2027, 1, 1)), isTrue);
      expect(e.occursOn(DateTime(2027, 1, 2)), isFalse);
    });

    test('süresi sıfır olan etkinlik başladığı güne değer', () {
      final e = ev(DateTime(2026, 11, 25, 9), DateTime(2026, 11, 25, 9));
      expect(e.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(e.occursOn(DateTime(2026, 11, 24)), isFalse);
      final midnight = ev(DateTime(2026, 11, 26), DateTime(2026, 11, 26));
      expect(midnight.occursOn(DateTime(2026, 11, 26)), isTrue);
      expect(midnight.occursOn(DateTime(2026, 11, 25)), isFalse);
    });

    // device_calendar_plus reports an all-day event as local midnight to the
    // next local midnight (EventKit's 23:59:59 end plus one second); an end at
    // the day's last instant must give the same days.
    test('tüm gün: bitişi günün son anı (23:59:59) olan etkinlik ertesi güne değmez', () {
      final one = ev(DateTime(2026, 11, 25), DateTime(2026, 11, 25, 23, 59, 59), allDay: true);
      expect(one.occursOn(DateTime(2026, 11, 24)), isFalse);
      expect(one.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(one.occursOn(DateTime(2026, 11, 26)), isFalse);
      final three = ev(DateTime(2026, 11, 25), DateTime(2026, 11, 27, 23, 59, 59, 999), allDay: true);
      expect(three.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(three.occursOn(DateTime(2026, 11, 27)), isTrue);
      expect(three.occursOn(DateTime(2026, 11, 28)), isFalse);
    });

    test('UTC anlar yerel güne göre değerlendirilir', () {
      // The same instants as local times, held as UTC DateTimes.
      final timed = ev(DateTime(2026, 11, 25, 23, 30).toUtc(), DateTime(2026, 11, 26, 0, 30).toUtc());
      expect(timed.occursOn(DateTime(2026, 11, 24)), isFalse);
      expect(timed.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(timed.occursOn(DateTime(2026, 11, 26)), isTrue);
      expect(timed.occursOn(DateTime(2026, 11, 27)), isFalse);
      final allDay = ev(DateTime(2026, 11, 25).toUtc(), DateTime(2026, 11, 26).toUtc(), allDay: true);
      expect(allDay.occursOn(DateTime(2026, 11, 24)), isFalse);
      expect(allDay.occursOn(DateTime(2026, 11, 25)), isTrue);
      expect(allDay.occursOn(DateTime(2026, 11, 26)), isFalse);
      // A UTC [day] names that calendar date, whatever the device zone.
      expect(allDay.occursOn(DateTime.utc(2026, 11, 25, 23)), isTrue);
      expect(allDay.occursOn(DateTime.utc(2026, 11, 26)), isFalse);
    });
  });

  test('NoCalendarSource: desteklenmiyor, istek de unsupported, listeler boş', () async {
    final s = NoCalendarSource();
    expect(s.isSupported, isFalse);
    expect(await s.access(), CalendarAccess.unsupported);
    expect(await s.request(), CalendarAccess.unsupported);
    expect(await s.calendars(), isEmpty);
    expect(await s.events(DateTime(2026, 11, 23), DateTime(2026, 11, 30)), isEmpty);
  });

  test('DeviceCalendarInfo ve CalendarEvent alanları', () {
    const info = DeviceCalendarInfo(id: '1', name: 'İş', color: 0xFF336699, account: 'iCloud');
    expect((info.id, info.name, info.color, info.account), ('1', 'İş', 0xFF336699, 'iCloud'));
    const bare = DeviceCalendarInfo(id: '2', name: 'Ev');
    expect((bare.color, bare.account), (null, null));
    final e = ev(DateTime(2026, 11, 25, 10), DateTime(2026, 11, 25, 11));
    expect((e.allDay, e.color), (false, null));
  });

  test('FakeCalendarSource: izin, istek sayısı, sorgu aralıkları ve hata', () async {
    final f = FakeCalendarSource();
    expect(f.isSupported, isTrue);
    expect(await f.access(), CalendarAccess.notAsked);
    f.onRequest = CalendarAccess.denied;
    expect(await f.request(), CalendarAccess.denied);
    expect((f.requests, await f.access()), (1, CalendarAccess.denied));
    f.state = CalendarAccess.granted;
    f.calendarsList = const [DeviceCalendarInfo(id: 'c', name: 'Takvim')];
    final e = ev(DateTime(2026, 11, 25, 10), DateTime(2026, 11, 25, 11));
    f.eventsList = [e];
    expect((await f.calendars()).single.id, 'c');
    final from = DateTime(2026, 11, 23), to = DateTime(2026, 11, 30);
    expect(await f.events(from, to), [e]);
    expect(f.eventsCalls, [(from, to)]);
    f.throwOnEvents = true;
    await expectLater(f.events(from, to), throwsA(anything));
    expect(f.eventsCalls.length, 2);
  });
}
