import 'dart:ui' show Locale;

/// Whether the engine can listen right now. The voice screen shows one state
/// per value.
enum SpeechAvailability {
  ready,

  /// Microphone or speech-recognition access is off (only Settings can fix it).
  permissionDenied,

  /// No recogniser for the requested language on this device.
  unsupportedLocale,

  /// A recogniser exists but cannot be used at the moment.
  unavailable,

  /// No implementation on this platform (everything but iOS, and tests by
  /// default).
  unsupportedPlatform,
}

enum SpeechErrorKind {
  /// Nothing recognisable was said. Treated as silence, not shown as an error.
  noMatch,

  /// Microphone or speech-recognition access was refused.
  permission,

  /// Siri & Dictation is turned off in the system settings.
  dictationDisabled,

  /// The audio session was taken away (a call, another app, the app leaving
  /// the foreground).
  interrupted,
  network,
  unknown,
}

/// Everything the voice screen reacts to arrives as one of these, in order.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// Capturing started (the microphone indicator is on).
class SpeechStarted extends SpeechEvent {
  const SpeechStarted();
}

/// Live transcript of the current utterance so far; replaces the previous one.
class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);
  final String text;
}

/// The recogniser's final text for the utterance.
class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);
  final String text;
}

/// Input level normalised to 0..1.
class SpeechLevel extends SpeechEvent {
  const SpeechLevel(this.level);
  final double level;
}

/// Capturing ended (after stop(), cancel(), a platform timeout or an error).
class SpeechStopped extends SpeechEvent {
  const SpeechStopped();
}

class SpeechFailure extends SpeechEvent {
  const SpeechFailure(this.kind, {this.permanent = true});
  final SpeechErrorKind kind;

  /// A permanent failure ends the session; a transient one may be retried.
  final bool permanent;
}

/// One-utterance speech recogniser. One session is one utterance; the UI owns
/// all timing, so a fake engine plus `tester.pump(duration)` drives every
/// state without a device.
abstract class SpeechEngine {
  /// Whether this platform has an engine at all. Never touches the plugin.
  bool get isSupported;

  /// Events for the current and future sessions (a broadcast stream).
  Stream<SpeechEvent> get events;

  /// Picks the recogniser locale for the phone's languages, in order of
  /// preference: an exact tag first, then the same language code. Null when
  /// none is supported. Never asks for permissions.
  Future<String?> resolveLocale(List<Locale> preferred);

  /// Asks for microphone and speech-recognition access when needed (the
  /// system prompts appear the first time) and checks that [localeId] can be
  /// recognised.
  Future<SpeechAvailability> prepare(String localeId);

  /// Starts capturing one utterance in [localeId].
  Future<void> start(String localeId);

  /// Stops capturing: [SpeechFinal] for what was heard, then [SpeechStopped].
  Future<void> stop();

  /// Stops capturing and discards the utterance: only [SpeechStopped].
  Future<void> cancel();

  Future<void> dispose();
}

/// The default engine: never listens and never calls the speech plugin.
class UnsupportedSpeechEngine implements SpeechEngine {
  @override
  bool get isSupported => false;

  @override
  Stream<SpeechEvent> get events => const Stream.empty();

  @override
  Future<String?> resolveLocale(List<Locale> preferred) async => null;

  @override
  Future<SpeechAvailability> prepare(String localeId) async => SpeechAvailability.unsupportedPlatform;

  @override
  Future<void> start(String localeId) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
