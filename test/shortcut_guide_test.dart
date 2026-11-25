import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/launch_actions.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/services/pip_player.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/guide/phone_hand_animation.dart';
import 'package:pamnot/ui/guide/shortcut_guide_page.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/settings/settings_page.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';
import 'package:pamnot/ui/today/today_page.dart';
import 'package:pamnot/ui/voice/voice_capture_controller.dart';
import 'package:pamnot/ui/voice/voice_capture_page.dart';

import 'support/fake_speech_engine.dart';

/// A Picture in Picture player that writes every call to [log], the same
/// list the fake [openExternal] writes to, so the order is visible.
class _FakePip implements PipPlayer {
  _FakePip(this.log, {this.gate});

  final List<String> log;

  /// When set, prepare logs 'prepared' only once this completes (a slow load).
  final Completer<void>? gate;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> prepare(String assetPath) async {
    log.add('prepare $assetPath');
    if (gate != null) {
      await gate!.future;
      log.add('prepared');
    }
  }

  @override
  Future<bool> start() async {
    log.add('start');
    return true;
  }

  @override
  Future<void> stop() async => log.add('stop');
}

void main() {
  setUpAll(() => initializeDateFormatting());
  const tr = S.tr;
  final now = DateTime(2026, 11, 25, 9);
  const base = AppSettings(language: AppLanguage.tr, seeded: true);

  /// What the page opened outside the app (`open <uri>`) and the pip calls.
  late List<String> log;

  setUp(() {
    log = [];
    shortcutRuns.value = 0;
    voiceRequests.value = null;
    notificationTaps.value = null;
    final original = openExternal;
    openExternal = (uri) async {
      log.add('open $uri');
      return true;
    };
    addTearDown(() => openExternal = original);
  });

  tearDown(() {
    shortcutRuns.value = 0;
    voiceRequests.value = null;
    notificationTaps.value = null;
  });

  Future<AppController> boot(
    WidgetTester tester, {
    PipPlayer? pip,
    SpeechEngine? speech,
    AppSettings settings = base,
    Size size = const Size(390, 844),
    bool load = true,
    AppController? controller,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = controller ??
        AppController(
          store: MemoryStore({'settings': jsonEncode(settings.toJson())}),
          clock: () => now,
          speech: speech ?? FakeSpeechEngine(),
          pip: pip,
          saveDelay: Duration.zero,
        );
    if (controller == null) await tester.runAsync(c.load);
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  /// Lets frames run without waiting for the looping animation to stop.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openGuide(WidgetTester tester) async {
    unawaited(ShortcutGuidePage.open(tester.element(find.byType(TodayPage))));
    await settle(tester);
    expect(find.byType(ShortcutGuidePage), findsOneWidget);
  }

  Finder header(String step) => find.byKey(Key('guide-step-$step'));

  Future<void> expand(WidgetTester tester, String step) async {
    await tester.ensureVisible(header(step));
    await settle(tester);
    await tester.tap(header(step));
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await settle(tester);
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    if (find.byType(VoiceCapturePage).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('voice-close')));
      await settle(tester);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  Finder inHeader(String step, Finder f) => find.descendant(of: header(step), matching: f);

  testWidgets('dört adım kartı "Yapılacak" rozetiyle; kart açılınca numaralı adımlar ve düğmeler', (tester) async {
    final c = await boot(tester);
    await openGuide(tester);
    expect(find.text(tr.guideTitle), findsOneWidget);
    for (final step in AppSettings.guideSteps) {
      expect(header(step), findsOneWidget);
      expect(inHeader(step, find.text(tr.guideStepTitle(step))), findsOneWidget);
      expect(inHeader(step, find.text(tr.guideTodo)), findsOneWidget);
      expect(inHeader(step, find.byIcon(Icons.radio_button_unchecked)), findsOneWidget);
    }
    // Closed: no lines, no animation.
    expect(find.text(tr.guideStepLines('actionButton').first), findsNothing);
    expect(find.byType(PhoneHandAnimation), findsNothing);

    await expand(tester, 'actionButton');
    final lines = tr.guideStepLines('actionButton');
    for (var i = 0; i < lines.length; i++) {
      expect(find.text(lines[i]), findsOneWidget);
      expect(find.text('${i + 1}.'), findsOneWidget);
    }
    expect(find.byType(PhoneHandAnimation), findsOneWidget);
    expect(tester.getSize(find.byType(PhoneHandAnimation)).height, 160);
    expect(find.byKey(const Key('guide-open-settings-actionButton')), findsOneWidget);
    expect(find.byKey(const Key('guide-mark-actionButton')), findsOneWidget);
    expect(find.text(tr.guideOpenSettings), findsOneWidget);
    expect(find.text(tr.guideMarkDone), findsOneWidget);

    // The shortcut step: Run shortcut, no manual mark.
    await expand(tester, 'shortcut');
    expect(find.byKey(const Key('guide-run-shortcut')), findsOneWidget);
    expect(find.byKey(const Key('guide-mark-shortcut')), findsNothing);
    expect(find.byKey(const Key('guide-open-settings-shortcut')), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('"Kısayolu çalıştır" shortcuts://run-shortcut?name=… açar (openExternal sahtesi)', (tester) async {
    final c = await boot(tester);
    await openGuide(tester);
    await expand(tester, 'shortcut');
    await tapKey(tester, 'guide-run-shortcut');
    expect(log, ['open ${runShortcutUri()}']);
    expect(log.single, startsWith('open shortcuts://run-shortcut?name='));
    // Running it is not proof: only the shortcut opening Pamnot marks it.
    expect(c.guideStepDone('shortcut'), isFalse);
    await shutdown(tester, c);
  });

  testWidgets('bağlantı boşken "Kısayolu ekle" yok ve ilk satır elle kurulumu anlatır', (tester) async {
    expect(voiceShortcutShareUrl, isEmpty);
    final c = await boot(tester);
    await openGuide(tester);
    await expand(tester, 'shortcut');
    expect(find.byKey(const Key('guide-add-shortcut')), findsNothing);
    expect(find.text(tr.guideAddShortcut), findsNothing);
    final lines = tr.guideStepLines('shortcut');
    expect(lines.first, tr.guideStepLines('shortcut', hasShareLink: false).first);
    expect(lines.first, contains('+'));
    // Every line in order, the manual one first.
    final ys = [for (final l in lines) tester.getTopLeft(find.text(l)).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }
    expect(find.text('1.'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('shortcutRuns artınca "Sesli görev kestirmesi" adımı Tamam olur; mikrofon düğmesi yapmaz',
      (tester) async {
    // The bridge: 'voice' (the App Intent) counts, a link does not.
    const channel = MethodChannel('app.pamnot/launch');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? pending;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final a = pending;
      pending = null;
      return a;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    pending = 'voice-link';
    await LaunchActionsBridge.pull();
    expect(shortcutRuns.value, 0);
    pending = 'voice';
    await LaunchActionsBridge.pull();
    expect(shortcutRuns.value, 1);
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    shortcutRuns.value = 0;
    voiceRequests.value = null;

    final c = await boot(tester);
    // The microphone button opens the voice screen but is not the shortcut.
    await tester.tap(find.byTooltip(tr.voiceMicTooltip).first);
    await settle(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-close')));
    await settle(tester);
    expect(shortcutRuns.value, 0);
    expect(c.guideStepDone('shortcut'), isFalse);

    await openGuide(tester);
    expect(inHeader('shortcut', find.text(tr.guideTodo)), findsOneWidget);
    shortcutRuns.value++;
    await settle(tester);
    expect(c.guideStepDone('shortcut'), isTrue);
    expect(inHeader('shortcut', find.text(tr.guideDoneBadge)), findsOneWidget);
    expect(inHeader('shortcut', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('"Ayarlar\'ı aç": önce pip.start, sonra app-settings: ; PiP desteklenmiyorsa yalnız Ayarlar',
      (tester) async {
    var c = await boot(tester, pip: _FakePip(log));
    await openGuide(tester);
    await expand(tester, 'backTap');
    expect(find.text(tr.guidePipHint), findsOneWidget);
    log.clear();
    await tapKey(tester, 'guide-open-settings-backTap');
    expect(log, ['start', 'open app-settings:']);
    expect(log.where((l) => l.contains('App-Prefs')), isEmpty);
    await shutdown(tester, c);

    log.clear();
    final none = NoPipPlayer();
    c = await boot(tester, pip: none);
    await openGuide(tester);
    await expand(tester, 'outlook');
    expect(find.text(tr.guidePipHint), findsNothing);
    await tapKey(tester, 'guide-open-settings-outlook');
    expect(log, ['open app-settings:']);
    expect(none.calls, isNot(contains('start')));
    await shutdown(tester, c);
  });

  testWidgets('kart açılınca pip.prepare doğru varlıkla çağrılır; uygulama öne dönünce pip.stop', (tester) async {
    final c = await boot(tester, pip: _FakePip(log));
    await openGuide(tester);
    await expand(tester, 'actionButton');
    expect(log, ['prepare assets/guide/action_button.mp4']);
    await expand(tester, 'backTap');
    expect(log.last, 'prepare assets/guide/back_tap.mp4');
    await expand(tester, 'outlook');
    expect(log.last, 'prepare assets/guide/outlook.mp4');
    // The shortcut step has no video.
    final before = log.length;
    await expand(tester, 'shortcut');
    expect(log.length, before);

    log.clear();
    await tapKey(tester, 'guide-open-settings-outlook');
    expect(log, ['start', 'open app-settings:']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(log, isNot(contains('stop')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(log, ['start', 'open app-settings:', 'stop']);
    await shutdown(tester, c);
  });

  testWidgets('kart kapanınca pip.stop; PiP Ayarlar için başladıysa kapanış durdurmaz', (tester) async {
    final c = await boot(tester, pip: _FakePip(log));
    await openGuide(tester);
    await expand(tester, 'actionButton');
    expect(log, ['prepare assets/guide/action_button.mp4']);
    // Closing the card removes the prepared player.
    await expand(tester, 'actionButton');
    expect(log, ['prepare assets/guide/action_button.mp4', 'stop']);

    // Closing a card whose video is not the prepared one leaves the prepared one alone.
    await expand(tester, 'backTap');
    await expand(tester, 'outlook');
    log.clear();
    await expand(tester, 'backTap');
    expect(log, isEmpty);

    // While the video plays for the trip to Settings, closing its card does not stop it.
    await tapKey(tester, 'guide-open-settings-outlook');
    expect(log, ['start', 'open app-settings:']);
    await expand(tester, 'outlook');
    expect(log, ['start', 'open app-settings:']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(log, ['start', 'open app-settings:', 'stop']);
    await shutdown(tester, c);
  });

  testWidgets('Ayarlar düğmesi kendi kartının videosunu oynatır; dönüşten sonra yeniden yükler', (tester) async {
    final c = await boot(tester, pip: _FakePip(log));
    await openGuide(tester);
    await expand(tester, 'actionButton');
    await expand(tester, 'outlook');
    // outlook loaded last; the actionButton card's button loads its own video first.
    log.clear();
    await tapKey(tester, 'guide-open-settings-actionButton');
    expect(log, ['prepare assets/guide/action_button.mp4', 'start', 'open app-settings:']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    // After the return the player is gone; a second tap loads the video again.
    log.clear();
    await tapKey(tester, 'guide-open-settings-actionButton');
    expect(log, ['prepare assets/guide/action_button.mp4', 'start', 'open app-settings:']);
    await shutdown(tester, c);
  });

  testWidgets('kılavuzdan çıkınca pip.stop', (tester) async {
    final c = await boot(tester, pip: _FakePip(log));
    await openGuide(tester);
    await expand(tester, 'backTap');
    log.clear();
    Navigator.of(tester.element(find.byType(ShortcutGuidePage))).pop();
    await settle(tester);
    expect(find.byType(ShortcutGuidePage), findsNothing);
    expect(log, ['stop']);
    await shutdown(tester, c);
  });

  testWidgets('hızlı "Ayarlar\'ı aç": start, video yüklenince (en çok 1 sn beklenir) çağrılır', (tester) async {
    final gate = Completer<void>();
    var c = await boot(tester, pip: _FakePip(log, gate: gate));
    await openGuide(tester);
    await expand(tester, 'backTap');
    expect(log, ['prepare assets/guide/back_tap.mp4']);
    final tap = find.byKey(const Key('guide-open-settings-backTap'));
    await tester.ensureVisible(tap);
    await settle(tester);
    await tester.tap(tap);
    await tester.pump(const Duration(milliseconds: 300));
    expect(log, ['prepare assets/guide/back_tap.mp4']);
    gate.complete();
    await settle(tester);
    expect(log, ['prepare assets/guide/back_tap.mp4', 'prepared', 'start', 'open app-settings:']);
    await shutdown(tester, c);

    // A load that never ends holds the trip to Settings for at most a second.
    log.clear();
    c = await boot(tester, pip: _FakePip(log, gate: Completer<void>()));
    await openGuide(tester);
    await expand(tester, 'outlook');
    await tester.ensureVisible(find.byKey(const Key('guide-open-settings-outlook')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('guide-open-settings-outlook')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(log, ['prepare assets/guide/outlook.mp4']);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(log, ['prepare assets/guide/outlook.mp4', 'start', 'open app-settings:']);
    await shutdown(tester, c);
  });

  testWidgets('elle "Tamam olarak işaretle" ve "Geri al" ayarı yazar ve rozet değişir', (tester) async {
    final c = await boot(tester);
    await openGuide(tester);
    await expand(tester, 'backTap');
    await tapKey(tester, 'guide-mark-backTap');
    expect(c.guideStepDone('backTap'), isTrue);
    expect(c.settings.guideDone, ['backTap']);
    expect(inHeader('backTap', find.text(tr.guideDoneBadge)), findsOneWidget);
    expect(inHeader('backTap', find.byIcon(Icons.check_circle_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('guide-mark-backTap')), matching: find.text(tr.guideMarkUndone)),
        findsOneWidget);
    // The other steps keep their own badge.
    expect(inHeader('outlook', find.text(tr.guideTodo)), findsOneWidget);

    await tapKey(tester, 'guide-mark-backTap');
    expect(c.guideStepDone('backTap'), isFalse);
    expect(inHeader('backTap', find.text(tr.guideTodo)), findsOneWidget);
    expect(inHeader('backTap', find.byIcon(Icons.radio_button_unchecked)), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('Bugün: ilk sesli kayıttan sonra kart bir kez görünür; kapatınca bir daha gelmez', (tester) async {
    final engine = FakeSpeechEngine();
    final c = AppController(
      store: MemoryStore({'settings': jsonEncode(base.toJson())}),
      clock: () => now,
      speech: engine,
      saveDelay: Duration.zero,
    );
    await tester.runAsync(c.load);

    Future<void> saveByVoice(String text) async {
      final e = FakeSpeechEngine();
      final v = VoiceCaptureController(app: c, engine: e, deviceLocales: () => const [Locale('tr', 'TR')]);
      unawaited(v.open());
      await tester.pump(VoiceTimings.startDelay);
      await tester.pump();
      e.say(text);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(VoiceTimings.previewHold);
      await v.close();
    }

    await boot(tester, controller: c);
    expect(c.settings.voiceUsed, isFalse);
    expect(find.text(tr.guideCardTitle), findsNothing);

    await saveByVoice('yarın annemi ara');
    expect(c.tasks, hasLength(1));
    expect(c.settings.voiceUsed, isTrue);
    await settle(tester);
    expect(find.text(tr.guideCardTitle), findsOneWidget);
    expect(find.text(tr.guideCardBody), findsOneWidget);
    expect(find.text(tr.guideOpen), findsOneWidget);
    // Right under the quick add field.
    final field = tester.getBottomLeft(find.byType(QuickAddField)).dy;
    final card = tester.getTopLeft(find.text(tr.guideCardTitle)).dy;
    expect(card, greaterThan(field));

    await tester.tap(find.byTooltip(tr.close));
    await settle(tester);
    expect(c.settings.guideCardDismissed, isTrue);
    expect(find.text(tr.guideCardTitle), findsNothing);

    await saveByVoice('akşam süt al');
    await settle(tester);
    expect(find.text(tr.guideCardTitle), findsNothing);
    await shutdown(tester, c);
  });

  testWidgets('Bugün kartındaki "Kılavuzu aç" kılavuzu açar ve kartı kapatır', (tester) async {
    final c = await boot(tester, settings: base.copyWith(voiceUsed: true));
    expect(find.text(tr.guideCardTitle), findsOneWidget);
    await tester.tap(find.text(tr.guideOpen));
    await settle(tester);
    expect(find.byType(ShortcutGuidePage), findsOneWidget);
    expect(c.settings.guideCardDismissed, isTrue);
    await shutdown(tester, c);
  });

  testWidgets('ses desteklenmeyen platformda kart ve Ayarlar girişi yok', (tester) async {
    var c = await boot(
      tester,
      speech: UnsupportedSpeechEngine(),
      settings: base.copyWith(voiceUsed: true),
      size: const Size(390, 4000),
    );
    expect(find.text(tr.guideCardTitle), findsNothing);
    await tester.tap(find.byTooltip(tr.settings).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text(tr.guideTitle), findsNothing);
    await shutdown(tester, c);

    // With speech the entry is there and opens the guide.
    c = await boot(tester, settings: base.copyWith(voiceUsed: true), size: const Size(390, 4000));
    expect(find.text(tr.guideCardTitle), findsOneWidget);
    await tester.tap(find.byTooltip(tr.settings).first);
    await tester.pumpAndSettle();
    expect(find.text(tr.guideTitle), findsOneWidget);
    await tester.tap(find.text(tr.guideTitle));
    await settle(tester);
    expect(find.byType(ShortcutGuidePage), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('Hareketi Azalt açıkken animasyon denetleyicisi çalışmaz (hasRunningAnimations false)', (tester) async {
    var c = await boot(tester);
    await openGuide(tester);
    await expand(tester, 'backTap');
    // Without the setting the hand loops.
    expect(tester.widget<PhoneHandAnimation>(find.byType(PhoneHandAnimation)).progress, isNull);
    expect(tester.hasRunningAnimations, isTrue);
    await shutdown(tester, c);

    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    c = await boot(tester);
    await openGuide(tester);
    await expand(tester, 'backTap');
    await tester.pumpAndSettle();
    expect(find.byType(PhoneHandAnimation), findsOneWidget);
    expect(tester.widget<PhoneHandAnimation>(find.byType(PhoneHandAnimation)).progress, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await shutdown(tester, c);
  });

  testWidgets('ölçek 2,0 ve 375 pt: taşma yok; düğmeler ≥ 44 pt; rozet ikon + yazı', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    // Tall enough that every open card is on screen at once.
    final c = await boot(tester, pip: _FakePip(log), size: const Size(375, 6000));
    await openGuide(tester);
    for (final step in AppSettings.guideSteps) {
      await expand(tester, step);
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(PhoneHandAnimation), findsNWidgets(4));
    for (final step in AppSettings.guideSteps) {
      expect(inHeader(step, find.byIcon(Icons.radio_button_unchecked)), findsOneWidget);
      expect(inHeader(step, find.text(tr.guideTodo)), findsOneWidget);
    }
    for (final key in [
      'guide-run-shortcut',
      for (final step in ['actionButton', 'backTap', 'outlook']) ...[
        'guide-open-settings-$step',
        'guide-mark-$step',
      ],
      for (final step in AppSettings.guideSteps) 'guide-step-$step',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
    }
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
    await shutdown(tester, c);
  });

  testWidgets('dört sahnenin her biri 0, 0.5 ve 1 ilerlemede hatasız çizilir', (tester) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      for (final scene in GuideScene.values) {
        for (final p in [0.0, 0.5, 1.0]) {
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 300, height: 160, child: PhoneHandAnimation(scene: scene, progress: p)),
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: '$scene $p');
          expect(find.descendant(of: find.byType(PhoneHandAnimation), matching: find.byType(CustomPaint)),
              findsWidgets);
          // No text in the drawing.
          expect(find.descendant(of: find.byType(PhoneHandAnimation), matching: find.byType(Text)), findsNothing);
        }
      }
    }
    // Its own six-second loop when no progress is given.
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: SizedBox(width: 300, height: 160, child: PhoneHandAnimation(scene: GuideScene.backTap))),
    ));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
