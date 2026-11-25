import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/core/dates.dart';
import 'package:pamnot/core/motivation.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/common/glass_nav_bar.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/planner/planner_page.dart';
import 'package:pamnot/ui/settings/settings_page.dart';
import 'package:pamnot/ui/today/today_page.dart';

/// Daily motivation (design §K3): 120 gentle lines per language, no line
/// twice within 30 days, the next 7 days scheduled, a tap opens Today.
void main() {
  setUpAll(() => initializeDateFormatting());

  final trQuotes = parseQuotes(File('assets/quotes/tr.txt').readAsStringSync());
  final enQuotes = parseQuotes(File('assets/quotes/en.txt').readAsStringSync());

  // ------------------------------------------------------------- the files

  test('cümle dosyaları: 120 TR, 120 EN, 20–70 karakter, yinelenen yok, emoji yok', () {
    expect(trQuotes.length, 120);
    expect(enQuotes.length, 120);
    // Pictographs, dingbats, variation selectors and the joiner.
    final emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true);
    for (final q in [...trQuotes, ...enQuotes]) {
      final n = q.runes.length;
      expect(n, inInclusiveRange(20, 70), reason: q);
      expect(q.trim(), q, reason: 'kenar boşluğu: "$q"');
      expect(emoji.hasMatch(q), isFalse, reason: q);
      expect(q.contains('"') || q.contains('“') || q.contains('”'), isFalse, reason: 'alıntı yok: $q');
    }
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '').trim();
    expect(trQuotes.map(norm).toSet().length, 120);
    expect(enQuotes.map(norm).toSet().length, 120);
  });

  test('parseQuotes boş satırları ve # ile başlayanları atlar', () {
    expect(parseQuotes('# başlık\n\nBir\r\n  İki  \n#yorum\nÜç\n'), ['Bir', 'İki', 'Üç']);
  });

  // ------------------------------------------------------------ planQuotes

  final day0 = DateTime(2026, 11, 25);

  test('planQuotes belirlenimli; 7 gün için 7 farklı dizin', () {
    final a = planQuotes(day0, 7, const {}, 120);
    final b = planQuotes(day0, 7, const {}, 120);
    expect(a, b);
    expect(a.keys, [for (var i = 0; i < 7; i++) dayKey(addDays(day0, i))]);
    expect(a.values.toSet().length, 7);
    expect(a.values.every((i) => i >= 0 && i < 120), isTrue);
  });

  test('RF: 200 gün art arda planlandığında hiçbir dizin önceki 30 günde yok', () {
    // Once in one go, and once a day at a time the way the app does it.
    final once = planQuotes(day0, 200, const {}, 120);
    final rolling = <String, int>{};
    for (var d = 0; d < 200; d++) {
      rolling.addAll(planQuotes(addDays(day0, d), 7, rolling, 120));
    }
    for (final plan in [once, rolling]) {
      for (var d = 0; d < 200; d++) {
        final pick = plan[dayKey(addDays(day0, d))]!;
        for (var back = 1; back <= 30 && d - back >= 0; back++) {
          expect(plan[dayKey(addDays(day0, d - back))], isNot(pick), reason: 'gün $d, $back gün önce');
        }
      }
    }
    // The picks are spread: most lines come up within 200 days.
    expect(once.values.toSet().length, greaterThan(90));
  });

  test('geçmişteki seçim korunur (history\'deki gün yeniden seçilmez)', () {
    final history = {dayKey(day0): 42, dayKey(addDays(day0, 2)): 7, dayKey(addDays(day0, -3)): 11};
    final plan = planQuotes(day0, 7, history, 120);
    expect(plan[dayKey(day0)], 42);
    expect(plan[dayKey(addDays(day0, 2))], 7);
    expect(plan.containsKey(dayKey(addDays(day0, -3))), isFalse);
    // The new picks avoid what is already taken within 30 days.
    final fresh = [for (var i = 0; i < 7; i++) if (i != 0 && i != 2) plan[dayKey(addDays(day0, i))]!];
    expect(fresh.any({42, 7, 11}.contains), isFalse);
    expect(fresh.toSet().length, fresh.length);
  });

  // ------------------------------------------------------- the controller

  Future<(AppController, MemoryStore, NoopScheduler)> boot(
    DateTime now, {
    AppSettings settings = const AppSettings(language: AppLanguage.tr, seeded: true),
    Map<String, String> extra = const {},
    bool quotes = true,
  }) async {
    final store = MemoryStore({'settings': jsonEncode(settings.toJson()), ...extra});
    final scheduler = NoopScheduler();
    final c = AppController(store: store, scheduler: scheduler, clock: () => now, saveDelay: Duration.zero);
    await c.load();
    if (quotes) c.attachQuotes(tr: trQuotes, en: enQuotes);
    return (c, store, scheduler);
  }

  List<Alert> motivation(AppController c) => [for (final a in c.alerts()) if (a.key.startsWith('m:')) a];

  test('motivationAlerts: 09:00, anahtar m:2026-11-25 …; saat 10:00 ise bugün yok, yarından 7 gün', () async {
    final (c, _, _) = await boot(DateTime(2026, 11, 25, 8));
    final a = c.motivationAlerts();
    expect(a.map((e) => e.key), [for (var i = 0; i < 7; i++) 'm:${dayKey(addDays(day0, i))}']);
    expect(a.first.key, 'm:2026-11-25');
    expect(a.first.at, DateTime(2026, 11, 25, 9));
    expect(a.last.at, DateTime(2026, 12, 1, 9));
    expect(a.every((e) => e.title == 'Pamnot' && trQuotes.contains(e.body)), isTrue);
    expect(a.map((e) => e.body).toSet().length, 7);
    // alerts() carries them at the end.
    expect(c.alerts().reversed.take(7).toList().reversed.map((e) => e.key), a.map((e) => e.key));
    c.dispose();

    final (late, _, _) = await boot(DateTime(2026, 11, 25, 10));
    final b = late.motivationAlerts();
    expect(b.map((e) => e.key), [for (var i = 1; i <= 7; i++) 'm:${dayKey(addDays(day0, i))}']);
    late.dispose();

    final (custom, _, _) = await boot(
      DateTime(2026, 11, 25, 10),
      settings: const AppSettings(language: AppLanguage.tr, seeded: true, motivationMinutes: 21 * 60 + 15),
    );
    final m = custom.motivationAlerts();
    expect(m.first.key, 'm:2026-11-25');
    expect(m.first.at, DateTime(2026, 11, 25, 21, 15));
    custom.dispose();
  });

  test('ayar kapalıyken ya da cümleler yokken motivasyon uyarısı yok', () async {
    final (off, _, _) = await boot(
      DateTime(2026, 11, 25, 8),
      settings: const AppSettings(language: AppLanguage.tr, seeded: true, dailyMotivation: false),
    );
    expect(off.motivationAlerts(), isEmpty);
    expect(motivation(off), isEmpty);
    off.dispose();

    final (none, _, _) = await boot(DateTime(2026, 11, 25, 8), quotes: false);
    expect(none.motivationAlerts(), isEmpty);
    expect(motivation(none), isEmpty);
    none.dispose();
  });

  test('seçimler kaydedilir ve yeniden yüklemede aynı gün aynı cümle', () async {
    final (c, store, _) = await boot(DateTime(2026, 11, 25, 8));
    final first = c.motivationAlerts();
    await c.flush();
    final saved = (jsonDecode((await store.read('motivation'))!) as Map).cast<String, Object?>();
    expect(saved.keys, [for (var i = 0; i < 7; i++) dayKey(addDays(day0, i))]);
    expect(first.first.body, trQuotes[saved['2026-11-25']! as int]);
    c.dispose();

    // A saved pick wins over what the planner would choose now, and picks
    // older than 60 days are dropped.
    final (again, store2, _) = await boot(DateTime(2026, 11, 26, 8), extra: {
      'motivation': jsonEncode({'2026-11-26': 5, '2026-09-01': 9, '2026-10-20': 3}),
    });
    final a = again.motivationAlerts();
    expect(a.first.key, 'm:2026-11-26');
    expect(a.first.body, trQuotes[5]);
    await again.flush();
    final kept = (jsonDecode((await store2.read('motivation'))!) as Map).cast<String, Object?>();
    expect(kept['2026-11-26'], 5);
    expect(kept.containsKey('2026-09-01'), isFalse);
    expect(kept['2026-10-20'], 3);
    // Index 3 was used 37 days ago, so it may come back; nothing used in
    // the last 30 days does.
    expect(a.skip(1).map((e) => e.body), isNot(contains(trQuotes[5])));
    again.dispose();
  });

  test('dil İngilizce ise gövde EN dosyasından', () async {
    final (c, _, _) = await boot(
      DateTime(2026, 11, 25, 8),
      settings: const AppSettings(language: AppLanguage.en, seeded: true),
    );
    final a = c.motivationAlerts();
    expect(a, hasLength(7));
    expect(a.every((e) => enQuotes.contains(e.body)), isTrue);
    // The same day gets the matching line in both languages.
    c.updateSettings(c.settings.copyWith(language: AppLanguage.tr));
    final t = c.motivationAlerts();
    for (var i = 0; i < 7; i++) {
      expect(enQuotes.indexOf(a[i].body), trQuotes.indexOf(t[i].body));
    }
    c.dispose();
  });

  test('motivasyon izin istemez: scheduler.permissionRequests == 0', () async {
    final (c, _, scheduler) = await boot(DateTime(2026, 11, 25, 8));
    await c.syncAlerts();
    c.updateSettings(c.settings.copyWith(motivationMinutes: 600));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await c.syncAlerts();
    expect(scheduler.synced.last.where((a) => a.key.startsWith('m:')), hasLength(7));
    expect(scheduler.permissionRequests, 0);
    expect(c.settings.notificationsAsked, isFalse);
    c.dispose();
  });

  // --------------------------------------------------------------- screens

  testWidgets('Ayarlar: anahtar ve saat seçimi ayarı yazar; kapalıyken saat satırı gizli', (tester) async {
    // A device set to 24-hour time, as Turkish ones usually are.
    tester.platformDispatcher.alwaysUse24HourFormatTestValue = true;
    addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scheduler = NoopScheduler();
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson())}),
      scheduler: scheduler,
      clock: () => DateTime(2026, 11, 25, 8),
      saveDelay: Duration.zero,
    );
    await tester.runAsync(c.load);
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
    const s = S.tr;

    final toggle = find.widgetWithText(SwitchListTile, s.dailyMotivation);
    final time = find.widgetWithText(ListTile, s.motivationTime);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(find.text(s.dailyMotivationSub), findsOneWidget);
    expect(time, findsOneWidget);
    expect(find.descendant(of: time, matching: find.text('09:00')), findsOneWidget);

    // A different time through the picker's text entry.
    await tester.tap(time);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '21');
    await tester.pump();
    await tester.enterText(fields.at(1), '15');
    await tester.pump();
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    expect(c.settings.motivationMinutes, 21 * 60 + 15);
    expect(find.descendant(of: time, matching: find.text('21:15')), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.settings.dailyMotivation, isFalse);
    expect(find.widgetWithText(ListTile, s.motivationTime), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.settings.dailyMotivation, isTrue);
    expect(find.widgetWithText(ListTile, s.motivationTime), findsOneWidget);
    // Turning it on asks for nothing.
    expect(scheduler.permissionRequests, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets('m: bildirimi Bugün sekmesini açar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    notificationTaps.value = null;
    addTearDown(() => notificationTaps.value = null);
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())}),
      clock: () => DateTime(2026, 11, 25, 8),
    );
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    int selected() => tester.widget<GlassNavBar>(find.byType(GlassNavBar)).selectedIndex;

    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(selected(), 3);
    planSection.value = PlanSection.agenda;

    notificationTaps.value = 'm:2026-11-25';
    await tester.pumpAndSettle();
    expect(selected(), 0);
    expect(find.byType(TodayPage), findsOneWidget);
    expect(planSection.value, PlanSection.agenda);
    expect(notificationTaps.value, isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });
}
