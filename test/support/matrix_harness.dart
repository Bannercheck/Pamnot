import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/matrix/matrix_page.dart';

/// The fixed clock of the matrix tests.
final matrixNow = DateTime(2026, 11, 25, 9);

/// A controller with the five ready-made lists, Turkish, no sample data.
Future<AppController> matrixController(WidgetTester tester) async {
  final c = AppController(
    store: MemoryStore({
      'settings': jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson()),
    }),
    clock: () => matrixNow,
    saveDelay: Duration.zero,
  );
  await tester.runAsync(c.load);
  return c;
}

/// Adds a task to [listId]/[q] at the end of that box.
TaskItem addTask(AppController c, String id, String title,
    {String listId = TaskList.personalId, Quadrant q = Quadrant.plan, List<SubTask> subtasks = const [], DateTime? due}) {
  final t = c.draftTask(listId: listId, quadrant: q);
  final item = TaskItem(
    id: id,
    title: title,
    createdAt: t.createdAt,
    listId: t.listId,
    quadrant: t.quadrant,
    order: t.order,
    subtasks: subtasks,
    due: due,
  );
  c.upsertTask(item);
  return item;
}

/// Pumps [MatrixPage] alone (no shell) at [size].
Future<void> pumpMatrix(
  WidgetTester tester,
  AppController c, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeMode theme = ThemeMode.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    controller: c,
    child: MaterialApp(
      theme: PamnotTheme.light(),
      darkTheme: PamnotTheme.dark(),
      themeMode: theme,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const MatrixPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> shutdownMatrix(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  c.dispose();
}

/// Long-presses [from] (600 ms), drags to [to] and lets go.
Future<void> dragCard(WidgetTester tester, Finder from, Offset to) async {
  final g = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 600));
  final start = tester.getCenter(from);
  for (var i = 1; i <= 5; i++) {
    await g.moveTo(Offset.lerp(start, to, i / 5)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await tester.pumpAndSettle();
}
