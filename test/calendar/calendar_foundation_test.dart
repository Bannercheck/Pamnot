import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/features/calendar/calendar_view_controller.dart';
import 'package:pamnot/features/features.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/state/app_controller.dart';

/// v3 milestone K2 foundation: calendar view settings, strings, [DayItem]
/// and the [Features.calendar] skeleton.
void main() {
  AppSettings roundTrip(AppSettings s) =>
      AppSettings.fromJson((jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, Object?>());

  test('takvim ayarlarının varsayılanları: gün görünümü, Pamnot görevleri açık', () {
    const s = AppSettings();
    expect(s.calendarView, CalendarViewMode.day);
    expect(s.calendarShowPamnot, isTrue);
    final old = AppSettings.fromJson(const {});
    expect(old.calendarView, CalendarViewMode.day);
    expect(old.calendarShowPamnot, isTrue);
  });

  test('takvim ayarları JSON gidiş dönüşünde korunur; görünüm adıyla yazılır', () {
    final s = const AppSettings().copyWith(calendarView: CalendarViewMode.month, calendarShowPamnot: false);
    expect(s.toJson()['calendarView'], 'month');
    expect(s.toJson()['calendarShowPamnot'], false);
    final back = roundTrip(s);
    expect(back.calendarView, CalendarViewMode.month);
    expect(back.calendarShowPamnot, isFalse);
    expect(roundTrip(const AppSettings().copyWith(calendarView: CalendarViewMode.week)).calendarView,
        CalendarViewMode.week);
  });

  test('bilinmeyen ya da hatalı calendarView gün görünümüne düşer', () {
    expect(AppSettings.fromJson(const {'calendarView': 'year'}).calendarView, CalendarViewMode.day);
    expect(AppSettings.fromJson(const {'calendarView': 3}).calendarView, CalendarViewMode.day);
  });

  test('DayItem: görev ve anımsatıcı sürüklenir; etkinlik ve tüm gün öğesi sürüklenmez', () {
    final start = DateTime(2026, 11, 27, 10, 30);
    final end = start.add(const Duration(minutes: taskBoxMinutes));
    DayItem item(AgendaKind kind, {bool allDay = false}) =>
        DayItem(id: 'x', kind: kind, title: 't', start: start, end: end, allDay: allDay);
    expect(item(AgendaKind.task).draggable, isTrue);
    expect(item(AgendaKind.reminder).draggable, isTrue);
    expect(item(AgendaKind.event).draggable, isFalse);
    expect(item(AgendaKind.task, allDay: true).draggable, isFalse);
    final d = item(AgendaKind.task);
    expect(d.colorIndex, 0);
    expect(d.argb, isNull);
    expect(d.icon, 'list');
    expect(d.done, isFalse);
    expect(d.repeat, Repeat.none);
  });

  test('takvim sabitleri tasarımdaki değerlerdir', () {
    expect(taskBoxMinutes, 30);
    expect(snapStepMinutes, 15);
    expect(maxColumns, 3);
    expect(maxMonthDots, 3);
  });

  test('K2 metinleri TR ve EN dolu ve farklı dillerde', () {
    List<String> all(S s) => [
          s.day,
          s.calendarPamnotToggle,
          s.calendarPamnotOn,
          s.calendarPamnotOff,
          s.allDay,
          s.moreItems(4),
          s.moreItemsLabel(4),
          s.nowLine,
          s.eventDetails,
          s.eventReadOnly,
          s.eventCalendar,
          s.itemMoved('11:15'),
          s.seriesMoved('11:15'),
          s.dragHint,
          s.calendarViewLabel,
          s.taskAt('Rapor', '11:15'),
          s.eventAt('Toplantı', '11:15'),
          s.reminderAt('İlaç', '11:15'),
        ];
    for (final s in [S.tr, S.en]) {
      for (final v in all(s)) {
        expect(v.trim(), isNotEmpty);
      }
    }
    expect(S.tr.day, 'Gün');
    expect(S.en.day, 'Day');
    expect(S.tr.moreItems(4), '+4');
    expect(S.en.moreItemsLabel(4), '4 more');
    expect(S.tr.moreItemsLabel(4), '4 öğe daha');
    expect(S.tr.itemMoved('11:15'), '11:15 saatine taşındı');
    expect(S.en.seriesMoved('11:15'), 'The repeating reminder now fires at 11:15');
    expect(S.tr.taskAt('Rapor', '11:15'), 'Görev: Rapor, 11:15');
    expect(S.en.eventAt('Meet', '11:15'), 'Event: Meet, 11:15');
    expect(S.en.reminderAt('Pill', '11:15'), 'Reminder: Pill, 11:15');
    expect(S.tr.calendarPamnotToggle, isNot(S.en.calendarPamnotToggle));
    expect(S.tr.eventReadOnly, isNot(S.en.eventReadOnly));
  });

  test('Features.local(app).calendar vardır, her seferinde aynı nesnedir', () {
    final app = AppController(store: MemoryStore());
    final f = Features.local(app);
    expect(f.calendar, isA<CalendarViewController>());
    expect(f.calendar, isA<ChangeNotifier>());
    expect(identical(f.calendar, f.calendar), isTrue);
    expect(f.calendar.app, same(app));
  });
}
