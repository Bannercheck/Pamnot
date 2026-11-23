import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/launch_actions.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/reminders/reminders_page.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';
import 'package:pamnot/ui/voice/voice_capture_page.dart';

import 'support/fake_speech_engine.dart';

/// The entry points of "Add by voice": pamnot:// links, the launch bridge's
/// requests and the microphone button in quick add (design §6.2, §6.7).
void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 10, 27, 9, 0);
  late AppController c;
  late FakeSpeechEngine engine;

  setUp(() {
    voiceRequests.value = false;
    notificationTaps.value = null;
  });

  tearDown(() {
    voiceRequests.value = false;
    notificationTaps.value = null;
  });

  /// The whole app on a phone, as in test/app_smoke_test.dart; [speech]
  /// defaults to a fresh [engine].
  Future<void> boot(
    WidgetTester tester, {
    SpeechEngine? speech,
    Size size = const Size(390, 844),
    AppSettings settings = const AppSettings(language: AppLanguage.tr),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('tr', 'TR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    engine = FakeSpeechEngine();
    c = AppController(
      store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
      clock: () => now,
      speech: speech ?? engine,
    );
    await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
  }

  /// Closes the voice screen if it is showing, then unmounts the app and
  /// lets its save and sync timers run out.
  Future<void> shutdown(WidgetTester tester) async {
    if (find.byType(VoiceCapturePage).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('voice-close')));
      await tester.pumpAndSettle();
    }
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(VoiceCapturePage.isOpen, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  /// The platform opens [location] in the app (deep link).
  Future<void> push(WidgetTester tester, String location) async {
    final msg = const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': location}));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', msg, (_) {});
    await tester.pumpAndSettle();
  }

  Finder inQuickAdd(Finder f) => find.descendant(of: find.byType(QuickAddField), matching: f);

  testWidgets('pamnot://ses ekranı açar; ikinci HomeShell eklenmez', (tester) async {
    await boot(tester);
    await push(tester, 'pamnot://ses');
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    // The screen is the one opened from HomeShell, and it listens.
    expect(VoiceCapturePage.isOpen, isTrue);
    expect(engine.listening, isTrue);
    await shutdown(tester);
  });

  testWidgets('pamnot://voice de açar; başka pamnot:// bağlantıları rota eklemez ve hata vermez', (tester) async {
    await boot(tester);
    await push(tester, 'pamnot://x?y=1');
    await push(tester, 'pamnot://today?homeWidget');
    expect(tester.takeException(), isNull);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    // Still on the Today tab, with nothing pushed over it.
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    expect(find.byType(QuickAddField), findsOneWidget);

    await push(tester, 'pamnot://voice');
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    await shutdown(tester);
  });

  testWidgets('bağlantıdaki metin görev yazmaz', (tester) async {
    await boot(tester);
    final tasks = c.tasks.length;
    final notes = c.notes.length;
    await push(tester, 'pamnot://ses?text=yar%C4%B1n%2010%20toplant%C4%B1');
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(c.tasks.length, tasks);
    expect(c.notes.length, notes);
    expect(c.tasks.where((t) => t.title.toLowerCase().contains('toplantı')), isEmpty);
    await shutdown(tester);
  });

  testWidgets('RF4: ekran açıkken gelen ikinci istek yok sayılır', (tester) async {
    await boot(tester);
    await push(tester, 'pamnot://ses');
    await push(tester, 'pamnot://ses');
    voiceRequests.value = true;
    await tester.pump();
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    // The open screen was not restarted: one permission check, one listen.
    await tester.pump(const Duration(seconds: 1));
    expect(engine.calls.where((call) => call.startsWith('prepare:')), hasLength(1));
    expect(engine.calls.where((call) => call.startsWith('start:')), hasLength(1));
    await shutdown(tester);
  });

  testWidgets('HomeShell kurulmadan önce gelen istek ilk kareden sonra açılır', (tester) async {
    // The shortcut was run before the app started.
    voiceRequests.value = true;
    await boot(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    await shutdown(tester);
  });

  testWidgets('mikrofon düğmesi yalnız motor destekliyorsa görünür ve ekranı açar', (tester) async {
    await boot(tester);
    final mic = inQuickAdd(find.byTooltip('Sesle görev ekle'));
    final send = inQuickAdd(find.byTooltip('Ekle'));
    expect(mic, findsOneWidget);
    expect(send, findsOneWidget);
    // Microphone first, then send; both tap targets (the whole IconButton,
    // not the 40 pt Material 3 visual inside it) at least 44×44 pt and 8 pt apart.
    Rect target(Finder tooltip) => tester.getRect(find.ancestor(of: tooltip, matching: find.byType(IconButton)));
    final micBox = target(mic);
    final sendBox = target(send);
    for (final box in [micBox, sendBox]) {
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
    }
    expect(sendBox.left - micBox.right, greaterThanOrEqualTo(8));

    await tester.tap(mic);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(voiceRequests.value, isFalse);
    // Nothing was typed, so nothing was added.
    expect(find.byType(SnackBar), findsNothing);
    await shutdown(tester);

    // The app's default engine on a platform without speech.
    await boot(tester, speech: UnsupportedSpeechEngine());
    expect(find.byTooltip('Sesle görev ekle'), findsNothing);
    expect(send, findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('mikrofon düğmesini göstermek motoru çağırmaz', (tester) async {
    await boot(tester);
    expect(inQuickAdd(find.byTooltip('Sesle görev ekle')), findsOneWidget);
    // The Tasks tab's own quick add shows one too; still no engine call.
    await tester.tap(find.text('Takip').last);
    await tester.pumpAndSettle();
    expect(inQuickAdd(find.byTooltip('Sesle görev ekle')), findsOneWidget);
    expect(engine.calls, isEmpty);
    await shutdown(tester);
  });

  testWidgets('mikrofon düğmesi büyük metinde ve dar ekranda taşmaz', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Without the sample notes, whose cards are not part of this change.
    await boot(
      tester,
      size: const Size(375, 812),
      settings: const AppSettings(language: AppLanguage.tr, seeded: true),
    );
    expect(tester.takeException(), isNull);
    expect(inQuickAdd(find.byTooltip('Sesle görev ekle')), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('yazarak hızlı ekleme değişmedi', (tester) async {
    await boot(tester);
    final before = c.tasks.map((t) => t.id).toSet();
    await tester.enterText(inQuickAdd(find.byType(TextField)), 'yarın 10:00 toplantı');
    await tester.tap(inQuickAdd(find.byTooltip('Ekle')));
    await tester.pump();
    final added = c.tasks.where((t) => !before.contains(t.id)).single;
    expect(added.title, 'Toplantı');
    expect(added.due, DateTime(2026, 10, 28, 10));
    expect(added.hasTime, isTrue);
    expect(added.remindAt, isNull);
    expect(find.text('✓ Toplantı · Yarın 10:00'), findsOneWidget);
    expect(tester.widget<TextField>(inQuickAdd(find.byType(TextField))).controller!.text, isEmpty);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(engine.calls, isEmpty);
    await shutdown(tester);
  });

  testWidgets('bildirim dokunuşu yolu değişmedi', (tester) async {
    await boot(tester);
    notificationTaps.value = 'r:x';
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);
    expect(find.byType(RemindersPage), findsOneWidget);
    expect(notificationTaps.value, isNull);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(voiceRequests.value, isFalse);
    await shutdown(tester);
  });
}
