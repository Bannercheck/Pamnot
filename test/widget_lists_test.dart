import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/services/widget_sync.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/common/glass_nav_bar.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/matrix/matrix_page.dart';

/// The list summary the iOS list widget reads, and the "done" taps it leaves
/// behind (design §8).
void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 11, 25, 9);
  final settingsDoc = jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson());

  final controllers = <AppController>[];
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  Future<AppController> boot(NoopWidgetSync w, {MemoryStore? store}) async {
    final c = AppController(
      store: store ?? MemoryStore({'settings': settingsDoc}),
      scheduler: NoopScheduler(),
      widgetSync: w,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    controllers.add(c);
    await c.load();
    return c;
  }

  TaskItem add(AppController c, String id, String title,
      {String listId = TaskList.personalId, Quadrant q = Quadrant.plan, DateTime? due, bool hasTime = false}) {
    final d = c.draftTask(listId: listId, quadrant: q);
    final t = TaskItem(
      id: id,
      title: title,
      createdAt: d.createdAt,
      listId: d.listId,
      quadrant: d.quadrant,
      order: d.order,
      due: due,
      hasTime: hasTime,
    );
    c.upsertTask(t);
    return t;
  }

  Map<String, Object?> listOf(Map<String, Object?> s, String id) =>
      (s['lists']! as List).cast<Map<String, Object?>>().firstWhere((l) => l['id'] == id);
  Map<String, Object?> boxOf(Map<String, Object?> list, String box) =>
      ((list['boxes']! as Map)[box]! as Map).cast<String, Object?>();
  List<Map<String, Object?>> itemsOf(Map<String, Object?> box) => (box['items']! as List).cast<Map<String, Object?>>();

  test('listsSummary: sözleşmedeki alanlar; kutu başına en çok 6 öğe, count gerçek sayı', () async {
    final c = await boot(NoopWidgetSync());
    for (var i = 0; i < 8; i++) {
      add(c, 'n$i', 'Görev $i', q: Quadrant.doNow);
    }
    add(c, 'a', 'Annemi ara', q: Quadrant.plan, due: DateTime(2026, 11, 25, 18), hasTime: true);
    add(c, 'b', 'Fatura', q: Quadrant.plan, due: DateTime(2026, 11, 27, 9, 5), hasTime: true);
    add(c, 'd', 'Gün', q: Quadrant.plan, due: DateTime(2026, 11, 26));

    final s = c.listsSummary();
    expect(s.keys, containsAll(['updatedAt', 'lang', 'labels', 'boxes', 'lists']));
    expect(s['updatedAt'], now.toIso8601String());
    expect(s['lang'], 'tr');
    expect(s['labels'], {'all': 'Tümü', 'empty': 'Görev yok', 'appName': 'Pamnot'});
    expect(s['boxes'], {
      'doNow': 'Önemli · Acil',
      'plan': 'Önemli · Planlı',
      'delegate': 'Acil · Önemsiz',
      'later': 'Sonra · Belki',
    });
    expect([for (final l in (s['lists']! as List).cast<Map<String, Object?>>()) l['id']],
        ['personal', 'work', 'school', 'shopping', 'home']);

    final personal = listOf(s, 'personal');
    expect(personal.keys, containsAll(['id', 'name', 'color', 'boxes']));
    expect(personal['name'], 'Kişisel');
    expect((personal['boxes']! as Map).keys, ['doNow', 'plan', 'delegate', 'later']);

    final doNow = boxOf(personal, 'doNow');
    expect(doNow['count'], 8);
    final items = itemsOf(doNow);
    expect(items, hasLength(6));
    expect([for (final i in items) i['title']], [for (var i = 0; i < 6; i++) 'Görev $i']);
    expect(items.first.keys, ['id', 'title', 'time']);
    expect(items.first['id'], 'n0');
    expect(items.first['time'], '');

    final plan = itemsOf(boxOf(personal, 'plan'));
    expect({for (final i in plan) i['id']: i['time']}, {'a': '18:00', 'b': '27 Kas 09:05', 'd': ''});

    final empty = boxOf(listOf(s, 'work'), 'later');
    expect(empty, {'count': 0, 'items': <Object?>[]});
    expect(jsonDecode(jsonEncode(s)), s);
  });

  test('biten görev özetten çıkar; liste rengi #RRGGBB', () async {
    final c = await boot(NoopWidgetSync());
    add(c, 'x', 'Açık', q: Quadrant.later);
    add(c, 'y', 'Biten', q: Quadrant.later);
    c.toggleTask('y');
    final s = c.listsSummary();
    final later = boxOf(listOf(s, 'personal'), 'later');
    expect(later['count'], 1);
    expect([for (final i in itemsOf(later)) i['id']], ['x']);
    for (final l in (s['lists']! as List).cast<Map<String, Object?>>()) {
      expect(l['color'], matches(RegExp(r'^#[0-9A-F]{6}$')));
    }
  });

  test('görev ya da liste değişince pushLists yeniden çağrılır (NoopWidgetSync.lastLists)', () async {
    final w = NoopWidgetSync();
    final c = await boot(w);
    await c.syncWidget();
    expect(w.last, isNotNull);
    expect(w.lastLists, isNotNull);

    w.lastLists = null;
    add(c, 'k', 'Kitap oku', q: Quadrant.delegate);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(w.lastLists, isNotNull);
    expect([for (final i in itemsOf(boxOf(listOf(w.lastLists!, 'personal'), 'delegate'))) i['title']], ['Kitap oku']);

    w.lastLists = null;
    final l = c.addList('Spor');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(w.lastLists, isNotNull);
    expect(listOf(w.lastLists!, l.id)['name'], 'Spor');
  });

  test('applyWidgetCompletions bekleyen id\'leri bitirir ve completedAt yazar', () async {
    final w = NoopWidgetSync();
    final c = await boot(w);
    add(c, 'p1', 'Bir');
    add(c, 'p2', 'İki', q: Quadrant.doNow);
    add(c, 'p3', 'Üç');
    w.pending = ['p1', 'p2'];
    w.lastLists = null;
    await c.applyWidgetCompletions();

    TaskItem t(String id) => c.tasks.firstWhere((x) => x.id == id);
    expect(t('p1').done, isTrue);
    expect(t('p1').completedAt, now);
    expect(t('p2').done, isTrue);
    expect(t('p3').done, isFalse);
    expect(w.pending, isEmpty);
    // The summary is pushed again right away, without the finished tasks.
    expect(w.lastLists, isNotNull);
    expect([for (final i in itemsOf(boxOf(listOf(w.lastLists!, 'personal'), 'plan'))) i['id']], ['p3']);
  });

  test('RF: silinmiş görevin id\'si ve zaten bitmiş görev yok sayılır; hata yok', () async {
    final w = NoopWidgetSync();
    final c = await boot(w);
    add(c, 'done', 'Biten');
    c.toggleTask('done');
    final finishedAt = c.tasks.firstWhere((x) => x.id == 'done').completedAt;
    add(c, 'open', 'Açık');
    w.pending = ['gone', 'done', 'open', 'open'];
    await c.applyWidgetCompletions();
    expect(c.tasks.firstWhere((x) => x.id == 'done').done, isTrue);
    expect(c.tasks.firstWhere((x) => x.id == 'done').completedAt, finishedAt);
    expect(c.tasks.firstWhere((x) => x.id == 'open').done, isTrue);
    expect(c.tasks.any((x) => x.id == 'gone'), isFalse);
    expect(w.pending, isEmpty);
  });

  test('bekleyen liste boşsa hiçbir şey değişmez ve kayıt tetiklenmez', () async {
    final w = NoopWidgetSync();
    final store = MemoryStore({'settings': settingsDoc});
    final c = await boot(w, store: store);
    add(c, 'q', 'Duran');
    await c.flush();
    store.data.remove('tasks');
    final revs = c.revisions;
    var notified = 0;
    c.addListener(() => notified++);
    w.pending = [];
    w.lastLists = null;
    await c.applyWidgetCompletions();
    await c.flush();
    expect(c.revisions, revs);
    expect(notified, 0);
    expect(store.data.containsKey('tasks'), isFalse);
    expect(w.lastLists, isNull);
    expect(c.tasks.firstWhere((x) => x.id == 'q').done, isFalse);
  });

  test('load() sonunda bekleyen istekler uygulanır', () async {
    final first = NoopWidgetSync();
    final store = MemoryStore({'settings': settingsDoc});
    final c = await boot(first, store: store);
    add(c, 'z', 'Kapanacak');
    await c.flush();

    final w = NoopWidgetSync()..pending = ['z'];
    final again = await boot(w, store: store);
    expect(again.tasks.firstWhere((x) => x.id == 'z').done, isTrue);
    expect(w.pending, isEmpty);
  });

  test('bekleyen metin çözülür: bozuk ya da dizi olmayan metin boş verir', () {
    expect(DedupingWidgetSync.decodePending('["a","b"]'), ['a', 'b']);
    expect(DedupingWidgetSync.decodePending('["a", 3, null, ""]'), ['a']);
    expect(DedupingWidgetSync.decodePending('[]'), isEmpty);
    expect(DedupingWidgetSync.decodePending(null), isEmpty);
    expect(DedupingWidgetSync.decodePending('{bozuk'), isEmpty);
    expect(DedupingWidgetSync.decodePending('{"a":1}'), isEmpty);
  });

  test('pushLists yalnız updatedAt değiştiyse yeniden yazmaz', () async {
    final w = _RecordingSync();
    await w.pushLists({'updatedAt': '1', 'lists': <Object?>[]});
    await w.pushLists({'updatedAt': '2', 'lists': <Object?>[]});
    await w.pushLists({'updatedAt': '3', 'lists': <Object?>['x']});
    expect(w.lists, hasLength(2));
    expect(w.today, isEmpty);
  });

  group('dokunma', () {
    setUp(() => notificationTaps.value = null);
    tearDown(() => notificationTaps.value = null);

    Future<AppController> shell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = AppController(
        store: MemoryStore({'settings': settingsDoc}),
        clock: () => now,
        saveDelay: Duration.zero,
      );
      await tester.runAsync(c.load);
      await tester.pumpWidget(PamnotApp(controller: c));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> close(WidgetTester tester, AppController c) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      c.dispose();
    }

    int selected(WidgetTester tester) => tester.widget<GlassNavBar>(find.byType(GlassNavBar)).selectedIndex;

    testWidgets('w:list:<id> Matris sekmesini o listeyle açar; bilinmeyen id yalnız sekmeyi açar', (tester) async {
      final c = await shell(tester);
      expect(selected(tester), 0);
      expect(c.currentListId, isNot('work'));

      notificationTaps.value = 'w:list:work';
      await tester.pumpAndSettle();
      expect(selected(tester), 2);
      expect(find.byType(MatrixPage), findsOneWidget);
      expect(c.currentListId, 'work');
      expect(notificationTaps.value, isNull);

      await tester.tap(find.byKey(const Key('nav-0')));
      await tester.pumpAndSettle();
      notificationTaps.value = 'w:list:nope';
      await tester.pumpAndSettle();
      expect(selected(tester), 2);
      expect(c.currentListId, 'work');
      expect(notificationTaps.value, isNull);
      await close(tester, c);
    });

    testWidgets('w:today hâlâ Bugün\'ü açar', (tester) async {
      final c = await shell(tester);
      await tester.tap(find.byKey(const Key('nav-3')));
      await tester.pumpAndSettle();
      expect(selected(tester), 3);
      notificationTaps.value = 'w:today';
      await tester.pumpAndSettle();
      expect(selected(tester), 0);
      expect(notificationTaps.value, isNull);
      await close(tester, c);
    });
  });
}

class _RecordingSync extends DedupingWidgetSync {
  final today = <String>[];
  final lists = <String>[];

  @override
  Future<void> write(String json) async => today.add(json);

  @override
  Future<void> writeLists(String json) async => lists.add(json);

  @override
  Future<List<String>> takePendingDone() async => const [];
}
