import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/features/overdue/overdue_notice.dart';
import 'package:pamnot/features/overdue/snooze.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/task.dart';

import '../support/overdue_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final h = OverdueHarness();
  setUp(() => h.now = DateTime(2026, 11, 27, 9));
  tearDown(h.disposeAll);

  TaskItem task(String id, {DateTime? due, bool hasTime = true, bool done = false}) =>
      TaskItem(id: id, title: id, due: due, hasTime: hasTime, done: done, createdAt: DateTime(2026));

  test('saatli görev: vade 14:00 → uyarı 15:00; tarihli görev: vade 27 Kas → 28 Kas 09:00', () async {
    expect(noticeAt(task('a', due: DateTime(2026, 11, 27, 14))), DateTime(2026, 11, 27, 15));
    expect(noticeAt(task('b', due: DateTime(2026, 11, 27), hasTime: false)), DateTime(2026, 11, 28, 9));
    expect(noticeAt(task('c', due: DateTime(2026, 12, 31), hasTime: false)), DateTime(2027, 1, 1, 9));

    final c = await h.boot();
    final t = h.add(c, 'Rapor', due: DateTime(2026, 11, 27, 14));
    final alerts = overdueAlerts(c);
    expect(alerts, hasLength(1));
    final a = alerts.single;
    expect(a.key, 'o:${t.id}');
    expect(a.at, DateTime(2026, 11, 27, 15));
    expect(a.title, S.tr.overdueTitle('Rapor'));
    expect(a.body, S.tr.overdueBody);
    expect(a.category, overdueCategory);
  });

  test('tamamlanmış, vadesiz ve uyarı anı geçmiş görev için uyarı yok', () async {
    expect(noticeAt(task('d', due: DateTime(2026, 11, 27, 14), done: true)), isNull);
    expect(noticeAt(task('e')), isNull);

    final c = await h.boot();
    final done = h.add(c, 'Bitti', due: DateTime(2026, 11, 27, 14));
    c.completeTask(done.id);
    h.add(c, 'Vadesiz');
    h.add(c, 'Geçmiş', due: DateTime(2026, 11, 27, 7)); // uyarı 08:00, şimdi 09:00
    h.add(c, 'Tam şimdi', due: DateTime(2026, 11, 27, 8)); // uyarı 09:00 == şimdi
    expect(overdueAlerts(c), isEmpty);
  });

  test('ayar kapalıyken liste boş', () async {
    final c = await h.boot(overdueNotice: false);
    h.add(c, 'Rapor', due: DateTime(2026, 11, 27, 14));
    expect(overdueAlerts(c), isEmpty);
  });

  test('RF5: aynı dakikaya düşen 5 görev 5 ayrı uyarıdır; 6 görev tek özettir (n == 6)', () async {
    final c = await h.boot();
    final due = DateTime(2026, 11, 27, 14);
    for (var i = 0; i < 5; i++) {
      h.add(c, 'G$i', due: due);
    }
    final five = overdueAlerts(c);
    expect(five, hasLength(5));
    expect(five.every((a) => a.category == overdueCategory && a.key.startsWith('o:')), isTrue);

    h.add(c, 'G5', due: due.add(const Duration(seconds: 30))); // aynı dakika
    h.add(c, 'Başka', due: DateTime(2026, 11, 27, 16));
    final alerts = overdueAlerts(c);
    expect(alerts, hasLength(2));
    final sum = alerts.firstWhere((a) => a.key.startsWith('o:sum:'));
    final minute = DateTime(2026, 11, 27, 15).millisecondsSinceEpoch ~/ 60000;
    expect(sum.key, 'o:sum:$minute');
    expect(sum.title, S.tr.overdueSummary(6));
    expect(sum.body, S.tr.overdueBody);
    expect(sum.category, isNull);
    expect(sum.at, DateTime(2026, 11, 27, 15));
    expect(alerts.where((a) => a.category == overdueCategory).single.at, DateTime(2026, 11, 27, 17));
  });

  test('RF5: alertsHere false olan görevin uyarısı yok ve özet sayısına girmez', () async {
    final policy = QuietPolicy();
    final c = await h.boot(policy: policy);
    final due = DateTime(2026, 11, 27, 14);
    final quiet = h.add(c, 'Sessiz', due: due);
    policy.quiet.add(quiet.id);
    for (var i = 0; i < 5; i++) {
      h.add(c, 'G$i', due: due);
    }
    final alerts = overdueAlerts(c);
    expect(alerts, hasLength(5));
    expect(alerts.any((a) => a.key == 'o:${quiet.id}'), isFalse);
    expect(alerts.any((a) => a.key.startsWith('o:sum:')), isFalse);
    expect(overdueNow(c), isEmpty); // vadeler henüz gelmedi
    h.now = DateTime(2026, 11, 27, 14, 30);
    expect(overdueNow(c).any((t) => t.id == quiet.id), isFalse);
    expect(overdueNow(c), hasLength(5));
  });

  test('RF5: ertelenen görevin uyarısı yeni vadeye taşınır; eski anahtar için ikinci uyarı yok', () async {
    final c = await h.boot();
    final t = h.add(c, 'Rapor', due: DateTime(2026, 11, 27, 7));
    expect(overdueAlerts(c), isEmpty); // eski vadenin uyarı anı geçti, yeniden uyarmaz
    c.upsertTask(snoozed(t, DateTime(2026, 11, 28, 10), hasTime: true));
    final alerts = overdueAlerts(c);
    expect(alerts.where((a) => a.key == 'o:${t.id}'), hasLength(1));
    expect(alerts.single.at, DateTime(2026, 11, 28, 11));
    c.completeTask(t.id);
    expect(overdueAlerts(c), isEmpty);
  });

  test(
    'RF5: 70 gecikmiş olacak görev için 70 uyarı üretilir (64 sınırına kırpma zamanlayıcının işidir, Görev 7)',
    () async {
      final c = await h.boot();
      for (var i = 0; i < 70; i++) {
        h.add(c, 'G$i', due: DateTime(2026, 11, 27, 10).add(Duration(minutes: i)));
      }
      expect(overdueAlerts(c), hasLength(70));
    },
  );

  test('overdueNow: vadesi geçmiş, açık görevler en eski vade önce', () async {
    final c = await h.boot();
    final late = h.add(c, 'Geç', due: DateTime(2026, 11, 27, 8));
    final early = h.add(c, 'Erken', due: DateTime(2026, 11, 25), hasTime: false);
    h.add(c, 'Bugün tarihli', due: DateTime(2026, 11, 27), hasTime: false);
    h.add(c, 'Gelecek', due: DateTime(2026, 11, 27, 10));
    final done = h.add(c, 'Bitti', due: DateTime(2026, 11, 20, 8));
    c.completeTask(done.id);
    expect(overdueNow(c).map((t) => t.id), [early.id, late.id]);
  });
}
