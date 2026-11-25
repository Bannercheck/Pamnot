import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/system_accessibility.dart';
import 'package:pamnot/ui/matrix/habits_page.dart';
import 'package:pamnot/ui/matrix/matrix_card.dart';
import 'package:pamnot/ui/tasks/task_tile.dart';

import 'support/matrix_harness.dart';

/// The Matrix screen (v2 design §3.3, Task 9): list tabs, the four boxes,
/// drag and drop, the long-press menu and the VoiceOver actions.
void main() {
  setUpAll(() => initializeDateFormatting());
  tearDown(() => SystemAccessibility.reduceTransparency.value = false);

  Finder card(String id) => find.byKey(Key('matrix-card-$id'));
  Finder box(Quadrant q) => find.byKey(Key('box-${q.name}'));

  testWidgets('dört kutu tasarımdaki başlıklarla ve alt satırlarla görünür', (tester) async {
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    for (final (q, title, hint) in [
      (Quadrant.doNow, 'Önemli · Acil', 'Bugün ilgilen'),
      (Quadrant.plan, 'Önemli · Planlı', 'Zamanını belirle'),
      (Quadrant.delegate, 'Acil · Önemsiz', 'Kısa tut ya da paylaş'),
      (Quadrant.later, 'Sonra · Belki', 'Gerekirse dön'),
    ]) {
      expect(find.descendant(of: box(q), matching: find.text(title)), findsOneWidget, reason: q.name);
      expect(find.descendant(of: box(q), matching: find.text(hint)), findsOneWidget, reason: q.name);
      // An empty box says so.
      expect(find.descendant(of: box(q), matching: find.text('Boş')), findsOneWidget, reason: q.name);
    }
    // Order: doNow | plan on top, delegate | later below.
    expect(tester.getTopLeft(box(Quadrant.doNow)).dx, lessThan(tester.getTopLeft(box(Quadrant.plan)).dx));
    expect(tester.getTopLeft(box(Quadrant.doNow)).dy, lessThan(tester.getTopLeft(box(Quadrant.delegate)).dy));
    expect(tester.getTopLeft(box(Quadrant.delegate)).dx, lessThan(tester.getTopLeft(box(Quadrant.later)).dx));
    // The five ready-made lists are tabs; the + is there.
    for (final id in ['personal', 'work', 'school', 'shopping', 'home']) {
      expect(find.byKey(Key('list-tab-$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('list-add')), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('sekmeye dokunmak listeyi değiştirir; yalnız o listenin görevleri görünür', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kişisel iş');
    addTask(c, 'b', 'Rapor yaz', listId: 'work', q: Quadrant.doNow);
    c.selectList(TaskList.personalId);
    await pumpMatrix(tester, c);
    expect(card('a'), findsOneWidget);
    expect(card('b'), findsNothing);
    await tester.tap(find.byKey(const Key('list-tab-work')));
    await tester.pumpAndSettle();
    expect(c.currentListId, 'work');
    expect(card('a'), findsNothing);
    expect(find.descendant(of: box(Quadrant.doNow), matching: card('b')), findsOneWidget);
    // The open count beside the title.
    expect(find.descendant(of: box(Quadrant.doNow), matching: find.text('1')), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('karttaki onay kutusu görevi bitirir; "Biten (1)" bölümüne geçer', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Süt al', subtasks: const [SubTask(id: 's1', title: 'x', done: true), SubTask(id: 's2', title: 'y')]);
    await pumpMatrix(tester, c);
    expect(find.descendant(of: card('a'), matching: find.text('1/2')), findsOneWidget);
    expect(find.text('Biten (1)'), findsNothing);
    await tester.tap(find.descendant(of: card('a'), matching: find.byType(SoftCheck)));
    await tester.pumpAndSettle();
    expect(c.tasks.single.done, isTrue);
    expect(find.text('Biten (1)'), findsOneWidget);
    // Folded: the finished card shows once the section is opened.
    expect(card('a'), findsNothing);
    await tester.tap(find.byKey(const Key('box-finished-plan')));
    await tester.pumpAndSettle();
    expect(card('a'), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('kutunun "Ekle" düğmesi o liste ve kutuyla düzenleyici açar', (tester) async {
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    await tester.ensureVisible(find.byKey(const Key('list-tab-school')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('list-tab-school')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('box-add-delegate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ödevi gönder');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    final t = c.tasks.single;
    expect(t.title, 'Ödevi gönder');
    expect(t.listId, 'school');
    expect(t.quadrant, Quadrant.delegate);
    expect(find.descendant(of: box(Quadrant.delegate), matching: find.text('Ödevi gönder')), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('kartı başka kutuya sürüklemek kutuyu değiştirir', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Faturayı öde');
    await pumpMatrix(tester, c);
    await dragCard(tester, card('a'), tester.getCenter(box(Quadrant.doNow)));
    expect(c.tasks.single.quadrant, Quadrant.doNow);
    expect(find.descendant(of: box(Quadrant.doNow), matching: card('a')), findsOneWidget);
    // Not a short drag: no menu.
    expect(find.text('Başka listeye taşı…'), findsNothing);
    await shutdownMatrix(tester, c);
  });

  testWidgets('kartı kutu içinde yukarı sürüklemek sırayı değiştirir', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Birinci');
    addTask(c, 'b', 'İkinci');
    addTask(c, 'c', 'Üçüncü');
    await pumpMatrix(tester, c);
    expect(c.tasksIn('personal', Quadrant.plan).map((t) => t.id), ['a', 'b', 'c']);
    // Onto the upper half of the first card: before it.
    await dragCard(tester, card('c'), tester.getTopLeft(card('a')) + const Offset(40, 6));
    expect(c.tasksIn('personal', Quadrant.plan).map((t) => t.id), ['c', 'a', 'b']);
    // Onto the empty space below the cards: to the end.
    final plan = tester.getRect(box(Quadrant.plan));
    await dragCard(tester, card('c'), Offset(plan.center.dx, plan.bottom - 12));
    expect(c.tasksIn('personal', Quadrant.plan).map((t) => t.id), ['a', 'b', 'c']);
    await shutdownMatrix(tester, c);
  });

  testWidgets('uzun bas-bırak menüyü açar: Başka listeye taşı…, Bitti, Sil', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kargo');
    await pumpMatrix(tester, c);
    await tester.longPress(card('a'));
    await tester.pumpAndSettle();
    expect(find.text('Başka listeye taşı…'), findsOneWidget);
    expect(find.text('Bitti'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);
    expect(c.tasks.single.quadrant, Quadrant.plan);
    await tester.tap(find.text('Bitti'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.done, isTrue);
    await shutdownMatrix(tester, c);
  });

  testWidgets('Sil geri alınabilir; Başka listeye taşı görevi taşır ve snack gösterir', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kargo');
    addTask(c, 'b', 'Fatura');
    await pumpMatrix(tester, c);

    await tester.longPress(card('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(c.tasks.map((t) => t.id), ['b']);
    expect(card('a'), findsNothing);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(c.tasks.map((t) => t.id).toSet(), {'a', 'b'});
    expect(card('a'), findsOneWidget);

    await tester.longPress(card('b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başka listeye taşı…'));
    await tester.pumpAndSettle();
    // The current list is not offered.
    expect(find.byKey(const Key('move-to-personal')), findsNothing);
    await tester.tap(find.byKey(const Key('move-to-work')));
    await tester.pumpAndSettle();
    expect(c.tasks.firstWhere((t) => t.id == 'b').listId, 'work');
    expect(card('b'), findsNothing);
    expect(find.text('İş içine taşındı'), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('erişilebilirlik eylemi "Önemli · Acil kutusuna taşı" görevi taşır', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kargo');
    await pumpMatrix(tester, c);
    final node = tester.getSemantics(card('a'));
    final labels = [
      for (final id in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label,
    ];
    expect(labels, containsAll([
      'Önemli · Acil kutusuna taşı',
      'Acil · Önemsiz kutusuna taşı',
      'Sonra · Belki kutusuna taşı',
      'Başka listeye taşı…',
      'Sil',
    ]));
    expect(labels, isNot(contains('Önemli · Planlı kutusuna taşı')));
    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Önemli · Acil kutusuna taşı')),
    );
    await tester.pumpAndSettle();
    expect(c.tasks.single.quadrant, Quadrant.doNow);
    handle.dispose();
    await shutdownMatrix(tester, c);
  });

  testWidgets('RF: 20 liste ve 40 karakterlik ad: sekmeler kaydırılır, taşma yok', (tester) async {
    final c = await matrixController(tester);
    String? last;
    for (var i = 0; c.lists.length < 20; i++) {
      last = c.addList('${'Uzun liste adı ${i.toString().padLeft(2, '0')} '.padRight(39, 'x')}y').id;
    }
    expect(c.lists.last.name.length, 40);
    await pumpMatrix(tester, c);
    expect(tester.takeException(), isNull);
    final lastTab = find.byKey(Key('list-tab-$last'));
    // Off screen at first; scrolling the strip reaches it.
    expect(tester.getTopLeft(lastTab).dx, greaterThan(390));
    await tester.ensureVisible(lastTab);
    await tester.pumpAndSettle();
    await tester.tap(lastTab);
    await tester.pumpAndSettle();
    expect(c.currentListId, last);
    expect(tester.takeException(), isNull);
    await shutdownMatrix(tester, c);
  });

  testWidgets('metin ölçeği 2,0 ve 375 pt: tek sütun, taşma yok', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Uzun bir görev başlığı ki iki satıra sığmasın diye yazıldı', due: DateTime(2026, 11, 26, 14));
    addTask(c, 'b', 'Kısa', q: Quadrant.doNow);
    await pumpMatrix(tester, c, size: const Size(375, 812), textScale: 2);
    expect(tester.takeException(), isNull);
    final doNow = tester.getTopLeft(box(Quadrant.doNow));
    final plan = tester.getTopLeft(box(Quadrant.plan));
    expect(plan.dx, doNow.dx);
    expect(plan.dy, greaterThan(doNow.dy));
    await tester.scrollUntilVisible(box(Quadrant.later), 300, scrollable: find.descendant(of: find.byKey(const Key('matrix-scroll')), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await shutdownMatrix(tester, c);
  });

  testWidgets('yan çevrilmiş telefon (844×390): tek sütun, taşma yok', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kargo');
    await pumpMatrix(tester, c, size: const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('matrix-scroll')), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  testWidgets('400 görevli listede yalnız görünen kartlar kurulur', (tester) async {
    final c = await matrixController(tester);
    for (var i = 0; i < 400; i++) {
      addTask(c, 't$i', 'Görev $i', q: Quadrant.values[i % 4]);
    }
    await pumpMatrix(tester, c);
    expect(find.byType(MatrixCard).evaluate().length, lessThan(60));
    expect(find.text('100'), findsNWidgets(4));
    await shutdownMatrix(tester, c);
  });

  testWidgets('en çok altı BackdropFilter; Saydamlığı Azalt açıkken hiç yok', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Kargo');
    await pumpMatrix(tester, c);
    final n = find.byType(BackdropFilter).evaluate().length;
    expect(n, inInclusiveRange(1, 6));
    // Cards are flat colour, never glass.
    expect(find.descendant(of: card('a'), matching: find.byType(BackdropFilter)), findsNothing);
    SystemAccessibility.reduceTransparency.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    await shutdownMatrix(tester, c);
  });

  testWidgets('üç nokta > Alışkanlıklar HabitsPage açar', (tester) async {
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    await tester.tap(find.byKey(const Key('matrix-more')));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsOneWidget);
    await tester.tap(find.text('Alışkanlıklar'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsPage), findsOneWidget);
    expect(find.text('Yeni alışkanlık'), findsOneWidget);
    await shutdownMatrix(tester, c);
  });

  for (final (name, mode) in [('açık', ThemeMode.light), ('koyu', ThemeMode.dark)]) {
    testWidgets('her dokunma hedefi ≥ 44 pt; açık/koyu temada metin kontrastı ≥ 4,5: $name', (tester) async {
      final handle = tester.ensureSemantics();
      final c = await matrixController(tester);
      for (final q in Quadrant.values) {
        addTask(c, 'x${q.name}', 'Görev ${q.name}', q: q, due: DateTime(2026, 11, 26, 10),
            subtasks: const [SubTask(id: 's', title: 's')]);
      }
      addTask(c, 'done', 'Biten');
      c.toggleTask('done');
      await pumpMatrix(tester, c, theme: mode);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await shutdownMatrix(tester, c);
    });
  }
}
