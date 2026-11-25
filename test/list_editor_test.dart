import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/models/task_list.dart';

import 'support/matrix_harness.dart';

/// Making, editing and deleting lists from the Matrix tabs (Task 9).
void main() {
  setUpAll(() => initializeDateFormatting());

  Finder tab(String id) => find.byKey(Key('list-tab-$id'));
  Finder deleteButton() => find.byKey(const Key('list-delete'));

  testWidgets('+ yeni liste oluşturur ve seçer', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    await tester.ensureVisible(find.byKey(const Key('list-add')));
    await tester.tap(find.byKey(const Key('list-add')));
    await tester.pumpAndSettle();
    expect(find.text('Yeni liste'), findsWidgets);
    // A new list has nothing to delete.
    expect(deleteButton(), findsNothing);
    await tester.enterText(find.byType(TextField), 'Spor');
    await tester.tap(find.bySemanticsLabel('Dambıl'));
    await tester.tap(find.bySemanticsLabel('gül'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(c.lists, hasLength(6));
    final l = c.lists.last;
    expect((l.name, l.icon, l.colorIndex), ('Spor', 'fitness', 6));
    expect(c.currentListId, l.id);
    expect(tab(l.id), findsOneWidget);
    expect(find.descendant(of: tab(l.id), matching: find.byIcon(Icons.fitness_center_rounded)), findsOneWidget);
    handle.dispose();
    await shutdownMatrix(tester, c);
  });

  testWidgets('ad 40 karakterle sınırlı; boş adla Kaydet kapalı', (tester) async {
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    await tester.ensureVisible(find.byKey(const Key('list-add')));
    await tester.tap(find.byKey(const Key('list-add')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet')).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'x' * 50);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, hasLength(40));
    await shutdownMatrix(tester, c);
  });

  testWidgets('uzun basınca ad, renk ve simge değişir', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await matrixController(tester);
    await pumpMatrix(tester, c);
    await tester.longPress(tab('work'));
    await tester.pumpAndSettle();
    expect(find.text('Listeyi düzenle'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'İş');
    await tester.enterText(find.byType(TextField), 'Ofis');
    await tester.tap(find.bySemanticsLabel('nane'));
    await tester.tap(find.bySemanticsLabel('Yıldız'));
    await tester.pump();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    final l = c.listById('work');
    expect((l.name, l.colorIndex, l.icon), ('Ofis', 2, 'star'));
    expect(find.descendant(of: tab('work'), matching: find.text('Ofis')), findsOneWidget);
    handle.dispose();
    await shutdownMatrix(tester, c);
  });

  testWidgets('silme onayı görev sayısını ve hedef listeyi söyler; geri al listeyi ve görevlerini geri getirir',
      (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'a', 'Rapor', listId: 'work');
    addTask(c, 'b', 'Toplantı', listId: 'work', q: Quadrant.doNow);
    addTask(c, 'c', 'Sunum', listId: 'work', q: Quadrant.later);
    addTask(c, 'd', 'Kendi işim');
    await pumpMatrix(tester, c);
    await tester.longPress(tab('work'));
    await tester.pumpAndSettle();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.text('“İş” silinecek. İçindeki 3 görev “Kişisel” listesine taşınır.'), findsOneWidget);
    // Cancelling changes nothing.
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(c.lists, hasLength(5));
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sil')));
    await tester.pumpAndSettle();
    expect(c.lists.map((l) => l.id), isNot(contains('work')));
    expect(tab('work'), findsNothing);
    expect(c.tasks.where((t) => t.listId == 'personal'), hasLength(4));
    expect(find.text('Liste silindi'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(tab('work'), findsOneWidget);
    expect(c.tasks.where((t) => t.listId == 'work').map((t) => t.id).toSet(), {'a', 'b', 'c'});
    expect(c.tasks.firstWhere((t) => t.id == 'd').listId, 'personal');
    await shutdownMatrix(tester, c);
  });

  testWidgets('son listede sil düğmesi devre dışı ve not görünür', (tester) async {
    final c = await matrixController(tester);
    for (final id in ['work', 'school', 'shopping', 'home']) {
      c.deleteList(id);
    }
    await pumpMatrix(tester, c);
    await tester.longPress(tab('personal'));
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(deleteButton()).onPressed, isNull);
    expect(find.text('Listeyi sil'), findsOneWidget);
    expect(find.text('En az bir liste kalmalı.'), findsOneWidget);
    await shutdownMatrix(tester, c);
  });
}
