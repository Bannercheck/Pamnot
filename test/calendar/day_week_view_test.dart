import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/calendar/calendar_item_card.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/features/calendar/calendar_view_controller.dart';
import 'package:pamnot/features/calendar/day_view.dart';
import 'package:pamnot/features/calendar/hour_grid_painter.dart';
import 'package:pamnot/features/calendar/week_view.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/theme/pamnot_theme.dart';

import '../support/contrast.dart';
import '../support/fake_calendar_source.dart';

void main() {
  // Friday 27 Nov 2026, 09:00. Thursday 26 Nov is "not today" (opens at 08:00).
  final now = DateTime(2026, 11, 27, 9);
  final yesterday = DateTime(2026, 11, 26);
  const base = AppSettings(language: AppLanguage.tr, seeded: true, showCalendar: true);
  const tr = S.tr;

  late FakeCalendarSource cal;

  /// Controllers to dispose at [done].
  final live = <(AppController, CalendarViewController)>[];

  setUp(() => cal = FakeCalendarSource()..state = CalendarAccess.granted);

  CalendarEvent event(String id, DateTime start, DateTime end) =>
      CalendarEvent(id: id, calendarId: 'work', title: id, start: start, end: end, color: 0xFF1E88E5);

  TaskItem task(String id, DateTime due) =>
      TaskItem(id: id, title: id, due: due, hasTime: true, createdAt: now, listId: 'work');

  Future<(AppController, CalendarViewController)> setup(DateTime day) async {
    final a = AppController(
      store: MemoryStore({'settings': jsonEncode(base.toJson())}),
      calendar: cal,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await a.load();
    await a.refreshCalendar();
    final v = CalendarViewController(a)..goTo(day);
    live.add((a, v));
    return (a, v);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget view, {
    Size size = const Size(800, 600),
    double textScale = 1,
    bool reduceMotion = false,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? PamnotTheme.light(),
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(body: view),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  /// Ends a test: no widgets, no controllers, no timers.
  Future<void> done(WidgetTester tester) async {
    await shutdown(tester);
    for (final (a, v) in live) {
      v.dispose();
      a.dispose();
    }
    live.clear();
    await tester.pump(const Duration(seconds: 5));
  }

  Finder box(AgendaKind kind, String id) => find.byKey(Key('calendar-box-${kind.name}-$id'));
  Finder card(AgendaKind kind, String id) => find.ancestor(of: box(kind, id), matching: find.byType(CalendarItemCard));
  final grid = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is HourGridPainter);

  Future<void> longDrag(WidgetTester tester, Finder target, double dy) async {
    final g = await tester.startGesture(tester.getTopLeft(target) + const Offset(10, 8));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveBy(Offset(0, dy / 3));
    await tester.pump();
    await g.moveBy(Offset(0, dy * 2 / 3));
    await tester.pump();
    await g.up();
  }

  testWidgets('gün: 09:00 etkinliği ve 10:30 görevi doğru dikey konumda; görev kutusu 30 dk yüksekliğinde',
      (tester) async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 10))];
    final (a, v) = await setup(yesterday);
    a.upsertTask(task('t1', DateTime(2026, 11, 26, 10, 30)));
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}));

    final painter = tester.widget<CustomPaint>(grid).painter! as HourGridPainter;
    final hh = painter.hourHeight;
    expect(hh, 56);
    final inset = HourGridPainter.metrics(painter.labels, painter.labelStyle).inset;
    final top = tester.getTopLeft(grid).dy;
    expect(tester.getTopLeft(box(AgendaKind.event, 'e1')).dy - top, closeTo(inset + 9 * hh, 0.01));
    expect(tester.getTopLeft(box(AgendaKind.task, 't1')).dy - top, closeTo(inset + 10.5 * hh, 0.01));
    expect(tester.getSize(box(AgendaKind.task, 't1')).height, closeTo(hh / 2, 0.01));
    expect(tester.getSize(box(AgendaKind.event, 'e1')).height, closeTo(hh, 0.01));
    // Not today: opens at 08:00.
    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
    expect(scroll.offset, closeTo(8 * hh, 0.01));
    await done(tester);
  });

  testWidgets('gün: 500 öğeli günde kurulan CalendarItemCard sayısı 60\'ın altında', (tester) async {
    cal.eventsList = [
      for (var i = 0; i < 500; i++)
        event(
          'e$i',
          yesterday.add(Duration(seconds: i * 24 * 3600 ~/ 500)),
          yesterday.add(Duration(seconds: i * 24 * 3600 ~/ 500 + 3600)),
        ),
    ];
    final (_, v) = await setup(yesterday);
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}));
    final built = find.byType(CalendarItemCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60));

    // Scrolling to the evening builds the evening's cards instead.
    Iterable<int> hours() =>
        tester.widgetList<CalendarItemCard>(find.byType(CalendarItemCard)).map((c) => c.placed.item.start.hour);
    expect(hours().where((h) => h >= 21), isEmpty);
    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(hours().where((h) => h >= 21), isNotEmpty);
    expect(hours().where((h) => h < 8), isEmpty);
    expect(find.byType(CalendarItemCard).evaluate().length, lessThan(60));
    await done(tester);
  });

  testWidgets('gün: tek CustomPaint (HourGridPainter) saat çizgilerini çizer; saat başına widget yok',
      (tester) async {
    final (_, v) = await setup(DateTime(2026, 11, 27));
    await pump(tester, DayView(controller: v, day: DateTime(2026, 11, 27), onOpen: (_) {}));
    expect(grid, findsOneWidget);
    final painter = tester.widget<CustomPaint>(grid).painter! as HourGridPainter;
    expect(painter.labels, hasLength(25));
    expect(painter.labels.first, '00:00');
    expect(painter.labels.last, '24:00');
    // Today: the "now" line at 09:00, the grid opened an hour above it.
    expect(painter.nowMinute, 9 * 60);
    expect(find.text('09:00'), findsNothing);
    expect(find.text('10:00'), findsNothing);
    final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
    expect(scroll.offset, closeTo(8 * painter.hourHeight, 0.01));
    await done(tester);
  });

  testWidgets('gün: uzun basıp 45 dk aşağı sürüklenen görev 15 dk adımına oturur, Geri al eski saate döndürür',
      (tester) async {
    final (a, v) = await setup(yesterday);
    a.upsertTask(task('t1', DateTime(2026, 11, 26, 10, 30)));
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}));

    // 42 pt is 45 minutes at 56 pt an hour; 44 minutes worth snaps to 45 too.
    await longDrag(tester, box(AgendaKind.task, 't1'), 44 / 60 * 56);
    await tester.pump();
    // The card settles on its step before the time changes.
    expect(a.tasks.single.due, DateTime(2026, 11, 26, 10, 30));
    await tester.pumpAndSettle();
    expect(a.tasks.single.due, DateTime(2026, 11, 26, 11, 15));
    expect(find.text(tr.itemMoved('11:15')), findsOneWidget);
    final top = tester.getTopLeft(grid).dy;
    final painter = tester.widget<CustomPaint>(grid).painter! as HourGridPainter;
    final inset = HourGridPainter.metrics(painter.labels, painter.labelStyle).inset;
    expect(tester.getTopLeft(box(AgendaKind.task, 't1')).dy - top, closeTo(inset + 11.25 * 56, 0.01));

    await tester.tap(find.text(tr.undo));
    await tester.pumpAndSettle();
    expect(a.tasks.single.due, DateTime(2026, 11, 26, 10, 30));
    await done(tester);
  });

  testWidgets('gün: etkinlik uzun basınca taşınmaz; dokununca onOpen çağrılır', (tester) async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 10))];
    final (_, v) = await setup(yesterday);
    final opened = <DayItem>[];
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: opened.add));
    double onGrid() => tester.getTopLeft(box(AgendaKind.event, 'e1')).dy - tester.getTopLeft(grid).dy;
    final before = onGrid();

    // The drag only scrolls the grid; the event stays at 09:00.
    await longDrag(tester, box(AgendaKind.event, 'e1'), 120);
    await tester.pumpAndSettle();
    expect(onGrid(), before);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(box(AgendaKind.event, 'e1'));
    await tester.pumpAndSettle();
    expect(opened.map((i) => i.id), ['e1']);
    await done(tester);
  });

  testWidgets('gün: aynı saatte 5 öğe 3 sütun ve "+2" gösterir', (tester) async {
    final (a, v) = await setup(yesterday);
    for (var i = 0; i < 5; i++) {
      a.upsertTask(task('t$i', DateTime(2026, 11, 26, 10)));
    }
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}));
    expect(find.byType(CalendarItemCard), findsNWidgets(3));
    final lefts = {
      for (final e in find.byType(CalendarItemCard).evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dx,
    };
    expect(lefts, hasLength(3));
    expect(find.text('+2'), findsOneWidget);
    await done(tester);
  });

  testWidgets('hafta: 375 pt genişlikte 3 gün sütunu görünür; 1024 pt\'de 7', (tester) async {
    Future<int> visibleDays(Size size) async {
      final (a, v) = await setup(DateTime(2026, 11, 25));
      a.upsertTask(task('wed', DateTime(2026, 11, 25, 10)));
      v.mode = CalendarViewMode.week;
      await pump(tester, WeekView(controller: v, onOpen: (_) {}), size: size);
      // The cards sit under their day's header, also when opened mid-week.
      expect(tester.getTopLeft(box(AgendaKind.task, 'wed')).dx,
          closeTo(tester.getTopLeft(find.byKey(const Key('week-day-2026-11-25'))).dx, 0.5));
      var n = 0;
      for (var i = 23; i <= 29; i++) {
        final r = tester.getRect(find.byKey(Key('week-day-2026-11-${i.toString().padLeft(2, '0')}')));
        if (r.left >= -0.5 && r.right <= size.width + 0.5) n++;
      }
      await shutdown(tester);
      return n;
    }

    expect(await visibleDays(const Size(375, 812)), 3);
    expect(await visibleDays(const Size(1024, 768)), 7);
    await done(tester);
  });

  testWidgets('hafta: dar ekranda sütun alanı yana kayar, saat etiketleri sabit, sütuna oturur', (tester) async {
    final (a, v) = await setup(DateTime(2026, 11, 23));
    a.upsertTask(task('t1', DateTime(2026, 11, 26, 10)));
    await pump(tester, WeekView(controller: v, onOpen: (_) {}), size: const Size(375, 812));
    final gridLeft = tester.getTopLeft(grid).dx;
    final monday = find.byKey(const Key('week-day-2026-11-23'));
    final colW = tester.getSize(monday).width;
    final mondayLeft = tester.getTopLeft(monday).dx;

    await tester.drag(find.byType(CalendarDayColumn).first, Offset(-colW * 0.7, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(grid).dx, gridLeft);
    // Settled one column further: Monday's header moved by exactly a column.
    expect(tester.getTopLeft(monday).dx, closeTo(mondayLeft - colW, 0.5));
    expect(tester.getTopLeft(box(AgendaKind.task, 't1')).dx,
        closeTo(tester.getTopLeft(find.byKey(const Key('week-day-2026-11-26'))).dx, 0.5));
    await done(tester);
  });

  testWidgets('metin ölçeği 2,0 ve 375 pt: gün ve haftada taşma yok; kartlar etiketli ve ≥ 44 pt', (tester) async {
    final semantics = tester.ensureSemantics();
    cal.eventsList = [
      event('e1', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 10)),
      CalendarEvent(
          id: 'all', calendarId: 'work', title: 'Tatil', start: yesterday, end: DateTime(2026, 11, 27), allDay: true),
    ];
    final (a, v) = await setup(yesterday);
    a.upsertTask(task('Uzun bir görev başlığı ki sığmasın diye yazıldı', DateTime(2026, 11, 26, 10, 30)));

    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}),
        size: const Size(375, 812), textScale: 2);
    expect(tester.takeException(), isNull);
    for (final e in find.byType(CalendarItemCard).evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    expect(tester.getSemantics(card(AgendaKind.event, 'e1')).label, tr.eventAt('e1', '09:00–10:00'));
    final taskNode = tester.getSemantics(card(AgendaKind.task, 'Uzun bir görev başlığı ki sığmasın diye yazıldı'));
    expect(taskNode.label, tr.taskAt('Uzun bir görev başlığı ki sığmasın diye yazıldı', '10:30'));
    expect(taskNode.hint, tr.dragHint);
    await shutdown(tester);

    v.mode = CalendarViewMode.week;
    await pump(tester, WeekView(controller: v, onOpen: (_) {}), size: const Size(375, 812), textScale: 2);
    expect(tester.takeException(), isNull);
    for (final e in find.byType(CalendarItemCard).evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    await done(tester);
    semantics.dispose();
  });

  testWidgets('hafta: aynı saatte 3 çakışan öğede kartlar ≥ 44 pt geniş, sığmayan "+n" olur', (tester) async {
    const cases = [(Size(375, 812), 1.0), (Size(700, 800), 1.0), (Size(375, 812), 2.0)];
    for (final (size, scale) in cases) {
      final (a, v) = await setup(yesterday);
      for (var i = 0; i < 3; i++) {
        a.upsertTask(task('o$i', DateTime(2026, 11, 26, 10)));
      }
      v.mode = CalendarViewMode.week;
      await pump(tester, WeekView(controller: v, onOpen: (_) {}), size: size, textScale: scale);
      expect(tester.takeException(), isNull);
      final cards = find.byType(CalendarItemCard);
      final shown = cards.evaluate().length;
      expect(shown, inInclusiveRange(1, 2), reason: '$size x$scale');
      for (final e in cards.evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).width, greaterThanOrEqualTo(44), reason: '$size x$scale');
      }
      expect(find.text('+${3 - shown}'), findsOneWidget, reason: '$size x$scale');
      await shutdown(tester);
    }
    await done(tester);
  });

  testWidgets('Hareketi Azalt: sürükleme bırakılınca animasyon süresi sıfır', (tester) async {
    final (a, v) = await setup(yesterday);
    a.upsertTask(task('t1', DateTime(2026, 11, 26, 10, 30)));
    await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}), reduceMotion: true);

    await longDrag(tester, box(AgendaKind.task, 't1'), 42);
    // No settling: the time changes on the frame the finger lifts.
    await tester.pump();
    expect(a.tasks.single.due, DateTime(2026, 11, 26, 11, 15));
    await done(tester);
  });

  testWidgets('açık ve koyu temada kart metni kontrastı ≥ 4,5:1 (test/support/contrast.dart)', (tester) async {
    cal.eventsList = [event('e1', DateTime(2026, 11, 26, 9), DateTime(2026, 11, 26, 10))];
    final (a, v) = await setup(yesterday);
    a.upsertTask(task('t1', DateTime(2026, 11, 26, 10, 30)));
    for (final theme in [PamnotTheme.light(), PamnotTheme.dark()]) {
      await pump(tester, DayView(controller: v, day: yesterday, onOpen: (_) {}), theme: theme);
      for (final (kind, id) in [(AgendaKind.event, 'e1'), (AgendaKind.task, 't1')]) {
        final face = tester.widget<DecoratedBox>(find.byKey(Key('calendar-face-${kind.name}-$id')));
        final bg = (face.decoration as BoxDecoration).color!;
        final text = tester.widget<Text>(find.descendant(of: box(kind, id), matching: find.text(id)));
        expect(contrast(text.style!.color!, bg), greaterThanOrEqualTo(4.5), reason: '$kind ${theme.brightness}');
      }
      await shutdown(tester);
    }
    await done(tester);
  });
}
