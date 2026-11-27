import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/features.dart';
import 'package:pamnot/features/sharing/task_policy.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';

/// v3 milestone K1 foundation: assignment fields, the overdue-notice
/// setting and strings, and the [Features] scope.
void main() {
  setUpAll(() => initializeDateFormatting());
  final created = DateTime(2026, 11, 27, 9);

  TaskItem roundTrip(TaskItem t) =>
      TaskItem.fromJson((jsonDecode(jsonEncode(t.toJson())) as Map).cast<String, Object?>());

  test('TaskItem atama alanları JSON gidiş dönüşünde korunur; null olan yazılmaz', () {
    final t = TaskItem(
      id: 'a',
      title: 'Rapor',
      createdAt: created,
      assigneeId: 'u2',
      assignedBy: 'u1',
      createdBy: 'u1',
      completedBy: 'u2',
    );
    final back = roundTrip(t);
    expect(back.assigneeId, 'u2');
    expect(back.assignedBy, 'u1');
    expect(back.createdBy, 'u1');
    expect(back.completedBy, 'u2');

    final plain = TaskItem(id: 'b', title: 'x', createdAt: created).toJson();
    for (final k in ['assigneeId', 'assignedBy', 'createdBy', 'completedBy', 'reopenedAt']) {
      expect(plain.containsKey(k), isFalse, reason: k);
    }
  });

  test('eski görev JSON\'u (atama alanı yok) okunur; dört alan null', () {
    final t = TaskItem.fromJson({
      'id': 'old',
      'title': 'Eski',
      'done': false,
      'priority': 'normal',
      'hasTime': false,
      'createdAt': created.toIso8601String(),
    });
    expect(t.assigneeId, isNull);
    expect(t.assignedBy, isNull);
    expect(t.createdBy, isNull);
    expect(t.completedBy, isNull);
  });

  test('copyWith(assigneeId: () => null) atamayı kaldırır', () {
    final t = TaskItem(id: 'a', title: 'x', createdAt: created, assigneeId: 'u2', assignedBy: 'u1');
    final cleared = t.copyWith(assigneeId: () => null);
    expect(cleared.assigneeId, isNull);
    expect(cleared.assignedBy, 'u1');
    expect(t.copyWith(title: 'y').assigneeId, 'u2');
    expect(t.copyWith(completedBy: () => 'u3').completedBy, 'u3');
  });

  test('reopenedAt JSON gidiş dönüşünde korunur; eski veride null', () {
    final at = DateTime(2026, 11, 27, 15, 30);
    final t = TaskItem(id: 'a', title: 'x', createdAt: created, reopenedAt: at);
    expect(roundTrip(t).reopenedAt, at);
    expect(t.toJson()['reopenedAt'], at.toIso8601String());
    expect(roundTrip(TaskItem(id: 'b', title: 'x', createdAt: created)).reopenedAt, isNull);
    expect(t.copyWith(reopenedAt: () => null).reopenedAt, isNull);
  });

  test('AppSettings.overdueNotice varsayılan true; false gidiş dönüşte korunur', () {
    expect(const AppSettings().overdueNotice, isTrue);
    expect(AppSettings.fromJson(const {}).overdueNotice, isTrue);
    final off = const AppSettings().copyWith(overdueNotice: false);
    expect(off.toJson()['overdueNotice'], isFalse);
    expect(AppSettings.fromJson(off.toJson()).overdueNotice, isFalse);
  });

  test('Alert.category fingerprint\'i değiştirir', () {
    final at = DateTime(2026, 11, 27, 10);
    final plain = Alert(key: 't:a', title: 'T', body: 'B', at: at);
    final overdue = Alert(key: 't:a', title: 'T', body: 'B', at: at, category: 'overdue');
    expect(plain.category, isNull);
    expect(overdue.category, 'overdue');
    expect(overdue.fingerprint, isNot(plain.fingerprint));
  });

  test('LocalTaskPolicy: me boş, alertsHere true', () {
    const TaskPolicy p = LocalTaskPolicy();
    expect(p.me, '');
    expect(p.alertsHere(TaskItem(id: 'a', title: 'x', createdAt: created, assigneeId: 'someone')), isTrue);
  });

  test('K1 metinleri TR ve EN\'de boş değil ve birbirinden farklı', () {
    List<String> k1(S s) => [
          s.overdueTitle('Rapor'),
          s.overdueBody,
          s.overdueSummary(6),
          s.overdueClose,
          s.overdueSnooze,
          s.overdueSetting,
          s.overdueSettingHint,
          s.snoozeTitle,
          s.snoozeTonight,
          s.snoozeTomorrow,
          s.snoozeNextWeek,
          s.snoozePick,
          s.snoozed('28 Kas 09:00'),
          s.overdueListTitle,
          s.overdueEmpty,
          s.taskClosed,
        ];
    final tr = k1(S.tr), en = k1(S.en);
    for (var i = 0; i < tr.length; i++) {
      expect(tr[i].trim(), isNotEmpty, reason: 'tr #$i');
      expect(en[i].trim(), isNotEmpty, reason: 'en #$i');
      expect(tr[i], isNot(en[i]), reason: '#$i');
    }
    expect(S.tr.overdueTitle('Rapor'), 'Zamanı geçti: Rapor');
    expect(S.en.overdueSummary(6), '6 tasks are overdue');
  });

  AppController controller() => AppController(
        store: MemoryStore({
          'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson()),
        }),
        clock: () => created,
      );

  testWidgets('Features.of: kapsam yokken aynı denetleyici için hep aynı Features döner', (tester) async {
    final c = controller();
    final seen = <Features>[];
    Widget probe() => AppScope(
          controller: c,
          child: Builder(builder: (context) {
            seen.add(Features.of(context));
            return const SizedBox();
          }),
        );
    await tester.pumpWidget(probe());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(probe());
    expect(seen, hasLength(2));
    expect(identical(seen[0], seen[1]), isTrue);
    expect(seen[0].app, same(c));

    final other = controller();
    late Features third;
    await tester.pumpWidget(AppScope(
      controller: other,
      child: Builder(builder: (context) {
        third = Features.of(context);
        return const SizedBox();
      }),
    ));
    expect(identical(third, seen[0]), isFalse);
    expect(third.app, same(other));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    other.dispose();
  });

  testWidgets('PamnotApp features verilmezse FeaturesScope yine vardır', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = controller();
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    final scope = tester.widget<FeaturesScope>(find.byType(FeaturesScope));
    expect(scope.features.app, same(c));

    final given = Features.local(c);
    await tester.pumpWidget(PamnotApp(controller: c, features: given));
    await tester.pumpAndSettle();
    expect(tester.widget<FeaturesScope>(find.byType(FeaturesScope)).features, same(given));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  });
}
