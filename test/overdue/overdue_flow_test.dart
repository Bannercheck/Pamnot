import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/features/overdue/overdue_inbox.dart';
import 'package:pamnot/features/overdue/overdue_notice.dart';
import 'package:pamnot/features/overdue/overdue_page.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/settings/settings_page.dart';

/// The final notice's taps, sheets and setting, end to end on the shell.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting());
  const tr = S.tr;
  final now = DateTime(2026, 11, 27, 9);
  late NoopScheduler scheduler;
  late AppController c;

  setUp(() {
    notificationTaps.value = null;
    scheduler = NoopScheduler();
  });
  tearDown(() => notificationTaps.value = null);

  AppController controller({bool overdueNotice = true}) {
    final settings = AppSettings(language: AppLanguage.tr, seeded: true, overdueNotice: overdueNotice);
    return AppController(
      store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
      scheduler: scheduler,
      clock: () => now,
      alertProviders: const [overdueAlerts],
    );
  }

  TaskItem add(String title, DateTime due, {bool hasTime = true}) {
    final t = c.draftTask().copyWith(title: title, due: () => due, hasTime: hasTime);
    c.upsertTask(t);
    return c.tasks.firstWhere((x) => x.id == t.id);
  }

  TaskItem task(String id) => c.tasks.firstWhere((t) => t.id == id);

  Future<void> boot(WidgetTester tester, {Size size = const Size(390, 844), bool overdueNotice = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = controller(overdueNotice: overdueNotice);
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets(
      '"o:<id>" bildirimi erteleme ekranını açar; "Yarın" görevin vadesini yarına taşır ve Geri al eski vadeyi getirir',
      (tester) async {
    await boot(tester);
    final t = add('Faturayı öde', DateTime(2026, 11, 26, 14));
    notificationTaps.value = 'o:${t.id}';
    await tester.pumpAndSettle();
    expect(notificationTaps.value, isNull);
    expect(find.text(tr.snoozeTitle), findsOneWidget);
    expect(find.text('Faturayı öde'), findsWidgets);
    expect(find.text(tr.snoozeTonight), findsOneWidget);
    expect(find.text(tr.snoozeNextWeek), findsOneWidget);
    expect(find.text(tr.snoozePick), findsOneWidget);

    await tap(tester, find.text(tr.snoozeTomorrow));
    expect(find.text(tr.snoozeTitle), findsNothing);
    expect(task(t.id).due, DateTime(2026, 11, 28, 14));
    expect(task(t.id).hasTime, isTrue);
    expect(find.textContaining('ertelendi'), findsOneWidget);

    await tester.tap(find.text(tr.undo));
    await tester.pumpAndSettle();
    expect(task(t.id).due, DateTime(2026, 11, 26, 14));
    await shutdown(tester);
  });

  testWidgets('RF5: silinmiş görevin "o:<id>" bildirimi hiçbir ekran açmaz ve istisna atmaz', (tester) async {
    await boot(tester);
    final gone = add('Silinen', DateTime(2026, 11, 26, 14));
    final done = add('Biten', DateTime(2026, 11, 26, 14));
    c.deleteTask(gone.id);
    c.completeTask(done.id);
    for (final p in ['o:${gone.id}', 'o:${done.id}', 'o:', 'o:unknown']) {
      notificationTaps.value = p;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: p);
      expect(notificationTaps.value, isNull, reason: p);
      expect(find.byType(BottomSheet), findsNothing, reason: p);
      expect(find.byType(OverduePage), findsNothing, reason: p);
    }
    await shutdown(tester);
  });

  testWidgets('"o:sum:..." gecikenler listesini açar; Kapat görevi tamamlar ve satır kalkar', (tester) async {
    await boot(tester);
    final a = add('Eski görev', DateTime(2026, 11, 25, 10));
    add('Yeni görev', DateTime(2026, 11, 26), hasTime: false);
    add('Gelecek görev', DateTime(2026, 11, 28, 10));
    notificationTaps.value = 'o:sum:123';
    await tester.pumpAndSettle();
    expect(find.byType(OverduePage), findsOneWidget);
    expect(find.text(tr.overdueListTitle), findsOneWidget);
    expect(find.text('Eski görev'), findsOneWidget);
    expect(find.text('Yeni görev'), findsOneWidget);
    expect(find.text('Gelecek görev'), findsNothing);

    await tap(tester, find.byKey(Key('overdue-close-${a.id}')));
    expect(task(a.id).done, isTrue);
    expect(find.text('Eski görev'), findsNothing);
    expect(find.text(tr.taskClosed), findsOneWidget);
    await tester.tap(find.text(tr.undo));
    await tester.pumpAndSettle();
    expect(task(a.id).done, isFalse);
    expect(find.text('Eski görev'), findsOneWidget);

    // Ertele on a row opens the snooze sheet for that task.
    await tap(tester, find.byKey(Key('overdue-snooze-${a.id}')));
    expect(find.text(tr.snoozeTitle), findsOneWidget);
    await tap(tester, find.text(tr.snoozeNextWeek));
    expect(task(a.id).due, DateTime(2026, 12, 4, 10));
    expect(find.text('Eski görev'), findsNothing);
    await shutdown(tester);
  });

  testWidgets('gecikenler listesi boşken boş metni gösterir', (tester) async {
    await boot(tester);
    notificationTaps.value = 'o:sum:1';
    await tester.pumpAndSettle();
    expect(find.text(tr.overdueEmpty), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('erteleme ekranı ve gecikenler listesi: 375 pt ve metin ölçeği 2,0\'da taşma yok; düğmeler ≥ 44 pt ve etiketli',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handle = tester.ensureSemantics();
    await boot(tester, size: const Size(375, 667));
    final t = add('Çok uzun bir görev başlığı ki iki satıra rahatça taşsın', DateTime(2026, 11, 26, 14));
    add('İkinci geciken görev', DateTime(2026, 11, 25), hasTime: false);

    notificationTaps.value = 'o:sum:1';
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final k in ['overdue-close-${t.id}', 'overdue-snooze-${t.id}']) {
      final size = tester.getSize(find.byKey(Key(k)));
      expect(size.height, greaterThanOrEqualTo(44), reason: k);
      expect(size.width, greaterThanOrEqualTo(44), reason: k);
    }

    await tap(tester, find.byKey(Key('overdue-snooze-${t.id}')));
    expect(find.text(tr.snoozeTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    for (final label in [tr.snoozeTonight, tr.snoozeTomorrow, tr.snoozeNextWeek, tr.snoozePick]) {
      final f = find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
      expect(tester.getSize(f).height, greaterThanOrEqualTo(44), reason: label);
    }
    handle.dispose();
    await shutdown(tester);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        theme: PamnotTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder overdueSwitch() => find.widgetWithText(SwitchListTile, tr.overdueSetting);

  testWidgets('Ayarlar: son uyarı anahtarı kapanınca alerts() içinde "o:" anahtarı kalmaz', (tester) async {
    c = controller();
    await tester.runAsync(c.load);
    final t = add('Bugün', DateTime(2026, 11, 27, 14));
    expect(c.alerts().map((a) => a.key), contains('o:${t.id}'));
    await pumpSettings(tester);
    await tester.scrollUntilVisible(overdueSwitch(), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text(tr.overdueSettingHint), findsOneWidget);
    expect(tester.widget<SwitchListTile>(overdueSwitch()).value, isTrue);

    await tap(tester, overdueSwitch());
    expect(c.settings.overdueNotice, isFalse);
    expect(c.alerts().where((a) => a.key.startsWith('o:')), isEmpty);
    // Turning it off asks for nothing.
    expect(scheduler.permissionRequests, 0);
    await shutdown(tester);
  });

  testWidgets('ilk açılışta bildirim izni istenmez (requests == 0); anahtar açılırken notAsked ise bir kez istenir',
      (tester) async {
    await boot(tester);
    add('Dün', DateTime(2026, 11, 26, 14));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 0);
    await shutdown(tester);

    c = controller(overdueNotice: false);
    await tester.runAsync(c.load);
    await pumpSettings(tester);
    expect(scheduler.permissionRequests, 0);
    await tester.scrollUntilVisible(overdueSwitch(), 200, scrollable: find.byType(Scrollable).first);
    await tap(tester, overdueSwitch());
    expect(c.settings.overdueNotice, isTrue);
    expect(scheduler.permissionRequests, 1);

    // Asked once: off and on again does not ask a second time.
    await tap(tester, overdueSwitch());
    await tap(tester, overdueSwitch());
    expect(c.settings.overdueNotice, isTrue);
    expect(scheduler.permissionRequests, 1);
    await shutdown(tester);
  });

  group('ön plan yanıtı', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory dir;
    late ReceivePort port;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pamnot_overdue');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => dir.path);
      port = ReceivePort();
      IsolateNameServer.removePortNameMapping(OverdueInbox.portName);
      IsolateNameServer.registerPortWithName(port.sendPort, OverdueInbox.portName);
    });

    tearDown(() {
      IsolateNameServer.removePortNameMapping(OverdueInbox.portName);
      port.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });

    test('ön planda actionId "done" gelen yanıt görevi tamamlar', () async {
      c = controller();
      await c.load();
      final t = add('Kapanacak', DateTime(2026, 11, 26, 14));
      final taps = <String?>[];
      final s = LocalNotificationScheduler(onTap: taps.add);
      final pinged = port.first.timeout(const Duration(seconds: 5));

      await s.respond(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: 'done',
        payload: 'o:${t.id}',
      ));
      await pinged;
      expect(taps, isEmpty);
      expect(await applyOverdueInbox(c, OverdueInbox(KeyValueStore.platformDefault())), 1);
      expect(task(t.id).done, isTrue);

      // Snooze and a plain tap go to the tap handler with their payload.
      await s.respond(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: 'snooze',
        payload: 'o:${t.id}',
      ));
      await s.respond(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 't:x',
      ));
      expect(taps, ['o:${t.id}', 't:x']);
      c.dispose();
    });
  });

  test('RF5: choose: 70 gecikme uyarısı + 10 anımsatıcıdan en yakın 60\'ı seçer; geçmiş tek seferlikler girmez', () {
    final alerts = <Alert>[
      for (var i = 0; i < 70; i++)
        Alert(
          key: 'o:t$i',
          title: 'o$i',
          body: '',
          at: now.add(Duration(minutes: 30 + i * 60)),
          category: overdueCategory,
        ),
      for (var i = 0; i < 10; i++) Alert(key: 'r:r$i', title: 'r$i', body: '', at: now.add(Duration(hours: i * 7, minutes: 10))),
      // A one-time alert in the past never fires again.
      Alert(key: 'r:past', title: 'past', body: '', at: now.subtract(const Duration(minutes: 1))),
      // A daily one that started in the past fires tomorrow at 08:00.
      Alert(key: 'r:daily', title: 'daily', body: '', at: DateTime(2026, 11, 1, 8), repeat: Repeat.daily),
    ];
    final chosen = LocalNotificationScheduler.choose(alerts, now);
    expect(chosen, hasLength(60));
    final keys = chosen.map((e) => e.$1.key).toList();
    expect(keys, isNot(contains('r:past')));
    expect(keys, contains('r:daily'));
    expect(chosen.firstWhere((e) => e.$1.key == 'r:daily').$2, DateTime(2026, 11, 28, 8));
    for (var i = 1; i < chosen.length; i++) {
      expect(chosen[i].$2.isBefore(chosen[i - 1].$2), isFalse);
    }
    // Everything left out is no nearer than the last one chosen.
    final last = chosen.last.$2;
    final left = alerts.where((a) => !keys.contains(a.key) && a.key != 'r:past');
    expect(left, hasLength(80 + 1 - 60));
    for (final a in left) {
      expect(a.at.isBefore(last), isFalse, reason: a.key);
    }
    // The nearest reminders and notices are in.
    expect(keys, containsAll(['r:r0', 'o:t0', 'r:r1', 'o:t1']));
  });
}
