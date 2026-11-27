import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/sharing/task_policy.dart';
import 'package:pamnot/features/sync/remote_batch.dart';
import 'package:pamnot/models/habit.dart';
import 'package:pamnot/models/ink.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';

/// A policy that knows the user and silences alerts of tasks in [quiet].
class _Policy implements TaskPolicy {
  _Policy(this.me);

  @override
  final String me;
  final Set<String> quiet = {};

  @override
  bool alertsHere(TaskItem t) => !quiet.contains(t.id);
}

/// v3 K1 seams on [AppController]: the task policy, alert providers,
/// [AppController.completeTask] and [AppController.applyRemote].
void main() {
  setUpAll(() => initializeDateFormatting());
  var now = DateTime(2026, 11, 27, 9);
  setUp(() => now = DateTime(2026, 11, 27, 9));

  final settingsDoc = jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson());

  final controllers = <AppController>[];
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  Future<AppController> boot({MemoryStore? store, TaskPolicy? policy, List<AlertProvider> providers = const []}) async {
    final a = AppController(
      store: store ?? MemoryStore({'settings': settingsDoc}),
      scheduler: NoopScheduler(),
      clock: () => now,
      saveDelay: const Duration(hours: 1),
      policy: policy,
      alertProviders: providers,
    );
    controllers.add(a);
    await a.load();
    return a;
  }

  TaskItem add(AppController c, String title, {DateTime? remindAt, String? listId}) {
    final t = c.draftTask(listId: listId).copyWith(title: title, remindAt: () => remindAt);
    c.upsertTask(t);
    return c.tasks.firstWhere((x) => x.id == t.id);
  }

  TaskItem byId(AppController c, String id) => c.tasks.firstWhere((t) => t.id == id);

  test('draftTask createdBy\'ı politikadan alır; LocalTaskPolicy ile null', () async {
    final shared = await boot(policy: _Policy('u1'));
    expect(shared.draftTask().createdBy, 'u1');
    final local = await boot();
    expect(local.policy, isA<LocalTaskPolicy>());
    expect(local.draftTask().createdBy, isNull);
  });

  test('toggleTask tamamlarken completedBy yazar, geri açarken siler', () async {
    final c = await boot(policy: _Policy('u1'));
    final t = add(c, 'Rapor');
    c.toggleTask(t.id);
    expect(byId(c, t.id).done, isTrue);
    expect(byId(c, t.id).completedBy, 'u1');
    c.toggleTask(t.id);
    expect(byId(c, t.id).done, isFalse);
    expect(byId(c, t.id).completedBy, isNull);

    final local = await boot();
    final l = add(local, 'Yerel');
    local.toggleTask(l.id);
    expect(byId(local, l.id).completedBy, isNull);
  });

  test(
    'toggleTask geri açarken reopenedAt yazar; yeniden tamamlamak completedAt\'i reopenedAt\'ten sonraya koyar',
    () async {
      final c = await boot(policy: _Policy('u1'));
      final t = add(c, 'Rapor');
      c.toggleTask(t.id);
      expect(byId(c, t.id).reopenedAt, isNull);
      now = now.add(const Duration(minutes: 5));
      c.toggleTask(t.id);
      final reopened = byId(c, t.id).reopenedAt;
      expect(reopened, now);
      now = now.add(const Duration(minutes: 5));
      c.toggleTask(t.id);
      final done = byId(c, t.id);
      expect(done.reopenedAt, reopened);
      expect(done.completedAt!.isAfter(done.reopenedAt!), isTrue);
    },
  );

  test(
    'completeTask: açık görevi tamamlar ve true; tamam, silinmiş ya da bilinmeyen kimlikte false ve değişiklik yok',
    () async {
      final c = await boot(policy: _Policy('u2'));
      final t = add(c, 'Rapor');
      expect(c.completeTask(t.id), isTrue);
      final done = byId(c, t.id);
      expect(done.done, isTrue);
      expect(done.completedAt, now);
      expect(done.completedBy, 'u2');

      now = now.add(const Duration(hours: 1));
      expect(c.completeTask(t.id), isFalse);
      expect(byId(c, t.id).completedAt, done.completedAt);
      final gone = add(c, 'Silinecek');
      c.deleteTask(gone.id);
      final afterDelete = c.revisions;
      expect(c.completeTask(gone.id), isFalse);
      expect(c.completeTask('nope'), isFalse);
      expect(c.revisions, afterDelete);
    },
  );

  test('alerts(): alertsHere false olan görevin uyarısı yok; anımsatıcılar etkilenmez', () async {
    final at = DateTime(2026, 11, 28, 10);
    final policy = _Policy('u1');
    final c = await boot(policy: policy);
    final here = add(c, 'Burada', remindAt: at);
    final there = add(c, 'Orada', remindAt: at);
    policy.quiet.add(there.id);
    c.upsertReminder(Reminder(id: 'r1', title: 'İlaç', at: at, createdAt: now));
    final keys = c.alerts().map((a) => a.key).toList();
    expect(keys, contains('t:${here.id}'));
    expect(keys, isNot(contains('t:${there.id}')));
    expect(keys, contains('r:r1'));
  });

  test('alerts(): sağlayıcıların uyarıları listenin sonunda', () async {
    final at = DateTime(2026, 11, 28, 10);
    final c = await boot(
      providers: [
        (app) => [Alert(key: 'p1:a', title: 'A', body: 'a', at: at)],
        (app) => [Alert(key: 'p2:a', title: 'B', body: 'b', at: at), Alert(key: 'p2:b', title: 'C', body: 'c', at: at)],
      ],
    );
    add(c, 'Rapor', remindAt: at);
    final keys = c.alerts().map((a) => a.key).toList();
    expect(keys.sublist(keys.length - 3), ['p1:a', 'p2:a', 'p2:b']);
    expect(keys.first, startsWith('t:'));
  });

  test('applyRemote: 3 dilime dokunan toplu iş dinleyicileri tam bir kez çağırır', () async {
    final c = await boot();
    var calls = 0;
    c.addListener(() => calls++);
    final before = c.revisions;
    c.applyRemote(
      RemoteBatch(
        tasks: [TaskItem(id: 'rt', title: 'Uzak', createdAt: now, listId: c.lists.first.id)],
        notes: [Note(id: 'rn', title: 'Not', createdAt: now, updatedAt: now)],
        habits: [Habit(id: 'rh', name: 'Yürüyüş', createdAt: now)],
      ),
    );
    expect(calls, 1);
    final after = c.revisions;
    for (final s in [Slice.tasks, Slice.notes, Slice.habits]) {
      expect(after[s], before[s]! + 1, reason: s.name);
    }
    for (final s in [Slice.reminders, Slice.lists, Slice.settings]) {
      expect(after[s], before[s], reason: s.name);
    }
    expect(c.tasks.any((t) => t.id == 'rt'), isTrue);
    expect(c.notes.any((n) => n.id == 'rn'), isTrue);
    expect(c.habits.any((h) => h.id == 'rh'), isTrue);
  });

  test(
    'applyRemote: silinen listenin kalan görevleri ilk listeye düşer; son liste de silinirse varsayılanlar gelir',
    () async {
      final c = await boot();
      final second = c.lists[1].id;
      final t = add(c, 'İkinci', listId: second);
      c.applyRemote(
        RemoteBatch(
          removedLists: {second},
          tasks: [TaskItem(id: 'orphan', title: 'Yetim', createdAt: now, listId: 'unknown')],
        ),
      );
      expect(c.lists.any((l) => l.id == second), isFalse);
      expect(byId(c, t.id).listId, c.lists.first.id);
      expect(byId(c, 'orphan').listId, c.lists.first.id);

      c.applyRemote(RemoteBatch(removedLists: {for (final l in c.lists) l.id}));
      final defaults = TaskList.defaults(tr: true);
      expect(c.lists.map((l) => l.id), defaults.map((l) => l.id));
      expect(byId(c, t.id).listId, c.lists.first.id);
    },
  );

  test('applyRemote: lastListId değişmez; boş toplu iş revizyonları değiştirmez', () async {
    final c = await boot();
    c.selectList(c.lists[1].id);
    final last = c.settings.lastListId;
    c.applyRemote(
      RemoteBatch(
        lists: [const TaskList(id: 'remote', name: 'Uzak', order: 99)],
        tasks: [TaskItem(id: 'x', title: 'Uzak görev', createdAt: now, listId: 'remote')],
      ),
    );
    expect(c.settings.lastListId, last);
    expect(c.lists.last.id, 'remote');

    var calls = 0;
    c.addListener(() => calls++);
    final revs = c.revisions;
    expect(const RemoteBatch().isEmpty, isTrue);
    c.applyRemote(const RemoteBatch());
    expect(c.revisions, revs);
    expect(calls, 0);
  });

  test('applyRemote: aynı kimlik hem upsert hem silmede ise silme kazanmaz (upsert sonra uygulanır)', () async {
    final c = await boot();
    final t = add(c, 'Eski');
    c.applyRemote(
      RemoteBatch(
        tasks: [t.copyWith(title: 'Yeni')],
        removedTasks: {t.id},
        reminders: [Reminder(id: 'r1', title: 'Uzak', at: now, createdAt: now)],
        removedReminders: {'r1'},
      ),
    );
    expect(byId(c, t.id).title, 'Yeni');
    expect(c.reminders.single.id, 'r1');
  });

  test('applyRemote sonrası flush() değişen dilimleri ve inkChanged notunun mürekkebini yazar', () async {
    final store = MemoryStore({'settings': settingsDoc});
    final c = await boot(store: store);
    await c.flush();
    store.data.remove('reminders');
    final stroke = InkStroke(data: Float32List.fromList([1, 2, 0.5, 0, 3, 4, 0.5, 10]), color: 0xFF000000, width: 2);
    c.applyRemote(
      RemoteBatch(
        notes: [
          Note(id: 'inked', ink: [stroke], createdAt: now, updatedAt: now),
          Note(id: 'plain', title: 'Düz', createdAt: now, updatedAt: now),
        ],
        tasks: [TaskItem(id: 'rt', title: 'Uzak', createdAt: now, listId: c.lists.first.id)],
        inkChanged: {'inked'},
      ),
    );
    await c.flush();
    expect(store.data['ink_inked'], isNotNull);
    expect(store.data.containsKey('ink_plain'), isFalse);
    expect(store.data['notes'], contains('"inked"'));
    expect(store.data['tasks'], contains('"rt"'));
    expect(store.data.containsKey('reminders'), isFalse, reason: 'untouched slice is not rewritten');
  });

  test('applyRemote: inkChanged dışındaki not yerel mürekkebi korur, silinip yeniden gelse de', () async {
    final store = MemoryStore({'settings': settingsDoc});
    final c = await boot(store: store);
    final stroke = InkStroke(data: Float32List.fromList([1, 2, 0.5, 0]), color: 0xFF000000, width: 2);
    c.upsertNote(Note(id: 'n', ink: [stroke], createdAt: now, updatedAt: now), inkChanged: true);
    await c.flush();
    c.applyRemote(
      RemoteBatch(
        notes: [Note(id: 'n', title: 'Uzak başlık', createdAt: now, updatedAt: now)],
        removedNotes: {'n'},
      ),
    );
    expect(c.notes.single.title, 'Uzak başlık');
    expect(c.notes.single.ink, hasLength(1));
    await c.flush();
    expect(store.data['ink_n'], isNotNull);
  });

  group('applyRemote mürekkep yüklenirken', () {
    final stroke = InkStroke(data: Float32List.fromList([1, 2, 0.5, 0]), color: 0xFF000000, width: 2);

    /// A store whose ink reads wait until [release] is called.
    Future<(_SlowStore, AppController)> bootSlow() async {
      final seed = MemoryStore({'settings': settingsDoc});
      final first = await boot(store: seed);
      for (final id in ['a', 'b']) {
        first.upsertNote(Note(id: id, ink: [stroke], createdAt: now, updatedAt: now), inkChanged: true);
      }
      await first.flush();
      final store = _SlowStore(seed.data);
      return (store, await boot(store: store));
    }

    test('uzaktan silinen mürekkep bekleyen yüklemeyle geri gelmez', () async {
      final (store, c) = await bootSlow();
      c.applyRemote(
        RemoteBatch(
          notes: [
            Note(id: 'a', createdAt: now, updatedAt: now),
            Note(id: 'b', createdAt: now, updatedAt: now),
          ],
          inkChanged: {'a', 'b'},
        ),
      );
      store.release();
      await pumpEventQueue();
      expect(c.notes.firstWhere((n) => n.id == 'a').ink, isEmpty);
      expect(c.notes.firstWhere((n) => n.id == 'b').ink, isEmpty);
      await c.flush();
      expect(store.data.containsKey('ink_a'), isFalse);
      expect(store.data.containsKey('ink_b'), isFalse);
    });

    test('mürekkep yüklenmeden yazılan notlar dilimi hasInk işaretini korur', () async {
      final (store, c) = await bootSlow();
      c.applyRemote(RemoteBatch(notes: [Note(id: 'a', title: 'Uzak', createdAt: now, updatedAt: now)]));
      await c.flush();
      final items = (jsonDecode(store.data['notes']!) as Map)['items'] as List;
      for (final id in ['a', 'b']) {
        expect(items.firstWhere((j) => j['id'] == id)['hasInk'], isTrue, reason: id);
      }
      store.release();
      await pumpEventQueue();
      expect(c.notes.firstWhere((n) => n.id == 'a').title, 'Uzak');
      expect(c.notes.firstWhere((n) => n.id == 'a').ink, hasLength(1));
      expect(c.notes.firstWhere((n) => n.id == 'b').ink, hasLength(1));
    });
  });
}

class _SlowStore extends MemoryStore {
  _SlowStore(super.initial);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String?> read(String key) async {
    if (key.startsWith('ink_')) await _gate.future;
    return super.read(key);
  }
}
