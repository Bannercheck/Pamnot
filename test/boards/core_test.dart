import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/board_editor.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/model/hlc.dart';
import 'package:pamnot/boards/model/order.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';

int _ids = 0;
String nextId() => 'id${(_ids++).toString().padLeft(6, '0')}';

BoardEditor editorWithColumns({HlcClock? clock}) {
  final c = clock ?? HlcClock(node: '0000000000000001', wallMs: () => 1000);
  final e = BoardEditor(doc: BoardDoc(id: nextId()), clock: c, newId: nextId);
  e.initialize(title: 'Pano', colorIndex: 3, columns: const [('A', 1, false), ('B', 2, false), ('C', 3, true)]);
  return e;
}

RemoteRow rowOf(BoardItem it, {Iterable<String>? fields, int? rev}) {
  final keys = fields ?? it.f.keys;
  return RemoteRow(
    id: it.id,
    kind: it.kind.name,
    data: {for (final k in keys) k: it.f[k]},
    fh: {for (final k in keys) if (it.h[k] != null) k: it.h[k]!},
    rev: rev,
  );
}

void main() {
  group('HLC', () {
    test('fixed width and ordered by string comparison', () {
      var wall = 5;
      final c = HlcClock(node: 'abcdef0123456789', wallMs: () => wall);
      final a = c.tick(), b = c.tick();
      wall = 4; // clock went back
      final d = c.tick();
      expect(a.length, 38);
      expect(HlcClock.isValid(a), isTrue);
      expect(a.compareTo(b) < 0 && b.compareTo(d) < 0, isTrue);
    });

    test('observe moves past a remote stamp', () {
      final c = HlcClock(node: '0000000000000001', wallMs: () => 10);
      c.observe(HlcClock.format(99999, 7, 'ffffffffffffffff'));
      expect(c.tick().compareTo(HlcClock.format(99999, 7, 'ffffffffffffffff')) > 0, isTrue);
      c.observe('garbage');
    });

    test('counter overflow rolls into the next millisecond', () {
      final c = HlcClock(node: '0000000000000001', wallMs: () => 1);
      String last = '';
      for (var i = 0; i < 100002; i++) {
        final t = c.tick();
        expect(t.compareTo(last) > 0, isTrue);
        last = t;
      }
      expect(last.startsWith('000000000000002'), isTrue);
    });

    test('per-launch nodes differ', () {
      expect(HlcClock().node, isNot(HlcClock().node));
    });
  });

  group('FractionalOrder', () {
    test('between stays strictly inside', () {
      final r = math.Random(1);
      for (var i = 0; i < 200; i++) {
        final v = FractionalOrder.between(10, 11, random: r);
        expect(v > 10 && v < 11, isTrue);
      }
      expect(FractionalOrder.between(null, null), 1024);
      expect(FractionalOrder.between(5, null), 5 + 1024);
      expect(FractionalOrder.between(null, 5), 5 - 1024);
    });

    test('exhaustion is detected', () {
      expect(FractionalOrder.exhausted(1, 1 + 1e-12), isTrue);
      expect(FractionalOrder.exhausted(1, 2), isFalse);
    });
  });

  group('BoardDoc merge and acks', () {
    test('per-field merge keeps concurrent edits to different fields', () {
      final a = editorWithColumns();
      final col = a.columns.first.id;
      final card = a.addCard(columnId: col, title: 'Kart');
      // Device B starts from A's state.
      final bClock = HlcClock(node: '000000000000000b', wallMs: () => 2000);
      final b = BoardDoc(id: a.id);
      b.merge(a.doc.items.values.map(rowOf), bClock);

      a.moveCard(card, columnId: a.columns[1].id, index: 0);
      b.write(card, ItemKind.card, {F.title: 'Yeni ad'}, bClock.tick());

      a.applyRemote([rowOf(b.items[card]!, fields: [F.title])]);
      b.merge([rowOf(a.doc.items[card]!, fields: [F.columnId, F.order])], bClock);

      expect(a.item(card)!.title, 'Yeni ad');
      expect(a.item(card)!.columnId, a.columns[1].id);
      expect(b.items[card]!.columnId, a.columns[1].id);
      expect(b.items[card]!.title, 'Yeni ad');
    });

    test('delete wins over a concurrent move; merge is idempotent', () {
      final a = editorWithColumns();
      final s = a.addSticky(at: const Offset(10, 10), text: 'x');
      final row = rowOf(a.item(s)!);
      final bClock = HlcClock(node: '000000000000000b', wallMs: () => 1000);
      final b = BoardDoc(id: a.id)..merge([row], bClock);
      b.write(s, ItemKind.sticky, {F.x: 99.0, F.y: 99.0}, bClock.tick());
      a.deleteItems({s});
      a.applyRemote([rowOf(b.items[s]!, fields: [F.x, F.y])]);
      a.applyRemote([rowOf(b.items[s]!, fields: [F.x, F.y])]);
      expect(a.item(s)!.deleted, isTrue);
      expect(a.item(s)!.x, 99);
    });

    test('a newer field without its value asks for a catch-up', () {
      final a = editorWithColumns();
      final r = a.applyRemote([
        RemoteRow(id: 'x', kind: 'sticky', data: const {}, fh: {F.text: HlcClock.format(9e12.toInt(), 0, 'ffffffffffffffff')}),
      ]);
      expect(r.incomplete, isTrue);
      expect(a.item('x')!.text, '');
    });

    test('ack clears confirmed fields but keeps edits made during the flight', () {
      final a = editorWithColumns();
      final s = a.addSticky(at: Offset.zero, text: 'Rapor');
      final sent = <String, Map<String, String>>{};
      final rows = a.doc.dirtyRows(sent);
      expect(rows.any((r) => r['id'] == s), isTrue);
      // Edit while the push is in flight.
      a.updateSticky(s, text: 'Rapor v2');
      a.applyAcks(sent, [for (final r in rows) PushAck(id: r['id']! as String, fh: (r['fh']! as Map).cast<String, String>())]);
      expect(a.item(s)!.d, contains(F.text));
      expect(a.item(s)!.d, isNot(contains(F.x)));
    });

    test('ack with a newer server value applies the lost value', () {
      final a = editorWithColumns();
      final s = a.addSticky(at: Offset.zero, text: 'mine');
      final sent = <String, Map<String, String>>{};
      a.doc.dirtyRows(sent);
      final newer = HlcClock.format(9e12.toInt(), 0, 'ffffffffffffffff');
      a.applyAcks(sent, [
        PushAck(id: s, fh: {...sent[s]!, F.text: newer}, lost: const {F.text: 'theirs'}),
      ]);
      expect(a.item(s)!.text, 'theirs');
      expect(a.item(s)!.d, isEmpty);
    });

    test('prepareUpload drops tombstones and dirties every field', () {
      final a = editorWithColumns();
      final s = a.addSticky(at: Offset.zero);
      a.deleteItems({s});
      a.doc.clearDirty();
      a.doc.prepareUpload(const BoardAccount(host: 'h', userId: 'u'));
      expect(a.doc.items.containsKey(s), isFalse);
      expect(a.doc.state, BoardState.uploading);
      expect(a.doc.items.values.every((i) => i.d.length == i.h.length), isTrue);
    });

    test('remint moves the meta item to the new id', () {
      final a = editorWithColumns();
      final old = a.id;
      a.doc.remint('newboard');
      expect(a.doc.items.containsKey(old), isFalse);
      expect(a.title, 'Pano');
      expect(a.doc.meta!.id, 'newboard');
    });

    test('JSON round trip keeps fields, HLCs and dirty sets but not strokes', () {
      final a = editorWithColumns();
      final ink = a.addInk(origin: const Offset(5, 5), strokes: 'PINK1:abc');
      final back = BoardDoc.fromJson(a.doc.toJson())!;
      expect(back.items.length, a.doc.items.length);
      expect(back.items[ink]!.strokes, isNull);
      expect(back.items[ink]!.h[F.strokes], a.item(ink)!.h[F.strokes]);
      expect(back.items[ink]!.d, a.item(ink)!.d);
    });
  });

  group('BoardEditor', () {
    test('cards keep order through moves and renormalise when out of room', () {
      final e = editorWithColumns();
      final col = e.columns.first.id;
      final ids = [for (var i = 0; i < 5; i++) e.addCard(columnId: col, title: '$i')];
      e.moveCard(ids[4], columnId: col, index: 0);
      expect(e.cardsIn(col).map((c) => c.title).toList(), ['4', '0', '1', '2', '3']);
      // Squeeze 80 cards between the same two neighbours.
      for (var i = 0; i < 80; i++) {
        final id = e.addCard(columnId: col, title: 'n$i');
        e.moveCard(id, columnId: col, index: 1);
      }
      final orders = e.cardsIn(col).map((c) => c.order).toList();
      for (var i = 1; i < orders.length; i++) {
        expect(orders[i] > orders[i - 1], isTrue);
      }
    });

    test('a card whose column was deleted shows in the first column', () {
      final e = editorWithColumns();
      final c = e.addCard(columnId: e.columns[2].id, title: 'k');
      e.doc.items[e.columns[2].id]!.f[F.deleted] = true;
      e.touch();
      expect(e.cardsIn(e.columns.first.id).map((x) => x.id), contains(c));
    });

    test('deleting a column moves its cards to a neighbour', () {
      final e = editorWithColumns();
      final b = e.columns[1].id;
      final c1 = e.addCard(columnId: b, title: '1');
      e.addCard(columnId: e.columns[0].id, title: 'x');
      e.deleteColumn(b);
      expect(e.columns.length, 2);
      expect(e.item(c1)!.columnId, e.columns[0].id);
      expect(e.cardsIn(e.columns[0].id).last.id, c1);
    });

    test('moveColumn swaps neighbours', () {
      final e = editorWithColumns();
      List<String> names() => e.columns.map((c) => c.title).toList();
      e.moveColumn(e.columns[0].id, 1);
      expect(names(), ['B', 'A', 'C']);
      e.moveColumn(e.columns[2].id, -1);
      expect(names(), ['B', 'C', 'A']);
    });

    test('done count follows done columns', () {
      final e = editorWithColumns();
      e.addCard(columnId: e.columns[2].id, title: 'd');
      e.addCard(columnId: e.columns[0].id, title: 'o');
      expect(e.doneCount, 1);
      expect(e.cardCount, 2);
      expect(e.isDoneColumn(e.columns[2].id), isTrue);
    });

    test('undo and redo; creation undo deletes', () {
      final e = editorWithColumns();
      final s = e.addSticky(at: const Offset(1, 2), text: 'a');
      e.updateSticky(s, text: 'b');
      e.undo();
      expect(e.item(s)!.text, 'a');
      e.undo();
      expect(e.item(s)!.deleted, isTrue);
      e.redo();
      expect(e.item(s)!.deleted, isFalse);
      e.redo();
      expect(e.item(s)!.text, 'b');
    });

    test('undo skips fields someone else changed since', () {
      final e = editorWithColumns();
      final s = e.addSticky(at: Offset.zero, text: 'mine');
      e.moveTo({s: const Offset(50, 50)});
      // A teammate edits the text after.
      e.applyRemote([
        RemoteRow(id: s, kind: 'sticky', data: const {F.text: 'theirs'}, fh: {F.text: HlcClock.format(9e12.toInt(), 0, 'ffffffffffffffff')}),
      ]);
      e.updateSticky(s, colorIndex: 2);
      final out = e.undo(); // colour
      expect(out.applied, isTrue);
      e.undo(); // move
      expect(e.item(s)!.x, 0);
      expect(e.item(s)!.text, 'theirs');
    });

    test('batch is one undo step and one notification', () {
      final e = editorWithColumns();
      var notes = 0;
      e.addListener(() => notes++);
      e.batch(() {
        e.addSticky(at: Offset.zero);
        e.addSticky(at: const Offset(10, 0));
      });
      expect(notes, 1);
      e.undo();
      expect(e.canvasItems, isEmpty);
    });

    test('sticky to card keeps text and colour', () {
      final e = editorWithColumns();
      final s = e.addSticky(at: Offset.zero, text: 'Başlık\nAyrıntı', colorIndex: 6);
      final c = e.stickyToCard(s, e.columns.first.id)!;
      expect(e.item(c)!.title, 'Başlık');
      expect(e.item(c)!.notes, 'Ayrıntı');
      expect(e.item(c)!.colorIndex, 6);
      expect(e.item(s)!.deleted, isTrue);
      e.undo();
      expect(e.item(s)!.deleted, isFalse);
      expect(e.item(c)!.deleted, isTrue);
    });

    test('updateCard writes only changed fields', () {
      final e = editorWithColumns();
      final c = e.addCard(columnId: e.columns.first.id, title: 't');
      e.doc.clearDirty();
      e.updateCard(c, {F.title: 't', F.notes: 'n', F.subtasks: const <Object?>[]});
      expect(e.item(c)!.d, {F.notes});
    });

    test('z order: front and back', () {
      final e = editorWithColumns();
      final a = e.addSticky(at: Offset.zero);
      final b = e.addSticky(at: Offset.zero);
      e.bringToFront({a});
      expect(e.canvasItems.last.id, a);
      e.sendToBack({a});
      expect(e.canvasItems.first.id, a);
      expect(e.canvasItems.last.id, b);
    });

    test('read-only boards ignore edits', () {
      final e = editorWithColumns();
      e.doc.state = BoardState.revoked;
      e.addSticky(at: Offset.zero);
      expect(e.canvasItems, isEmpty);
    });
  });

  group('BoardsController', () {
    test('create, edit, persist and reload', () async {
      final store = MemoryStore();
      final c = BoardsController(store: store, saveDelay: Duration.zero, newId: nextId);
      await c.load();
      final id = await c.createBoard(title: 'Proje', colorIndex: 4, template: BoardTemplate.tasks, strings: S.tr);
      final b = (await c.open(id))!;
      expect(b.editor.columns.map((x) => x.title), ['Yapılacak', 'Yapılıyor', 'Bitti']);
      b.editor.addCard(columnId: b.editor.columns.first.id, title: 'Kart');
      b.editor.addInk(origin: Offset.zero, strokes: 'PINK1:xyz');
      await c.release(b);
      await c.flush();
      expect(store.data.keys.where((k) => k.startsWith('boardink_')), hasLength(1));

      final c2 = BoardsController(store: store, saveDelay: Duration.zero, newId: nextId);
      await c2.load();
      expect(c2.boards.single.title, 'Proje');
      expect(c2.boards.single.cardCount, 1);
      final b2 = (await c2.open(id))!;
      await pumpEventQueue();
      expect(b2.editor.cardsIn(b2.editor.columns.first.id).single.title, 'Kart');
      expect(b2.editor.canvasItems.single.strokes, 'PINK1:xyz');
    });

    test('blank template has no columns; sample board is device-only and clean', () async {
      final c = BoardsController(store: MemoryStore(), saveDelay: Duration.zero, newId: nextId);
      await c.load();
      final blank = await c.createBoard(title: 'Boş', colorIndex: 0, template: BoardTemplate.blank, strings: S.en);
      expect((await c.open(blank))!.editor.columns, isEmpty);
      final sample = await c.seedSample(S.tr);
      final b = (await c.open(sample))!;
      expect(b.editor.cardCount, 4);
      expect(b.editor.canvasItems.length, 3);
      expect(b.doc.pendingCount, 0);
      expect(b.doc.state, BoardState.local);
    });

    test('shared boards of another account are hidden', () async {
      final c = BoardsController(store: MemoryStore(), saveDelay: Duration.zero, newId: nextId);
      await c.load();
      await c.addJoined(boardId: 'shared1', title: 'Ekip', account: const BoardAccount(host: 'h', userId: 'u1'));
      expect(c.boards, isEmpty);
      c.currentAccount = () => const BoardAccount(host: 'h', userId: 'u1');
      expect(c.boards.single.title, 'Ekip');
    });

    test('beginUpload marks everything dirty under the account', () async {
      final c = BoardsController(store: MemoryStore(), saveDelay: Duration.zero, newId: nextId);
      await c.load();
      final id = await c.createBoard(title: 'P', colorIndex: 0, template: BoardTemplate.tasks, strings: S.tr);
      await c.beginUpload(id, const BoardAccount(host: 'h', userId: 'u'));
      final b = (await c.open(id))!;
      expect(b.doc.state, BoardState.uploading);
      expect(b.doc.pendingCount, b.doc.items.length);
    });
  });
}
