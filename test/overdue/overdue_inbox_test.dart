import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/overdue/overdue_inbox.dart';

import '../support/overdue_harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final h = OverdueHarness();
  tearDown(h.disposeAll);

  test('add iki kez aynı kimliği bir kez tutar; take okur ve boşaltır', () async {
    final store = MemoryStore();
    final inbox = OverdueInbox(store);
    await inbox.add('a');
    await inbox.add('a');
    await inbox.add('b');
    expect(await inbox.take(), ['a', 'b']);
    expect(store.data.containsKey(OverdueInbox.storeKey), isFalse);
    expect(await inbox.take(), isEmpty);
  });

  test('add en çok 200 kimlik tutar; en eskiler düşer', () async {
    final inbox = OverdueInbox(MemoryStore());
    for (var i = 0; i < 205; i++) {
      await inbox.add('t$i');
    }
    final ids = await inbox.take();
    expect(ids, hasLength(200));
    expect(ids.first, 't5');
    expect(ids.last, 't204');
  });

  test(
    'RF5: applyOverdueInbox silinmiş ve zaten tamam görevi atlar, açık olanı tamamlar; ikinci çağrı 0 döner',
    () async {
      final c = await h.boot();
      final open = h.add(c, 'Açık', due: DateTime(2026, 11, 26, 14));
      final done = h.add(c, 'Bitti', due: DateTime(2026, 11, 26, 14));
      final gone = h.add(c, 'Silinen', due: DateTime(2026, 11, 26, 14));
      c.completeTask(done.id);
      c.deleteTask(gone.id);
      final inbox = OverdueInbox(MemoryStore());
      for (final id in [open.id, done.id, gone.id, 'unknown']) {
        await inbox.add(id);
      }
      expect(await applyOverdueInbox(c, inbox), 1);
      expect(c.tasks.firstWhere((t) => t.id == open.id).done, isTrue);
      expect(await applyOverdueInbox(c, inbox), 0);
    },
  );

  test('bozuk overdue_done belgesi boş sayılır', () async {
    for (final raw in ['not json', '{"a":1}', '[1, null, "x"]', '']) {
      final store = MemoryStore({OverdueInbox.storeKey: raw});
      final inbox = OverdueInbox(store);
      final ids = await inbox.take();
      expect(ids, raw.startsWith('[') ? ['x'] : isEmpty, reason: raw);
      expect(store.data.containsKey(OverdueInbox.storeKey), isFalse);
    }
    final store = MemoryStore({OverdueInbox.storeKey: 'not json'});
    await OverdueInbox(store).add('a');
    expect(jsonDecode(store.data[OverdueInbox.storeKey]!), ['a']);
  });
}
