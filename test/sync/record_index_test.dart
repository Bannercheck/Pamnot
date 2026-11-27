import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/sync/record_index.dart';
import 'package:pamnot/features/sync/snapshot.dart';
import 'package:pamnot/features/sync/zone_ref.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';

/// A store whose writes never land, as if the app stopped before saving.
class _LostWrites extends MemoryStore {
  _LostWrites();

  @override
  Future<void> write(String key, String value) async => throw StateError('disk full');
}

void main() {
  setUpAll(() => initializeDateFormatting());
  var clock = DateTime.utc(2026, 11, 27, 12);
  DateTime now() => clock;
  final created = DateTime.utc(2026, 11, 1, 8);

  final settingsDoc = jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson());

  final controllers = <AppController>[];
  setUp(() => clock = DateTime.utc(2026, 11, 27, 12));
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  Future<AppController> boot() async {
    final a = AppController(
      store: MemoryStore({'settings': settingsDoc}),
      scheduler: NoopScheduler(),
      clock: now,
      saveDelay: Duration.zero,
    );
    controllers.add(a);
    await a.load();
    return a;
  }

  TaskItem addTask(AppController app, String id, {String listId = 'work'}) {
    final t = TaskItem(id: id, title: 'Görev $id', createdAt: created, listId: listId);
    app.upsertTask(t);
    return t;
  }

  Note addNote(AppController app, String id) {
    final n = Note(id: id, title: 'Not', body: 'gövde', createdAt: created, updatedAt: created);
    app.upsertNote(n);
    return n;
  }

  /// A loaded index that has already migrated [app]'s records.
  Future<RecordIndex> migrated(AppController app, MemoryStore store) async {
    final index = RecordIndex(store, now: now);
    await index.load();
    index.scan(snapshotApp(app));
    expect(index.migrated, isTrue);
    index.markSent(index.dirtyKeys.toList());
    return index;
  }

  void quiet() {
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = saved);
  }

  test('RF1: göç her kayda createdAt verir, hepsini kirli yapar, hiçbirini silmez ve bir kez çalışır', () async {
    final app = await boot();
    addTask(app, 't1');
    addNote(app, 'n1');
    final store = MemoryStore();
    final index = RecordIndex(store, now: now);
    await index.load();
    expect(index.migrated, isFalse);

    clock = DateTime.utc(2026, 11, 28);
    final diff = index.scan(snapshotApp(app), only: {RecordType.note});
    expect(index.migrated, isTrue);
    final keys = snapshotApp(app).keys.toSet();
    expect(keys, containsAll(['task:t1', 'note:n1', 'list:work', 'list:personal']));
    expect(diff.changed, keys, reason: 'migration ignores `only`');
    expect(diff.deleted, isEmpty);
    expect(index.dirtyKeys.toSet(), keys);
    expect(index['task:t1']!.updatedAt, created);
    expect(index['task:t1']!.updatedAt.isUtc, isTrue);
    expect(index['task:t1']!.zone, ZoneRef.forList('work'));
    expect(index['note:n1']!.zone, ZoneRef.personal);
    expect(index['note:n1']!.deleted, isFalse);

    // Saved without being asked; the saved document holds no user text.
    await pumpEventQueue();
    final doc = store.data[RecordIndex.storeKey]!;
    expect(doc, isNot(contains('Görev')));
    expect(doc, isNot(contains('gövde')));

    expect(index.scan(snapshotApp(app)).isEmpty, isTrue);
    final again = RecordIndex(store, now: now);
    await again.load();
    expect(again.migrated, isTrue);
    expect(again['task:t1']!.updatedAt, created);
    expect(again.dirtyKeys.toSet(), keys);
    expect(again.scan(snapshotApp(app)).isEmpty, isTrue);
  });

  test('RF1: göç yarıda kalırsa (save öncesi yeniden yükleme) baştan ve eksiksiz çalışır', () async {
    quiet();
    final app = await boot();
    addTask(app, 't1');
    final store = _LostWrites();
    final first = RecordIndex(store, now: now);
    await first.load();
    first.scan(snapshotApp(app));
    await first.save().catchError((_) {});

    addTask(app, 't2');
    final second = RecordIndex(store, now: now);
    await second.load();
    expect(second.migrated, isFalse);
    final diff = second.scan(snapshotApp(app), only: {RecordType.note});
    expect(diff.changed, containsAll(['task:t1', 'task:t2']));
    expect(second['task:t2']!.updatedAt, created);
    expect(second.dirtyKeys, containsAll(['task:t1', 'task:t2']));
    await pumpEventQueue();
  });

  test('RF1: dokunulmamış hazır liste pristineTime alır; adı değişmiş "work" createdAt yokken now() alır', () async {
    final app = await boot();
    app.updateList(app.lists.firstWhere((l) => l.id == 'work').copyWith(name: 'Ofis'));
    final snap = snapshotApp(app);
    expect(snap['list:personal']!.pristine, isTrue);
    expect(snap['list:work']!.pristine, isFalse);
    final index = RecordIndex(MemoryStore(), now: now);
    await index.load();
    index.scan(snap);
    expect(index['list:personal']!.updatedAt, RecordIndex.pristineTime);
    expect(index['list:school']!.updatedAt, RecordIndex.pristineTime);
    expect(index['list:work']!.updatedAt, clock);
  });

  test('hazır liste İngilizce varsayılan adıyla da dokunulmamış sayılır; rengi değişen sayılmaz', () async {
    final app = await boot();
    final en = TaskList.defaults(tr: false).firstWhere((l) => l.id == 'home');
    app.updateList(app.lists.firstWhere((l) => l.id == 'home').copyWith(name: en.name));
    app.updateList(app.lists.firstWhere((l) => l.id == 'shopping').copyWith(colorIndex: 0));
    final snap = snapshotApp(app);
    expect(snap['list:home']!.pristine, isTrue);
    expect(snap['list:shopping']!.pristine, isFalse);
    final custom = app.addList('Proje');
    expect(snapshotApp(app)['list:${custom.id}']!.pristine, isFalse);
  });

  test('değişen görev changed\'e girer ve updatedAt ilerler; değişmeyenler girmez', () async {
    final app = await boot();
    final t1 = addTask(app, 't1');
    addTask(app, 't2');
    final index = await migrated(app, MemoryStore());

    clock = DateTime.utc(2026, 11, 29, 10);
    app.upsertTask(t1.copyWith(title: 'Yeni başlık'));
    final diff = index.scan(snapshotApp(app), only: {RecordType.task});
    expect(diff.changed, {'task:t1'});
    expect(diff.deleted, isEmpty);
    expect(diff.movedFrom, isEmpty);
    expect(index['task:t1']!.updatedAt, clock);
    expect(index['task:t1']!.dirty, isTrue);
    expect(index['task:t2']!.updatedAt, created);
    expect(index['task:t2']!.dirty, isFalse);
    expect(index.dirtyKeys.toList(), ['task:t1']);
  });

  test('silinen görev silme işareti olur; restoreTask sonrası işaret kalkar ve changed\'e girer', () async {
    final app = await boot();
    addTask(app, 't1');
    final index = await migrated(app, MemoryStore());

    clock = DateTime.utc(2026, 11, 29);
    final gone = app.deleteTask('t1')!;
    var diff = index.scan(snapshotApp(app), only: {RecordType.task});
    expect(diff.deleted, {'task:t1'});
    expect(diff.changed, isEmpty);
    expect(index['task:t1']!.deleted, isTrue);
    expect(index['task:t1']!.dirty, isTrue);
    expect(index['task:t1']!.updatedAt, clock);
    expect(index.scan(snapshotApp(app), only: {RecordType.task}).isEmpty, isTrue);

    clock = DateTime.utc(2026, 11, 29, 0, 1);
    app.restoreTask(gone);
    diff = index.scan(snapshotApp(app), only: {RecordType.task});
    expect(diff.changed, {'task:t1'});
    expect(diff.deleted, isEmpty);
    expect(index['task:t1']!.deleted, isFalse);
    expect(index['task:t1']!.updatedAt, clock);
  });

  test('RF3: liste değiştiren görev movedFrom ile eski bölgesini bildirir', () async {
    final app = await boot();
    final t1 = addTask(app, 't1');
    final index = await migrated(app, MemoryStore());

    app.upsertTask(t1.copyWith(listId: 'school'));
    final diff = index.scan(snapshotApp(app), only: {RecordType.task});
    expect(diff.changed, {'task:t1'});
    expect(diff.movedFrom, {'task:t1': ZoneRef.forList('work')});
    expect(index['task:t1']!.zone, ZoneRef.forList('school'));
  });

  test('RF3: yalnız mürekkebi değişen not (editör updatedAt\'i ilerletir) changed\'e girer', () async {
    final app = await boot();
    final n = addNote(app, 'n1');
    final index = await migrated(app, MemoryStore());

    final later = created.add(const Duration(minutes: 5));
    app.upsertNote(n.copyWith(updatedAt: later), inkChanged: true);
    final diff = index.scan(snapshotApp(app), only: {RecordType.note});
    expect(diff.changed, {'note:n1'});
    expect(snapshotApp(app)['note:n1']!.createdAt, later, reason: 'a note offers its updatedAt');
  });

  test('adopt edilen kayıt bir sonraki scan\'de changed değildir', () async {
    final app = await boot();
    final t1 = addTask(app, 't1');
    final index = await migrated(app, MemoryStore());

    // A newer version arrives from the server and is applied locally.
    final remote = t1.copyWith(title: 'Sunucudan');
    app.upsertTask(remote);
    final at = DateTime.utc(2026, 11, 28, 7);
    index.adopt('task:t1', snapshotApp(app)['task:t1'], updatedAt: at);
    expect(index['task:t1']!.dirty, isFalse);
    expect(index['task:t1']!.updatedAt, at);
    expect(index.scan(snapshotApp(app), only: {RecordType.task}).isEmpty, isTrue);

    // A remote deletion: the record leaves the app and stays a clean tombstone.
    app.deleteTask('t1');
    index.adopt('task:t1', null, updatedAt: at, deleted: true);
    expect(index['task:t1']!.deleted, isTrue);
    expect(index['task:t1']!.dirty, isFalse);
    expect(index.scan(snapshotApp(app), only: {RecordType.task}).isEmpty, isTrue);
    expect(index.dirtyKeys, isEmpty);

    index.markAllDirty();
    expect(index.dirtyKeys, containsAll(['task:t1', 'list:work']));
  });

  test('purge 30 günden eski işaretleri döner ve çıkarır; 29 günlük kalır', () async {
    final app = await boot();
    addTask(app, 'old');
    addTask(app, 'young');
    final index = await migrated(app, MemoryStore());

    clock = DateTime.utc(2026, 11, 1);
    app.deleteTask('old');
    index.scan(snapshotApp(app), only: {RecordType.task});
    clock = DateTime.utc(2026, 11, 3);
    app.deleteTask('young');
    index.scan(snapshotApp(app), only: {RecordType.task});

    clock = DateTime.utc(2026, 12, 2);
    expect(index.purge(), ['task:old']);
    expect(index['task:old'], isNull);
    expect(index['task:young']!.deleted, isTrue);
    expect(index['list:work'], isNotNull, reason: 'live records are never purged');
    expect(index.purge(), isEmpty);
  });

  test('only: {task} verilince not değişikliği taranmaz', () async {
    final app = await boot();
    final n = addNote(app, 'n1');
    addNote(app, 'n2');
    final index = await migrated(app, MemoryStore());

    app.upsertNote(n.copyWith(title: 'Başka', updatedAt: created.add(const Duration(hours: 1))));
    app.deleteNote('n2');
    expect(index.scan(snapshotApp(app), only: {RecordType.task}).isEmpty, isTrue);
    expect(index['note:n2']!.deleted, isFalse);
    expect(snapshotApp(app, only: {RecordType.task}).keys.every((k) => k.startsWith('task:')), isTrue);

    final diff = index.scan(snapshotApp(app), only: {RecordType.note});
    expect(diff.changed, {'note:n1'});
    expect(diff.deleted, {'note:n2'});
  });

  test('bozuk sync_index belgesi boş dizin ve yeniden göç demektir; istisna yok', () async {
    quiet();
    final app = await boot();
    addTask(app, 't1');
    for (final bad in [
      '{',
      '[]',
      'null',
      jsonEncode({'v': 1, 'migrated': true, 'entries': []}),
      jsonEncode({
        'v': 1,
        'migrated': true,
        'entries': {
          'task:t1': {'f': 'x', 'u': 'dün', 'd': false, 'z': 'list-work', 'k': false},
        },
      }),
      jsonEncode({
        'v': 1,
        'migrated': true,
        'entries': {
          'task:t1': {'f': 'x', 'u': 0, 'd': false, 'z': '../etc', 'k': false},
        },
      }),
    ]) {
      final store = MemoryStore({RecordIndex.storeKey: bad});
      final index = RecordIndex(store, now: now);
      await index.load();
      expect(index.migrated, isFalse, reason: bad);
      expect(index['task:t1'], isNull, reason: bad);
      final diff = index.scan(snapshotApp(app));
      expect(diff.changed, contains('task:t1'), reason: bad);
      expect(index.migrated, isTrue, reason: bad);
    }
  });

  test('fingerprint: FNV-1a onaltılık ve uzunluk; içerik değişince değişir', () {
    expect(fingerprint(const {}), '${_fnv('{}')}:2');
    expect(fingerprint(const {'a': 'ç'}), '${_fnv('{"a":"ç"}')}:${utf8.encode('{"a":"ç"}').length}');
    expect(fingerprint(const {'a': 1}), isNot(fingerprint(const {'a': 2})));
    expect(fingerprint(const {'a': 1}), matches(RegExp(r'^[0-9a-f]{8}:\d+$')));
  });

  test('5 000 görevlik anlık görüntünün taraması 500 ms\'nin altında', () async {
    final app = await boot();
    for (var i = 0; i < 5000; i++) {
      app.upsertTask(TaskItem(
        id: 'task-$i',
        title: 'Görev numarası $i, biraz uzunca bir başlık',
        notes: 'Not $i' * 10,
        createdAt: created,
        listId: i.isEven ? 'work' : 'home',
      ));
    }
    final index = await migrated(app, MemoryStore());
    app.upsertTask(app.tasks.first.copyWith(title: 'değişti'));
    final sw = Stopwatch()..start();
    final diff = index.scan(snapshotApp(app, only: {RecordType.task}), only: {RecordType.task});
    sw.stop();
    expect(diff.changed, hasLength(1));
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}

/// Reference 32-bit FNV-1a over UTF-8 bytes, written independently.
String _fnv(String s) {
  var h = BigInt.from(0x811c9dc5);
  final mask = BigInt.from(0xffffffff);
  for (final b in utf8.encode(s)) {
    h = ((h ^ BigInt.from(b)) * BigInt.from(0x01000193)) & mask;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
