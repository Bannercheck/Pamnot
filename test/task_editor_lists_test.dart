import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/services/launch_actions.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/state/sample_data.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/glass_nav_bar.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/matrix/matrix_page.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';
import 'package:pamnot/ui/tasks/task_tile.dart';
import 'package:pamnot/ui/today/today_page.dart';

import 'support/fake_speech_engine.dart';
import 'support/matrix_harness.dart';

/// Task 10: the Matrix tab in the shell, list and box in the task editor,
/// the list dot on Today and quick add into the last used list.
void main() {
  setUpAll(() => initializeDateFormatting());

  setUp(() {
    voiceRequests.value = null;
    notificationTaps.value = null;
  });

  tearDown(() {
    voiceRequests.value = null;
    notificationTaps.value = null;
  });

  Finder listChip(String id) => find.byKey(Key('editor-list-$id'));
  Finder boxChip(Quadrant q) => find.byKey(Key('editor-box-${q.name}'));

  /// A bare app with a button-less host page; the editor is opened on it.
  Future<void> pumpHost(
    WidgetTester tester,
    AppController c, {
    Size size = const Size(390, 844),
    double textScale = 1,
    Locale locale = const Locale('tr'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        theme: PamnotTheme.light(),
        locale: locale,
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, AppController c, TaskItem task, {bool isNew = false}) async {
    showTaskEditor(tester.element(find.byType(Scaffold).first), c, task, isNew: isNew);
    await tester.pumpAndSettle();
  }

  /// Builds and scrolls [f] into view in the editor's lazily built list.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      final scroll = find.descendant(of: find.byType(TaskEditor), matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(scroll).position;
      // Down first; what is not below is above.
      while (f.evaluate().isEmpty && position.pixels < position.maxScrollExtent) {
        position.jumpTo(position.pixels + 100);
        await tester.pump();
      }
      while (f.evaluate().isEmpty && position.pixels > 0) {
        position.jumpTo(position.pixels - 100);
        await tester.pump();
      }
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  bool isSelected(WidgetTester tester, Finder f) {
    final data = tester.getSemantics(f).getSemanticsData();
    // Selectable either way, so a missing flag does not read as "not selected".
    expect(data.flagsCollection.isSelected, isNot(Tristate.none));
    return data.flagsCollection.isSelected == Tristate.isTrue;
  }

  Future<void> save(WidgetTester tester) => tapVisible(tester, find.widgetWithText(FilledButton, 'Kaydet'));

  testWidgets('düzenleyici listeyi ve kutuyu gösterir; değiştirip kaydetmek görevi taşır', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await matrixController(tester);
    addTask(c, 'b', 'Sunum', listId: 'work', q: Quadrant.doNow);
    final a = addTask(c, 'a', 'Rapor yaz');
    await pumpHost(tester, c);
    await openEditor(tester, c, a);

    expect(find.text('Liste'), findsOneWidget);
    expect(find.text('Kutu'), findsOneWidget);
    for (final l in c.lists) {
      expect(listChip(l.id), findsOneWidget, reason: l.id);
    }
    for (final q in Quadrant.values) {
      expect(boxChip(q), findsOneWidget, reason: q.name);
    }
    expect(find.descendant(of: boxChip(Quadrant.doNow), matching: find.text('Önemli · Acil')), findsOneWidget);
    expect(find.descendant(of: listChip('work'), matching: find.text('İş')), findsOneWidget);
    // List and box sit above the priority picker, which stays.
    expect(tester.getTopLeft(boxChip(Quadrant.later)).dy, lessThan(tester.getTopLeft(find.text('Öncelik')).dy));
    expect(find.byType(SegmentedButton<Priority>), findsOneWidget);

    expect(isSelected(tester, listChip(TaskList.personalId)), isTrue);
    expect(isSelected(tester, listChip('work')), isFalse);
    expect(isSelected(tester, boxChip(Quadrant.plan)), isTrue);
    expect(isSelected(tester, boxChip(Quadrant.doNow)), isFalse);

    await tapVisible(tester, listChip('work'));
    await tapVisible(tester, boxChip(Quadrant.doNow));
    expect(isSelected(tester, listChip('work')), isTrue);
    expect(isSelected(tester, listChip(TaskList.personalId)), isFalse);
    expect(isSelected(tester, boxChip(Quadrant.doNow)), isTrue);
    // The priority is independent of the box.
    expect(c.tasks.firstWhere((t) => t.id == 'a').priority, Priority.normal);
    await save(tester);

    final moved = c.tasks.firstWhere((t) => t.id == 'a');
    expect(moved.listId, 'work');
    expect(moved.quadrant, Quadrant.doNow);
    expect(moved.priority, Priority.normal);
    // At the end of its new box, after the task already there.
    expect(c.tasksIn('work', Quadrant.doNow).map((t) => t.id), ['b', 'a']);
    expect(c.tasksIn(TaskList.personalId, Quadrant.plan), isEmpty);
    handle.dispose();
    await shutdownMatrix(tester, c);
  });

  testWidgets('yeni görev: bugüne saat seçilince kutu Önemli · Acil olur; elle seçilen kutu korunur', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await matrixController(tester);
    await pumpHost(tester, c);
    await openEditor(tester, c, c.draftTask(), isNew: true);
    final ok = MaterialLocalizations.of(tester.element(find.byType(TaskEditor))).okButtonLabel;

    Future<void> pickTime() async {
      await tapVisible(tester, find.text('Saat'));
      await tester.tap(find.text(ok));
      await tester.pumpAndSettle();
    }

    expect(isSelected(tester, boxChip(Quadrant.plan)), isTrue);
    // A day without a time keeps "plan".
    await tapVisible(tester, find.text('Bugün'));
    expect(isSelected(tester, boxChip(Quadrant.plan)), isTrue);
    // Today at 09:00: "do now".
    await pickTime();
    expect(isSelected(tester, boxChip(Quadrant.doNow)), isTrue);
    // Tomorrow (still at 09:00): back to "plan".
    await tapVisible(tester, find.text('Yarın'));
    expect(isSelected(tester, boxChip(Quadrant.plan)), isTrue);

    // Once the user picks a box, date changes leave it alone.
    await tapVisible(tester, boxChip(Quadrant.later));
    await tapVisible(tester, find.text('Bugün'));
    expect(isSelected(tester, boxChip(Quadrant.later)), isTrue);
    expect(isSelected(tester, boxChip(Quadrant.doNow)), isFalse);

    final title = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Ne yapılacak?');
    await reveal(tester, title);
    await tester.enterText(title, 'Fatura öde');
    await save(tester);
    final t = c.tasks.single;
    expect(t.title, 'Fatura öde');
    expect(t.quadrant, Quadrant.later);
    expect(t.hasTime, isTrue);
    handle.dispose();
    await shutdownMatrix(tester, c);
  });

  testWidgets('Bugün: görev satırında liste rengi noktası ve liste adı etiketi', (tester) async {
    final c = await matrixController(tester);
    addTask(c, 'w', 'Sunum hazırla', listId: 'work', due: matrixNow);
    addTask(c, 'p', 'Süt al', due: matrixNow);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byType(TodayPage), findsOneWidget);

    // Both lists' tasks are on Today, each row with its list's dot.
    for (final (id, listId) in [('w', 'work'), ('p', TaskList.personalId)]) {
      final tile = find.byWidgetPredicate((w) => w is TaskTile && w.task.id == id);
      expect(tile, findsOneWidget, reason: id);
      expect(tester.widget<TaskTile>(tile).showList, isTrue);
      final list = c.listById(listId);
      final label = find.descendant(
        of: tile,
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == list.name),
      );
      expect(label, findsOneWidget, reason: id);
      final dot = find.descendant(of: label, matching: find.byKey(const Key('task-list-dot')));
      expect(tester.getSize(dot), const Size(8, 8));
      final deco = tester.widget<Container>(dot).decoration! as BoxDecoration;
      expect(deco.color, pastelAt(list.colorIndex).accent);
      expect(deco.shape, BoxShape.circle);
      // Left of the title.
      final title = find.descendant(of: tile, matching: find.text(id == 'w' ? 'Sunum hazırla' : 'Süt al'));
      expect(tester.getCenter(dot).dx, lessThan(tester.getTopLeft(title).dx));
    }

    // Elsewhere a tile shows no dot unless asked.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: TaskTile(app: c, task: c.tasks.first)),
      ),
    ));
    expect(find.byKey(const Key('task-list-dot')), findsNothing);
    await shutdownMatrix(tester, c);
  });

  testWidgets('kabuk: üçüncü sekme Matris, MatrixPage açılır; t: bildirimi Matris\'i açar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())}),
      clock: () => matrixNow,
      speech: FakeSpeechEngine(),
    );
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    int selected() => tester.widget<GlassNavBar>(find.byType(GlassNavBar)).selectedIndex;

    final nav = find.byKey(const Key('nav-2'));
    expect(find.descendant(of: nav, matching: find.text('Matris')), findsOneWidget);
    expect(find.descendant(of: nav, matching: find.byIcon(Icons.grid_view_outlined)), findsOneWidget);
    expect(find.byType(MatrixPage), findsNothing);
    await tester.tap(nav);
    await tester.pumpAndSettle();
    expect(selected(), 2);
    expect(find.byType(MatrixPage), findsOneWidget);
    expect(find.descendant(of: nav, matching: find.byIcon(Icons.grid_view_rounded)), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-0')));
    await tester.pumpAndSettle();
    expect(selected(), 0);
    notificationTaps.value = 't:x';
    await tester.pumpAndSettle();
    expect(selected(), 2);
    expect(find.byType(MatrixPage), findsOneWidget);
    expect(notificationTaps.value, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets('yazarak hızlı ekleme: "yarın 10:00 toplantı" son kullanılan listeye, plan kutusuna', (tester) async {
    final c = await matrixController(tester);
    c.selectList('school');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();

    final quick = find.descendant(of: find.byType(TodayPage), matching: find.byType(QuickAddField));
    expect(quick, findsOneWidget);
    await tester.enterText(find.descendant(of: quick, matching: find.byType(TextField)), 'yarın 10:00 toplantı');
    await tester.tap(find.descendant(of: quick, matching: find.byTooltip('Ekle')));
    await tester.pump();
    final t = c.tasks.single;
    expect(t.title.toLowerCase(), 'toplantı');
    expect(t.listId, 'school');
    expect(t.quadrant, Quadrant.plan);
    expect(t.hasTime, isTrue);
    expect(t.due, DateTime(2026, 11, 26, 10));
    await tester.pumpAndSettle();
    await shutdownMatrix(tester, c);
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    testWidgets('düzenleyici metin ölçeği 2,0 ve 375 pt\'de taşmaz (${locale.languageCode})', (tester) async {
      final c = await matrixController(tester);
      final a = addTask(c, 'a', 'Haftalık raporu hazırla ve gönder', due: matrixNow);
      await pumpHost(tester, c, size: const Size(375, 812), textScale: 2, locale: locale);
      await openEditor(tester, c, a);
      expect(tester.takeException(), isNull);
      for (final q in Quadrant.values) {
        await reveal(tester, boxChip(q));
        expect(tester.takeException(), isNull, reason: q.name);
        expect(tester.getRect(boxChip(q)).right, lessThanOrEqualTo(375));
        expect(tester.getSize(boxChip(q)).height, greaterThanOrEqualTo(44));
      }
      final last = c.lists.last.id;
      await reveal(tester, listChip(last));
      expect(tester.takeException(), isNull);
      await tester.tap(listChip(last));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await shutdownMatrix(tester, c);
    });
  }

  test('karşılama notu Matris sekmesini anar', () {
    final tr = SampleData.build(S.tr, DateTime(2026), () => 'id').notes.single.body;
    final en = SampleData.build(S.en, DateTime(2026), () => 'id').notes.single.body;
    expect(tr, contains('Matris sekmesi'));
    expect(tr, isNot(contains('Takip')));
    expect(en, contains('the Matrix tab'));
    expect(en, isNot(contains('Track')));
  });
}
