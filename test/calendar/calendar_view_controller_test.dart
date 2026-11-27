import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/features/calendar/calendar_view_controller.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/state/app_controller.dart';

import '../support/fake_calendar_source.dart';

/// A calendar whose answers the test releases one by one.
class _SlowCalendarSource extends FakeCalendarSource {
  final List<Completer<List<CalendarEvent>>> pending = [];

  @override
  Future<List<CalendarEvent>> events(DateTime from, DateTime to) {
    eventsCalls.add((from, to));
    final c = Completer<List<CalendarEvent>>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  // Friday 27 Nov 2026; Monday-first week [Mon 23 Nov, Mon 30 Nov).
  final now = DateTime(2026, 11, 27, 9);
  final today = DateTime(2026, 11, 27);
  const base = AppSettings(language: AppLanguage.tr, seeded: true, showCalendar: true);

  CalendarEvent event(String id, DateTime start, DateTime end,
          {String calendarId = 'work', bool allDay = false, int? color = 0xFFE53935}) =>
      CalendarEvent(id: id, calendarId: calendarId, title: id, start: start, end: end, allDay: allDay, color: color);

  late FakeCalendarSource cal;

  setUp(() => cal = FakeCalendarSource()..state = CalendarAccess.granted);

  Future<AppController> app({AppSettings settings = base, MemoryStore? store, FakeCalendarSource? source}) async {
    final c = AppController(
      store: store ?? MemoryStore({'settings': jsonEncode(settings.toJson())}),
      calendar: source ?? cal,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await c.load();
    // Reads the access like a resume does; loads no week yet.
    await c.refreshCalendar();
    (source ?? cal).eventsCalls.clear();
    return c;
  }

  CalendarViewController view(AppController a) {
    final v = CalendarViewController(a);
    addTearDown(v.dispose);
    return v;
  }

  TaskItem task(String id, DateTime due, {bool hasTime = true, DateTime? remindAt, String listId = 'work'}) =>
      TaskItem(id: id, title: id, due: due, hasTime: hasTime, remindAt: remindAt, createdAt: now, listId: listId);

  Reminder reminder(String id, DateTime at, {Repeat repeat = Repeat.none}) =>
      Reminder(id: id, title: id, at: at, repeat: repeat, createdAt: now, colorIndex: 2);

  test('showPamnot kapalıyken yalnız etkinlikler; açıkken görev ve anımsatıcılar da', () async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 27, 9), DateTime(2026, 11, 27, 10))];
    final a = await app();
    a.upsertTask(task('t1', DateTime(2026, 11, 27, 10, 30)));
    a.upsertTask(task('t2', today, hasTime: false));
    a.upsertReminder(reminder('r1', DateTime(2026, 11, 20, 8), repeat: Repeat.daily));
    final v = view(a);
    await v.ensureRange();

    expect(v.showPamnot, isTrue);
    expect(v.timedOn(today).map((i) => i.id), ['r1', 'e1', 't1']);
    expect(v.allDayOn(today).map((i) => i.id), ['t2']);
    final t1 = v.timedOn(today).last;
    expect(t1.end.difference(t1.start), const Duration(minutes: taskBoxMinutes));
    final r1 = v.timedOn(today).first;
    expect(r1.start, DateTime(2026, 11, 27, 8));
    expect(r1.kind, AgendaKind.reminder);
    expect(r1.repeat, Repeat.daily);
    expect(r1.icon, 'alarm');

    v.showPamnot = false;
    expect(v.timedOn(today).map((i) => i.id), ['e1']);
    expect(v.allDayOn(today), isEmpty);
  });

  test('mode ve showPamnot ayarlara yazılır ve yeni denetleyicide hatırlanır', () async {
    final store = MemoryStore({'settings': jsonEncode(base.toJson())});
    final a = await app(store: store);
    final v = view(a);
    var notified = 0;
    v.addListener(() => notified++);
    v.mode = CalendarViewMode.month;
    v.showPamnot = false;
    expect(a.settings.calendarView, CalendarViewMode.month);
    expect(a.settings.calendarShowPamnot, isFalse);
    expect(notified, greaterThanOrEqualTo(2));
    await a.flush();

    final again = view(await app(store: store));
    expect(again.mode, CalendarViewMode.month);
    expect(again.showPamnot, isFalse);
  });

  test('görev listesinin rengini ve simgesini taşır; etkinlik takvim rengini (argb)', () async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 27, 9), DateTime(2026, 11, 27, 10), color: 0xFF1E88E5)];
    final a = await app();
    a.upsertTask(task('t1', DateTime(2026, 11, 27, 10, 30), listId: 'work'));
    final v = view(a);
    await v.ensureRange();
    final work = a.listById('work');
    final t1 = v.timedOn(today).firstWhere((i) => i.id == 't1');
    expect(t1.colorIndex, work.colorIndex);
    expect(t1.icon, work.icon);
    expect(t1.argb, isNull);
    final e1 = v.timedOn(today).firstWhere((i) => i.id == 'e1');
    expect(e1.argb, 0xFF1E88E5);
    expect(e1.icon, 'event');
    expect(e1.kind, AgendaKind.event);
  });

  test('ay görünümünde ensureRange 42 günlük tek sorgu yapar; aynı aralık ikinci kez sorulmaz', () async {
    final a = await app();
    final v = view(a);
    v.mode = CalendarViewMode.month;
    await v.ensureRange();
    await v.ensureRange();
    // November 2026 starts on a Sunday; the grid starts Monday 26 Oct.
    expect(cal.eventsCalls, [(DateTime(2026, 10, 26), DateTime(2026, 12, 7))]);
    // A task change does not ask again.
    a.upsertTask(task('t1', DateTime(2026, 11, 27, 10, 30)));
    await v.ensureRange();
    expect(cal.eventsCalls, hasLength(1));
  });

  test('aralık hızlı değişince geç gelen eski yanıt yok sayılır', () async {
    final slow = _SlowCalendarSource()..state = CalendarAccess.granted;
    final a = await app(source: slow);
    final v = view(a);
    final first = v.ensureRange();
    v.goTo(DateTime(2026, 11, 28));
    final second = v.ensureRange();
    expect(slow.pending, hasLength(2));

    slow.pending[1].complete([event('new', DateTime(2026, 11, 28, 9), DateTime(2026, 11, 28, 10))]);
    await second;
    slow.pending[0].complete([event('old', DateTime(2026, 11, 28, 11), DateTime(2026, 11, 28, 12))]);
    await first;

    expect(v.timedOn(DateTime(2026, 11, 28)).map((i) => i.id), ['new']);
  });

  test('takvim erişimi yokken ya da kaynak hata fırlatınca etkinlik yok, istisna yok', () async {
    final printed = <String?>[];
    final original = debugPrint;
    debugPrint = (m, {wrapWidth}) => printed.add(m);
    addTearDown(() => debugPrint = original);

    cal
      ..eventsList = [event('e1', DateTime(2026, 11, 27, 9), DateTime(2026, 11, 27, 10))]
      ..state = CalendarAccess.denied;
    final denied = view(await app());
    await denied.ensureRange();
    expect(cal.eventsCalls, isEmpty);
    expect(denied.timedOn(today), isEmpty);

    cal
      ..state = CalendarAccess.granted
      ..throwOnEvents = true;
    final failing = view(await app());
    await failing.ensureRange();
    expect(cal.eventsCalls, hasLength(1));
    expect(failing.timedOn(today), isEmpty);
    expect(failing.dotsOn(today).dots, isEmpty);
  });

  test('soğuk açılışta erişim istem olmadan okunur ve aralık tek sorguyla yüklenir', () async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 27, 9), DateTime(2026, 11, 27, 10))];
    final a = AppController(
      store: MemoryStore({'settings': jsonEncode(base.toJson())}),
      calendar: cal,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await a.load();
    final v = view(a);
    await v.ensureRange();
    expect(cal.requests, 0);
    expect(cal.eventsCalls, [(today, DateTime(2026, 11, 28))]);
    expect(v.timedOn(today).map((i) => i.id), ['e1']);
  });

  test('move: saatli görev 10:30 → 11:15, remindAt 45 dk kayar; geri alma eski hâli getirir', () async {
    final a = await app();
    a.upsertTask(task('t1', DateTime(2026, 11, 27, 10, 30), remindAt: DateTime(2026, 11, 27, 10, 15)));
    final v = view(a);
    final item = v.timedOn(today).single;
    final undo = v.move(item, DateTime(2026, 11, 27, 11, 15));
    expect(undo, isNotNull);
    final moved = a.tasks.single;
    expect(moved.due, DateTime(2026, 11, 27, 11, 15));
    expect(moved.hasTime, isTrue);
    expect(moved.remindAt, DateTime(2026, 11, 27, 11));
    expect(v.timedOn(today).single.start, DateTime(2026, 11, 27, 11, 15));

    undo!();
    expect(a.tasks.single.due, DateTime(2026, 11, 27, 10, 30));
    expect(a.tasks.single.remindAt, DateTime(2026, 11, 27, 10, 15));
  });

  test('move: yinelenen anımsatıcıda at\'in günü aynı, saati yeni; tek seferlikte gün de saat de yeni başlangıç',
      () async {
    final a = await app();
    a.upsertReminder(reminder('daily', DateTime(2026, 11, 20, 8), repeat: Repeat.daily));
    a.upsertReminder(reminder('once', DateTime(2026, 11, 27, 14)));
    final v = view(a);
    final items = {for (final i in v.timedOn(today)) i.id: i};

    final undoSeries = v.move(items['daily']!, DateTime(2026, 11, 28, 9, 45));
    expect(a.reminders.firstWhere((r) => r.id == 'daily').at, DateTime(2026, 11, 20, 9, 45));
    final undoOnce = v.move(items['once']!, DateTime(2026, 11, 28, 16, 30));
    expect(a.reminders.firstWhere((r) => r.id == 'once').at, DateTime(2026, 11, 28, 16, 30));

    undoSeries!();
    undoOnce!();
    expect(a.reminders.firstWhere((r) => r.id == 'daily').at, DateTime(2026, 11, 20, 8));
    expect(a.reminders.firstWhere((r) => r.id == 'once').at, DateTime(2026, 11, 27, 14));
  });

  test('move: etkinlik ve tüm gün görevi için null', () async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 27, 9), DateTime(2026, 11, 27, 10))];
    final a = await app();
    a.upsertTask(task('t2', today, hasTime: false));
    final v = view(a);
    await v.ensureRange();
    expect(v.move(v.timedOn(today).single, DateTime(2026, 11, 27, 11)), isNull);
    expect(v.move(v.allDayOn(today).single, DateTime(2026, 11, 27, 11)), isNull);
    expect(a.tasks.single.due, today);
    expect(a.tasks.single.hasTime, isFalse);
  });

  test('dotsOn: 5 öğeli günde 3 nokta ve more == 2', () async {
    final a = await app();
    for (var i = 0; i < 5; i++) {
      a.upsertTask(task('t$i', DateTime(2026, 11, 27, 8 + i)));
    }
    final v = view(a);
    final d = v.dotsOn(today);
    expect(d.dots, hasLength(maxMonthDots));
    expect(d.more, 2);
    final empty = v.dotsOn(DateTime(2026, 11, 26));
    expect(empty.dots, isEmpty);
    expect(empty.more, 0);
  });
}
