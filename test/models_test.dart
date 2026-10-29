import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/core/quick_parse.dart';
import 'package:pamnot/models/habit.dart';
import 'package:pamnot/models/ink.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/ui/notes/ink/ink_controller.dart';
import 'package:pamnot/ui/notes/ink/ink_lines.dart';

InkStroke line(double x0, double y0, double x1, double y1, {int n = 10, InkTool tool = InkTool.pen}) {
  final d = Float32List(n * 4);
  for (var i = 0; i < n; i++) {
    final f = i / (n - 1);
    d[i * 4] = x0 + (x1 - x0) * f;
    d[i * 4 + 1] = y0 + (y1 - y0) * f;
    d[i * 4 + 2] = 0.5;
    d[i * 4 + 3] = i * 8.0;
  }
  return InkStroke(data: d, color: 0xFF3E3A4A, width: 4, tool: tool, hasPressure: true, startedAt: 1000);
}

void main() {
  // Tuesday 27 October 2026, 18:30.
  final now = DateTime(2026, 10, 27, 18, 30);

  group('quickParse', () {
    test('Turkish day and time', () {
      final r = quickParse('yarın 10:00 toplantı', now);
      expect(r.title, 'Toplantı');
      expect(r.due, DateTime(2026, 10, 28, 10));
      expect(r.hasTime, isTrue);
    });

    test('saat N and weekday', () {
      final r = quickParse('cuma saat 14 sunum', now);
      expect(r.title, 'Sunum');
      expect(r.due, DateTime(2026, 10, 30, 14));
    });

    test('Turkish suffix after time', () {
      final r = quickParse("Annemi ara 20.15'te", now);
      expect(r.title, 'Annemi ara');
      expect(r.due, DateTime(2026, 10, 27, 20, 15));
    });

    test('English with pm', () {
      final r = quickParse('call mom tomorrow 6pm', now);
      expect(r.title, 'Call mom');
      expect(r.due, DateTime(2026, 10, 28, 18));
    });

    test('a past time today moves to tomorrow', () {
      final r = quickParse('10:00 koşu', now);
      expect(r.due, DateTime(2026, 10, 28, 10));
    });

    test('day without time', () {
      final r = quickParse('haftaya fatura öde', now);
      expect(r.due, DateTime(2026, 11, 3));
      expect(r.hasTime, isFalse);
      expect(r.title, 'Fatura öde');
    });

    test('no date stays undated', () {
      final r = quickParse('kitap oku', now);
      expect(r.due, isNull);
      expect(r.title, 'Kitap oku');
    });
  });

  group('Reminder recurrence', () {
    Reminder r(DateTime at, Repeat rep) => Reminder(id: 'x', title: 't', at: at, repeat: rep, createdAt: now);

    test('one-off', () {
      expect(r(DateTime(2026, 10, 28, 9), Repeat.none).nextOccurrence(now), DateTime(2026, 10, 28, 9));
      expect(r(DateTime(2026, 10, 26, 9), Repeat.none).nextOccurrence(now), isNull);
    });

    test('daily rolls to tomorrow once today has passed', () {
      expect(r(DateTime(2026, 10, 1, 9), Repeat.daily).nextOccurrence(now), DateTime(2026, 10, 28, 9));
      expect(r(DateTime(2026, 10, 1, 21), Repeat.daily).nextOccurrence(now), DateTime(2026, 10, 27, 21));
    });

    test('weekly keeps the weekday', () {
      // 5 Oct 2026 is a Monday.
      final next = r(DateTime(2026, 10, 5, 8), Repeat.weekly).nextOccurrence(now)!;
      expect(next, DateTime(2026, 11, 2, 8));
      expect(next.weekday, DateTime.monday);
    });

    test('monthly on the 31st skips short months', () {
      final rem = r(DateTime(2026, 8, 31, 9), Repeat.monthly);
      expect(rem.nextOccurrence(now), DateTime(2026, 10, 31, 9));
      expect(rem.nextOccurrence(DateTime(2026, 11, 1)), DateTime(2026, 12, 31, 9));
      expect(rem.occursOn(DateTime(2026, 11, 30)), isFalse);
    });

    test('yearly on 29 February', () {
      final rem = r(DateTime(2024, 2, 29, 9), Repeat.yearly);
      expect(rem.nextOccurrence(now), DateTime(2028, 2, 29, 9));
    });

    test('occursOn ignores days before the start', () {
      final rem = r(DateTime(2026, 10, 27, 9), Repeat.daily);
      expect(rem.occursOn(DateTime(2026, 10, 26)), isFalse);
      expect(rem.occursOn(DateTime(2026, 12, 1)), isTrue);
    });
  });

  group('Habit', () {
    test('streak counts back from today or yesterday', () {
      final h = Habit(
        id: 'h',
        name: 'Su',
        checkins: {'2026-10-24', '2026-10-25', '2026-10-26'},
        createdAt: now,
      );
      expect(h.streak(now), 3);
      expect(h.toggled(now).streak(now), 4);
      expect(h.toggled(DateTime(2026, 10, 25)).streak(now), 1);
    });
  });

  group('JSON round trips', () {
    test('task', () {
      final t = TaskItem(
        id: '1',
        title: 'Sunum',
        due: DateTime(2026, 10, 28, 10),
        hasTime: true,
        priority: Priority.high,
        remindAt: DateTime(2026, 10, 28, 9),
        subtasks: const [SubTask(id: 's', title: 'Slaytlar', done: true)],
        createdAt: now,
      );
      final back = TaskItem.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
    });

    test('note keeps ink out of its JSON', () {
      final n = Note(id: 'n', title: 'A', ink: [line(0, 0, 10, 10)], createdAt: now, updatedAt: now);
      final j = n.toJson();
      expect(j['hasInk'], isTrue);
      expect(j.containsKey('ink'), isFalse);
      expect(Note.fromJson(j).title, 'A');
    });
  });

  group('Ink', () {
    test('binary codec round trip', () {
      final strokes = [line(0, 0, 100, 50), line(10, 300, 400, 310, tool: InkTool.highlighter)];
      final back = InkCodec.decode(InkCodec.encode(strokes));
      expect(back.length, 2);
      expect(back[0].data, strokes[0].data);
      expect(back[1].tool, InkTool.highlighter);
      expect(back[0].hasPressure, isTrue);
      expect(back[0].startedAt, 1000);
      expect(InkCodec.decode('garbage'), isEmpty);
    });

    test('codec handles a big page quickly', () {
      final strokes = [for (var i = 0; i < 2000; i++) line(0, i * 5.0, 900, i * 5.0 + 3, n: 100)];
      final sw = Stopwatch()..start();
      final text = InkCodec.encode(strokes);
      final back = InkCodec.decode(text);
      sw.stop();
      // ignore: avoid_print
      print('ink codec: ${sw.elapsedMilliseconds} ms for 200k points (${(text.length / 1e6).toStringAsFixed(1)} MB)');
      expect(back.length, 2000);
      expect(sw.elapsedMilliseconds, lessThan(1500), reason: '${sw.elapsedMilliseconds} ms for 200k points');
    });

    test('hit test uses segments, not just points', () {
      final s = line(0, 0, 100, 0, n: 2);
      expect(s.hitTest(const Offset(50, 3), 2), isTrue);
      expect(s.hitTest(const Offset(50, 30), 2), isFalse);
    });

    test('controller undo, redo and a single-step erase', () {
      final c = InkController(const []);
      c.add(line(0, 0, 100, 0));
      c.add(line(0, 100, 100, 100));
      expect(c.strokes.length, 2);
      c.beginErase();
      c.eraseAt(const Offset(50, 0), 5);
      c.eraseAt(const Offset(50, 100), 5);
      c.endErase();
      expect(c.strokes, isEmpty);
      c.undo();
      expect(c.strokes.length, 2);
      c.undo();
      expect(c.strokes.length, 1);
      c.redo();
      expect(c.strokes.length, 2);
    });

    test('lines are segmented top to bottom in writing order', () {
      final a = line(0, 100, 50, 120);
      final b = line(60, 102, 120, 118);
      final c = line(0, 200, 50, 220);
      final lines = segmentLines([c, a, b, line(0, 0, 500, 0, tool: InkTool.highlighter)]);
      expect(lines.length, 2);
      expect(lines[0], [a, b]);
      expect(lines[1], [c]);
    });
  });
}
