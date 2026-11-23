import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/ui/voice/voice_capture_controller.dart';

import 'support/fake_speech_engine.dart';
import 'support/voice_harness.dart';

Future<VoiceCaptureController> start(WidgetTester tester, VoiceHarness h, FakeSpeechEngine e,
    {bool accessible = false}) async {
  final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('tr', 'TR')])
    ..accessible = accessible;
  unawaited(c.open());
  await tester.pump(VoiceTimings.startDelay);
  await tester.pump();
  return c;
}

int starts(FakeSpeechEngine e) => e.calls.where((c) => c.startsWith('start:')).length;

void main() {
  testWidgets('açılış: hazırlık, yerel ayar, izin, sonra Started ile dinleme', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('tr', 'TR')]);
    unawaited(c.open());
    expect(c.phase, VoicePhase.preparing);
    await tester.pump(VoiceTimings.startDelay);
    await tester.pump();
    expect(e.calls, ['resolve', 'prepare:tr-TR', 'start:tr-TR']);
    expect((c.phase, c.localeId), (VoicePhase.listening, 'tr-TR'));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('söyle → 1,6 sn → önizleme → 2 sn → kayıt → yeniden dinle → 6 sn → kapan', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump();
    expect(c.transcript, 'yarın akşam yedide annemi ara');
    expect((c.preview!.title, c.preview!.due), ('Annemi ara', DateTime(2026, 11, 24, 19)));
    await tester.pump(const Duration(milliseconds: 1599));
    expect(c.phase, VoicePhase.listening);
    await tester.pump(const Duration(milliseconds: 1));
    expect(e.calls.last, 'stop');
    expect(c.phase, VoicePhase.preview);
    expect(h.app.tasks, isEmpty);
    await tester.pump(VoiceTimings.previewHold);
    final t = h.app.tasks.single;
    expect((t.title, t.due, t.hasTime, t.remindAt),
        ('Annemi ara', DateTime(2026, 11, 24, 19), true, DateTime(2026, 11, 24, 19)));
    expect((c.saved.single.id, c.saved.single.reminder, c.saved.single.inBackground), (t.id, true, false));
    await tester.pump();
    expect((starts(e), c.phase), (2, VoicePhase.listening));
    await tester.pump(VoiceTimings.idleClose);
    expect(c.phase, VoicePhase.closed);
    expect(e.listening, isFalse);
    await h.dispose(tester);
  });

  testWidgets('ilk dinlemede sessizlik ekranı kapatmaz; 30 sn sonra duraklar', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    await tester.pump(VoiceTimings.idleClose);
    expect(c.phase, VoicePhase.listening);
    expect(e.listening, isTrue);
    await tester.pump(const Duration(seconds: 24));
    expect(c.phase, VoicePhase.paused);
    expect(e.listening, isFalse);
    expect(e.calls.last, 'stop');
    expect(h.app.tasks, isEmpty);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('Düzelt geri sayımı durdurur; taslak kaydedilir ve yeniden dinlenir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(c.phase, VoicePhase.preview);
    c.edit();
    expect((c.phase, c.transcript), (VoicePhase.editing, 'yarın 10:00 toplantı'));
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, isEmpty);
    expect(c.phase, VoicePhase.editing);
    c.updateDraft('yarın 10:30 toplantı');
    expect(c.transcript, 'yarın 10:30 toplantı');
    expect(c.preview!.due, DateTime(2026, 11, 24, 10, 30));
    await c.saveNow();
    final t = h.app.tasks.single;
    expect((t.title, t.due), ('Toplantı', DateTime(2026, 11, 24, 10, 30)));
    expect(c.saved.single.id, t.id);
    await tester.pump();
    expect((starts(e), c.phase), (2, VoicePhase.listening));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('kapatma önizlemedeki görevi kaydetmez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(c.phase, VoicePhase.preview);
    await c.close();
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, isEmpty);
    expect(c.saved, isEmpty);
    expect(c.phase, VoicePhase.closed);
    expect(starts(e), 1);
    await h.dispose(tester);
  });

  testWidgets('geri al kaydı siler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.single.title, 'Toplantı');
    c.undo(c.saved.single);
    expect(h.app.tasks, isEmpty);
    expect(c.saved, isEmpty);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('"not al süt bitmiş" not olur; geri al notu siler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('not al süt bitmiş');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(c.preview!.isNote, isTrue);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.notes.first.body, 'Süt bitmiş');
    expect(h.app.tasks, isEmpty);
    final item = c.saved.single;
    expect((item.isNote, item.title, item.id), (true, 'Süt bitmiş', h.app.notes.first.id));
    c.undo(item);
    expect(h.app.notes, isEmpty);
    expect(c.saved, isEmpty);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('motor yoksa platform desteklenmiyor; eklenti çağrılmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine(supported: false);
    final c = await start(tester, h, e);
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase, VoicePhase.unsupportedPlatform);
    expect(e.calls, isEmpty);
    await c.close();
    expect(e.calls, isEmpty);
    await h.dispose(tester);
  });

  testWidgets('dil yoksa unsupportedLocale', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('de', 'DE')]);
    unawaited(c.open());
    await tester.pump(VoiceTimings.startDelay);
    await tester.pump();
    expect(c.phase, VoicePhase.unsupportedLocale);
    expect(e.calls, ['resolve']);
    expect(c.localeId, isNull);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('izin reddi permissionDenied; start çağrılmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine(availability: SpeechAvailability.permissionDenied);
    final c = await start(tester, h, e);
    expect(c.phase, VoicePhase.permissionDenied);
    expect(e.calls, ['resolve', 'prepare:tr-TR']);
    c.toggleMic();
    await tester.pump(const Duration(seconds: 1));
    expect(starts(e), 0);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('dikte kapalı hatası dictationOff', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('süt al');
    e.fail(SpeechErrorKind.dictationDisabled);
    expect(c.phase, VoicePhase.dictationOff);
    await tester.pump(const Duration(seconds: 5));
    expect(c.phase, VoicePhase.dictationOff);
    expect(h.app.tasks, isEmpty);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('noMatch hata sayılmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.fail(SpeechErrorKind.noMatch, permanent: false);
    expect(c.phase, isNot(VoicePhase.error));
    expect(c.phase, VoicePhase.paused);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('ağ hatası error; toggleMic yeniden dinler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.fail(SpeechErrorKind.network);
    expect(c.phase, VoicePhase.error);
    await tester.pump(const Duration(seconds: 1));
    expect(starts(e), 1);
    c.toggleMic();
    await tester.pump();
    expect(starts(e), 2);
    expect(c.phase, VoicePhase.listening);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('kesinti duraklatır', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.fail(SpeechErrorKind.interrupted);
    expect(c.phase, VoicePhase.paused);
    await tester.pump(const Duration(seconds: 10));
    expect((c.phase, starts(e)), (VoicePhase.paused, 1));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('toggleMic dinlerken durdurur ve söyleneni önizler', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('süt al');
    c.toggleMic();
    expect(e.calls.last, 'stop');
    expect(e.listening, isFalse);
    expect(c.phase, VoicePhase.preview);
    expect(c.preview!.title, 'Süt al');
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.single.title, 'Süt al');
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('arka plan: metin yokken mikrofon kapanır, kayıt yok', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    c.onLifecycle(AppLifecycleState.hidden);
    expect(e.calls.last, 'cancel');
    expect(e.listening, isFalse);
    expect(c.phase, VoicePhase.paused);
    expect(h.app.tasks, isEmpty);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 10));
    expect(starts(e), 1); // the microphone does not come back on by itself
    expect(c.phase, VoicePhase.paused);
    c.toggleMic();
    await tester.pump();
    expect((starts(e), c.phase), (2, VoicePhase.listening));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('arka plan: bitmemiş konuşma kaydedilir ve diske yazılır', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(const Duration(milliseconds: 500));
    c.onLifecycle(AppLifecycleState.hidden);
    c.onLifecycle(AppLifecycleState.paused);
    expect(h.app.tasks.single.title, 'Toplantı');
    expect((c.saved.single.inBackground, c.saved.single.id), (true, h.app.tasks.single.id));
    expect((e.calls.last, e.listening, c.phase), ('cancel', false, VoicePhase.paused));
    // Written by the flush, before the app's own save timer runs.
    await Future<void>.value();
    expect(h.store.data['tasks'], contains('Toplantı'));
    await tester.pump();
    expect(h.store.data['tasks'], contains('Toplantı'));
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, hasLength(1));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('arka plan: önizleme hemen kaydedilir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(c.phase, VoicePhase.preview);
    c.onLifecycle(AppLifecycleState.paused);
    expect(h.app.tasks.single.title, 'Toplantı');
    expect(c.saved.single.inBackground, isTrue);
    expect(c.phase, VoicePhase.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, hasLength(1)); // the countdown does not save it again
    expect(starts(e), 1);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect((c.phase, starts(e)), (VoicePhase.paused, 1));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('arka plan: düzeltme taslağı kaydedilmez ve yerinde kalır', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    c.edit();
    c.updateDraft('yarın 10:30 toplantı');
    c.onLifecycle(AppLifecycleState.hidden);
    expect(c.phase, VoicePhase.editing);
    expect(c.transcript, 'yarın 10:30 toplantı');
    expect(h.app.tasks, isEmpty);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect((c.phase, c.transcript, h.app.tasks.length), (VoicePhase.editing, 'yarın 10:30 toplantı', 0));
    await c.saveNow();
    expect(h.app.tasks.single.due, DateTime(2026, 11, 24, 10, 30));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('inactive oturumu kesmez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('süt al');
    c.onLifecycle(AppLifecycleState.inactive);
    expect(c.phase, VoicePhase.listening);
    expect(e.calls, isNot(contains('cancel')));
    expect(e.listening, isTrue);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(VoiceTimings.utteranceGap);
    expect((c.phase, c.preview!.title), (VoicePhase.preview, 'Süt al'));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('5 dakikadan uzun arka plan dönüşte kapatır; taslak varsa kapatmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    c.onLifecycle(AppLifecycleState.hidden);
    h.now = h.now.add(const Duration(minutes: 4));
    c.onLifecycle(AppLifecycleState.resumed);
    expect(c.phase, VoicePhase.paused); // a short trip away keeps the screen
    c.onLifecycle(AppLifecycleState.hidden);
    h.now = h.now.add(const Duration(minutes: 6));
    c.onLifecycle(AppLifecycleState.resumed);
    expect(c.phase, VoicePhase.closed);

    final e2 = FakeSpeechEngine();
    final c2 = await start(tester, h, e2);
    e2.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    c2.edit();
    c2.onLifecycle(AppLifecycleState.hidden);
    h.now = h.now.add(const Duration(minutes: 6));
    c2.onLifecycle(AppLifecycleState.resumed);
    expect((c2.phase, c2.transcript), (VoicePhase.editing, 'yarın 10:00 toplantı'));
    await c2.close();
    await h.dispose(tester);
  });

  testWidgets('arka planda bildirim izni sorulmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(const Duration(milliseconds: 500));
    c.onLifecycle(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 3));
    expect(h.app.tasks.single.remindAt, DateTime(2026, 11, 24, 10));
    expect(c.saved.single.reminder, isTrue);
    expect(h.scheduler.permissionRequests, 0);
    expect(h.app.settings.notificationsAsked, isFalse);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(h.scheduler.permissionRequests, 0);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('bildirim izni saatli ilk görevde, mikrofon kapalıyken, bir kez sorulur', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    var micOnAtRequest = true;
    var startsAtRequest = -1;
    h.scheduler.onRequest = () {
      micOnAtRequest = e.listening;
      startsAtRequest = starts(e);
    };
    final c = await start(tester, h, e);
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(h.scheduler.permissionRequests, 0); // not while previewing
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.single.remindAt, DateTime(2026, 11, 24, 10));
    expect(h.scheduler.permissionRequests, 1);
    expect(micOnAtRequest, isFalse);
    expect(startsAtRequest, 1); // asked before listening again
    await tester.pump();
    expect((starts(e), c.phase), (2, VoicePhase.listening));
    e.say('yarın 11:00 rapor');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks, hasLength(2));
    expect(h.scheduler.permissionRequests, 1);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('saatsiz görev izin sormaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('süt al');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    e.say('yarın faturayı öde');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.map((t) => (t.title, t.remindAt)), [('Süt al', null), ('Faturayı öde', null)]);
    expect(c.saved.map((s) => s.reminder), [false, false]);
    expect(h.scheduler.permissionRequests, 0);
    expect(h.app.settings.notificationsAsked, isFalse);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('günlük yalnız ayar açıkken yazılır', (tester) async {
    final off = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, off, e);
    e.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(off.app.tasks, hasLength(1));
    expect(off.app.voiceLog, isEmpty);
    await c.close();
    await off.dispose(tester);

    final on = await VoiceHarness.create(tester,
        settings: const AppSettings(language: AppLanguage.tr, seeded: true, keepVoiceLog: true));
    final e2 = FakeSpeechEngine();
    final c2 = await start(tester, on, e2);
    e2.say('yarın akşam yedide annemi ara');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    final entry = on.app.voiceLog.single;
    expect((entry.transcript, entry.localeId, entry.title, entry.due),
        ('yarın akşam yedide annemi ara', 'tr-TR', 'Annemi ara', DateTime(2026, 11, 24, 19)));
    // A typed correction is saved, but the log keeps what was recognised.
    await tester.pump();
    e2.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    c2.edit();
    c2.updateDraft('yarın 10:30 toplantı');
    await c2.saveNow();
    expect(on.app.tasks.map((t) => t.due), contains(DateTime(2026, 11, 24, 10, 30)));
    expect((on.app.voiceLog.first.transcript, on.app.voiceLog.first.due),
        ('yarın 10:00 toplantı', DateTime(2026, 11, 24, 10)));
    await c2.close();
    await on.dispose(tester);
  });

  testWidgets('VoiceOver açıkken: geri sayım yok, kendiliğinden kapanma yok, yeniden dinleme yok', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e, accessible: true);
    // The first listen starts by itself as usual.
    expect((starts(e), c.phase), (1, VoicePhase.listening));
    e.say('yarın 10:00 toplantı');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(c.phase, VoicePhase.preview);
    await tester.pump(const Duration(seconds: 30));
    expect((c.phase, h.app.tasks.length), (VoicePhase.preview, 0));
    await c.saveNow();
    await tester.pump(const Duration(seconds: 30));
    expect((c.phase, h.app.tasks.length, starts(e)), (VoicePhase.saved, 1, 1));
    c.toggleMic();
    await tester.pump();
    expect(starts(e), 2);
    expect(c.phase, VoicePhase.listening);
    // Silence after a save does not close the screen; the 30 s limit stays.
    await tester.pump(VoiceTimings.idleClose);
    expect((c.phase, e.listening), (VoicePhase.listening, true));
    await tester.pump(VoiceTimings.maxListen - VoiceTimings.idleClose);
    expect((c.phase, e.listening, e.calls.last), (VoicePhase.paused, false, 'stop'));
    expect(starts(e), 2);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('RF1: Final gelmeden Stopped — son ara metin bir kez kaydedilir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine()..finalOnStop = false;
    final c = await start(tester, h, e);
    e.say('süt al');
    await tester.pump(VoiceTimings.utteranceGap);
    expect(e.calls.last, 'stop');
    expect((c.phase, c.preview!.title), (VoicePhase.preview, 'Süt al'));
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.single.title, 'Süt al');
    expect(c.saved.single.id, h.app.tasks.single.id);
    await tester.pump();
    expect((starts(e), c.phase), (2, VoicePhase.listening));
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, hasLength(1));
    expect(c.saved, hasLength(1));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('RF1: geç gelen Final yeni oturumu bozmaz ve çift kayıt yapmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine()..finalOnStop = false;
    final c = await start(tester, h, e);
    e.say('süt al');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect((h.app.tasks.single.title, starts(e), c.phase), ('Süt al', 2, VoicePhase.listening));
    // The first listen's final arrives after the second listen started.
    e.sendFinal('süt al');
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, hasLength(1));
    expect(c.phase, VoicePhase.listening);
    // The new listen still hears and saves what is said in it.
    e.say('ekmek al');
    expect(c.transcript, 'ekmek al');
    await tester.pump(VoiceTimings.utteranceGap);
    expect((c.phase, c.preview!.title), (VoicePhase.preview, 'Ekmek al'));
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks.map((t) => t.title), ['Süt al', 'Ekmek al']);
    expect(c.saved.map((s) => s.title), ['Ekmek al', 'Süt al']);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('RF2: boş ve dolgu metin kaydedilmez, hata göstermez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    // Before the first save: nothing is saved and the screen waits for a tap.
    e.say('Bir görev ekle.');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks, isEmpty);
    expect(h.app.notes, isEmpty);
    expect(c.saved, isEmpty);
    expect(c.phase, isNot(VoicePhase.error));
    expect(c.phase, VoicePhase.paused);
    // After a save: a filler sentence is skipped and listening goes on.
    c.toggleMic();
    await tester.pump();
    e.say('süt al');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect(h.app.tasks.single.title, 'Süt al');
    final before = starts(e);
    e.say('hatırlat');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    expect(h.app.tasks, hasLength(1));
    expect(c.saved, hasLength(1));
    expect(c.phase, isNot(VoicePhase.error));
    expect((c.phase, starts(e)), (VoicePhase.listening, before + 1));
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('RF4: izin beklenirken kapatılırsa mikrofon hiç açılmaz', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine()..prepareGate = Completer<void>();
    final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('tr', 'TR')]);
    unawaited(c.open());
    await tester.pump(VoiceTimings.startDelay);
    expect(e.calls, ['resolve', 'prepare:tr-TR']);
    await c.close();
    e.prepareGate!.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(starts(e), 0);
    expect(e.listening, isFalse);
    expect(c.phase, VoicePhase.closed);
    await h.dispose(tester);
  });

  testWidgets('RF4: başka yerden silinmiş görevi geri almak hata vermez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    e.say('süt al');
    await tester.pump(VoiceTimings.utteranceGap);
    await tester.pump(VoiceTimings.previewHold);
    final item = c.saved.single;
    h.app.deleteTask(item.id);
    expect(h.app.tasks, isEmpty);
    expect(() => c.undo(item), returnsNormally);
    expect(c.saved, isEmpty);
    expect(h.app.tasks, isEmpty);
    await c.close();
    await h.dispose(tester);
  });

  testWidgets('kapatıldıktan sonra hiçbir zamanlayıcı ya da olay durumu değiştirmez', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = FakeSpeechEngine();
    final c = await start(tester, h, e);
    // Close mid-utterance, with the 1.6 s and 30 s timers running.
    e.say('yarın 10:00 toplantı');
    e.level(0.6);
    expect(c.level, 0.6);
    await c.close();
    expect((c.phase, e.calls.last, e.listening), (VoicePhase.closed, 'cancel', false));
    final callsAtClose = e.calls.length;
    e.say('x');
    e.sendFinal('x');
    e.level(0.8);
    e.fail(SpeechErrorKind.network);
    c.toggleMic();
    c.onLifecycle(AppLifecycleState.hidden);
    c.onLifecycle(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 40));
    expect(c.phase, VoicePhase.closed);
    expect(h.app.tasks, isEmpty);
    expect(c.saved, isEmpty);
    expect(c.level, 0);
    expect(e.calls.length, callsAtClose);
    await h.dispose(tester);
  });
}
