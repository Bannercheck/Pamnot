import 'dart:async';
import 'dart:ui' show Locale;

import 'package:pamnot/services/speech/speech_engine.dart';

/// Scriptable engine for tests: the test decides what is "heard".
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({
    this.supported = true,
    this.availability = SpeechAvailability.ready,
    this.supportedLocales = const ['tr-TR', 'en-US'],
  });

  bool supported;
  SpeechAvailability availability;
  final List<String> supportedLocales;

  /// What the code under test asked for: `resolve`, `prepare:<id>`,
  /// `start:<id>`, `stop`, `cancel`.
  final List<String> calls = [];
  bool listening = false;

  /// False: stop() only sends [SpeechStopped]; the test delivers the text
  /// with [sendFinal] whenever it likes.
  bool finalOnStop = true;

  /// When set, prepare() waits for it before answering.
  Completer<void>? prepareGate;

  /// When set, start() waits for it before the engine reports it started.
  Completer<void>? startGate;

  /// When set, cancel() throws it (after recording the call).
  Object? cancelError;

  final _events = StreamController<SpeechEvent>.broadcast(sync: true);
  final _queue = <SpeechEvent>[];
  bool _firing = false;
  String _partial = '';

  /// Delivers [e] synchronously. Events raised by an engine call made from
  /// inside a handler (a sync controller would throw "Cannot fire new event")
  /// follow right after that handler returns, in order, as the real engine's
  /// would.
  void _emit(SpeechEvent e) {
    _queue.add(e);
    if (_firing) return;
    _firing = true;
    try {
      while (_queue.isNotEmpty) {
        _events.add(_queue.removeAt(0));
      }
    } catch (_) {
      _queue.clear();
      rethrow;
    } finally {
      _firing = false;
    }
  }

  @override
  bool get isSupported => supported;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  /// The exact tag first ("tr-TR"), then the same language code; '-' and '_'
  /// count as the same separator.
  @override
  Future<String?> resolveLocale(List<Locale> preferred) async {
    calls.add('resolve');
    String norm(String tag) => tag.replaceAll('_', '-');
    for (final l in preferred) {
      final tag = l.toLanguageTag();
      for (final s in supportedLocales) {
        if (norm(s) == tag) return s;
      }
      for (final s in supportedLocales) {
        if (norm(s).split('-').first == l.languageCode) return s;
      }
    }
    return null;
  }

  @override
  Future<SpeechAvailability> prepare(String localeId) async {
    calls.add('prepare:$localeId');
    final gate = prepareGate;
    if (gate != null) await gate.future;
    return availability;
  }

  @override
  Future<void> start(String localeId) async {
    calls.add('start:$localeId');
    final gate = startGate;
    if (gate != null) await gate.future;
    listening = true;
    _partial = '';
    _emit(const SpeechStarted());
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (!listening) return;
    listening = false;
    if (finalOnStop && _partial.isNotEmpty) _emit(SpeechFinal(_partial));
    _partial = '';
    _emit(const SpeechStopped());
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    final error = cancelError;
    if (error != null) throw error;
    if (!listening) return;
    listening = false;
    _partial = '';
    _emit(const SpeechStopped());
  }

  @override
  Future<void> dispose() => _events.close();

  // ---- test controls

  /// Simulates the user saying [text], one [SpeechPartial] per word.
  void say(String text) {
    final words = text.split(' ');
    for (var i = 1; i <= words.length; i++) {
      _partial = words.take(i).join(' ');
      _emit(SpeechPartial(_partial));
    }
  }

  /// A lone [SpeechFinal], whether or not the engine is listening.
  void sendFinal(String text) => _emit(SpeechFinal(text));

  void level(double v) => _emit(SpeechLevel(v));

  /// A [SpeechFailure] followed by [SpeechStopped]; listening ends.
  void fail(SpeechErrorKind kind, {bool permanent = true}) {
    listening = false;
    _partial = '';
    _emit(SpeechFailure(kind, permanent: permanent));
    _emit(const SpeechStopped());
  }
}
