import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/core/spoken/spoken_task.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 11, 23, 9);

  final settingsDoc = jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson());

  final controllers = <AppController>[];
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  Future<AppController> boot(MemoryStore s) async {
    final a = AppController(store: s, scheduler: NoopScheduler(), clock: () => now, saveDelay: Duration.zero);
    controllers.add(a);
    await a.load();
    return a;
  }

  /// Swallows the log lines a deliberately damaged input produces.
  void quiet() {
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = saved);
  }

  String tasksDoc(List<Map<String, Object?>> items) => jsonEncode({'v': 1, 'items': items});

  Map<String, Object?> legacyTask(String id, {String priority = 'normal'}) => {
        'id': id,
        'title': 'Görev $id',
        'done': false,
        'priority': priority,
        'hasTime': false,
        'color': 3,
        'createdAt': DateTime(2026, 11, 1).toIso8601String(),
      };

  Future<AppController> seeded([Map<String, String> extra = const {}]) =>
      boot(MemoryStore({'settings': settingsDoc, ...extra}));

  TaskItem task(AppController c, String title, {String? listId, Quadrant? quadrant}) {
    final t = c.draftTask(listId: listId, quadrant: quadrant).copyWith(title: title);
    c.upsertTask(t);
    return c.tasks.firstWhere((x) => x.id == t.id);
  }

  List<String> titles(List<TaskItem> l) => [for (final t in l) t.title];

  test('silinen görevi geri almak Matris\'in gösterdiği listeyi değiştirmez', () async {
    final c = await boot(MemoryStore({'settings': settingsDoc}));
    final t = c.draftTask(listId: 'work', quadrant: Quadrant.doNow).copyWith(title: 'Rapor');
    c.upsertTask(t);
    c.selectList(TaskList.personalId);
    final removed = c.deleteTask(t.id)!;
    c.restoreTask(removed);
    expect(c.currentListId, TaskList.personalId);
    expect(c.tasks.single.id, t.id);
    expect(c.tasks.single.listId, 'work');
    // A task whose list was deleted meanwhile comes back in an existing list.
    final gone = c.deleteTask(t.id)!;
    c.restoreTask(gone.copyWith(listId: 'missing'));
    expect(c.lists.map((l) => l.id), contains(c.tasks.single.listId));
    expect(c.currentListId, TaskList.personalId);
  });

  test('ilk açılış: beş hazır liste oluşur ve kaydedilir', () async {
    final store = MemoryStore();
    final c = await boot(store);
    expect([for (final l in c.lists) l.id], ['personal', 'work', 'school', 'shopping', 'home']);
    await c.flush();
    expect(store.data['lists'], isNotNull);
    final saved = (jsonDecode(store.data['lists']!) as Map)['items'] as List;
    expect(saved, hasLength(5));
    // Sample tasks land in an existing list.
    final ids = {for (final l in c.lists) l.id};
    expect(c.tasks.every((t) => ids.contains(t.listId)), isTrue);
  });

  test('eski veri: görevler personal/plan, yüksek öncelikli doNow; hiçbiri kaybolmaz', () async {
    final store = MemoryStore({
      'settings': settingsDoc,
      'tasks': tasksDoc([legacyTask('a'), legacyTask('b', priority: 'high'), legacyTask('c', priority: 'low')]),
    });
    final c = await boot(store);
    expect(c.tasks.length, 3);
    expect(c.tasks.every((t) => t.listId == TaskList.personalId), isTrue);
    expect(c.tasks.firstWhere((t) => t.id == 'b').quadrant, Quadrant.doNow);
    expect(c.tasks.firstWhere((t) => t.id == 'a').quadrant, Quadrant.plan);
    expect(c.tasks.firstWhere((t) => t.id == 'c').quadrant, Quadrant.plan);
    expect(c.lists, hasLength(5));
    await c.flush();
    expect(store.data['lists'], isNotNull);
  });

  test('RF1: lists belgesi yok ama görevde bilinmeyen list var → ilk listeye çekilir', () async {
    final store = MemoryStore({
      'settings': settingsDoc,
      'tasks': tasksDoc([
        {...legacyTask('a'), 'list': 'gone'},
        {...legacyTask('b'), 'list': ''},
        {...legacyTask('c'), 'list': 'work'},
      ]),
    });
    final c = await boot(store);
    expect(c.tasks.firstWhere((t) => t.id == 'a').listId, c.lists.first.id);
    expect(c.tasks.firstWhere((t) => t.id == 'b').listId, c.lists.first.id);
    expect(c.tasks.firstWhere((t) => t.id == 'c').listId, 'work');
    await c.flush();
    // The fix-up is saved.
    final saved = (jsonDecode(store.data['tasks']!) as Map)['items'] as List;
    expect(saved.map((j) => (j as Map)['list']), isNot(contains('gone')));
  });

  test('RF1: lists boş dizi → hazır listeler; bozuk liste öğesi atlanır, diğerleri kalır', () async {
    quiet();
    final empty = await seeded({'lists': jsonEncode({'v': 1, 'items': []})});
    expect(empty.lists, hasLength(5));

    final store = MemoryStore({
      'settings': settingsDoc,
      'lists': jsonEncode({
        'v': 1,
        'items': [
          const TaskList(id: 'a', name: 'A', order: 0).toJson(),
          {'name': 'kimliksiz'},
          const TaskList(id: 'b', name: 'B', order: 1).toJson(),
        ],
      }),
    });
    final c = await boot(store);
    expect([for (final l in c.lists) l.id], ['a', 'b']);
    expect(c.listById('nope').id, 'a');
    expect(c.listById('b').name, 'B');
  });

  test('göç bir kez: Kişisel yeniden adlandırılıp kaydedildikten sonra yeniden yükleme adı korur', () async {
    final store = MemoryStore({'settings': settingsDoc});
    final a = await boot(store);
    a.updateList(a.listById(TaskList.personalId).copyWith(name: 'Benim'));
    await a.flush();

    final b = await boot(store);
    expect(b.lists, hasLength(5));
    expect(b.listById(TaskList.personalId).name, 'Benim');
  });

  test('RF2: içinde görev olan listeyi silmek görevleri ilk kalan listeye taşır; restoreList geri alır', () async {
    final c = await seeded();
    final t1 = task(c, 'iş 1', listId: 'work', quadrant: Quadrant.doNow);
    final t2 = task(c, 'iş 2', listId: 'work', quadrant: Quadrant.later);
    final other = task(c, 'okul', listId: 'school');
    final before = c.revisions;

    final r = c.deleteList('work')!;
    expect(r.list.id, 'work');
    expect(r.movedTaskIds.toSet(), {t1.id, t2.id});
    expect(c.lists.map((l) => l.id), isNot(contains('work')));
    expect(c.tasks.firstWhere((t) => t.id == t1.id).listId, TaskList.personalId);
    expect(c.tasks.firstWhere((t) => t.id == t1.id).quadrant, Quadrant.doNow);
    expect(c.tasks.firstWhere((t) => t.id == t2.id).listId, TaskList.personalId);
    expect(c.tasks.firstWhere((t) => t.id == other.id).listId, 'school');
    expect(c.revisions[Slice.lists], greaterThan(before[Slice.lists]!));
    expect(c.revisions[Slice.tasks], greaterThan(before[Slice.tasks]!));

    c.restoreList(r.list, r.movedTaskIds);
    expect([for (final l in c.lists) l.id], ['personal', 'work', 'school', 'shopping', 'home']);
    expect(c.tasks.firstWhere((t) => t.id == t1.id).listId, 'work');
    expect(c.tasks.firstWhere((t) => t.id == t2.id).listId, 'work');
    expect(c.tasks.firstWhere((t) => t.id == other.id).listId, 'school');
  });

  test('RF2: son liste silinemez (null döner, liste durur)', () async {
    final c = await seeded();
    for (final id in ['work', 'school', 'shopping', 'home']) {
      expect(c.deleteList(id), isNotNull);
    }
    expect(c.deleteList(TaskList.personalId), isNull);
    expect([for (final l in c.lists) l.id], [TaskList.personalId]);
    expect(c.deleteList('unknown'), isNull);
  });

  test('RF2: seçili liste silinince currentListId geçerli bir listeye döner', () async {
    final c = await seeded();
    c.selectList('school');
    expect(c.currentListId, 'school');
    expect(c.settings.lastListId, 'school');
    c.deleteList('school');
    expect(c.lists.map((l) => l.id), contains(c.currentListId));
    expect(c.currentListId, TaskList.personalId);

    c.selectList('nope');
    expect(c.lists.map((l) => l.id), contains(c.currentListId));
  });

  test('tasksIn order sırasıyla; moveTask kutu değiştirir ve hedefte verilen dizine oturur', () async {
    final c = await seeded();
    final a = task(c, 'a', listId: 'work', quadrant: Quadrant.plan);
    final b = task(c, 'b', listId: 'work', quadrant: Quadrant.plan);
    final x = task(c, 'x', listId: 'work', quadrant: Quadrant.doNow);
    final y = task(c, 'y', listId: 'work', quadrant: Quadrant.doNow);
    expect(titles(c.tasksIn('work', Quadrant.plan)), ['a', 'b']);
    expect(titles(c.tasksIn('work', Quadrant.doNow)), ['x', 'y']);
    expect(a.order, lessThan(b.order));

    c.moveTask(b.id, quadrant: Quadrant.doNow, index: 1);
    expect(titles(c.tasksIn('work', Quadrant.doNow)), ['x', 'b', 'y']);
    expect([for (final t in c.tasksIn('work', Quadrant.doNow)) t.order], [0, 1, 2]);
    expect(titles(c.tasksIn('work', Quadrant.plan)), ['a']);

    // Reorder inside the box.
    c.moveTask(y.id, index: 0);
    expect(titles(c.tasksIn('work', Quadrant.doNow)), ['y', 'x', 'b']);

    // Done tasks are queried separately.
    c.toggleTask(x.id);
    expect(titles(c.tasksIn('work', Quadrant.doNow)), ['y', 'b']);
    expect(titles(c.tasksIn('work', Quadrant.doNow, done: true)), ['x']);
  });

  test('moveTask başka listeye: kutusu korunur, hedef kutunun sonuna gelir', () async {
    final c = await seeded();
    task(c, 'h1', listId: 'home', quadrant: Quadrant.delegate);
    task(c, 'h2', listId: 'home', quadrant: Quadrant.delegate);
    final w = task(c, 'w', listId: 'work', quadrant: Quadrant.delegate);
    final before = c.revisions[Slice.tasks]!;
    c.moveTask(w.id, listId: 'home');
    final moved = c.tasks.firstWhere((t) => t.id == w.id);
    expect(moved.listId, 'home');
    expect(moved.quadrant, Quadrant.delegate);
    expect(titles(c.tasksIn('home', Quadrant.delegate)), ['h1', 'h2', 'w']);
    expect(c.tasksIn('work', Quadrant.delegate), isEmpty);
    expect(c.revisions[Slice.tasks], greaterThan(before));
  });

  test('defaultQuadrant: bugüne saatli doNow; yarına saatli, bugüne saatsiz ve tarihsiz plan', () async {
    final c = await seeded();
    expect(c.defaultQuadrant(due: DateTime(2026, 11, 23, 15), hasTime: true), Quadrant.doNow);
    expect(c.defaultQuadrant(due: DateTime(2026, 11, 24, 15), hasTime: true), Quadrant.plan);
    expect(c.defaultQuadrant(due: DateTime(2026, 11, 23), hasTime: false), Quadrant.plan);
    expect(c.defaultQuadrant(), Quadrant.plan);
    expect(c.draftTask(due: DateTime(2026, 11, 23, 15), hasTime: true).quadrant, Quadrant.doNow);
  });

  test('addQuickTask: "yarın 10:00 toplantı" eskisi gibi ayrışır; liste currentListId, kutu plan', () async {
    final c = await seeded();
    c.selectList('work');
    final t = c.addQuickTask('yarın 10:00 toplantı')!;
    expect(t.title, 'Toplantı');
    expect(t.due, DateTime(2026, 11, 24, 10));
    expect(t.hasTime, isTrue);
    expect(t.listId, 'work');
    expect(t.quadrant, Quadrant.plan);

    final u = c.addQuickTask('alışveriş', listId: 'shopping', quadrant: Quadrant.later)!;
    expect(u.listId, 'shopping');
    expect(u.quadrant, Quadrant.later);
    // Every path that adds a task remembers its list.
    expect(c.currentListId, 'shopping');
    expect(c.settings.lastListId, 'shopping');
  });

  test('addSpokenTask(listId:, quadrant:) verileni kullanır; verilmezse son liste ve varsayılan kutu', () async {
    final c = await seeded();
    final a = c.addSpokenTask(const SpokenTask(title: 'Rapor'), listId: 'school', quadrant: Quadrant.delegate)!;
    expect(a.listId, 'school');
    expect(a.quadrant, Quadrant.delegate);
    expect(c.currentListId, 'school');

    final b = c.addSpokenTask(SpokenTask(title: 'Sunum', due: DateTime(2026, 11, 23, 14), hasTime: true))!;
    expect(b.listId, 'school');
    expect(b.quadrant, Quadrant.doNow);
    final d = c.addSpokenTask(const SpokenTask(title: 'Kitap'))!;
    expect(d.quadrant, Quadrant.plan);
    expect(titles(c.tasksIn('school', Quadrant.plan)), ['Kitap']);
  });

  test('addList boş adı reddeder; 20 liste eklenebilir; adlar 40 karaktere kırpılmaz', () async {
    final c = await seeded();
    expect(() => c.addList(''), throwsArgumentError);
    expect(() => c.addList('   '), throwsArgumentError);
    expect(c.lists, hasLength(5));

    final long = 'A' * 60;
    final first = c.addList(long, colorIndex: 2, icon: 'star');
    expect(first.name, long);
    expect(first.colorIndex, 2);
    expect(first.icon, 'star');
    expect(first.builtIn, isFalse);
    for (var i = 1; i < 20; i++) {
      c.addList('Liste $i');
    }
    expect(c.lists, hasLength(25));
    expect(c.lists[5].id, first.id);
    expect(c.lists.last.name, 'Liste 19');
    expect(c.listById(first.id).name, long);
  });
}
