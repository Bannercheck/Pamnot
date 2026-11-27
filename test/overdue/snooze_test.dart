import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/features/overdue/snooze.dart';
import 'package:pamnot/models/task.dart';

void main() {
  TaskItem task({DateTime? due, bool hasTime = true, DateTime? remindAt}) =>
      TaskItem(id: 't', title: 'Rapor', due: due, hasTime: hasTime, remindAt: remindAt, createdAt: DateTime(2026));

  test('snoozed: remindAt vadeyle aynı farkla kayar; geçmişe düşerse null', () {
    final now = DateTime(2026, 11, 27, 9);
    final t = task(due: DateTime(2026, 11, 26, 14), remindAt: DateTime(2026, 11, 26, 13, 30));
    final s = snoozed(t, DateTime(2026, 11, 28, 10), hasTime: true, now: now);
    expect(s.due, DateTime(2026, 11, 28, 10));
    expect(s.hasTime, isTrue);
    expect(s.remindAt, DateTime(2026, 11, 28, 9, 30));
    expect(s.done, isFalse);
    expect(s.id, t.id);
    expect(s.title, t.title);

    // Erken bir vadeye taşınınca hatırlatma geçmişe düşer.
    final early = task(due: DateTime(2026, 11, 28, 14), remindAt: DateTime(2026, 11, 28, 9));
    final e = snoozed(early, DateTime(2026, 11, 27, 10), hasTime: true, now: now);
    expect(e.due, DateTime(2026, 11, 27, 10));
    expect(e.remindAt, isNull);

    // Hatırlatmasız görevde remindAt null kalır; tarihli seçimde saat düşer.
    final d = snoozed(task(due: DateTime(2026, 11, 26, 14)), DateTime(2026, 11, 28, 17), hasTime: false, now: now);
    expect(d.due, DateTime(2026, 11, 28));
    expect(d.hasTime, isFalse);
    expect(d.remindAt, isNull);
  });

  test('snoozeOptions: 20:00\'de "tonight" yok; tarihli görevde yarın hasTime false', () {
    final timed = task(due: DateTime(2026, 11, 26, 14, 15));
    final morning = snoozeOptions(timed, DateTime(2026, 11, 27, 9));
    expect(morning.map((o) => o.id), ['tonight', 'tomorrow', 'nextWeek']);
    expect(morning[0].due, DateTime(2026, 11, 27, 19));
    expect(morning[0].hasTime, isTrue);
    expect(morning[1].due, DateTime(2026, 11, 28, 14, 15));
    expect(morning[1].hasTime, isTrue);
    expect(morning[2].due, DateTime(2026, 12, 4, 14, 15));

    final evening = snoozeOptions(timed, DateTime(2026, 11, 27, 20));
    expect(evening.map((o) => o.id), ['tomorrow', 'nextWeek']);
    expect(snoozeOptions(timed, DateTime(2026, 11, 27, 19)).map((o) => o.id), ['tomorrow', 'nextWeek']);

    final dated = task(due: DateTime(2026, 11, 26), hasTime: false);
    final opts = snoozeOptions(dated, DateTime(2026, 11, 27, 9));
    expect(opts.map((o) => o.id), ['tonight', 'tomorrow', 'nextWeek']);
    expect(opts[0].hasTime, isTrue);
    expect(opts[0].due, DateTime(2026, 11, 27, 19));
    expect(opts[1].due, DateTime(2026, 11, 28));
    expect(opts[1].hasTime, isFalse);
    expect(opts[2].due, DateTime(2026, 12, 4));
    expect(opts[2].hasTime, isFalse);
  });

  test('defaultSnooze: saatli görevde yarın aynı saat', () {
    final now = DateTime(2026, 11, 27, 9);
    expect(defaultSnooze(task(due: DateTime(2026, 11, 25, 14, 15)), now), DateTime(2026, 11, 28, 14, 15));
    expect(defaultSnooze(task(due: DateTime(2026, 11, 25), hasTime: false), now), DateTime(2026, 11, 28));
    // Ay sonu.
    expect(defaultSnooze(task(due: DateTime(2026, 11, 29, 8)), DateTime(2026, 11, 30, 9)), DateTime(2026, 12, 1, 8));
  });
}
