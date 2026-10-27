import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamuk/data/store.dart';
import 'package:pamuk/models/ink.dart';
import 'package:pamuk/models/reminder.dart';
import 'package:pamuk/models/settings.dart';
import 'package:pamuk/services/reminder_scheduler.dart';
import 'package:pamuk/services/widget_sync.dart';
import 'package:pamuk/state/app_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 10, 27, 8, 0);

  AppController make(MemoryStore store, {NoopScheduler? scheduler, NoopWidgetSync? widget}) => AppController(
        store: store,
        clock: () => now,
        scheduler: scheduler,
        widgetSync: widget,
        saveDelay: Duration.zero,
      );

  Future<AppController> fresh(MemoryStore store) async {
    // Fix the language so sample content is predictable.
    await store.write('settings', jsonEncode(const AppSettings(language: AppLanguage.tr).toJson()));
    final c = make(store);
    await c.load();
    return c;
  }

  test('first launch seeds a friendly workspace and saves it', () async {
    final store = MemoryStore();
    final c = await fresh(store);
    expect(c.notes, isNotEmpty);
    expect(c.tasks, isNotEmpty);
    expect(c.settings.seeded, isTrue);
    await c.flush();
    expect(store.data.keys, containsAll(['notes', 'tasks', 'reminders', 'habits', 'settings']));
  });

  test('state survives a restart, ink in its own document', () async {
    final store = MemoryStore();
    final a = await fresh(store);
    final strokes = [
      InkStroke(data: Float32List.fromList([1, 2, 0.5, 0, 3, 4, 0.5, 8]), color: 0xFF000000, width: 4),
    ];
    final n = a.draftNote(handwriting: true).copyWith(title: 'Kroki', ink: strokes);
    a.upsertNote(n, inkChanged: true);
    a.addQuickTask('yarın 10:00 diş hekimi');
    await a.flush();
    expect(store.data['ink_${n.id}'], startsWith('PINK1:'));
    expect(store.data['notes'], isNot(contains('PINK1')));

    final b = make(store);
    await b.load();
    expect(b.tasks.any((t) => t.title == 'Diş hekimi' && t.due == DateTime(2026, 10, 28, 10)), isTrue);
    await b.ensureInk(n.id);
    expect(b.noteById(n.id)!.ink.single.data, strokes.single.data);

    b.deleteNote(n.id);
    await b.flush();
    expect(store.data.containsKey('ink_${n.id}'), isFalse);
  });

  test('a damaged item is skipped, not fatal', () async {
    final store = MemoryStore({
      'settings': jsonEncode(const AppSettings(seeded: true).toJson()),
      'tasks': jsonEncode({
        'v': 1,
        'items': [
          {'id': 'ok', 'title': 'Fine', 'createdAt': now.toIso8601String()},
          {'id': 'bad'},
        ],
      }),
    });
    final c = make(store);
    await c.load();
    expect(c.tasks.map((t) => t.id), ['ok']);
  });

  test('alerts include reminders and task reminders, not done tasks', () async {
    final store = MemoryStore();
    final c = await fresh(store);
    final r = c.draftReminder(at: DateTime(2026, 10, 27, 12)).copyWith(title: 'İlaç', repeat: Repeat.daily);
    c.upsertReminder(r);
    final t = c.draftTask().copyWith(title: 'Ara', remindAt: () => DateTime(2026, 10, 27, 15));
    c.upsertTask(t);
    expect(c.alerts().map((a) => a.key), containsAll(['r:${r.id}', 't:${t.id}']));
    c.toggleTask(t.id);
    expect(c.alerts().map((a) => a.key), isNot(contains('t:${t.id}')));
  });

  test('agenda orders timed entries before all-day ones', () async {
    final c = await fresh(MemoryStore());
    final day = DateTime(2026, 10, 27);
    final entries = c.agenda(day);
    expect(entries, isNotEmpty);
    final firstAllDay = entries.indexWhere((e) => e.time == null);
    if (firstAllDay >= 0) {
      expect(entries.skip(firstAllDay).every((e) => e.time == null), isTrue);
    }
  });

  test('widget summary has the shape the native widgets read', () async {
    final widget = NoopWidgetSync();
    final store = MemoryStore();
    await store.write('settings', jsonEncode(const AppSettings(language: AppLanguage.tr).toJson()));
    final c = make(store, widget: widget);
    await c.load();
    final s = c.todaySummary();
    expect(s.keys, containsAll(['updatedAt', 'lang', 'title', 'dateLabel', 'done', 'total', 'progressLabel', 'emptyText', 'items', 'nextReminder']));
    expect(s['lang'], 'tr');
    expect(s['dateLabel'], '27 Ekim Salı');
    final items = s['items']! as List;
    expect(items.length, lessThanOrEqualTo(6));
    for (final i in items.cast<Map<String, Object?>>()) {
      expect(i['color'], matches(RegExp(r'^#[0-9A-F]{6}$')));
      expect(['task', 'reminder', 'event'], contains(i['kind']));
    }
    expect(jsonEncode(s), isA<String>());
  });

  test('alert ids are stable and positive', () {
    final at = DateTime(2026);
    Alert a(String key, String title) => Alert(key: key, title: title, body: 'b', at: at);
    expect(a('r:abc', 't').id, a('r:abc', 'x').id);
    expect(a('r:abc', 't').id, greaterThan(0));
    expect(a('r:abc', 't').id, isNot(a('r:abd', 't').id));
  });
}
