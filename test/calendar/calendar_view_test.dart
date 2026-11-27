import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/core/dates.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/calendar/calendar_header.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/features/calendar/calendar_view.dart';
import 'package:pamnot/features/calendar/day_view.dart';
import 'package:pamnot/features/calendar/event_detail_sheet.dart';
import 'package:pamnot/features/calendar/month_view.dart';
import 'package:pamnot/features/calendar/week_view.dart';
import 'package:pamnot/features/features.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/services/system_accessibility.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/glass.dart';
import 'package:pamnot/ui/planner/planner_page.dart';
import 'package:pamnot/ui/reminders/reminders_page.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';

import '../support/contrast.dart';
import '../support/fake_calendar_source.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  const tr = S.tr;

  // Friday 27 Nov 2026, 10:00; Monday-first week [Mon 23, Mon 30).
  final now = DateTime(2026, 11, 27, 10);
  final today = DateTime(2026, 11, 27);
  const base = AppSettings(language: AppLanguage.tr, seeded: true, showCalendar: true);
  const work = DeviceCalendarInfo(id: 'work', name: 'İş', color: 0xFF1E88E5, account: 'Outlook');

  late FakeCalendarSource cal;

  setUp(() {
    planSection.value = PlanSection.agenda;
    cal = FakeCalendarSource()
      ..state = CalendarAccess.granted
      ..calendarsList = const [work];
  });
  tearDown(() => SystemAccessibility.reduceTransparency.value = false);

  CalendarEvent event(String id, DateTime start, DateTime end, {String? title}) =>
      CalendarEvent(id: id, calendarId: 'work', title: title ?? id, start: start, end: end, color: 0xFF1E88E5);

  TaskItem task(String id, DateTime due, {bool hasTime = true}) =>
      TaskItem(id: id, title: id, due: due, hasTime: hasTime, createdAt: now, listId: 'work');

  Future<AppController> controller({AppSettings settings = base, MemoryStore? store}) async {
    final c = AppController(
      store: store ?? MemoryStore({'settings': jsonEncode(settings.toJson())}),
      calendar: cal,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await c.load();
    await c.refreshCalendar();
    return c;
  }

  Future<AppController> pump(
    WidgetTester tester, {
    Widget page = const PlannerPage(),
    AppController? app,
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = app ?? await controller();
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        theme: theme ?? PamnotTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

  Finder segment(String label) =>
      find.descendant(of: find.byType(SegmentedButton<CalendarViewMode>), matching: find.text(label));

  CalendarViewMode selectedMode(WidgetTester tester) =>
      tester.widget<SegmentedButton<CalendarViewMode>>(find.byType(SegmentedButton<CalendarViewMode>)).selected.single;

  testWidgets('segment Gün/Hafta/Ay arasında geçer ve seçim yeniden açılışta hatırlanır', (tester) async {
    final store = MemoryStore({'settings': jsonEncode(base.toJson())});
    var c = await pump(tester, app: await controller(store: store));
    expect(selectedMode(tester), CalendarViewMode.day);
    expect(find.byType(DayView), findsOneWidget);
    expect(find.byType(CalendarHeader), findsOneWidget);
    expect(find.text('Kasım 2026'), findsOneWidget);

    await tester.tap(segment(tr.week));
    await tester.pumpAndSettle();
    expect(find.byType(WeekView), findsOneWidget);
    expect(find.byType(DayView), findsNothing);
    await tester.tap(segment(tr.month));
    await tester.pumpAndSettle();
    expect(find.byType(MonthView), findsOneWidget);
    expect(c.settings.calendarView, CalendarViewMode.month);
    await tester.pump(const Duration(seconds: 1));
    await shutdown(tester, c);

    // Opened again from the same store: the month shows.
    c = await pump(tester, app: await controller(store: store));
    expect(selectedMode(tester), CalendarViewMode.month);
    expect(find.byType(MonthView), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('"Pamnot görevleri" kapatılınca görevler ve anımsatıcılar kaybolur, etkinlikler kalır; ilk açılışta açıktır',
      (tester) async {
    cal.eventsList = [event('Toplantı', DateTime(2026, 11, 27, 11), DateTime(2026, 11, 27, 12))];
    final c = await controller();
    c.upsertTask(task('Rapor', DateTime(2026, 11, 27, 13)));
    c.upsertReminder(Reminder(id: 'r1', title: 'İlaç', at: DateTime(2026, 11, 27, 12, 30), createdAt: now));
    await pump(tester, app: c);
    expect(c.settings.calendarShowPamnot, isTrue);
    expect(find.text('Rapor'), findsOneWidget);
    expect(find.text('İlaç'), findsOneWidget);
    expect(find.text('Toplantı'), findsOneWidget);

    final toggle = find.byKey(const Key('calendar-pamnot-toggle'));
    expect(find.descendant(of: toggle, matching: find.text(tr.calendarPamnotToggle)), findsOneWidget);
    var data = tester.getSemantics(toggle).getSemanticsData();
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    expect(data.value, tr.calendarPamnotOn);
    expect(data.label, tr.calendarPamnotToggle);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.settings.calendarShowPamnot, isFalse);
    expect(find.text('Rapor'), findsNothing);
    expect(find.text('İlaç'), findsNothing);
    expect(find.text('Toplantı'), findsOneWidget);
    data = tester.getSemantics(toggle).getSemanticsData();
    expect(data.flagsCollection.isToggled, Tristate.isFalse);
    expect(data.value, tr.calendarPamnotOff);
    // The icon changes too, not only the colour.
    expect(find.descendant(of: toggle, matching: find.byIcon(Icons.visibility_off_rounded)), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('ay: 5 öğeli hücre 3 nokta ve "+2" gösterir; hücreye dokunmak Gün görünümünü o günle açar', (tester) async {
    final day = DateTime(2026, 11, 18);
    cal.eventsList = [
      event('E1', DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 10)),
      event('E2', DateTime(2026, 11, 18, 15), DateTime(2026, 11, 18, 16)),
    ];
    final c = await controller(settings: base.copyWith(calendarView: CalendarViewMode.month));
    for (final (i, h) in [(1, 11), (2, 12), (3, 13)]) {
      c.upsertTask(task('T$i', DateTime(2026, 11, 18, h)));
    }
    await pump(tester, app: c);
    final key = dayKey(day);
    final cell = find.byKey(Key('month-day-$key'));
    expect(cell, findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('month-dot-$key-$i')), findsOneWidget);
    }
    expect(find.byKey(Key('month-dot-$key-3')), findsNothing);
    expect(find.descendant(of: cell, matching: find.text('+2')), findsOneWidget);
    // A Pamnot item is a filled dot, an event a ring.
    BoxDecoration dot(int i) =>
        tester.widget<Container>(find.byKey(Key('month-dot-$key-$i'))).decoration! as BoxDecoration;
    expect(dot(0).border, isNotNull);
    expect(dot(0).color, isNull);
    expect(dot(2).border, isNull);
    expect(dot(2).color, isNotNull);
    // Read as the date and its items.
    final label = tester.getSemantics(cell).label;
    expect(label, contains('18 Kasım'));
    expect(label, contains(tr.moreItemsLabel(2)));
    expect(tester.getSize(cell).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(cell).width, greaterThanOrEqualTo(44));

    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(c.settings.calendarView, CalendarViewMode.day);
    expect(Features.of(tester.element(find.byType(CalendarView))).calendar.anchor, day);
    expect(find.byType(DayView), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('E1'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('Bugün düğmesi çapayı bugüne getirir; oklar ve yatay kaydırma bir gün / hafta / ay ilerletir', (tester) async {
    final c = await pump(tester);
    final v = Features.of(tester.element(find.byType(CalendarView))).calendar;
    Future<void> tap(Finder f) async {
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> swipe(Finder f, double dx) async {
      await tester.fling(f, Offset(dx, 0), 1000);
      await tester.pumpAndSettle();
    }

    final header = find.byType(CalendarHeader);
    final body = find.byKey(const Key('calendar-body'));

    // Day.
    await tap(find.byTooltip(tr.next));
    expect(v.anchor, DateTime(2026, 11, 28));
    await tap(find.byTooltip(tr.previous));
    expect(v.anchor, today);
    await swipe(body, -200);
    expect(v.anchor, DateTime(2026, 11, 28));
    await swipe(body, 200);
    expect(v.anchor, today);
    // A slow drag is not a swipe.
    await tester.timedDrag(body, const Offset(-120, 0), const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(v.anchor, today);

    // Week: the columns keep their own sideways scroll; the bar still swipes.
    await tap(segment(tr.week));
    await swipe(body, -200);
    expect(v.anchor, today);
    await swipe(header, -200);
    expect(v.anchor, DateTime(2026, 12, 4));
    await tap(find.byTooltip(tr.previous));
    expect(v.anchor, today);

    // Month.
    await tap(segment(tr.month));
    await tap(find.byTooltip(tr.next));
    expect(v.anchor, DateTime(2026, 12, 27));
    expect(find.text('Aralık 2026'), findsOneWidget);
    await swipe(body, -200);
    expect(v.anchor, DateTime(2027, 1, 27));

    final todayButton = find.byKey(const Key('calendar-today'));
    expect(find.descendant(of: todayButton, matching: find.text(tr.today)), findsOneWidget);
    await tap(todayButton);
    expect(v.anchor, today);
    expect(find.text('Kasım 2026'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('etkinliğe dokununca salt okunur ayrıntı açılır; düzenleme düğmesi yoktur', (tester) async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 27, 11), DateTime(2026, 11, 27, 12), title: 'Ekip toplantısı')];
    final c = await controller();
    c.upsertTask(task('Rapor', DateTime(2026, 11, 27, 13)));
    await pump(tester, app: c);

    await tester.tap(find.text('Ekip toplantısı'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('event-detail'));
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Ekip toplantısı')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('11:00–12:00')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('İş')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(tr.eventReadOnly)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.byType(TextField)), findsNothing);
    expect(find.descendant(of: sheet, matching: find.byType(FilledButton)), findsNothing);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(c.tasks.length, 1);

    // A task opens the same editor as the agenda row.
    await tester.tap(find.text('Rapor'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    await shutdown(tester, c);

    // Without a calendar name the line is left out.
    final c2 = await pump(tester, page: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showEventDetail(
            context,
            DayItem(
              id: 'x',
              kind: AgendaKind.event,
              title: ' ',
              start: today,
              end: addDays(today, 1),
              allDay: true,
            ),
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: sheet, matching: find.text(tr.untitledEvent)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining(tr.allDay)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('${tr.eventCalendar}:')), findsNothing);
    await shutdown(tester, c2);
  });

  testWidgets('Plan > Anımsatıcılar bölümü değişmeden çalışır', (tester) async {
    final c = await controller();
    c.upsertReminder(Reminder(id: 'r1', title: 'İlaç al', at: DateTime(2026, 11, 28, 20), createdAt: now));
    await pump(tester, app: c);
    expect(find.byType(CalendarView), findsOneWidget);
    await tester.tap(find.text(tr.reminders));
    await tester.pumpAndSettle();
    expect(planSection.value, PlanSection.reminders);
    expect(find.byType(RemindersList), findsOneWidget);
    expect(find.byType(CalendarView), findsNothing);
    expect(find.text('İlaç al'), findsOneWidget);
    expect(find.text(tr.newReminder), findsOneWidget);

    planSection.value = PlanSection.agenda;
    await tester.pumpAndSettle();
    expect(find.byType(CalendarView), findsOneWidget);
    expect(find.byType(RemindersList), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('üç görünüm: 375 pt ve metin ölçeği 2,0\'da taşma yok; sayfa yatay kaymaz; denetimler ≥ 44 pt ve etiketli',
      (tester) async {
    cal.eventsList = [
      event('e1', DateTime(2026, 11, 27, 11), DateTime(2026, 11, 27, 12), title: 'Çok uzun bir etkinlik başlığı'),
      event('e2', DateTime(2026, 11, 27), DateTime(2026, 11, 28), title: 'Gün boyu etkinlik'),
    ];
    final handle = tester.ensureSemantics();
    for (final theme in [PamnotTheme.light(), PamnotTheme.dark()]) {
      final c = await controller();
      c.upsertTask(task('Rapor', DateTime(2026, 11, 27, 13)));
      c.upsertTask(task('Tarihli', today, hasTime: false));
      await pump(tester, app: c, size: const Size(375, 667), textScale: 2, theme: theme);
      for (final mode in CalendarViewMode.values) {
        c.updateSettings(c.settings.copyWith(calendarView: mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: mode.name);
        final view = tester.getRect(find.byType(CalendarView));
        expect(view.left, greaterThanOrEqualTo(0), reason: mode.name);
        expect(view.right, lessThanOrEqualTo(375), reason: mode.name);
        // Only the week's day columns scroll sideways.
        final sideways = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right);
        expect(sideways.evaluate().length, mode == CalendarViewMode.week ? greaterThan(0) : 0, reason: mode.name);
        for (final f in [
          find.byTooltip(tr.previous),
          find.byTooltip(tr.next),
          find.byKey(const Key('calendar-today')),
          find.byKey(const Key('calendar-pamnot-toggle')),
          for (final m in [tr.day, tr.week, tr.month]) find.ancestor(of: segment(m), matching: find.byType(TextButton)),
        ]) {
          final size = tester.getSize(f.first);
          expect(size.width, greaterThanOrEqualTo(44), reason: '$mode $f');
          expect(size.height, greaterThanOrEqualTo(44), reason: '$mode $f');
        }
        await tester.dragFrom(const Offset(187, 400), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${mode.name} kaydırma');
        await tester.dragFrom(const Offset(187, 300), const Offset(0, 600));
        await tester.pumpAndSettle();
      }
      expect(find.bySemanticsLabel(tr.today), findsWidgets);
      expect(find.byTooltip(tr.previous), findsOneWidget);
      if (theme.brightness == Brightness.light) {
        // Month cells keep 44 pt at this size too.
        final cell = find.byKey(Key('month-day-${dayKey(today)}'));
        expect(tester.getSize(cell).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(cell).height, greaterThanOrEqualTo(44));
      }
      await shutdown(tester, c);
    }
    handle.dispose();
  });

  testWidgets('cam kapalıyken (Saydamlığı Azalt) üst çubuk düz yüzeydir ve kontrast ≥ 4,5:1', (tester) async {
    for (final theme in [PamnotTheme.light(), PamnotTheme.dark()]) {
      SystemAccessibility.reduceTransparency.value = false;
      final c = await pump(tester, theme: theme);
      final panel = find.ancestor(of: find.text('Kasım 2026'), matching: find.byType(GlassPanel));
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.byType(BackdropFilter)), findsOneWidget);

      SystemAccessibility.reduceTransparency.value = true;
      await tester.pumpAndSettle();
      expect(find.descendant(of: panel, matching: find.byType(BackdropFilter)), findsNothing);
      final ctx = tester.element(find.text('Kasım 2026'));
      final surface = GlassPanel.plainDecoration(ctx, 24).color!;
      final box = find.descendant(
        of: panel,
        matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.color == surface),
      );
      expect(box, findsOneWidget);
      final title = tester.widget<Text>(find.text('Kasım 2026'));
      final cs = theme.colorScheme;
      expect(contrast(title.style?.color ?? cs.onSurface, surface), greaterThanOrEqualTo(4.5));
      expect(contrast(cs.onSurface, surface), greaterThanOrEqualTo(4.5));
      expect(contrast(cs.onSurfaceVariant, surface), greaterThanOrEqualTo(4.5));
      await shutdown(tester, c);
    }
  });
}
