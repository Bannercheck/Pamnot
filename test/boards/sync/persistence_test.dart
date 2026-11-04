
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/board_editor.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/model/hlc.dart';
import 'package:pamnot/boards/sync/board_sync.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';

/// Records the order of writes and deletes.
class LogStore extends MemoryStore {
  final List<String> log = [];

  @override
  Future<void> write(String key, String value) {
    log.add('write $key');
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    log.add('delete $key');
    return super.delete(key);
  }
}

int _n = 0;
String _id() => '00000000-0000-4000-8000-${(_n++).toRadixString(16).padLeft(12, '0')}';

void main() {
  test('a steady stream of changes cannot postpone the save forever', () {
    fakeAsync((async) {
      final store = MemoryStore();
      final repo = BoardsRepository(store);
      final doc = BoardDoc(id: 'b');
      final clock = HlcClock(node: '0000000000000001', wallMs: () => 1);
      for (var i = 0; i < 30; i++) {
        doc.write('s', ItemKind.sticky, {F.text: 'v$i'}, clock.tick());
        repo.saveBoard(doc);
        async.elapse(const Duration(milliseconds: 100));
        if (i == 20) expect(store.data[BoardsRepository.docKey('b')], isNotNull, reason: 'saved within 5 × saveDelay');
      }
      async.elapse(const Duration(seconds: 1));
      expect(store.data[BoardsRepository.docKey('b')], contains('v29'));
    });
  });

  test('remint writes the new document before deleting the old one', () async {
    final store = LogStore();
    final c = BoardsController(store: store, saveDelay: Duration.zero, newId: _id);
    await c.load();
    final id = await c.createBoard(title: 'P', colorIndex: 0, template: BoardTemplate.tasks, strings: S.tr);
    store.log.clear();
    final nid = await c.remint(id);
    final wrote = store.log.indexOf('write ${BoardsRepository.docKey(nid)}');
    final deleted = store.log.indexOf('delete ${BoardsRepository.docKey(id)}');
    expect(wrote, greaterThanOrEqualTo(0));
    expect(deleted, greaterThan(wrote));
    expect(store.data.containsKey(BoardsRepository.docKey(id)), isFalse);
    expect((await c.open(nid))!.editor.title, 'P');
  });

  test('open loads the strokes of deleted ink that still has to be pushed', () async {
    final store = MemoryStore();
    final c = BoardsController(store: store, saveDelay: Duration.zero, newId: _id);
    await c.load();
    final id = await c.createBoard(title: 'P', colorIndex: 0, template: BoardTemplate.blank, strings: S.tr);
    final b = (await c.open(id))!;
    final dirty = b.editor.addInk(origin: Offset.zero, strokes: 'PINK1:dirty');
    final clean = b.editor.addInk(origin: Offset.zero, strokes: 'PINK1:clean');
    b.doc.items[clean]!.d.clear();
    b.editor.deleteItems({dirty, clean});
    b.doc.items[clean]!.d.clear();
    await c.release(b);
    await c.flush();
    final c2 = BoardsController(store: store, saveDelay: Duration.zero, newId: _id);
    await c2.load();
    final b2 = (await c2.open(id))!;
    await pumpEventQueue();
    expect(b2.doc.items[dirty]!.strokes, 'PINK1:dirty');
    expect(b2.doc.items[clean]!.strokes, isNull, reason: 'clean deleted ink stays on disk');
    expect(b2.editor, isA<BoardEditor>());
  });

  testWidgets('AppForeground follows the app lifecycle', (tester) async {
    final f = AppForeground();
    expect(f.value, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(f.value, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(f.value, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(f.value, isTrue);
    f.dispose();
  });
}
