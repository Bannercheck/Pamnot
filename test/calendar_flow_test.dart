import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/calendar/calendar_item_card.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/features/calendar/calendar_view.dart';
import 'package:pamnot/features/calendar/day_view.dart';
import 'package:pamnot/features/calendar/month_view.dart';
import 'package:pamnot/features/calendar/week_view.dart';
import 'package:pamnot/features/features.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/tasks/task_tile.dart';
import 'package:pamnot/ui/planner/planner_page.dart';
import 'package:pamnot/ui/settings/settings_page.dart';

import 'support/fake_calendar_source.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  const tr = S.tr;

  // Wednesday; the week (Monday first) is [Mon 23 Nov, Mon 30 Nov).
  final now = DateTime(2026, 11, 25, 10);
  final monday = DateTime(2026, 11, 23);
  final wednesday = DateTime(2026, 11, 25);
  const base = AppSettings(language: AppLanguage.tr, seeded: true);
  const work = DeviceCalendarInfo(id: 'work', name: 'İş', color: 0xFFE53935, account: 'iCloud');
  const home = DeviceCalendarInfo(id: 'home', name: 'Ev', color: 0xFF1E88E5, account: 'Outlook');

  CalendarEvent event(
    String id,
    DateTime start,
    DateTime end, {
    String title = 'Toplantı',
    String calendarId = 'work',
    bool allDay = false,
    int? color = 0xFFE53935,
  }) =>
      CalendarEvent(id: id, calendarId: calendarId, title: title, start: start, end: end, allDay: allDay, color: color);

  late FakeCalendarSource cal;
  late List<Uri> opened;

  setUp(() {
    planSection.value = PlanSection.agenda;
    cal = FakeCalendarSource()..calendarsList = const [work, home];
    opened = [];
    final original = openExternal;
    openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openExternal = original);
  });

  Future<AppController> controller({AppSettings settings = base, CalendarSource? source}) async {
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
      calendar: source ?? cal,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await c.load();
    return c;
  }

  Future<AppController> pump(
    WidgetTester tester,
    Widget page, {
    AppSettings settings = base,
    CalendarSource? source,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await controller(settings: settings, source: source);
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        theme: PamnotTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: page,
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  final shown = base.copyWith(showCalendar: true);

  testWidgets('desteklenmeyen cihazda "Takvimi göster" ve Ayarlar grubu yok', (tester) async {
    var c = await pump(tester, const PlannerPage(), source: NoCalendarSource());
    expect(find.byKey(const Key('show-calendar')), findsNothing);
    expect(find.text(tr.calendarDenied), findsNothing);
    await shutdown(tester, c);

    c = await pump(tester, const SettingsPage(), source: NoCalendarSource());
    expect(find.text(tr.calendarEvents), findsNothing);
    expect(find.text(tr.calendarOutlookHint), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('ilk açılışta takvim izni istenmez (requests == 0); "Takvimi göster" ister', (tester) async {
    final c = await pump(tester, const PlannerPage());
    expect(cal.requests, 0);
    expect(cal.eventsCalls, isEmpty);
    final button = find.byKey(const Key('show-calendar'));
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.text(tr.showCalendar)), findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(cal.requests, 1);
    expect(c.settings.showCalendar, isTrue);
    expect(c.calendarAccess, CalendarAccess.granted);
    expect(find.byKey(const Key('show-calendar')), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('izin verilince bugünün etkinlikleri Gün görünümünde takvim renginde, onay kutusuz görünür', (tester) async {
    cal.eventsList = [
      event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15)),
      event('e2', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 10), title: 'Yarın'),
    ];
    final c = await pump(tester, const PlannerPage());
    await tester.tap(find.byKey(const Key('show-calendar')));
    await tester.pumpAndSettle();

    expect(find.byType(DayView), findsOneWidget);
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('Yarın'), findsNothing);
    final card = find.byKey(const Key('calendar-face-event-e1'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byIcon(Icons.event_rounded)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(Checkbox)), findsNothing);
    expect(find.descendant(of: card, matching: find.byType(SoftCheck)), findsNothing);
    final stripe = find.descendant(of: card, matching: find.byType(Container)).first;
    expect(tester.widget<Container>(stripe).color, const Color(0xFFE53935));
    expect(tester.getSize(stripe).width, 4);
    expect(find.bySemanticsLabel(tr.eventAt('Toplantı', '14:00–15:00')), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('etkinliğe dokunmak yalnız salt okunur ayrıntıyı açar; kayıt eklenmez', (tester) async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15))];
    final c = await pump(tester, const PlannerPage(), settings: shown);
    expect(find.text('Toplantı'), findsOneWidget);
    await tester.tap(find.text('Toplantı'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('event-detail'));
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(tr.eventReadOnly)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('${tr.eventCalendar}: İş')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(PlannerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(c.tasks.length + c.reminders.length, 0);
    await shutdown(tester, c);
  });

  testWidgets('izin reddedilince açıklama satırı Ayarlar\'ı açar; showCalendar false kalır', (tester) async {
    cal.onRequest = CalendarAccess.denied;
    final c = await pump(tester, const PlannerPage());
    await tester.tap(find.byKey(const Key('show-calendar')));
    await tester.pumpAndSettle();
    expect(c.settings.showCalendar, isFalse);
    expect(c.calendarAccess, CalendarAccess.denied);
    expect(find.text(tr.calendarDenied), findsOneWidget);
    await tester.tap(find.text(tr.calendarDenied));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('app-settings:')]);
    expect(cal.eventsCalls, isEmpty);
    await shutdown(tester, c);
  });

  test('sorgu yalnız görünen hafta: eventsCalls tek kayıt, [Pzt 00:00, sonraki Pzt 00:00)', () async {
    cal.state = CalendarAccess.granted;
    final c = await controller(settings: shown);
    await c.loadCalendarWeek(wednesday);
    expect(cal.eventsCalls, [(monday, DateTime(2026, 11, 30))]);
    c.dispose();

    // Sunday-first weeks start on Sunday 22 November.
    cal.eventsCalls.clear();
    final sunday = await controller(settings: shown.copyWith(mondayFirst: false));
    await sunday.loadCalendarWeek(wednesday);
    expect(cal.eventsCalls, [(DateTime(2026, 11, 22), DateTime(2026, 11, 29))]);
    sunday.dispose();
  });

  test('aynı haftada gün değiştirmek yeniden sormaz; haftayı değiştirmek sorar', () async {
    cal.state = CalendarAccess.granted;
    final c = await controller(settings: shown);
    await Future.wait([c.loadCalendarWeek(wednesday), c.loadCalendarWeek(monday)]);
    await c.loadCalendarWeek(DateTime(2026, 11, 29, 23));
    expect(cal.eventsCalls, hasLength(1));
    await c.loadCalendarWeek(DateTime(2026, 11, 30));
    expect(cal.eventsCalls, [
      (monday, DateTime(2026, 11, 30)),
      (DateTime(2026, 11, 30), DateTime(2026, 12, 7)),
    ]);
    c.dispose();
  });

  test('RF5: izin uygulama açıkken geri alınırsa refreshCalendar sonrası etkinlik yok, hata yok', () async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15))];
    final c = await controller(settings: shown);
    await c.loadCalendarWeek(wednesday);
    expect(c.eventsOn(wednesday), hasLength(1));
    expect(c.agenda(wednesday).where((e) => e.kind == AgendaKind.event), hasLength(1));

    cal.state = CalendarAccess.denied;
    await c.refreshCalendar();
    expect(c.calendarAccess, CalendarAccess.denied);
    expect(c.eventsOn(wednesday), isEmpty);
    expect(c.agenda(wednesday), isEmpty);
    expect(c.deviceCalendars, isEmpty);
    expect(c.busyDays(monday, 7), isEmpty);

    // Given back: the next refresh reads the wanted week again.
    cal.state = CalendarAccess.granted;
    cal.eventsCalls.clear();
    await c.refreshCalendar();
    expect(cal.eventsCalls, [(monday, DateTime(2026, 11, 30))]);
    expect(c.eventsOn(wednesday), hasLength(1));
    expect(c.deviceCalendars.map((k) => k.id), ['work', 'home']);

    // A refresh while access stays granted reads the loaded week again.
    await c.refreshCalendar();
    expect(cal.eventsCalls, hasLength(2));
    expect(cal.requests, 0);
    c.dispose();
  });

  test('RF5: events() hata fırlatırsa agenda görevleri göstermeye devam eder', () async {
    cal
      ..state = CalendarAccess.granted
      ..throwOnEvents = true;
    final logged = <String?>[];
    final print = debugPrint;
    debugPrint = (m, {wrapWidth}) => logged.add(m);
    addTearDown(() => debugPrint = print);
    final c = await controller(settings: shown);
    c.upsertTask(c.draftTask(due: DateTime(2026, 11, 25, 16)).copyWith(title: 'Rapor', hasTime: true));
    await c.loadCalendarWeek(wednesday);
    expect(c.eventsOn(wednesday), isEmpty);
    final agenda = c.agenda(wednesday);
    expect(agenda.map((e) => (e.kind, e.title)), [(AgendaKind.task, 'Rapor')]);
    expect(logged, [contains('calendar failed')]);
    await Future<void>.delayed(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets('RF5: bir günde 500 etkinlik: kartlar tembel kurulur, taşma yok', (tester) async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [
        for (var i = 0; i < 500; i++)
          event('e$i', DateTime(2026, 11, 25, 8, i), DateTime(2026, 11, 25, 9, i), title: 'Etkinlik $i'),
      ];
    final c = await pump(tester, const PlannerPage(), settings: shown);
    final view = Features.of(tester.element(find.byType(CalendarView))).calendar;
    expect(view.timedOn(wednesday), hasLength(500));
    expect(find.text('Etkinlik 0'), findsOneWidget);
    expect(find.byType(CalendarItemCard).evaluate().length, lessThan(60));
    expect(tester.takeException(), isNull);
    final calls = cal.eventsCalls.length;
    await tester.drag(find.byType(TimeGrid), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarItemCard).evaluate().length, lessThan(60));
    expect(cal.eventsCalls, hasLength(calls));
    await shutdown(tester, c);
  });

  test('RF5: 23:00–01:00 etkinliği iki günde, üç günlük tüm gün etkinliği üç günde görünür', () async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [
        event('night', DateTime(2026, 11, 24, 23), DateTime(2026, 11, 25, 1), title: 'Gece'),
        event('trip', DateTime(2026, 11, 26), DateTime(2026, 11, 29), title: 'Gezi', allDay: true),
        event('lunch', DateTime(2026, 11, 26, 12), DateTime(2026, 11, 26, 13), title: 'Öğle'),
      ];
    final c = await controller(settings: shown);
    await c.loadCalendarWeek(wednesday);
    List<String> on(int day) => [for (final e in c.eventsOn(DateTime(2026, 11, day))) e.title];
    expect(on(24), ['Gece']);
    expect(on(25), ['Gece']);
    // All-day events first, then by time.
    expect(on(26), ['Gezi', 'Öğle']);
    expect(on(27), ['Gezi']);
    expect(on(28), ['Gezi']);
    expect(on(29), isEmpty);
    expect(c.busyDays(monday, 7), {'2026-11-24': 1, '2026-11-25': 1, '2026-11-26': 2, '2026-11-27': 1, '2026-11-28': 1});

    // In the agenda, timed entries come by time and all-day ones last.
    final thursday = c.agenda(DateTime(2026, 11, 26));
    expect(thursday.map((e) => e.title), ['Öğle', 'Gezi']);
    expect(thursday.first.kind, AgendaKind.event);
    expect(thursday.first.time, DateTime(2026, 11, 26, 12));
    expect(thursday.first.end, DateTime(2026, 11, 26, 13));
    expect(thursday.first.color, 0xFFE53935);
    expect(thursday.last.time, isNull);

    // The night event: its own start on the first day, from 00:00 on the next.
    final tuesday = c.agenda(DateTime(2026, 11, 24)).single;
    expect(tuesday.time, DateTime(2026, 11, 24, 23));
    final next = c.agenda(wednesday).single;
    expect(next.title, 'Gece');
    expect(next.time, DateTime(2026, 11, 25));
    expect(next.end, DateTime(2026, 11, 25, 1));
    c.dispose();
  });

  testWidgets('RF5: başlıksız etkinlik "Adsız etkinlik" olarak görünür', (tester) async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [
        event('e1', DateTime(2026, 11, 25), DateTime(2026, 11, 26), title: '  ', allDay: true),
      ];
    final c = await pump(tester, const PlannerPage(), settings: shown);
    expect(find.text(tr.untitledEvent), findsOneWidget);
    final strip = find.ancestor(of: find.text(tr.untitledEvent), matching: find.byType(AllDayStrip));
    expect(find.descendant(of: strip, matching: find.text(tr.allDay)), findsOneWidget);
    expect(find.bySemanticsLabel(tr.eventAt(tr.untitledEvent, tr.allDay)), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('Ayarlar: takvim işaretini kaldırmak o takvimin etkinliklerini gizler', (tester) async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [
        event('w', DateTime(2026, 11, 25, 9), DateTime(2026, 11, 25, 10), title: 'İş toplantısı'),
        event('h', DateTime(2026, 11, 25, 18), DateTime(2026, 11, 25, 19), title: 'Akşam', calendarId: 'home'),
      ];
    final c = await pump(tester, const SettingsPage(), settings: shown);
    await c.loadCalendarWeek(wednesday);
    expect(c.eventsOn(wednesday).map((e) => e.title), ['İş toplantısı', 'Akşam']);

    final section = find.text(tr.calendarEvents);
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    expect(find.text(tr.calendarsToShow), findsOneWidget);
    expect(find.text(tr.calendarOutlookHint), findsOneWidget);
    final homeTile = find.widgetWithText(CheckboxListTile, 'Ev');
    expect(homeTile, findsOneWidget);
    expect(find.descendant(of: homeTile, matching: find.text('Outlook')), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(homeTile).value, isTrue);

    await tester.ensureVisible(homeTile);
    await tester.pumpAndSettle();
    await tester.tap(homeTile);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(homeTile).value, isFalse);
    expect(c.settings.hiddenCalendarIds, ['home']);
    expect(c.eventsOn(wednesday).map((e) => e.title), ['İş toplantısı']);
    expect(c.agenda(wednesday).map((e) => e.title), ['İş toplantısı']);

    // Turning the switch off hides every event and keeps the access.
    final toggle = find.widgetWithText(SwitchListTile, tr.calendarEvents);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.settings.showCalendar, isFalse);
    expect(c.agenda(wednesday), isEmpty);
    expect(find.text(tr.calendarsToShow), findsNothing);
    expect(cal.requests, 0);
    await shutdown(tester, c);
  });

  testWidgets('metin ölçeği 2,0 ve 375 pt genişlikte etkinlik satırı, düğme ve Ayarlar grubu taşmaz', (tester) async {
    Future<AppController> big(Widget page, AppSettings settings) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await controller(settings: settings);
      await tester.pumpWidget(AppScope(
        controller: c,
        child: MaterialApp(
          theme: PamnotTheme.dark(),
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: page,
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    var c = await big(const PlannerPage(), base);
    expect(find.byKey(const Key('show-calendar')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);

    cal
      ..state = CalendarAccess.granted
      ..eventsList = [
        event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15),
            title: 'Çok uzun bir etkinlik başlığı, iki satıra sarması gerekir'),
      ];
    c = await big(const PlannerPage(), shown);
    final box = find.byKey(const Key('calendar-box-event-e1'));
    await tester.scrollUntilVisible(box, 100,
        scrollable: find.descendant(of: find.byType(TimeGrid), matching: find.byType(Scrollable)));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.ancestor(of: box, matching: find.byType(CalendarItemCard))).height,
        greaterThanOrEqualTo(44));
    expect(tester.getRect(box).right, lessThanOrEqualTo(375));
    await shutdown(tester, c);

    c = await big(const SettingsPage(), shown);
    await tester.scrollUntilVisible(find.text(tr.calendarOutlookHint), 300, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);
  });

  test('Bugün özeti (todaySummary) etkinlik içermez', () async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15))];
    final c = await controller(settings: shown);
    await c.loadCalendarWeek(wednesday);
    expect(c.agenda(wednesday), hasLength(1));
    final summary = c.todaySummary();
    expect(summary['items'], isEmpty);
    expect(summary['total'], 0);
    c.dispose();
  });

  testWidgets('F1: hafta görünümünde oklar haftayı kaydırır; görünen hafta sorgulanır, etkinlik görünür', (tester) async {
    cal
      ..state = CalendarAccess.granted
      ..eventsList = [event('n', DateTime(2026, 12, 2, 9), DateTime(2026, 12, 2, 10), title: 'Gelecek hafta')];
    final c = await pump(tester, const PlannerPage(), settings: shown.copyWith(calendarView: CalendarViewMode.week));
    expect(find.byType(WeekView), findsOneWidget);
    expect(cal.eventsCalls, contains((monday, DateTime(2026, 11, 30))));
    final view = Features.of(tester.element(find.byType(CalendarView))).calendar;

    await tester.tap(find.byTooltip(tr.next));
    await tester.pumpAndSettle();
    // The visible week [Mon 30 Nov, Mon 7 Dec) is queried, the anchor moved
    // with it (Wednesday 2 December), so its event shows.
    expect(view.anchor, DateTime(2026, 12, 2));
    expect(cal.eventsCalls.last, (DateTime(2026, 11, 30), DateTime(2026, 12, 7)));
    expect(view.timedOn(DateTime(2026, 12, 2)).map((e) => e.title), ['Gelecek hafta']);
    expect(find.text('Gelecek hafta'), findsOneWidget);

    await tester.tap(find.byTooltip(tr.previous));
    await tester.pumpAndSettle();
    expect(cal.eventsCalls.last, (monday, DateTime(2026, 11, 30)));
    expect(find.text('Gelecek hafta'), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('F1: ay görünümünde ok çapayı yeni aya taşır (gün sınırlanır) ve o ayın 6×7 ızgarasını sorgular', (tester) async {
    cal.state = CalendarAccess.granted;
    final c = await pump(tester, const PlannerPage(), settings: shown);
    await tester.tap(find.text(tr.month));
    await tester.pumpAndSettle();
    expect(find.byType(MonthView), findsOneWidget);
    final view = Features.of(tester.element(find.byType(CalendarView))).calendar;
    await tester.tap(find.byTooltip(tr.next));
    await tester.pumpAndSettle();
    // 25 November -> 25 December; its grid runs from Monday 30 November for 42 days.
    expect(view.anchor, DateTime(2026, 12, 25));
    expect(cal.eventsCalls.last, (DateTime(2026, 11, 30), DateTime(2027, 1, 11)));

    // 31 January -> 28 February.
    view.goTo(DateTime(2027, 1, 31));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tr.next));
    await tester.pumpAndSettle();
    expect(view.anchor, DateTime(2027, 2, 28));
    expect(find.text('Şubat 2027'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('F2: showCalendar açık ama izin hiç sorulmamış: Plan "Takvimi göster" gösterir, Ayarlar anahtarı kapalı', (tester) async {
    // e.g. settings restored to a new device; the system has not asked yet.
    cal
      ..state = CalendarAccess.notAsked
      ..eventsList = [event('e1', DateTime(2026, 11, 25, 14), DateTime(2026, 11, 25, 15))];
    var c = await pump(tester, const PlannerPage(), settings: shown);
    expect(cal.requests, 0);
    expect(c.calendarNeedsAccess, isTrue);
    final button = find.byKey(const Key('show-calendar'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(cal.requests, 1);
    expect(c.calendarAccess, CalendarAccess.granted);
    expect(c.calendarNeedsAccess, isFalse);
    expect(find.byKey(const Key('show-calendar')), findsNothing);
    expect(find.text('Toplantı'), findsOneWidget);
    await shutdown(tester, c);

    cal
      ..state = CalendarAccess.notAsked
      ..requests = 0;
    c = await pump(tester, const SettingsPage(), settings: shown);
    final toggle = find.widgetWithText(SwitchListTile, tr.calendarEvents);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(cal.requests, 0);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(cal.requests, 1);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text(tr.calendarsToShow), findsOneWidget);
    await shutdown(tester, c);
  });
}
