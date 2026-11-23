import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

// fake_async and the platform interface come with flutter_test and
// speech_to_text; pubspec.yaml is not this task's file to change.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/services/speech/stt_speech_engine.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
// ignore: depend_on_referenced_packages
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Stands in for the native side of the plugin: records what the plugin asked
/// for and lets the test play the native callbacks, which the real
/// `SpeechToText` then filters exactly as it does on a device.
class FakeSttPlatform extends SpeechToTextPlatform {
  final calls = <String>[];
  bool initResult = true;
  PlatformException? initError;
  PlatformException? listenError;
  List<String> localeIds = ['en-US', 'tr-TR'];
  SpeechListenOptions? lastOptions;

  @override
  Future<bool> initialize({debugLogging = false, List<SpeechConfigOption>? options}) async {
    calls.add('initialize');
    final error = initError;
    if (error != null) throw error;
    return initResult;
  }

  /// The native side answers "id:display name" pairs.
  @override
  Future<List<dynamic>> locales() async {
    calls.add('locales');
    return [for (final id in localeIds) '$id:$id'];
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    calls.add('listen');
    lastOptions = options;
    final error = listenError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> cancel() async => calls.add('cancel');

  void emitResult(String words, {required bool isFinal}) => onTextRecognition!(jsonEncode(
      SpeechRecognitionResult.init([SpeechRecognitionWords(words, null, 0.9)],
              isFinal ? ResultType.finalResult : ResultType.partial)
          .toJson()));

  void emitStatus(String status) => onStatus!(status);

  void emitError(String msg, bool permanent) =>
      onError!(jsonEncode(SpeechRecognitionError(msg, permanent).toJson()));

  void emitLevel(double db) => onSoundLevel!(db);
}

String show(SpeechEvent e) => switch (e) {
      SpeechStarted() => 'Started',
      SpeechPartial(:final text) => 'Partial($text)',
      SpeechFinal(:final text) => 'Final($text)',
      SpeechLevel(:final level) => 'Level($level)',
      SpeechStopped() => 'Stopped',
      SpeechFailure(:final kind, :final permanent) => 'Failure(${kind.name}, permanent: $permanent)',
    };

void main() {
  late SpeechToTextPlatform original;
  late FakeSttPlatform platform;
  late SttSpeechEngine engine;
  late List<String> seen;

  int listens() => platform.calls.where((c) => c == 'listen').length;

  setUp(() {
    original = SpeechToTextPlatform.instance;
    platform = FakeSttPlatform();
    SpeechToTextPlatform.instance = platform;
    engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
    seen = [];
    engine.events.listen((e) => seen.add(show(e)));
  });

  tearDown(() async {
    await engine.dispose();
    SpeechToTextPlatform.instance = original;
  });

  test('pickLocale: tam eşleşme, sonra dil kodu, yoksa null', () {
    expect(pickLocale(const [Locale('tr', 'TR')], ['en-US', 'tr-TR']), 'tr-TR');
    expect(pickLocale(const [Locale('tr', 'TR')], ['en_US', 'tr_TR']), 'tr_TR');
    expect(pickLocale(const [Locale('en', 'TR')], ['en-GB', 'tr-TR']), 'en-GB');
    expect(pickLocale(const [Locale('de'), Locale('en', 'US')], ['en-US']), 'en-US');
    expect(pickLocale(const [Locale('de', 'DE')], ['en-US', 'tr-TR']), isNull);
  });

  test('mapSttError tablosu', () {
    expect(mapSttError('error_no_match', permanent: false).kind, SpeechErrorKind.noMatch);
    expect(mapSttError('error_speech_recognizer_disabled', permanent: true).kind, SpeechErrorKind.dictationDisabled);
    expect(mapSttError('error_speech_recognizer_request_not_authorized', permanent: true).kind, SpeechErrorKind.permission);
    expect(mapSttError('error_speech_recognizer_connection_interrupted', permanent: true).kind, SpeechErrorKind.interrupted);
    expect(mapSttError('error_retry', permanent: false).kind, SpeechErrorKind.network);
    expect(mapSttError('bilinmeyen', permanent: true).kind, SpeechErrorKind.unknown);
    // The rest of the table.
    expect(mapSttError('error_request_cancelled', permanent: true).kind, SpeechErrorKind.noMatch);
    expect(mapSttError('error_speech_recognizer_connection_invalidated', permanent: true).kind, SpeechErrorKind.interrupted);
    expect(mapSttError('error_listen_failed', permanent: true).kind, SpeechErrorKind.network);
    // iOS reports every error as permanent; "nothing heard" is still not one.
    expect(mapSttError('error_no_match', permanent: true).permanent, isFalse);
    expect(mapSttError('error_request_cancelled', permanent: true).permanent, isFalse);
    expect(mapSttError('error_speech_recognizer_disabled', permanent: true).permanent, isTrue);
    expect(mapSttError('error_retry', permanent: false).permanent, isFalse);
  });

  test('normalizeLevel 0..1 aralığında kalır', () {
    expect(normalizeLevel(-160), 0);
    expect(normalizeLevel(-25), 0.5);
    expect(normalizeLevel(10), 1);
    expect(normalizeLevel(double.negativeInfinity), 0);
  });

  test('start seçenekleri tasarımdaki gibi ve yerel ayar açık verilir', () async {
    expect(await engine.prepare('tr-TR'), SpeechAvailability.ready);
    await engine.start('tr-TR');
    final o = platform.lastOptions!;
    expect((o.partialResults, o.onDevice, o.autoPunctuation, o.cancelOnError), (true, false, false, false));
    expect(o.listenMode, ListenMode.confirmation);
    expect(o.localeId, 'tr-TR');
    expect(o.pauseFor, isNull);
    expect(o.listenFor, const Duration(seconds: 55));
  });

  test('önceki oturum bitmeden ikinci listen çağrılmaz', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening'); // iOS sends it before the listen call returns
    unawaited(engine.stop());
    final second = engine.start('tr-TR'); // sıraya girer
    await pumpEventQueue();
    expect(listens(), 1);
    // The plugin passes "done" on only after the final text, so a device
    // sends the final result first; on its own it does not end the session.
    platform.emitResult('süt al', isFinal: true);
    await pumpEventQueue();
    expect(listens(), 1);
    platform.emitStatus('done'); // ilk oturum bitti
    await pumpEventQueue(); // well before the 3 s fallback could fire
    expect(listens(), 2);
    await second;
    expect(seen, ['Started', 'Final(süt al)', 'Stopped']);
    expect(platform.calls, isNot(contains('cancel'))); // an ending session is waited for
  });

  test('stop sonrası hiçbir şey duyulmadan bitiş: doneNoResult oturumu hemen kapatır', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    await engine.stop();
    platform.emitStatus('done'); // the plugin swallows this one: no text yet
    await pumpEventQueue();
    expect(seen, ['Started']);
    platform.emitStatus('doneNoResult'); // iOS: the recognition task ended
    await pumpEventQueue();
    expect(seen, ['Started', 'Stopped']);
    await engine.start('tr-TR');
    expect(listens(), 2);
  });

  test('bitiş bildirimi gelmezse sıra 3 sn sonra açılır', () {
    fakeAsync((async) {
      // Built inside the fake zone so its queue and timers run on fake time.
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      platform.emitStatus('listening');
      engine.stop();
      engine.start('tr-TR');
      async.flushMicrotasks();
      expect(listens(), 1);
      async.elapse(const Duration(milliseconds: 2999));
      expect(listens(), 1);
      expect(seen, ['Started']);
      async.elapse(const Duration(milliseconds: 1));
      expect(listens(), 2);
      expect(seen, ['Started', 'Stopped']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('eklenti dinlemeyi bırakıp bitişi bildirmezse oturum 3 sn sonra biter', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      platform.emitStatus('listening');
      platform.emitStatus('notListening'); // the microphone is off, no "done"
      async.elapse(const Duration(milliseconds: 2999));
      expect(seen, ['Started']);
      async.elapse(const Duration(milliseconds: 1));
      expect(seen, ['Started', 'Stopped']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('metinsiz done sonrası stop oturumu hemen bitirir', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    platform.emitStatus('doneNoResult'); // the error would follow, but...
    await engine.stop(); // ...after stop the plugin drops it
    await pumpEventQueue();
    expect(seen, ['Started', 'Stopped']);
    expect(platform.calls, isNot(contains('stop'))); // nothing left to stop
  });

  test('olay sırası: Started, Partial, Final, Stopped (bir kez)', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    platform.emitResult('süt', isFinal: false);
    platform.emitResult('süt al', isFinal: true);
    platform.emitStatus('done');
    platform.emitStatus('done');
    await pumpEventQueue();
    expect(seen, ['Started', 'Partial(süt)', 'Final(süt al)', 'Stopped']);
  });

  test('ses düzeyi normalizeLevel ile 0..1 gelir', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    platform.emitLevel(-25);
    platform.emitLevel(-160);
    await pumpEventQueue();
    expect(seen, ['Started', 'Level(0.5)', 'Level(0.0)']);
  });

  test('iOS hatayı done ardından gönderir; Failure yine Stopped öncesinde gelir', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    // didFinishSuccessfully(false): status first, then the error.
    platform.emitStatus('doneNoResult');
    await pumpEventQueue();
    expect(seen, ['Started']);
    platform.emitError('error_speech_recognizer_disabled', true);
    await pumpEventQueue();
    expect(seen, ['Started', 'Failure(dictationDisabled, permanent: true)', 'Stopped']);
    await engine.start('tr-TR');
    expect(listens(), 2);
  });

  test('cancel tamamlanınca oturum biter: yalnız Stopped, sonraki listen beklemez', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    platform.emitResult('süt', isFinal: false);
    await engine.cancel();
    platform.emitResult('süt al', isFinal: true); // late text of the cancelled session
    await pumpEventQueue();
    expect(seen, ['Started', 'Partial(süt)', 'Stopped']);
    await engine.start('tr-TR'); // no "done" needed
    expect(platform.calls.where((c) => c != 'locales'), ['initialize', 'listen', 'cancel', 'listen']);
  });

  test('dinleyen oturum varken start önce onu iptal eder', () async {
    await engine.prepare('tr-TR');
    await engine.start('tr-TR');
    platform.emitStatus('listening');
    await engine.start('tr-TR');
    expect(platform.calls.where((c) => c != 'locales'), ['initialize', 'listen', 'cancel', 'listen']);
    await pumpEventQueue();
    expect(seen, ['Started', 'Stopped']);
  });

  test('iptal edilen oturumun geç gelen durumları ve hatası sonraki oturuma işlemez', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      platform.emitStatus('listening');
      engine.cancel();
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped']);
      engine.start('tr-TR');
      async.flushMicrotasks();
      expect(listens(), 2);
      // cancelSpeech replies before the cancelled task's delegates run, and
      // the next listen() has already reset the plugin's _userEnded, so the
      // plugin passes all of these on. The new session has not reported
      // "listening" yet.
      platform.emitStatus('notListening'); // speechRecognitionTaskWasCancelled
      platform.emitResult('süt', isFinal: false); // a hypothesis still in flight
      platform.emitStatus('doneNoResult'); // didFinishSuccessfully(false)...
      platform.emitError('error_request_cancelled', true); // ...its error...
      platform.emitStatus('done'); // ...and its stopCurrentListen()
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped']);
      platform.emitStatus('listening'); // the new session's own
      async.elapse(const Duration(seconds: 10));
      expect(seen, ['Started', 'Stopped', 'Started']); // no failure, no 3 s end
      platform.emitResult('süt al', isFinal: true);
      platform.emitStatus('done');
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped', 'Started', 'Final(süt al)', 'Stopped']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('hiçbir şey duyulmadan biten oturumun geç hatası yeniden başlayan oturuma işlemez', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      var restarted = false;
      engine.events.listen((e) {
        seen.add(show(e));
        // The voice screen's re-listen loop: start again on Stopped.
        if (e is SpeechStopped && !restarted) {
          restarted = true;
          engine.start('tr-TR');
        }
      });
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      platform.emitStatus('listening');
      engine.stop();
      async.flushMicrotasks();
      platform.emitStatus('done'); // stopSpeech's own; the plugin swallows it (no text)
      platform.emitStatus('notListening');
      platform.emitStatus('doneNoResult'); // nothing heard
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped']);
      expect(listens(), 2);
      // didFinishSuccessfully(false) sent its error right after that status,
      // but the restart's listen() ran first and reset the plugin's _userEnded.
      platform.emitError('error_retry', true);
      platform.emitStatus('done');
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped']);
      platform.emitStatus('listening');
      async.elapse(const Duration(seconds: 10));
      expect(seen, ['Started', 'Stopped', 'Started']);
      platform.emitResult('süt', isFinal: false);
      async.flushMicrotasks();
      expect(seen, ['Started', 'Stopped', 'Started', 'Partial(süt)']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('listening hiç gelmezse oturum 3 sn sonra Failure(unknown) ile biter, eklenti iptal edilir', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      // listenForSpeech failed natively: the call returned without
      // "listening". What follows cannot be told apart from a previous
      // task's late callbacks, so it does not count.
      platform.emitStatus('notListening');
      platform.emitError('error_listen_failed', true);
      platform.emitStatus('doneNoResult');
      async.elapse(const Duration(milliseconds: 2999));
      expect(seen, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(seen, ['Failure(unknown, permanent: true)', 'Stopped']);
      engine.start('tr-TR');
      async.flushMicrotasks();
      // Whatever the plugin still held is cancelled before the next listen.
      expect(platform.calls.where((c) => c != 'locales'), ['initialize', 'listen', 'cancel', 'listen']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('listen hata fırlatırsa yalnız bir Failure ve Stopped, sonra başka olay yok', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      async.flushMicrotasks();
      platform.listenError = PlatformException(code: 'noRecognizerError');
      engine.start('tr-TR');
      async.elapse(const Duration(seconds: 10));
      expect(seen, ['Failure(unknown, permanent: true)', 'Stopped']);
      expect(platform.calls, isNot(contains('cancel')));
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('listening gelmeden stop: Failure yok, oturum 3 sn içinde biter', () {
    fakeAsync((async) {
      final engine = SttSpeechEngine(stt: SpeechToText.withMethodChannel());
      final seen = <String>[];
      engine.events.listen((e) => seen.add(show(e)));
      engine.prepare('tr-TR');
      engine.start('tr-TR');
      async.flushMicrotasks();
      engine.stop();
      async.elapse(const Duration(seconds: 3));
      expect(seen, ['Stopped']);
      engine.dispose();
      async.flushMicrotasks();
    });
  });

  test('listen başarısız olursa Failure ve Stopped, sıra kilitlenmez', () async {
    await engine.prepare('tr-TR');
    platform.listenError = PlatformException(code: 'noRecognizerError', message: 'Failed to create speech recognizer');
    await engine.start('tr-TR');
    await pumpEventQueue();
    expect(seen, ['Failure(unknown, permanent: true)', 'Stopped']);
    platform.listenError = null;
    await engine.start('tr-TR');
    expect(listens(), 2);
  });

  test('prepare: izin reddi permissionDenied, bilinmeyen yerel ayar unsupportedLocale', () async {
    platform.initResult = false;
    expect(await engine.prepare('tr-TR'), SpeechAvailability.permissionDenied);
    platform.initResult = true; // allowed later in Settings: asked again
    expect(await engine.prepare('de-DE'), SpeechAvailability.unsupportedLocale);
    expect(await engine.prepare('tr_TR'), SpeechAvailability.ready);
    expect(platform.calls.where((c) => c == 'initialize').length, 2);
  });

  test('prepare: ikinci çağrıda eklenti yeniden başlatılmaz', () async {
    expect(await engine.prepare('tr-TR'), SpeechAvailability.ready);
    expect(await engine.prepare('tr-TR'), SpeechAvailability.ready);
    expect(platform.calls, ['initialize', 'locales', 'locales']);
  });

  test('prepare: eklenti hata fırlatırsa unavailable', () async {
    platform.initError = PlatformException(code: 'recognizerNotAvailable');
    expect(await engine.prepare('tr-TR'), SpeechAvailability.unavailable);
  });

  test('resolveLocale eklentinin dil listesinden seçer', () async {
    expect(await engine.resolveLocale(const [Locale('tr', 'TR')]), 'tr-TR');
    expect(await engine.resolveLocale(const [Locale('de', 'DE')]), isNull);
    expect(platform.calls, ['locales', 'locales']);
  });

  test('createSpeechEngine iOS dışında eklentiye dokunmaz', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final e = createSpeechEngine();
    expect(e, isA<UnsupportedSpeechEngine>());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(createSpeechEngine(), isA<SttSpeechEngine>());
    expect(createSpeechEngine().isSupported, isTrue);
    expect(platform.calls, isEmpty); // kurmak eklentiyi çağırmaz
  });
}
