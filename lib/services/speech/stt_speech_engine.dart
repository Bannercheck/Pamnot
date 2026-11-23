import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_engine.dart';

/// iOS gets [SttSpeechEngine]; every other platform, web included, gets
/// [UnsupportedSpeechEngine], so the speech plugin is never called there.
/// Building the engine does not call the plugin either.
SpeechEngine createSpeechEngine() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? SttSpeechEngine() : UnsupportedSpeechEngine();

String _normTag(String tag) => tag.replaceAll('_', '-').toLowerCase();

/// The recogniser locale for the phone's languages, taken in order of
/// preference: for each language the exact tag first, then the same language
/// code. '-' and '_' are the same separator. Returns the entry of [supported]
/// as written, or null when none matches.
String? pickLocale(List<Locale> preferred, List<String> supported) {
  for (final locale in preferred) {
    final tag = _normTag(locale.toLanguageTag());
    for (final s in supported) {
      if (_normTag(s) == tag) return s;
    }
    final language = locale.languageCode.toLowerCase();
    for (final s in supported) {
      if (_normTag(s).split('-').first == language) return s;
    }
  }
  return null;
}

/// Maps the plugin's error code to what the voice screen shows. iOS reports
/// every error as permanent; "nothing heard" is never one.
SpeechFailure mapSttError(String errorMsg, {required bool permanent}) {
  final kind = switch (errorMsg) {
    'error_no_match' || 'error_request_cancelled' => SpeechErrorKind.noMatch,
    'error_speech_recognizer_request_not_authorized' => SpeechErrorKind.permission,
    'error_speech_recognizer_disabled' => SpeechErrorKind.dictationDisabled,
    'error_speech_recognizer_connection_interrupted' ||
    'error_speech_recognizer_connection_invalidated' =>
      SpeechErrorKind.interrupted,
    'error_retry' || 'error_listen_failed' => SpeechErrorKind.network,
    _ => SpeechErrorKind.unknown,
  };
  return SpeechFailure(kind, permanent: kind != SpeechErrorKind.noMatch && permanent);
}

/// The plugin's input level in dB (iOS) as 0..1: -50 dB and below is 0,
/// 0 dB and above is 1.
double normalizeLevel(double db) => ((db + 50) / 50).clamp(0.0, 1.0);

/// One `listen()` of the plugin, from the call until it is over.
class _Session {
  final ended = Completer<void>();
  bool get isEnded => ended.isCompleted;

  /// The plugin reported "listening" for this session. Until then its
  /// statuses, errors and results are not this session's.
  bool started = false;

  /// Ends a session whose listen call returned without "listening".
  Timer? startDeadline;

  bool heardFinal = false;
  bool failed = false;

  /// stop() asked for the end; from then on the plugin drops errors.
  bool stopRequested = false;

  /// The plugin said "done" with no text, so iOS's error report is on its way.
  bool doneWithoutText = false;

  /// Counts the session as ended if the plugin never reports it; set once the
  /// session is ending.
  Timer? fallback;
}

/// [SpeechEngine] on the `speech_to_text` plugin (design §6.3).
///
/// Every plugin call goes through one queue, and `listen` is never called
/// before the previous session is over: open plugin crash #680 is a `listen`
/// that overlaps the previous session. A session is over when the plugin
/// reports "done" or when `cancel` completes. A session that is ending
/// (stop() was called, or the plugin stopped listening or failed) counts as
/// over after [endFallback] even without that report, so the queue never
/// locks.
///
/// The plugin reports "done" only once it has the final text. A session that
/// ends on its own with no final text (iOS: the recognition task failed) gets
/// "done" first and the error right after it; the session stays open until the
/// error arrives, so [SpeechFailure] still comes before [SpeechStopped].
///
/// The plugin's statuses and errors carry no session, and an ended session's
/// recognition task can still report after the next `listen` (a cancelled
/// task's "notListening", "done" and error; the error that follows a
/// text-less "done" once the next session has started). A session therefore
/// takes statuses other than "listening", errors and results only after its
/// own "listening": iOS sends that from inside the native `listen`, after
/// everything the previous task had already sent. A session whose listen call
/// returns without "listening" did not start; it ends after [endFallback] with
/// [SpeechFailure] (unknown), and the plugin is cancelled before the next
/// `listen`.
class SttSpeechEngine implements SpeechEngine {
  SttSpeechEngine({SpeechToText? stt}) : _stt = stt ?? SpeechToText();

  static const endFallback = Duration(seconds: 3);

  final SpeechToText _stt;
  final _events = StreamController<SpeechEvent>.broadcast();
  Future<void> _tail = Future.value();
  bool _initialized = false;
  _Session? _session;

  @override
  bool get isSupported => true;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  /// Runs [op] once every plugin call queued before it has finished.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<String?> resolveLocale(List<Locale> preferred) => _serial(() async {
        final locales = await _stt.locales();
        return pickLocale(preferred, [for (final l in locales) l.localeId]);
      });

  @override
  Future<SpeechAvailability> prepare(String localeId) => _serial(() async {
        try {
          if (!_initialized) {
            // The first call shows the speech-recognition and microphone
            // prompts; after a refusal it only reports it again.
            if (!await _stt.initialize(onError: _onError, onStatus: _onStatus)) {
              return SpeechAvailability.permissionDenied;
            }
            _initialized = true;
          }
          final locales = await _stt.locales();
          final known = locales.any((l) => _normTag(l.localeId) == _normTag(localeId));
          return known ? SpeechAvailability.ready : SpeechAvailability.unsupportedLocale;
        } on PlatformException {
          return SpeechAvailability.unavailable;
        }
      });

  @override
  Future<void> start(String localeId) => _serial(() async {
        final previous = _session;
        if (previous != null && !previous.isEnded) {
          // A session still listening is discarded; one that is ending is
          // waited for.
          if (previous.fallback == null) await _cancel(previous);
          await previous.ended.future;
        }
        final s = _session = _Session();
        try {
          await _stt.listen(
            onResult: (r) => _onResult(s, r),
            onSoundLevelChange: (db) => _onLevel(s, db),
            listenOptions: SpeechListenOptions(
              partialResults: true,
              onDevice: false,
              autoPunctuation: false,
              cancelOnError: false,
              listenMode: ListenMode.confirmation,
              localeId: localeId,
              listenFor: const Duration(seconds: 55),
            ),
          );
        } on ListenFailedException {
          s.failed = true;
          _emit(const SpeechFailure(SpeechErrorKind.unknown));
          _end(s);
          return;
        }
        if (!s.started) {
          s.startDeadline = Timer(endFallback, () => _onNeverStarted(s));
        }
      });

  @override
  Future<void> stop() => _serial(() async {
        final s = _session;
        if (s == null || s.isEnded) return;
        s.stopRequested = true;
        if (s.doneWithoutText) {
          // Already over. The error that was due is dropped: by the plugin
          // until the next listen, by the next session until its "listening".
          _end(s);
          return;
        }
        _armFallback(s);
        await _stt.stop();
      });

  @override
  Future<void> cancel() => _serial(() async {
        final s = _session;
        if (s != null && !s.isEnded) await _cancel(s);
      });

  @override
  Future<void> dispose() async {
    await cancel();
    await _events.close();
  }

  Future<void> _cancel(_Session s) async {
    try {
      await _stt.cancel();
    } finally {
      _end(s);
    }
  }

  void _onStatus(String status) {
    final s = _session;
    if (s == null || s.isEnded) return;
    if (status == SpeechToText.listeningStatus) {
      if (!s.started) {
        s.started = true;
        s.startDeadline?.cancel();
        _emit(const SpeechStarted());
      }
      return;
    }
    if (!s.started) return; // a previous task's
    switch (status) {
      case SpeechToText.notListeningStatus:
        _armFallback(s);
      case SpeechToText.doneStatus:
        if (s.heardFinal || s.failed || s.stopRequested) {
          _end(s);
        } else {
          s.doneWithoutText = true;
          _armFallback(s);
        }
    }
  }

  void _onError(SpeechRecognitionError error) {
    final s = _session;
    if (s == null || s.isEnded || !s.started) return;
    final failure = mapSttError(error.errorMsg, permanent: error.permanent);
    s.failed = true;
    _emit(failure);
    if (s.doneWithoutText) {
      _end(s);
    } else if (failure.permanent) {
      _armFallback(s);
    }
  }

  void _onResult(_Session s, SpeechRecognitionResult result) {
    // The plugin hands results to the latest listen's callback, so a previous
    // task's late text would land here before "listening".
    if (s.isEnded || !s.started) return;
    if (result.finalResult) {
      s.heardFinal = true;
      _emit(SpeechFinal(result.recognizedWords));
    } else {
      _emit(SpeechPartial(result.recognizedWords));
    }
  }

  void _onLevel(_Session s, double db) {
    if (!s.isEnded) _emit(SpeechLevel(normalizeLevel(db)));
  }

  void _armFallback(_Session s) => s.fallback ??= Timer(endFallback, () => _end(s));

  /// The listen call returned [endFallback] ago and "listening" never came:
  /// the native listen failed, or the plugin refused it because an earlier
  /// task was still running. Nothing it reported since counted, so this is
  /// the session's only end report.
  void _onNeverStarted(_Session s) {
    if (!s.stopRequested) _emit(const SpeechFailure(SpeechErrorKind.unknown));
    _end(s);
    // Whatever the plugin still holds is cancelled before the next listen,
    // unless a start() waiting for this session got there first (only after
    // stop(), which already reached the plugin).
    _serial(() async {
      if (identical(_session, s)) await _stt.cancel();
    }).ignore();
  }

  /// Ends [s] once: [SpeechStopped], then the queue moves on.
  void _end(_Session s) {
    if (s.isEnded) return;
    s.fallback?.cancel();
    s.startDeadline?.cancel();
    _emit(const SpeechStopped());
    s.ended.complete();
  }

  void _emit(SpeechEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
