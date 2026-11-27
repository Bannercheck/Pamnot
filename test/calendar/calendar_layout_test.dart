import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/features/calendar/calendar_layout.dart';
import 'package:pamnot/features/calendar/calendar_models.dart';
import 'package:pamnot/state/app_controller.dart' show AgendaKind;

/// Task 9: pure calendar layout (columns, 15 min snapping, visible range).
void main() {
  final day = DateTime(2026, 11, 27);

  DayItem item(String id, DateTime start, DateTime end) =>
      DayItem(id: id, kind: AgendaKind.event, title: id, start: start, end: end);

  DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 27, h, m);

  test('çakışmayan iki öğe tek sütun, tam genişlik (columns == 1)', () {
    final placed = layoutDay([
      item('a', at(9), at(10)),
      item('b', at(10), at(11)),
    ], day);
    expect(placed, hasLength(2));
    for (final p in placed) {
      expect(p.column, 0);
      expect(p.columns, 1);
      expect(p.hidden, 0);
    }
    expect(placed.map((p) => p.item.id), ['a', 'b']);
    expect(placed.first.startMinute, 540);
    expect(placed.first.endMinute, 600);
  });

  test('üç çakışan öğe 3 sütuna yayılır', () {
    final placed = layoutDay([
      item('a', at(9), at(11)),
      item('b', at(9, 30), at(10, 30)),
      item('c', at(10), at(12)),
      item('d', at(13), at(14)),
    ], day);
    final byId = {for (final p in placed) p.item.id: p};
    expect(byId.keys, containsAll(['a', 'b', 'c', 'd']));
    expect([byId['a']!.column, byId['b']!.column, byId['c']!.column], [0, 1, 2]);
    for (final id in ['a', 'b', 'c']) {
      expect(byId[id]!.columns, 3);
      expect(byId[id]!.hidden, 0);
    }
    expect(byId['d']!.columns, 1);
    expect(byId['d']!.column, 0);
  });

  test('boşalan sütun yeniden kullanılır', () {
    final placed = layoutDay([
      item('a', at(9), at(12)),
      item('b', at(9), at(10)),
      item('c', at(10), at(11)),
    ], day);
    final byId = {for (final p in placed) p.item.id: p};
    expect(byId['b']!.column, 1);
    expect(byId['c']!.column, 1);
    expect(byId['a']!.columns, 2);
  });

  test('aynı saatte 7 çakışan öğe: 3 sütun, üçüncü kutuda hidden == 4', () {
    final placed = layoutDay([for (var i = 0; i < 7; i++) item('e$i', at(9), at(10))], day);
    expect(placed, hasLength(3));
    expect(placed.map((p) => p.column), [0, 1, 2]);
    expect(placed.every((p) => p.columns == 3), isTrue);
    expect(placed[0].hidden, 0);
    expect(placed[1].hidden, 0);
    expect(placed[2].hidden, 4);
  });

  test('gece yarısını aşan etkinlik iki günde de kendi gününe kırpılır (23:00–01:00 → 1380..1440 ve 0..60)', () {
    final e = item('n', at(23), DateTime(2026, 11, 28, 1));
    final today = layoutDay([e], day).single;
    expect(today.startMinute, 1380);
    expect(today.endMinute, 1440);
    final tomorrow = layoutDay([e], DateTime(2026, 11, 28)).single;
    expect(tomorrow.startMinute, 0);
    expect(tomorrow.endMinute, 60);
    expect(layoutDay([e], DateTime(2026, 11, 29)), isEmpty);
    expect(layoutDay([e], DateTime(2026, 11, 26)), isEmpty);
  });

  test('sıfır süreli ve bitişi başlangıçtan önce olan öğe 15 dk yüksekliğinde çizilir, istisna yok', () {
    final zero = layoutDay([item('z', at(9), at(9))], day).single;
    expect(zero.startMinute, 540);
    expect(zero.endMinute, 555);
    final backwards = layoutDay([item('b', at(9), at(8))], day).single;
    expect(backwards.startMinute, 540);
    expect(backwards.endMinute, 555);
    final short = layoutDay([item('s', at(9), at(9, 5))], day).single;
    expect(short.endMinute - short.startMinute, 15);
    final lateZero = layoutDay([item('l', at(23, 55), at(23, 55))], day).single;
    expect(lateZero.endMinute, 1440);
    expect(lateZero.endMinute - lateZero.startMinute, 15);
  });

  test('snapMinute: 607.4 → 600; 608 → 615; -20 → 0; 1439 → 1425', () {
    expect(snapMinute(607.4), 600);
    expect(snapMinute(608), 615);
    expect(snapMinute(-20), 0);
    expect(snapMinute(1439), 1425);
    expect(snappedStart(day, 608), DateTime(2026, 11, 27, 10, 15));
    expect(snappedStart(DateTime(2026, 11, 27, 18, 40), 0), DateTime(2026, 11, 27));
  });

  test('visibleRange month: Kasım 2026 pazartesi başlangıçlı 26 Eki – 7 Ara (42 gün)', () {
    final r = visibleRange(CalendarViewMode.month, DateTime(2026, 11, 15), mondayFirst: true);
    expect(r.from, DateTime(2026, 10, 26));
    expect(r.to, DateTime(2026, 12, 7));
    final cells = monthCells(DateTime(2026, 11, 15), mondayFirst: true);
    expect(cells, hasLength(42));
    expect(cells.first, DateTime(2026, 10, 26));
    expect(cells.last, DateTime(2026, 12, 6));
    expect(monthCells(DateTime(2026, 11), mondayFirst: false).first, DateTime(2026, 11, 1));

    final d = visibleRange(CalendarViewMode.day, DateTime(2026, 11, 27, 15), mondayFirst: true);
    expect(d.from, DateTime(2026, 11, 27));
    expect(d.to, DateTime(2026, 11, 28));
    final w = visibleRange(CalendarViewMode.week, DateTime(2026, 11, 27), mondayFirst: true);
    expect(w.from, DateTime(2026, 11, 23));
    expect(w.to, DateTime(2026, 11, 30));
    final ws = visibleRange(CalendarViewMode.week, DateTime(2026, 11, 27), mondayFirst: false);
    expect(ws.from, DateTime(2026, 11, 22));
  });

  test('shifted: ay görünümünde 31 Ocak + 1 → Şubat (ayın ilk günü çapa)', () {
    expect(shifted(CalendarViewMode.month, DateTime(2027, 1, 31), 1), DateTime(2027, 2, 1));
    expect(shifted(CalendarViewMode.month, DateTime(2027, 1, 31), -1), DateTime(2026, 12, 1));
    expect(shifted(CalendarViewMode.day, DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    expect(shifted(CalendarViewMode.week, DateTime(2026, 11, 27), -1), DateTime(2026, 11, 20));
  });

  test('500 öğelik gün 50 ms\'nin altında yerleşir', () {
    final items = [
      for (var i = 0; i < 500; i++)
        item('p$i', at(0).add(Duration(minutes: (i * 37) % 1380)),
            at(0).add(Duration(minutes: (i * 37) % 1380 + 15 + i % 90))),
    ];
    layoutDay(items, day); // warm-up
    final sw = Stopwatch()..start();
    final placed = layoutDay(items, day);
    sw.stop();
    expect(placed, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(50));
    final shown = placed.length + placed.fold<int>(0, (s, p) => s + p.hidden);
    expect(shown, 500);
  });
}
