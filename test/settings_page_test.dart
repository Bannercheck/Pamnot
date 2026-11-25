import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/core/spoken/spoken_task.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/ink.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/handwriting.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/guide/shortcut_guide_page.dart';
import 'package:pamnot/ui/settings/settings_page.dart';

import 'support/fake_speech_engine.dart';

/// A handwriting recogniser that works and already has both models.
class _ReadyInk implements HandwritingRecognizer {
  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelReady(String model) async => true;

  @override
  Future<bool> prepare(String model) async => true;

  @override
  Future<List<String>> recognize(List<InkStroke> strokes, {required String model, String preContext = ''}) async =>
      const [];
}

/// Remembers the bodies of the notifications it was asked to show.
class _RecordingScheduler extends NoopScheduler {
  final List<String> shown = [];

  @override
  Future<void> showNow(String title, String body) async => shown.add(body);
}

void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 11, 23, 9);
  const tr = S.tr;
  const base = AppSettings(language: AppLanguage.tr, seeded: true);

  late NoopScheduler scheduler;

  /// Every address the page asked to open outside the app.
  late List<Uri> opened;

  setUp(() {
    scheduler = NoopScheduler();
    opened = [];
    final original = openExternal;
    openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openExternal = original);
  });

  Future<AppController> pumpPage(
    WidgetTester tester, {
    SpeechEngine? speech,
    HandwritingRecognizer? handwriting,
    AppSettings settings = base,
    Size size = const Size(390, 844),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
      scheduler: scheduler,
      speech: speech,
      handwriting: handwriting,
      clock: () => now,
      saveDelay: Duration.zero,
    );
    await c.load();
    await tester.pumpWidget(AppScope(
      controller: c,
      child: MaterialApp(
        theme: theme ?? PamnotTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  /// Unmounts the page and lets the controller's save and sync timers run out.
  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder tileWith(String text) => find.widgetWithText(ListTile, text);

  // --------------------------------------------------------- Sesle ekleme

  testWidgets('Sesle ekleme grubu yalnız motor destekliyorsa görünür', (tester) async {
    var c = await pumpPage(tester);
    expect(find.text(tr.voiceSettings), findsNothing);
    expect(find.text(tr.voiceSetupReady), findsNothing);
    expect(find.text(tr.voiceKeepLog), findsNothing);
    await shutdown(tester, c);

    final off = FakeSpeechEngine(supported: false);
    c = await pumpPage(tester, speech: off);
    expect(find.text(tr.voiceSettings), findsNothing);
    expect(find.text(tr.voicePrivacyNote), findsNothing);
    await shutdown(tester, c);

    final on = FakeSpeechEngine();
    c = await pumpPage(tester, speech: on);
    expect(find.text(tr.voiceSettings), findsOneWidget);
    expect(find.text(tr.voiceSetupReady), findsOneWidget);
    // After the "Plan" group, before "Bildirimler".
    final voiceY = tester.getTopLeft(find.text(tr.voiceSettings)).dy;
    expect(voiceY, greaterThan(tester.getTopLeft(find.text(tr.weekStartsMonday)).dy));
    expect(voiceY, lessThan(tester.getTopLeft(find.text(tr.notifications)).dy));
    // Showing the group never touches the recogniser, so no permission prompt.
    expect([...off.calls, ...on.calls], isEmpty);
    await shutdown(tester, c);
  });

  testWidgets('kurulum yardımı: hazır satırı ve Siri ipucu var; Eylem düğmesi adımları ve "Yan tuş" yok',
      (tester) async {
    final c = await pumpPage(tester, speech: FakeSpeechEngine());
    expect(find.text(tr.voiceSetupReady), findsOneWidget);
    expect(find.descendant(of: tileWith(tr.voiceSetupReady), matching: find.byIcon(Icons.bolt_outlined)),
        findsOneWidget);
    expect(find.text(tr.voiceSiriHint), findsOneWidget);
    expect(find.textContaining('Yan tuş'), findsNothing);
    expect(find.textContaining('Ayarlar > Eylem'), findsNothing);
    // Back Tap and Voice Control moved into the "Shortcuts & Siri" guide page.
    expect(find.text(tr.voiceBackTapSteps), findsNothing);
    expect(find.text(tr.voiceVoiceControlSteps), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.descendant(of: tileWith(tr.guideTitle), matching: find.byIcon(Icons.chevron_right_rounded)),
        findsOneWidget);

    // Order: ready line, Siri hint, the guide link, log switch.
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y(tr.voiceSetupReady), lessThan(y(tr.voiceSiriHint)));
    expect(y(tr.voiceSiriHint), lessThan(y(tr.guideTitle)));
    expect(y(tr.guideTitle), lessThan(y(tr.voiceKeepLog)));

    await tapText(tester, tr.guideTitle);
    expect(find.byType(ShortcutGuidePage), findsOneWidget);
    expect(find.text(tr.voiceVoiceControlSteps), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('günlük anahtarı varsayılan kapalı; açınca Son tanınanlar; Temizle siler; kapatınca silinir',
      (tester) async {
    final c = await pumpPage(tester, speech: FakeSpeechEngine());
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, tr.voiceKeepLog)).value, isFalse);
    expect(find.text(tr.voiceKeepLogSub), findsOneWidget);
    expect(find.text('Son tanınanlar'), findsNothing);

    await tapText(tester, tr.voiceKeepLog);
    expect(c.settings.keepVoiceLog, isTrue);
    expect(find.text('Son tanınanlar'), findsOneWidget);
    expect(find.text('Henüz kayıt yok.'), findsOneWidget);
    // Nothing to clear yet.
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Temizle')).onPressed, isNull);

    c.logRecognized('yarın onda toplantı',
        SpokenTask(title: 'Toplantı', due: DateTime(2026, 11, 24, 10), hasTime: true),
        localeId: 'tr-TR');
    c.logRecognized('faturayı yarın öde', SpokenTask(title: 'Faturayı öde', due: DateTime(2026, 11, 24)),
        localeId: 'tr-TR');
    c.logRecognized('annemi ara', const SpokenTask(title: 'Annemi ara'), localeId: 'tr-TR');
    c.logRecognized('not al süt bitti', const SpokenTask(title: 'Süt bitti', isNote: true), localeId: 'tr-TR');
    await tester.pumpAndSettle();
    expect(find.text('Henüz kayıt yok.'), findsNothing);
    // The raw text, and under it what the parser made of it.
    expect(find.text('yarın onda toplantı'), findsOneWidget);
    expect(find.text('Toplantı · Yarın 10:00'), findsOneWidget);
    expect(find.text('Faturayı öde · Yarın'), findsOneWidget);
    expect(find.text('Annemi ara · ${tr.someday}'), findsOneWidget);
    expect(find.text('Süt bitti · ${tr.voiceNoteChip}'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Toplantı · Yarın 10:00')).dy,
        greaterThan(tester.getTopLeft(find.text('yarın onda toplantı')).dy));
    // Newest first.
    expect(tester.getTopLeft(find.text('not al süt bitti')).dy,
        lessThan(tester.getTopLeft(find.text('yarın onda toplantı')).dy));

    await tapText(tester, 'Temizle');
    expect(c.voiceLog, isEmpty);
    expect(find.text('yarın onda toplantı'), findsNothing);
    expect(find.text('Henüz kayıt yok.'), findsOneWidget);

    c.logRecognized('yarın onda toplantı',
        SpokenTask(title: 'Toplantı', due: DateTime(2026, 11, 24, 10), hasTime: true),
        localeId: 'tr-TR');
    await tester.pumpAndSettle();
    expect(find.text('yarın onda toplantı'), findsOneWidget);

    await tapText(tester, tr.voiceKeepLog);
    expect(c.settings.keepVoiceLog, isFalse);
    expect(c.voiceLog, isEmpty);
    expect(find.text('Son tanınanlar'), findsNothing);
    expect(find.text('yarın onda toplantı'), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('gizlilik notu görünür', (tester) async {
    final c = await pumpPage(tester, speech: FakeSpeechEngine());
    final note = find.text(tr.voicePrivacyNote);
    expect(note, findsOneWidget);
    final theme = Theme.of(tester.element(note));
    final style = tester.widget<Text>(note).style!;
    expect(style.color, theme.colorScheme.onSurfaceVariant);
    expect(style.fontSize, theme.textTheme.bodySmall!.fontSize);
    // The group's last line.
    expect(tester.getTopLeft(note).dy, greaterThan(tester.getTopLeft(find.text(tr.voiceKeepLog)).dy));
    expect(tester.getTopLeft(note).dy, lessThan(tester.getTopLeft(find.text(tr.notifications)).dy));
    await shutdown(tester, c);
  });

  // ---------------------------------------------------------- Bildirimler

  testWidgets('bildirim satırı: sorulmadı → izin ister', (tester) async {
    final c = await pumpPage(tester);
    expect(find.text('Bildirimlere izin ver'), findsOneWidget);
    expect(find.text(tr.notificationsOn), findsNothing);
    expect(find.text(tr.notificationsDenied), findsNothing);
    // Opening Settings asks nothing by itself.
    expect(scheduler.permissionRequests, 0);

    await tapText(tester, 'Bildirimlere izin ver');
    expect(scheduler.permissionRequests, 1);
    expect(c.settings.notificationsAsked, isTrue);
    expect(find.text('Bildirimler açık'), findsOneWidget);
    expect(find.text('Bildirimlere izin ver'), findsNothing);

    // Allowed: a check icon, and nothing happens on tap.
    expect(find.descendant(of: tileWith('Bildirimler açık'), matching: find.byIcon(Icons.check_circle_outline_rounded)),
        findsOneWidget);
    expect(tester.widget<ListTile>(tileWith('Bildirimler açık')).onTap, isNull);
    await tester.tap(find.text('Bildirimler açık'));
    await tester.pumpAndSettle();
    expect(scheduler.permissionRequests, 1);
    expect(opened, isEmpty);
    await shutdown(tester, c);
  });

  testWidgets('bildirim satırı: reddedildi → Ayarlar\'ı açar', (tester) async {
    final c = await pumpPage(tester, settings: base.copyWith(notificationsAsked: true));
    expect(scheduler.granted, isFalse);
    expect(find.text('Bildirimler kapalı — Ayarlar’ı aç'), findsOneWidget);
    expect(find.descendant(of: tileWith(tr.notificationsDenied), matching: find.byIcon(Icons.open_in_new_rounded)),
        findsOneWidget);

    await tapText(tester, tr.notificationsDenied);
    expect(opened.single.toString(), 'app-settings:');
    // The system prompt is not tried again.
    expect(scheduler.permissionRequests, 0);

    // The user allows notifications in Settings and comes back to the app.
    scheduler.granted = true;
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.text(tr.notificationsOn), findsOneWidget);
    expect(find.text(tr.notificationsDenied), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('bildirim satırı: izin zaten varsa açık görünür', (tester) async {
    scheduler.granted = true;
    final c = await pumpPage(tester);
    expect(find.text(tr.notificationsOn), findsOneWidget);
    expect(find.text(tr.notificationsAllow), findsNothing);
    expect(scheduler.permissionRequests, 0);
    await shutdown(tester, c);
  });

  testWidgets('deneme bildirimi izni app.requestNotifications ile ister', (tester) async {
    final recording = _RecordingScheduler();
    scheduler = recording;
    final c = await pumpPage(tester);
    await tapText(tester, tr.testNotification);
    expect(recording.permissionRequests, 1);
    // Asked through the controller, so the app remembers it asked.
    expect(c.settings.notificationsAsked, isTrue);
    expect(recording.shown, [tr.testNotificationBody]);
    // The status line follows.
    expect(find.text(tr.notificationsOn), findsOneWidget);
    await shutdown(tester, c);
  });

  // ------------------------------------------------------------- Hakkında

  testWidgets('Hakkında: gizlilik ve destek bağlantıları, lisans sayfası', (tester) async {
    final c = await pumpPage(tester);
    expect(find.text(tr.dataNote), findsOneWidget);
    // The decorative emoji is not read out.
    expect(find.ancestor(of: find.text('☁️'), matching: find.byType(ExcludeSemantics)), findsOneWidget);
    for (final label in ['Gizlilik Politikası', 'Destek']) {
      expect(find.descendant(of: tileWith(label), matching: find.byIcon(Icons.open_in_new_rounded)), findsOneWidget);
    }
    // Order: about line, data note, privacy, support, licences.
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y(tr.aboutText), lessThan(y(tr.dataNote)));
    expect(y(tr.dataNote), lessThan(y(tr.privacyPolicy)));
    expect(y(tr.privacyPolicy), lessThan(y(tr.support)));
    expect(y(tr.support), lessThan(y(tr.licenses)));

    await tapText(tester, 'Gizlilik Politikası');
    expect(opened.last.toString(), privacyPolicyUrl);
    await tapText(tester, 'Destek');
    expect(opened.last.toString(), supportUrl);
    expect(opened, hasLength(2));

    final licenses = find.text('Açık kaynak lisansları');
    await tester.ensureVisible(licenses);
    await tester.pumpAndSettle();
    await tester.tap(licenses);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(opened, hasLength(2));
    await shutdown(tester, c);
  });

  // ------------------------------------------------- Apple Pencil ve kalem

  testWidgets('el yazısı notu yalnız el yazısı destekleniyorsa', (tester) async {
    var c = await pumpPage(tester);
    expect(find.text(tr.handwritingPrivacyNote), findsNothing);
    await shutdown(tester, c);

    c = await pumpPage(tester, handwriting: _ReadyInk());
    final note = find.text(tr.handwritingPrivacyNote);
    expect(note, findsOneWidget);
    // Under the model rows, still inside the pencil group.
    expect(tester.getTopLeft(note).dy, greaterThan(tester.getTopLeft(find.byIcon(Icons.draw_outlined).last).dy));
    expect(tester.getTopLeft(note).dy, lessThan(tester.getTopLeft(find.text(tr.planner)).dy));
    final theme = Theme.of(tester.element(note));
    expect(tester.widget<Text>(note).style!.color, theme.colorScheme.onSurfaceVariant);
    await shutdown(tester, c);
  });

  // ------------------------------------------------------ Erişilebilirlik

  /// Everything the page can show at once: voice group with entries,
  /// handwriting models, the "denied" notification row.
  Future<AppController> pumpEverything(WidgetTester tester, {required Size size, ThemeData? theme}) async {
    final c = await pumpPage(
      tester,
      speech: FakeSpeechEngine(),
      handwriting: _ReadyInk(),
      settings: base.copyWith(keepVoiceLog: true, notificationsAsked: true),
      size: size,
      theme: theme,
    );
    c.logRecognized('yarın sabah onda doktora gitmeyi hatırlat',
        SpokenTask(title: 'Doktora git', due: DateTime(2026, 11, 24, 10), hasTime: true, remind: true),
        localeId: 'tr-TR');
    c.logRecognized('not al süt bitti', const SpokenTask(title: 'Süt bitti', isNote: true), localeId: 'tr-TR');
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('yönergeler: hedef boyutu, etiket, kontrast', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final theme in [PamnotTheme.light(), PamnotTheme.dark()]) {
      // Tall enough that every row is on screen at once.
      final c = await pumpEverything(tester, size: const Size(390, 4400), theme: theme);
      // The guidelines skip what is off screen, so the page must not scroll.
      expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, 0);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await shutdown(tester, c);
    }
    semantics.dispose();
  });

  testWidgets('metin ölçeği 2,0 ve 375×667: taşma yok', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = await pumpEverything(tester, size: const Size(375, 667));
    expect(MediaQuery.textScalerOf(tester.element(find.text(tr.voiceSettings))).scale(10), 20);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text(tr.licenses), 300);
    await tester.pumpAndSettle();
    expect(find.text(tr.licenses), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);
  });
}
