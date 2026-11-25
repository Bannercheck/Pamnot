import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/alarm_scheduler.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/reminders/reminder_editor.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';

/// Task 14: the "Alert type" choice and how alarms and notifications split
/// (design §7.1).
void main() {
  setUpAll(() => initializeDateFormatting());

  final now = DateTime(2026, 11, 25, 9);
  final s = S.tr;

  String settingsDoc() => jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson());

  Future<AppController> controller({
    required NoopAlarmScheduler alarms,
    NoopScheduler? scheduler,
    Map<String, String>? extra,
  }) async {
    final c = AppController(
      store: MemoryStore({'settings': settingsDoc(), ...?extra}),
      scheduler: scheduler ?? NoopScheduler(),
      alarms: alarms,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await c.load();
    return c;
  }

  Reminder reminder(String id, DateTime at, {Repeat repeat = Repeat.none, AlertKind kind = AlertKind.alarm}) =>
      Reminder(id: id, title: id, at: at, repeat: repeat, createdAt: now, alertKind: kind);

  TaskItem task(String id, DateTime? remindAt, {AlertKind kind = AlertKind.alarm, bool done = false}) =>
      TaskItem(id: id, title: id, createdAt: now, remindAt: remindAt, alertKind: kind, done: done);

  List<String> keys(List<Alert> l) => [for (final a in l) a.key]..sort();

  // ------------------------------------------------------------ controller

  test('RF4: yetkiliyken alarm öğesi yalnız alarms.sync\'e, diğerleri yalnız scheduler.sync\'e gider', () async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final scheduler = NoopScheduler();
    final c = await controller(alarms: alarms, scheduler: scheduler);
    expect(c.alarmAccess, AlarmAccess.authorized);
    expect(c.alarmSupported, isTrue);
    c.upsertReminder(reminder('ra', now.add(const Duration(hours: 2))));
    c.upsertReminder(reminder('rn', now.add(const Duration(hours: 3)), kind: AlertKind.notification));
    c.upsertTask(task('ta', now.add(const Duration(hours: 4))));
    c.upsertTask(task('tn', now.add(const Duration(hours: 5)), kind: AlertKind.notification));

    final alerts = c.alerts();
    expect(alerts.firstWhere((a) => a.key == 'r:ra').alarm, isTrue);
    expect(alerts.firstWhere((a) => a.key == 't:ta').alarm, isTrue);
    expect(alerts.firstWhere((a) => a.key == 'r:rn').alarm, isFalse);
    expect(alerts.firstWhere((a) => a.key == 't:tn').alarm, isFalse);

    await c.syncAlerts();
    expect(keys(alarms.synced.last), ['r:ra', 't:ta']);
    expect(keys(scheduler.synced.last), ['r:rn', 't:tn']);
    c.dispose();
  });

  test('RF4: yetki denied olunca aynı öğe bildirim olarak kurulur; alarms.sync([]) çağrılır', () async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final scheduler = NoopScheduler();
    final c = await controller(alarms: alarms, scheduler: scheduler);
    c.upsertReminder(reminder('ra', now.add(const Duration(hours: 2))));
    await c.syncAlerts();
    expect(keys(alarms.synced.last), ['r:ra']);

    // Turned off in the system Settings; the app learns it on resume.
    alarms.state = AlarmAccess.denied;
    await c.refreshAlarmAccess();
    expect(c.alarmAccess, AlarmAccess.denied);
    expect(c.alarmSupported, isTrue);
    await c.syncAlerts();
    expect(alarms.synced.last, isEmpty);
    expect(keys(scheduler.synced.last), ['r:ra']);
    c.dispose();
  });

  test('RF4: unsupported iken alarms.sync hiç çağrılmaz; alertKind alarm olan eski veri bildirim olur', () async {
    final alarms = NoopAlarmScheduler(); // unsupported
    final scheduler = NoopScheduler();
    final at = now.add(const Duration(hours: 2));
    final c = await controller(alarms: alarms, scheduler: scheduler, extra: {
      'reminders': jsonEncode({
        'v': 1,
        'items': [reminder('old', at).toJson()],
      }),
    });
    expect(c.reminders.single.alertKind, AlertKind.alarm);
    expect(c.alarmSupported, isFalse);
    await c.syncAlerts();
    expect(keys(scheduler.synced.last), ['r:old']);
    expect(alarms.synced, isEmpty);
    expect(alarms.requests, 0);
    expect(await c.ensureAlarmAccess(), isFalse);
    expect(alarms.requests, 0);
    c.dispose();
  });

  test('RF4: geçmişteki tek seferlik alarm hiçbir yere kurulmaz; yinelenen alarm kurulur', () async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final scheduler = NoopScheduler();
    final c = await controller(alarms: alarms, scheduler: scheduler);
    c.upsertReminder(reminder('past', DateTime(2026, 11, 20, 8)));
    c.upsertReminder(reminder('daily', DateTime(2026, 11, 1, 9), repeat: Repeat.daily));
    c.upsertReminder(reminder('weekly', DateTime(2026, 11, 2, 7, 30), repeat: Repeat.weekly)); // a Monday
    c.upsertReminder(reminder('monthly', DateTime(2026, 10, 3, 8), repeat: Repeat.monthly));
    c.upsertReminder(reminder('yearly', DateTime(2024, 2, 29, 8), repeat: Repeat.yearly));
    await c.syncAlerts();

    final byKey = {for (final a in alarms.synced.last) a.key: a};
    expect(byKey.keys.toSet(), {'r:daily', 'r:weekly', 'r:monthly', 'r:yearly'});
    expect(scheduler.synced.last, isEmpty);
    // The bridge gets the next occurrence, never one in the past.
    expect(byKey['r:daily']!.at, DateTime(2026, 11, 26, 9));
    expect(byKey['r:weekly']!.at, DateTime(2026, 11, 30, 7, 30));
    expect(byKey['r:monthly']!.at, DateTime(2026, 12, 3, 8));
    expect(byKey['r:yearly']!.at, DateTime(2028, 2, 29, 8));
    expect(byKey['r:monthly']!.repeat, Repeat.monthly);
    for (final a in byKey.values) {
      expect(a.at.isAfter(now), isTrue, reason: a.key);
    }
    c.dispose();
  });

  test('biten görevin alarmı listeden çıkar', () async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final c = await controller(alarms: alarms);
    c.upsertTask(task('t', now.add(const Duration(hours: 1))));
    await c.syncAlerts();
    expect(keys(alarms.synced.last), ['t:t']);
    c.toggleTask('t');
    await c.syncAlerts();
    expect(alarms.synced.last, isEmpty);
    c.dispose();
  });

  test('ensureAlarmAccess: notDetermined iken bir kez sorar; authorized iken sormadan true', () async {
    final alarms = NoopAlarmScheduler()
      ..state = AlarmAccess.notDetermined
      ..onRequest = AlarmAccess.authorized;
    final c = await controller(alarms: alarms);
    expect(alarms.requests, 0);
    expect(await c.ensureAlarmAccess(), isTrue);
    expect(alarms.requests, 1);
    expect(c.alarmAccess, AlarmAccess.authorized);
    expect(await c.ensureAlarmAccess(), isTrue);
    expect(alarms.requests, 1);
    c.dispose();
  });

  test('sync çağrıları üst üste binmez; bekleyen istek sonra en güncel listeyle çalışır', () async {
    final alarms = _GatedAlarms()..state = AlarmAccess.authorized;
    final c = await controller(alarms: alarms);
    c.upsertReminder(reminder('a', now.add(const Duration(hours: 1))));
    final first = c.syncAlerts();
    await Future<void>.delayed(Duration.zero);
    expect(alarms.inFlight, 1);
    c.upsertReminder(reminder('b', now.add(const Duration(hours: 2))));
    final second = c.syncAlerts();
    final third = c.syncAlerts();
    await Future<void>.delayed(Duration.zero);
    expect(alarms.inFlight, 1);
    expect(alarms.calls, 1);
    alarms.release();
    await Future.wait([first, second, third]);
    expect(alarms.maxInFlight, 1);
    // One more run for both waiting calls, with the newest list.
    expect(alarms.calls, 2);
    expect(keys(alarms.synced.last), ['r:a', 'r:b']);
    c.dispose();
  });

  // --------------------------------------------------------------- editors

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

  BuildContext host(WidgetTester tester) => tester.element(find.byType(Scaffold).first);

  Future<AppController> widgetController(WidgetTester tester, NoopAlarmScheduler alarms, NoopScheduler scheduler) async {
    final c = AppController(
      store: MemoryStore({'settings': settingsDoc()}),
      scheduler: scheduler,
      alarms: alarms,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await tester.runAsync(c.load);
    return c;
  }

  /// Scrolls the sheet's list until [f] is built, then into view.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      final scroll = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(scroll).position;
      while (f.evaluate().isEmpty && position.pixels < position.maxScrollExtent) {
        position.jumpTo(position.pixels + 100);
        await tester.pump();
      }
    }
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f.first);
    await tester.pumpAndSettle();
  }

  Finder kindButton() => find.byType(SegmentedButton<AlertKind>);
  AlertKind selectedKind(WidgetTester tester) => tester.widget<SegmentedButton<AlertKind>>(kindButton()).selected.single;
  Finder alarmSegment() => find.descendant(of: kindButton(), matching: find.text(s.alertAlarm));

  Future<void> close(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  testWidgets('hatırlatıcı düzenleyici: desteklenmiyorsa "Uyarı türü" yok', (tester) async {
    final c = await widgetController(tester, NoopAlarmScheduler(), NoopScheduler());
    await pumpHost(tester, c);
    showReminderEditor(host(tester), c, c.draftReminder(), isNew: true);
    await tester.pumpAndSettle();
    await reveal(tester, find.widgetWithText(FilledButton, s.save));
    expect(find.text(s.alertKind), findsNothing);
    expect(kindButton(), findsNothing);
    expect(find.text(s.alarmHint), findsNothing);
    await close(tester, c);
  });

  testWidgets('Alarm seçilince izin istenir; verilirse seçim kalır ve kaydedilir', (tester) async {
    final alarms = NoopAlarmScheduler()
      ..state = AlarmAccess.notDetermined
      ..onRequest = AlarmAccess.authorized;
    final scheduler = NoopScheduler();
    final c = await widgetController(tester, alarms, scheduler);
    await pumpHost(tester, c);
    final draft = c.draftReminder();
    showReminderEditor(host(tester), c, draft, isNew: true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'İlaç');

    await reveal(tester, kindButton());
    expect(find.text(s.alertKind), findsOneWidget);
    expect(find.text(s.alarmHint), findsOneWidget);
    expect(selectedKind(tester), AlertKind.notification);
    expect(alarms.requests, 0);

    await tapVisible(tester, alarmSegment());
    expect(alarms.requests, 1);
    expect(selectedKind(tester), AlertKind.alarm);
    expect(find.text(s.alarmDenied), findsNothing);

    await tapVisible(tester, find.widgetWithText(FilledButton, s.save));
    final saved = c.reminders.singleWhere((r) => r.id == draft.id);
    expect(saved.title, 'İlaç');
    expect(saved.alertKind, AlertKind.alarm);
    // The alarm does not need it, but its notification fallback (a revoked alarm permission)
    // does: saving asks once, the first time.
    expect(scheduler.permissionRequests, 1);
    expect(c.settings.notificationsAsked, isTrue);
    await close(tester, c);
  });

  testWidgets('görev düzenleyici: Alarm ile kaydetmek bildirim iznini bir kez ister (geri dönüş için)',
      (tester) async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final scheduler = NoopScheduler();
    final c = await widgetController(tester, alarms, scheduler);
    await pumpHost(tester, c);
    final t = task('alarmTask', now.add(const Duration(hours: 2)));
    c.upsertTask(t);
    showTaskEditor(host(tester), c, t);
    await tester.pumpAndSettle();
    expect(selectedKind(tester), AlertKind.alarm);
    await tapVisible(tester, find.widgetWithText(FilledButton, s.save));
    expect(find.byType(TaskEditor), findsNothing);
    expect(scheduler.permissionRequests, 1);

    // Asked once: a second save does not ask again.
    showTaskEditor(host(tester), c, c.tasks.singleWhere((x) => x.id == t.id));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, s.save));
    expect(scheduler.permissionRequests, 1);
    await close(tester, c);
  });

  testWidgets('izin reddedilirse Bildirim\'e döner ve açıklama gösterilir', (tester) async {
    final alarms = NoopAlarmScheduler()
      ..state = AlarmAccess.notDetermined
      ..onRequest = AlarmAccess.denied;
    final scheduler = NoopScheduler();
    final c = await widgetController(tester, alarms, scheduler);
    await pumpHost(tester, c);
    final draft = c.draftReminder();
    showReminderEditor(host(tester), c, draft, isNew: true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Toplantı');

    await tapVisible(tester, alarmSegment());
    expect(alarms.requests, 1);
    expect(selectedKind(tester), AlertKind.notification);
    expect(find.text(s.alarmDenied), findsWidgets);

    await tapVisible(tester, find.widgetWithText(FilledButton, s.save));
    expect(c.reminders.singleWhere((r) => r.id == draft.id).alertKind, AlertKind.notification);
    expect(scheduler.permissionRequests, 1);
    await close(tester, c);
  });

  testWidgets('görev düzenleyici: hatırlatma yokken "Uyarı türü" gizli; varken görünür', (tester) async {
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
    final c = await widgetController(tester, alarms, NoopScheduler());
    await pumpHost(tester, c);

    showTaskEditor(host(tester), c, task('a', null, kind: AlertKind.notification));
    await tester.pumpAndSettle();
    await reveal(tester, find.widgetWithText(FilledButton, s.save));
    expect(kindButton(), findsNothing);
    expect(find.text(s.alertKind), findsNothing);
    Navigator.of(tester.element(find.byType(TaskEditor))).pop();
    await tester.pumpAndSettle();

    showTaskEditor(host(tester), c, task('b', now.add(const Duration(hours: 1))));
    await tester.pumpAndSettle();
    await reveal(tester, kindButton());
    expect(find.text(s.alertKind), findsOneWidget);
    expect(find.text(s.alarmHint), findsOneWidget);
    expect(selectedKind(tester), AlertKind.alarm);
    // The choice sits under the reminder chip.
    expect(
      tester.getTopLeft(kindButton()).dy,
      greaterThan(tester.getTopLeft(find.byIcon(Icons.notifications_active_rounded)).dy),
    );
    await close(tester, c);
  });

  for (final locale in const [Locale('tr'), Locale('en')]) {
    testWidgets('Uyarı türü 375 pt genişlikte, metin ölçeği 2,0\'da taşmaz (${locale.languageCode})', (tester) async {
      final alarms = NoopAlarmScheduler()..state = AlarmAccess.authorized;
      final c = await widgetController(tester, alarms, NoopScheduler());
      await pumpHost(tester, c, size: const Size(375, 812), textScale: 2, locale: locale);
      showReminderEditor(host(tester), c, c.draftReminder().copyWith(alertKind: AlertKind.alarm), isNew: true);
      await tester.pumpAndSettle();
      await reveal(tester, kindButton());
      expect(tester.takeException(), isNull);
      final sheet = tester.getRect(find.byType(BottomSheet));
      final rect = tester.getRect(kindButton());
      expect(rect.left, greaterThanOrEqualTo(sheet.left));
      expect(rect.right, lessThanOrEqualTo(sheet.right));
      expect(rect.height, greaterThanOrEqualTo(44));
      await close(tester, c);
    });
  }

  testWidgets('ilk açılışta alarm izni istenmez (requests == 0)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final alarms = NoopAlarmScheduler()..state = AlarmAccess.notDetermined;
    final scheduler = NoopScheduler();
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())}),
      scheduler: scheduler,
      alarms: alarms,
      clock: () => now,
    );
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(alarms.requests, 0);
    expect(c.alarmAccess, AlarmAccess.notDetermined);
    await close(tester, c);
  });
}

/// Holds the first [sync] until [release]; counts overlapping calls.
class _GatedAlarms extends NoopAlarmScheduler {
  final _gate = Completer<void>();
  int inFlight = 0, maxInFlight = 0, calls = 0;

  void release() => _gate.complete();

  @override
  Future<void> sync(List<Alert> alarms) async {
    calls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await super.sync(alarms);
    await _gate.future;
    inFlight--;
  }
}
