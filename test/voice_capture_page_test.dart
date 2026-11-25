import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/voice/voice_capture_controller.dart';
import 'package:pamnot/ui/voice/voice_capture_page.dart';

import 'support/contrast.dart';
import 'support/fake_speech_engine.dart';
import 'support/voice_harness.dart';

/// Shows the voice screen as the app's home with a Turkish phone, and waits
/// until the first listen has started ([autoListen] false: opened by a
/// pamnot:// link, it waits for a tap instead).
Future<FakeSpeechEngine> pumpPage(
  WidgetTester tester,
  VoiceHarness h, {
  FakeSpeechEngine? engine,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  bool accessibleNavigation = false,
  bool autoListen = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Recognition follows the phone's language, not the app's.
  tester.platformDispatcher.localesTestValue = const [Locale('tr', 'TR')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final e = engine ?? FakeSpeechEngine();
  await tester.pumpWidget(
    AppScope(
      controller: h.app,
      child: MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme ?? PamnotTheme.light(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale), accessibleNavigation: accessibleNavigation),
          child: child!,
        ),
        home: VoiceCapturePage(engine: e, autoListen: autoListen),
      ),
    ),
  );
  await tester.pump(VoiceTimings.startDelay);
  await tester.pump();
  return e;
}

/// Unmounts the screen (which cancels the engine) and lets the app's save
/// and sync timers run out.
Future<void> shutdown(WidgetTester tester, VoiceHarness h) async {
  await tester.pumpWidget(const SizedBox());
  await h.dispose(tester);
}

/// The app's home with one button that opens the voice screen the way the
/// app does; the screen then uses the app's engine.
Future<void> pumpLauncher(WidgetTester tester, VoiceHarness h) async {
  tester.platformDispatcher.localesTestValue = const [Locale('tr', 'TR')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    AppScope(
      controller: h.app,
      child: MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: PamnotTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(onPressed: () => VoiceCapturePage.open(c), child: const Text('Aç')),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Lets a route transition finish (and the first listen start).
Future<void> settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Says [text] and waits until it has been saved.
Future<void> sayAndSave(WidgetTester tester, FakeSpeechEngine e, String text) async {
  e.say(text);
  await tester.pump(VoiceTimings.utteranceGap);
  await tester.pump(VoiceTimings.previewHold);
  await tester.pump();
}

/// Every haptic the screen asked for, with whether the microphone was on.
List<String> recordHaptics(WidgetTester tester, FakeSpeechEngine e) {
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments} mic:${e.listening}');
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return haptics;
}

void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

int starts(FakeSpeechEngine e) => e.calls.where((c) => c.startsWith('start:')).length;

const tr = S.tr;

void main() {
  testWidgets('açılınca dinler: ikon + "Dinliyorum…" ve kapat düğmesi görünür', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    expect(find.text('Dinliyorum…'), findsOneWidget);
    expect(find.byKey(const Key('voice-close')), findsOneWidget);
    expect(find.byTooltip('Dinlemeyi durdur'), findsOneWidget);
    expect(e.listening, isTrue);
    await shutdown(tester, h);
  });

  testWidgets('canlı metin, önizleme çipleri, geri sayım, kayıt, Eklenenler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    final haptics = recordHaptics(tester, e);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump();
    expect(find.text('yarın akşam yedide annemi ara'), findsOneWidget);
    expect(find.text('Yarın'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('Annemi ara'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
    expect(find.text('8 sn'), findsOneWidget);
    expect(find.text('Düzelt'), findsOneWidget);
    expect(find.text('Dinliyorum…'), findsNothing); // mikrofon kapalıyken yazı kalmaz
    expect(find.byTooltip('Dinlemeyi başlat'), findsOneWidget);
    expect(e.listening, isFalse);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('7 sn'), findsOneWidget);
    expect(h.app.tasks, isEmpty);
    expect(haptics, isEmpty);
    await tester.pump(VoiceTimings.previewHold - const Duration(milliseconds: 1100));
    await tester.pump();
    final t = h.app.tasks.single;
    expect(find.text('Eklenenler'), findsOneWidget);
    expect(find.byKey(Key('voice-saved-${t.id}')), findsOneWidget);
    expect(find.text('Annemi ara · Yarın 19:00'), findsOneWidget);
    expect(find.byTooltip('Annemi ara görevini geri al'), findsOneWidget);
    // One light tap at the save, while the microphone was off.
    expect(haptics, ['HapticFeedbackType.lightImpact mic:false']);
    // It listens again.
    expect(find.text('Dinliyorum…'), findsOneWidget);
    expect(e.listening, isTrue);
    // Undo deletes the task and the row.
    await tester.tap(find.byKey(Key('voice-undo-${t.id}')));
    await tester.pump();
    expect(h.app.tasks, isEmpty);
    expect(find.byKey(Key('voice-saved-${t.id}')), findsNothing);
    expect(find.text('Eklenenler'), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('belirsiz saat "?" ile gösterilir ve "saat tahmini" diye okunur', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say("saat 3'te dişçi");
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('15:00 ?'), findsOneWidget);
    expect(find.text('15:00'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('saat tahmini')), findsOneWidget);
    expect(find.bySemanticsLabel('Dişçi, Bugün 15:00, hatırlatma açık, saat tahmini'), findsOneWidget);
    // "?" is not read out.
    expect(find.bySemanticsLabel(RegExp(r'\?')), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('önizleme tek öğe olarak okunur', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.bySemanticsLabel('Annemi ara, Yarın 19:00, hatırlatma açık'), findsOneWidget);
    // The chips and the title are not separate elements.
    for (final part in ['Annemi ara', 'Yarın', '19:00']) {
      expect(find.bySemanticsLabel(part), findsNothing, reason: part);
    }
    expect(
      tester.getSemantics(find.byKey(const Key('voice-preview'))),
      isSemantics(label: 'Annemi ara, Yarın 19:00, hatırlatma açık'),
    );
    await shutdown(tester, h);
  });

  testWidgets('Düzelt: metin alanı, canlı önizleme, Kaydet', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.tap(find.byKey(const Key('voice-fix')));
    await tester.pump();
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    final draft = find.byKey(const Key('voice-draft'));
    expect(draft, findsOneWidget);
    final field = tester.widget<TextField>(draft);
    expect(field.autofocus, isTrue);
    expect(field.controller!.text, 'yarın akşam yedide annemi ara');
    expect(field.decoration?.hintText, 'Görevi düzelt');
    // The countdown stopped: nothing is saved while typing.
    await tester.pump(VoiceTimings.previewHold * 2);
    expect(h.app.tasks, isEmpty);
    await tester.enterText(draft, 'yarın 10:30 toplantı');
    await tester.pump();
    expect(find.text('10:30 ?'), findsOneWidget);
    expect(find.text('Toplantı'), findsOneWidget);
    expect(find.text('19:00'), findsNothing);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.title, t.due), ('Toplantı', DateTime(2026, 11, 24, 10, 30)));
    expect(find.byKey(Key('voice-saved-${t.id}')), findsOneWidget);
    expect(find.byKey(const Key('voice-draft')), findsNothing);
    expect(find.text('Dinliyorum…'), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('Düzelt: başlık boşken Kaydet kapalı', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.tap(find.byKey(const Key('voice-fix')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('voice-draft')), 'yarın');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('voice-save'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('voice-save')), warnIfMissed: false);
    await tester.pump();
    expect(h.app.tasks, isEmpty);
    await shutdown(tester, h);
  });

  testWidgets('kapat önizlemedeki görevi kaydetmez; sayfa kapanır', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(e.listening, isTrue);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(e.calls.last, 'cancel');
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('geri hareketi kapat ile aynı yoldan kapatır', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    await sayAndSave(tester, e, 'yarın akşam yedide annemi ara');
    e.say("saat 3'te dişçi");
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('15:00 ?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(e.calls.last, 'cancel');
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.single.title, 'Annemi ara');
    expect(find.text('1 kayıt eklendi'), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('sayfa başka bir yoldan kapanınca mikrofon kapanır', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    expect(e.listening, isTrue);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(VoiceCapturePage.isOpen, isFalse);
    expect(e.listening, isFalse);
    expect(e.calls.last, 'cancel');
    await shutdown(tester, h);
  });

  testWidgets('izin yok: yazı + tek "Ayarlar’ı Aç" düğmesi app-settings: açar', (tester) async {
    final opened = <Uri>[];
    final original = openExternal;
    openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openExternal = original);
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, engine: FakeSpeechEngine(availability: SpeechAvailability.permissionDenied));
    expect(find.text(tr.voicePermissionDenied), findsOneWidget);
    expect(find.text('Dinliyorum…'), findsNothing);
    // One button, and no microphone button that could ask again.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text(tr.voiceRetry), findsNothing);
    expect(find.byKey(const Key('voice-mic')), findsNothing);
    // On the error card.
    final colors = PamnotTheme.light().colorScheme;
    final card = tester.widget<Material>(
      find.ancestor(of: find.text(tr.voicePermissionDenied), matching: find.byType(Material)).first,
    );
    expect(card.color, colors.errorContainer);
    expect(tester.widget<Text>(find.text(tr.voicePermissionDenied)).style?.color, colors.onErrorContainer);
    await tester.tap(find.byKey(const Key('voice-open-settings')));
    await tester.pump();
    expect(opened.single.toString(), 'app-settings:');
    // Back from Settings: the system prompt is not tried again.
    lifecycle(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump(VoiceTimings.startDelay);
    await tester.pump();
    expect(e.calls.where((c) => c.startsWith('prepare')), hasLength(1));
    expect(find.text(tr.voicePermissionDenied), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('dikte kapalı, dil yok, platform yok metinleri', (tester) async {
    var h = await VoiceHarness.create(tester);
    var e = await pumpPage(tester, h);
    e.fail(SpeechErrorKind.dictationDisabled);
    await tester.pump();
    expect(find.text(tr.voiceDictationOff), findsOneWidget);
    expect(find.text('Dinliyorum…'), findsNothing);
    expect(find.byKey(const Key('voice-mic')), findsNothing);
    await shutdown(tester, h);

    h = await VoiceHarness.create(tester);
    e = await pumpPage(tester, h, engine: FakeSpeechEngine(supportedLocales: const ['de-DE']));
    expect(find.text(tr.voiceUnsupportedLocale), findsOneWidget);
    expect(find.byKey(const Key('voice-mic')), findsNothing);
    expect(e.calls, ['resolve']);
    await shutdown(tester, h);

    h = await VoiceHarness.create(tester);
    e = await pumpPage(tester, h, engine: FakeSpeechEngine(supported: false));
    expect(find.text(tr.voiceUnsupportedPlatform), findsOneWidget);
    expect(find.byKey(const Key('voice-mic')), findsNothing);
    await shutdown(tester, h);
    // The engine is never called on an unsupported platform.
    expect(e.calls, isEmpty);
  });

  testWidgets('hata: kartta genel metin, "Tekrar dene" yeniden dinler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.fail(SpeechErrorKind.network);
    await tester.pump();
    expect(find.text(tr.voiceErrorGeneric), findsOneWidget);
    expect(find.text('Dinliyorum…'), findsNothing);
    final card = tester.widget<Material>(
      find.ancestor(of: find.text(tr.voiceErrorGeneric), matching: find.byType(Material)).first,
    );
    expect(card.color, PamnotTheme.light().colorScheme.errorContainer);
    await tester.tap(find.text(tr.voiceRetry));
    await tester.pump();
    expect(starts(e), 2);
    expect(find.text('Dinliyorum…'), findsOneWidget);
    expect(find.text(tr.voiceErrorGeneric), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('tarihsiz hatırlatma ipucu', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('kitap oku');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('Tarihsiz'), findsOneWidget);
    expect(find.bySemanticsLabel('Kitap oku, Tarihsiz'), findsOneWidget);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect(find.text('Kitap oku · Tarihsiz'), findsOneWidget);
    e.say('annemi aramayı hatırlat');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('Tarihsiz · hatırlatma için gün söyle'), findsOneWidget);
    // No bell without a day.
    expect(find.byIcon(Icons.notifications_rounded), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r', Tarihsiz, hatırlatma için gün söyle$')), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('not: yalnız "Not" çipi', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('not al: süt bitmiş');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('Not'), findsOneWidget);
    expect(find.text('Süt bitmiş'), findsOneWidget);
    expect(find.text('Tarihsiz'), findsNothing);
    expect(find.byIcon(Icons.notifications_rounded), findsNothing);
    expect(find.bySemanticsLabel('Süt bitmiş, Not'), findsOneWidget);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    final n = h.app.notes.single;
    expect(find.byKey(Key('voice-saved-${n.id}')), findsOneWidget);
    expect(find.text('Süt bitmiş · Not'), findsOneWidget);
    // F7: a note is not called a task.
    expect(find.byTooltip('Notu geri al: Süt bitmiş'), findsOneWidget);
    expect(find.byTooltip('Süt bitmiş görevini geri al'), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('kilitlenirken kaydedilen satır notuyla görünür', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump();
    lifecycle(tester, const [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    expect(e.listening, isFalse);
    final t = h.app.tasks.single;
    lifecycle(tester, const [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await tester.pump();
    expect(find.byKey(Key('voice-saved-${t.id}')), findsOneWidget);
    expect(find.text('Kilitlenirken kaydedildi'), findsOneWidget);
    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Devam etmek için dokun'), findsOneWidget);
    // The microphone does not come back on by itself.
    await tester.pump(VoiceTimings.startDelay * 2);
    expect(e.listening, isFalse);
    expect(find.byTooltip('Dinlemeyi başlat'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pump();
    expect(e.listening, isTrue);
    expect(find.text('Dinliyorum…'), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('kapanınca özet snack\'i çıkar', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    await sayAndSave(tester, e, 'yarın akşam yedide annemi ara');
    expect(h.app.tasks, hasLength(1));
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(find.text('1 kayıt eklendi'), findsOneWidget);

    // What was undone is not counted.
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    await sayAndSave(tester, e, 'kitap oku');
    final t = h.app.tasks.firstWhere((t) => t.title == 'Kitap oku');
    await tester.tap(find.byKey(Key('voice-undo-${t.id}')));
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('açıkken ikinci open ikinci sayfa açmaz', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    final context = tester.element(find.text('Aç'));
    expect(VoiceCapturePage.isOpen, isFalse);
    unawaited(VoiceCapturePage.open(context));
    expect(VoiceCapturePage.isOpen, isTrue);
    unawaited(VoiceCapturePage.open(context));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    unawaited(VoiceCapturePage.open(context));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(starts(e), 1);
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsNothing);
    expect(VoiceCapturePage.isOpen, isFalse);
    // It opens again afterwards.
    await tester.tap(find.text('Aç'));
    await settleRoute(tester);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    await shutdown(tester, h);
  });

  // ------------------------------------------------- erişilebilir gezinme

  testWidgets('VoiceOver açıkken geri sayım yerine Kaydet ve Düzelt görünür; kendiliğinden kaydetmez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, accessibleNavigation: true);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    expect(find.byKey(const Key('voice-save')), findsOneWidget);
    expect(find.byKey(const Key('voice-fix')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(h.app.tasks, isEmpty);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    expect(h.app.tasks.single.title, 'Annemi ara');
    // It does not listen again by itself, and does not close on silence.
    expect(find.text('Kaydedildi'), findsOneWidget);
    expect(e.listening, isFalse);
    await tester.pump(VoiceTimings.idleClose * 2);
    expect(find.text('Kaydedildi'), findsOneWidget);
    expect(e.calls.last, isNot('cancel'));
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pump();
    expect(e.listening, isTrue);
    await shutdown(tester, h);
  });

  testWidgets('dinlerken durum satırı ve canlı metin canlı bölge değildir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    // F2: VoiceOver would say "Dinliyorum…" into the open microphone.
    expect(
      tester.getSemantics(find.byKey(const Key('voice-status'))),
      isSemantics(label: 'Dinliyorum…', isLiveRegion: false),
    );
    e.say('yarın akşam yedide annemi ara');
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('voice-transcript'))),
      isSemantics(label: 'yarın akşam yedide annemi ara', isLiveRegion: false),
    );
    // The words coming in do not change the status line.
    expect(
      tester.getSemantics(find.byKey(const Key('voice-status'))),
      isSemantics(label: 'Dinliyorum…', isLiveRegion: false),
    );
    // The live preview is not read out while the words still come...
    expect(tester.getSemantics(find.byKey(const Key('voice-preview'))), isSemantics(isLiveRegion: false));
    await tester.pump(VoiceTimings.utteranceGap);
    // ...but once, when listening ends.
    expect(
      tester.getSemantics(find.byKey(const Key('voice-preview'))),
      isSemantics(label: 'Annemi ara, Yarın 19:00, hatırlatma açık', isLiveRegion: true),
    );
    expect(find.byKey(const Key('voice-status')), findsNothing);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('voice-status'))),
      isSemantics(label: 'Dinliyorum…', isLiveRegion: false),
    );
    await shutdown(tester, h);
  });

  testWidgets('F2: durum satırı hazırlanırken ve dinlerken sessiz, değişimlerde canlı bölgedir', (tester) async {
    SemanticsNode status() => tester.getSemantics(find.byKey(const Key('voice-status')));
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, engine: FakeSpeechEngine()..prepareGate = Completer<void>());
    // Getting ready: the microphone opens right after; nothing is announced.
    expect(status(), isSemantics(label: 'Hazırlanıyor…', isLiveRegion: false));
    e.prepareGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(status(), isSemantics(label: 'Dinliyorum…', isLiveRegion: false));
    // Stopped with nothing said: "Paused" is announced, the microphone is off.
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pump();
    expect(e.listening, isFalse);
    expect(status().label, startsWith('Duraklatıldı'));
    expect(status(), isSemantics(isLiveRegion: true));
    // An error is announced.
    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pump();
    expect(status(), isSemantics(label: 'Dinliyorum…', isLiveRegion: false));
    e.fail(SpeechErrorKind.network);
    await tester.pump();
    expect(status(), isSemantics(label: tr.voiceErrorGeneric, isLiveRegion: true));
    await shutdown(tester, h);

    // "Saved" is announced (VoiceOver: it stays until a tap).
    final h2 = await VoiceHarness.create(tester);
    final e2 = await pumpPage(tester, h2, accessibleNavigation: true);
    e2.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    expect(status(), isSemantics(label: 'Kaydedildi', isLiveRegion: true));
    await shutdown(tester, h2);
  });

  testWidgets('F1: hatayla biten dinlemede söylenen önizlenir; geri sayım yok, Kaydet ile kaydedilir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    e.fail(SpeechErrorKind.unknown);
    await tester.pump();
    expect(find.text(tr.voiceErrorGeneric), findsNothing);
    expect(find.bySemanticsLabel('Annemi ara, Yarın 19:00, hatırlatma açık'), findsOneWidget);
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    expect(find.byKey(const Key('voice-fix')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(h.app.tasks, isEmpty);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    expect(h.app.tasks.single.title, 'Annemi ara');
    expect(find.text('Kaydedildi'), findsOneWidget);
    expect(e.listening, isFalse);
    await shutdown(tester, h);
  });

  testWidgets('geri sayım çubuğu değer duyurmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    final node = tester.getSemantics(find.byKey(const Key('voice-countdown')));
    // The countdown's own node: the seconds as text, no value.
    expect(node.label, '8 sn');
    expect(node.value, isEmpty);
    expect(node, isSemantics(isLiveRegion: false));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(tester.getSemantics(find.byKey(const Key('voice-countdown'))).value, isEmpty);
    await shutdown(tester, h);
  });

  // ------------------------------------- yönergeler (hedef, etiket, kontrast)

  for (final (name, theme) in [('açık', PamnotTheme.light()), ('koyu', PamnotTheme.dark())]) {
    testWidgets('yönergeler: $name tema, önizleme ve Eklenenler görünürken', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await VoiceHarness.create(tester);
      final e = await pumpPage(tester, h, theme: theme);
      await sayAndSave(tester, e, 'yarın akşam yedide annemi ara');
      e.say("saat 3'te dişçi");
      await tester.pump(VoiceTimings.utteranceGap);
      expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
      expect(find.text('Eklenenler'), findsOneWidget);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await shutdown(tester, h);
    });

    testWidgets('yönergeler: $name tema, VoiceOver düğmeleri ve izin kartı', (tester) async {
      final handle = tester.ensureSemantics();
      var h = await VoiceHarness.create(tester);
      final e = await pumpPage(tester, h, theme: theme, accessibleNavigation: true);
      e.say('yarın akşam yedide annemi ara');
      await tester.pump(VoiceTimings.utteranceGap);
      expect(find.byKey(const Key('voice-save')), findsOneWidget);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await shutdown(tester, h);

      h = await VoiceHarness.create(tester);
      await pumpPage(
        tester,
        h,
        theme: theme,
        engine: FakeSpeechEngine(availability: SpeechAvailability.permissionDenied),
      );
      expect(find.byKey(const Key('voice-open-settings')), findsOneWidget);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await shutdown(tester, h);
    });
  }

  // ------------------------------------------------------------- düzen

  testWidgets('metin ölçeği 2,0 ve 375×667: taşma yok', (tester) async {
    var h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, size: const Size(375, 667), textScale: 2);
    await sayAndSave(tester, e, 'yarın akşam yedide annemi ara');
    expect(tester.takeException(), isNull);
    e.say("saat 3'te dişçi");
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('15:00 ?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('voice-fix')));
    await tester.tap(find.byKey(const Key('voice-fix')));
    await tester.pump();
    expect(find.byKey(const Key('voice-draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, h);

    // The longest chip and the error card.
    h = await VoiceHarness.create(tester);
    final e2 = await pumpPage(tester, h, size: const Size(375, 667), textScale: 2, accessibleNavigation: true);
    e2.say('annemi aramayı hatırlat');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text('Tarihsiz · hatırlatma için gün söyle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, h);

    h = await VoiceHarness.create(tester);
    await pumpPage(
      tester,
      h,
      size: const Size(375, 667),
      textScale: 2,
      engine: FakeSpeechEngine(availability: SpeechAvailability.permissionDenied),
    );
    expect(find.text(tr.voicePermissionDenied), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, h);
  });

  testWidgets('yatay 667×375: taşma yok, kapat düğmesi görünür', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, size: const Size(667, 375));
    await sayAndSave(tester, e, 'yarın akşam yedide annemi ara');
    e.say("saat 3'te dişçi");
    await tester.pump(VoiceTimings.utteranceGap);
    expect(tester.takeException(), isNull);
    // The close button stays on screen even scrolled to the end.
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final close = find.byKey(const Key('voice-close'));
    expect(close.hitTestable(), findsOneWidget);
    expect(const Rect.fromLTWH(0, 0, 667, 375).contains(tester.getCenter(close)), isTrue);
    await shutdown(tester, h);
  });

  testWidgets('halka ses düzeyiyle büyür', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    final ring = find.byKey(const Key('voice-ring'));
    final before = tester.getRect(ring);
    e.level(1);
    // One frame starts the animation, the next one shows where it got to.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(ring).width, moreOrLessEquals(before.width * 1.15, epsilon: 0.5));
    expect(find.byKey(const Key('voice-level-bar')), findsNothing);
    await shutdown(tester, h);
  });

  testWidgets('Hareketi Azalt açıkken halka ölçeklenmez, düzey çubuğu görünür', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h);
    final ring = find.byKey(const Key('voice-ring'));
    final before = tester.getRect(ring);
    e.level(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getRect(ring), before);
    expect(find.byKey(const Key('voice-level-bar')), findsOneWidget);
    await shutdown(tester, h);
  });

  // -------------------------------------------- Review Focus 5: uzun konuşma

  testWidgets('RF5: 600 karakterlik ve satır sonlu metin taşmaz, başlık kesilmeden kaydedilir', (tester) async {
    final long = List.filled(100, 'kelime').join(' '); // 699 karakter
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, size: const Size(375, 667));
    e.say(long);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final t = h.app.tasks.single;
    expect(t.title.length, long.length);
    expect(t.title, 'K${long.substring(1)}');
    // F7: the undo button's label keeps the first 60 characters.
    final undo = tester.widget<IconButton>(find.byKey(Key('voice-undo-${t.id}')));
    expect(undo.tooltip, '${t.title.substring(0, 59)}… görevini geri al');
    e.say('satır bir\nsatır iki');
    await tester.pump(VoiceTimings.utteranceGap + VoiceTimings.previewHold);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(h.app.tasks, hasLength(2));
    await shutdown(tester, h);
  });

  // ---------------------------------------------------- final fix wave

  testWidgets('F8: open içindeki bir arama hata verirse isOpen takılı kalmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    await pumpLauncher(tester, h);
    final context = tester.element(find.text('Aç'));
    // The launcher is gone: every lookup through its context fails.
    await tester.pumpWidget(const SizedBox());
    await expectLater(VoiceCapturePage.open(context), throwsA(anything));
    expect(VoiceCapturePage.isOpen, isFalse);
    await h.dispose(tester);
  });

  for (final (name, theme) in [('açık', PamnotTheme.light()), ('koyu', PamnotTheme.dark())]) {
    testWidgets('F11: $name tema, ses halkasının kenarı yüzeye karşı en az 3:1', (tester) async {
      final h = await VoiceHarness.create(tester);
      await pumpPage(tester, h, theme: theme);
      final ring = tester.widget<Container>(find.byKey(const Key('voice-ring')));
      final border = (ring.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, greaterThanOrEqualTo(2));
      expect(border.top.color.a, 1);
      expect(contrast(border.top.color, theme.colorScheme.surface), greaterThanOrEqualTo(3));
      await shutdown(tester, h);
    });
  }

  // ------------------------------------------- R9: a link opens paused

  testWidgets('R9: bağlantıyla açılan ekran "Duraklatıldı · Devam etmek için dokun" gösterir; mikrofon dokunuşla açılır', (
    tester,
  ) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpPage(tester, h, autoListen: false);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(find.text('Devam etmek için dokun'), findsOneWidget);
    expect(find.text('Dinliyorum…'), findsNothing);
    expect(find.byTooltip('Dinlemeyi başlat'), findsOneWidget);
    expect(e.calls, isEmpty);
    expect(e.listening, isFalse);
    expect(h.app.tasks, isEmpty);

    await tester.tap(find.byKey(const Key('voice-mic')));
    await tester.pump();
    expect(e.calls, ['resolve', 'prepare:tr-TR', 'start:tr-TR']);
    expect(e.listening, isTrue);
    expect(find.text('Dinliyorum…'), findsOneWidget);
    await shutdown(tester, h);
  });

  testWidgets('R9: open(autoListen: false) ekranı açar ama dinlemez', (tester) async {
    final e = FakeSpeechEngine();
    final h = await VoiceHarness.create(tester, speech: e);
    await pumpLauncher(tester, h);
    unawaited(VoiceCapturePage.open(tester.element(find.text('Aç')), autoListen: false));
    await settleRoute(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(find.text('Duraklatıldı'), findsOneWidget);
    expect(e.calls, isEmpty);
    expect(e.listening, isFalse);
    await tester.tap(find.byKey(const Key('voice-close')));
    await settleRoute(tester);
    expect(VoiceCapturePage.isOpen, isFalse);
    await shutdown(tester, h);
  });
}
