import 'dart:async';
import 'dart:ui' show AppLifecycleState, Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/spoken/parse.dart';
import '../../core/spoken/spoken_task.dart';
import '../../services/speech/speech_engine.dart';
import '../../state/app_controller.dart';

/// Every timing of the voice screen (design §5). They live in Dart only.
abstract final class VoiceTimings {
  /// Wait before the first listen so Siri's audio session is released.
  static const startDelay = Duration(milliseconds: 300);

  /// No new partial result for this long ends the utterance.
  static const utteranceGap = Duration(milliseconds: 1600);

  /// How long the preview is shown before it is saved.
  static const previewHold = Duration(seconds: 2);

  /// Silence in a listen after a save closes the screen.
  static const idleClose = Duration(seconds: 6);

  /// The longest a single listen lasts.
  static const maxListen = Duration(seconds: 30);

  /// Longer than this in the background closes the screen on return.
  static const backgroundClose = Duration(minutes: 5);
}

enum VoicePhase {
  preparing,
  listening,
  preview,
  editing,
  saved,
  paused,
  error,
  permissionDenied,
  dictationOff,
  unsupportedLocale,
  unsupportedPlatform,
  closed,
}

/// One thing saved from the voice screen; the screen lists them and can undo
/// each.
class SavedItem {
  const SavedItem({
    required this.id,
    required this.isNote,
    required this.title,
    this.due,
    this.hasTime = false,
    this.reminder = false,
    this.inBackground = false,
  });

  /// The task's or the note's id.
  final String id;
  final bool isNote;

  /// The task title; the note's text when [isNote].
  final String title;
  final DateTime? due;
  final bool hasTime;

  /// A notification is set for the task.
  final bool reminder;

  /// Saved because the app left the foreground ("saved while locking").
  final bool inBackground;
}

/// The voice screen's state machine (design §5, §6.3, §6.6): listens, shows
/// the parsed task, saves it after a short preview and listens again. All
/// timing lives here; the [SpeechEngine] only reports what it heard.
///
/// The microphone state follows the engine's events, never a timer: the
/// phase becomes [VoicePhase.listening] on [SpeechStarted] and leaves it on
/// [SpeechStopped].
class VoiceCaptureController extends ChangeNotifier {
  VoiceCaptureController({
    required this.app,
    required this.engine,
    List<Locale> Function()? deviceLocales,
    this.onSaved,
  }) : _deviceLocales = deviceLocales ?? (() => PlatformDispatcher.instance.locales);

  final AppController app;
  final SpeechEngine engine;
  final List<Locale> Function() _deviceLocales;

  /// Called right after each save, while the microphone is off (haptics).
  final VoidCallback? onSaved;

  VoicePhase _phase = VoicePhase.preparing;
  String _transcript = '';
  SpokenTask? _preview;
  double _level = 0;
  final List<SavedItem> _saved = [];
  String? _localeId;
  String _lang = 'en';
  bool _accessible = false;

  StreamSubscription<SpeechEvent>? _events;
  Timer? _startTimer, _gapTimer, _holdTimer, _idleTimer, _maxTimer;
  bool _closed = false;
  bool _disposed = false;

  /// engine.start was called and its [SpeechStarted] has not come yet.
  bool _awaitingStart = false;

  /// Between this screen's [SpeechStarted] and the matching [SpeechStopped].
  bool _inSession = false;

  /// The latest partial and the first final text of the current session.
  String _partial = '';
  String? _final;

  /// prepare() answered ready for [_localeId].
  bool _prepared = false;

  /// What the recogniser heard for the preview being shown (the voice log
  /// keeps this, not the typed correction).
  String _heard = '';

  /// The app is in the foreground (resumed, or only inactive).
  bool _foreground = true;

  /// When the app went to the background; null in the foreground.
  DateTime? _backgroundAt;

  /// The opening steps wait for the app to come to the foreground.
  bool _openOnResume = false;

  VoicePhase get phase => _phase;

  /// The live transcript, or the correction draft while editing.
  String get transcript => _transcript;

  /// The live or the last parse of [transcript].
  SpokenTask? get preview => _preview;

  /// Input level, 0..1.
  double get level => _level;

  /// Saved this time the screen was open, newest first.
  List<SavedItem> get saved => List.unmodifiable(_saved);

  String? get localeId => _localeId;

  /// VoiceOver or Switch Control is on (compliance §4.2-3): the preview is not
  /// saved on a timer, the screen does not close on silence and listening
  /// does not restart by itself after a save.
  bool get accessible => _accessible;
  set accessible(bool value) {
    if (value == _accessible) return;
    _accessible = value;
    if (value) {
      _holdTimer?.cancel();
      _idleTimer?.cancel();
    }
  }

  // ------------------------------------------------------------------ opening

  /// Starts listening once the app is in the foreground ([lifecycle] null or
  /// resumed), after [VoiceTimings.startDelay]. Permissions are asked here,
  /// by the engine's prepare(), and nowhere else.
  Future<void> open({AppLifecycleState? lifecycle}) async {
    if (_closed || _events != null) return;
    _events = engine.events.listen(_onEvent);
    if (!engine.isSupported) return _setPhase(VoicePhase.unsupportedPlatform);
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleOpen();
    } else {
      _openOnResume = true;
    }
  }

  void _scheduleOpen() {
    _startTimer?.cancel();
    _startTimer = Timer(VoiceTimings.startDelay, () => unawaited(_prepareAndListen()));
  }

  Future<void> _prepareAndListen() async {
    if (_closed) return;
    if (!_foreground) {
      _openOnResume = true;
      return;
    }
    try {
      final locale = await engine.resolveLocale(_deviceLocales());
      if (_closed) return;
      if (locale == null) return _setPhase(VoicePhase.unsupportedLocale);
      _localeId = locale;
      _lang = locale.split(RegExp('[-_]')).first.toLowerCase();
      final availability = await engine.prepare(locale);
      if (_closed) return;
      switch (availability) {
        case SpeechAvailability.ready:
          _prepared = true;
          // Left while the permission prompts were up: start on return.
          if (!_foreground) {
            _openOnResume = true;
            return;
          }
          await _listen();
        case SpeechAvailability.permissionDenied:
          _setPhase(VoicePhase.permissionDenied);
        case SpeechAvailability.unsupportedLocale:
          _setPhase(VoicePhase.unsupportedLocale);
        case SpeechAvailability.unavailable:
          _setPhase(VoicePhase.error);
        case SpeechAvailability.unsupportedPlatform:
          _setPhase(VoicePhase.unsupportedPlatform);
      }
    } catch (e) {
      debugPrint('Voice capture could not start: $e');
      if (!_closed) _setPhase(VoicePhase.error);
    }
  }

  // ---------------------------------------------------------------- listening

  /// Starts one listen, only in the foreground. The phase changes when the
  /// engine reports it started.
  Future<void> _listen() async {
    final locale = _localeId;
    if (_closed || !_foreground || locale == null || _awaitingStart || _inSession) return;
    _awaitingStart = true;
    _partial = '';
    _final = null;
    try {
      await engine.start(locale);
    } catch (e) {
      debugPrint('Voice capture could not listen: $e');
      if (_closed || !_awaitingStart) return;
      _awaitingStart = false;
      _setPhase(VoicePhase.error);
    }
  }

  void _onEvent(SpeechEvent e) {
    if (_closed) return;
    switch (e) {
      case SpeechStarted():
        _onStarted();
      case SpeechPartial(:final text):
        _onPartial(text);
      case SpeechFinal(:final text):
        _onFinal(text);
      case SpeechLevel(:final level):
        if (!_inSession) return;
        _level = level.clamp(0.0, 1.0);
        _notify();
      case SpeechStopped():
        _onStopped();
      case SpeechFailure(:final kind):
        _onFailure(kind);
    }
  }

  void _onStarted() {
    // Only the start this screen asked for; anything else is stale.
    if (!_awaitingStart) return;
    _awaitingStart = false;
    _inSession = true;
    _transcript = '';
    _preview = null;
    _maxTimer = Timer(VoiceTimings.maxListen, _stopListening);
    _armIdleClose();
    _setPhase(VoicePhase.listening);
  }

  /// After a save, a listen with nothing said closes the screen. The timer
  /// keeps running across a listen that ended without text.
  void _armIdleClose() {
    if (_saved.isEmpty || _accessible || (_idleTimer?.isActive ?? false)) return;
    _idleTimer = Timer(VoiceTimings.idleClose, () => unawaited(close()));
  }

  void _onPartial(String text) {
    if (!_inSession || _final != null) return;
    _partial = text;
    _transcript = text;
    _preview = parseSpokenTask(text, app.now(), _lang);
    _gapTimer?.cancel();
    _gapTimer = Timer(VoiceTimings.utteranceGap, _stopListening);
    _idleTimer?.cancel();
    _notify();
  }

  void _onFinal(String text) {
    // Only the first final of a session counts, and only once this session
    // has heard something: a final with no partial before it is a previous
    // session's late result.
    if (!_inSession || _final != null || _partial.isEmpty) return;
    _final = text;
  }

  void _onStopped() {
    if (!_inSession) return;
    _inSession = false;
    _level = 0;
    _cancelListenTimers();
    final text = (_final ?? _partial).trim();
    final parsed = text.isEmpty ? null : parseSpokenTask(text, app.now(), _lang);
    if (parsed == null || parsed.title.trim().isEmpty) return _endWithoutText();
    _heard = text;
    _transcript = text;
    _preview = parsed;
    _setPhase(VoicePhase.preview);
    if (!_accessible) _holdTimer = Timer(VoiceTimings.previewHold, () => unawaited(_save()));
  }

  /// A failure ends the session as far as this screen is concerned: what was
  /// heard is dropped and the session's own [SpeechStopped] is ignored.
  /// "Nothing recognised" is not a failure; the listen just ends empty.
  void _onFailure(SpeechErrorKind kind) {
    if (!_inSession && !_awaitingStart) return;
    final phase = switch (kind) {
      SpeechErrorKind.noMatch => null,
      SpeechErrorKind.permission => VoicePhase.permissionDenied,
      SpeechErrorKind.dictationDisabled => VoicePhase.dictationOff,
      SpeechErrorKind.interrupted => VoicePhase.paused,
      SpeechErrorKind.network || SpeechErrorKind.unknown => VoicePhase.error,
    };
    if (phase == null) return;
    _awaitingStart = false;
    _inSession = false;
    _level = 0;
    _cancelListenTimers();
    _idleTimer?.cancel();
    _setPhase(phase);
  }

  /// A listen ended with nothing to save: before the first save the screen
  /// waits for a tap; after it, it listens again and closes on silence.
  void _endWithoutText() {
    _transcript = '';
    _preview = null;
    if (_saved.isEmpty || _accessible) return _setPhase(VoicePhase.paused);
    // The microphone is off until the engine reports the next start.
    _setPhase(VoicePhase.preparing);
    unawaited(_listen());
  }

  void _stopListening() {
    _gapTimer?.cancel();
    if (_inSession) unawaited(engine.stop());
  }

  void _cancelListenTimers() {
    for (final t in [_gapTimer, _maxTimer]) {
      t?.cancel();
    }
  }

  /// While listening: stops and previews what was said. After a save, a
  /// pause or an error: listens again.
  void toggleMic() {
    switch (_phase) {
      case VoicePhase.listening:
        _stopListening();
      case VoicePhase.error when !_prepared:
        _setPhase(VoicePhase.preparing);
        unawaited(_prepareAndListen());
      case VoicePhase.saved || VoicePhase.paused || VoicePhase.error:
        unawaited(_listen());
      default:
    }
  }

  // ---------------------------------------------------------- preview and edit

  /// Preview → correction: the countdown stops and [transcript] becomes the
  /// draft.
  void edit() {
    if (_phase != VoicePhase.preview) return;
    _holdTimer?.cancel();
    _setPhase(VoicePhase.editing);
  }

  /// The correction draft changed; the preview follows it.
  void updateDraft(String text) {
    if (_phase != VoicePhase.editing) return;
    _transcript = text;
    _preview = parseSpokenTask(text, app.now(), _lang);
    _notify();
  }

  /// Saves the task in preview or in the draft now, then listens again.
  Future<void> saveNow() async {
    if (_phase != VoicePhase.preview && _phase != VoicePhase.editing) return;
    await _save();
  }

  /// Deletes a saved task or note; one already deleted elsewhere is fine.
  void undo(SavedItem item) {
    if (item.isNote) {
      app.deleteNote(item.id);
    } else {
      app.deleteTask(item.id);
    }
    _saved.removeWhere((s) => s.id == item.id);
    _notify();
  }

  // ------------------------------------------------------------------- saving

  /// Saves the preview in the foreground: the microphone is off now. A task
  /// with a reminder asks for notifications before listening again.
  Future<void> _save() async {
    final item = _commit();
    if (item == null) return;
    _setPhase(VoicePhase.saved);
    onSaved?.call();
    if (item.reminder && _foreground) await app.ensureNotificationPermission();
    if (_closed || _accessible || _phase != VoicePhase.saved) return;
    await _listen();
  }

  /// Adds the previewed task or note to the app and to [saved].
  SavedItem? _commit({bool inBackground = false}) {
    _holdTimer?.cancel();
    final p = _preview;
    final locale = _localeId;
    if (_closed || p == null || locale == null) return null;
    final SavedItem item;
    if (p.isNote) {
      final n = app.addSpokenNote(p.title);
      if (n == null) return null;
      item = SavedItem(id: n.id, isNote: true, title: n.body, inBackground: inBackground);
    } else {
      final t = app.addSpokenTask(p);
      if (t == null) return null;
      item = SavedItem(
        id: t.id,
        isNote: false,
        title: t.title,
        due: t.due,
        hasTime: t.hasTime,
        reminder: t.remindAt != null,
        inBackground: inBackground,
      );
    }
    app.logRecognized(_heard, parseSpokenTask(_heard, app.now(), _lang), localeId: locale);
    _saved.insert(0, item);
    _transcript = '';
    _preview = null;
    return item;
  }

  // --------------------------------------------------------------- lifecycle

  /// `hidden` and `paused` are the background; `inactive` alone (Control
  /// Centre, a permission prompt, an incoming-call banner) changes nothing.
  void onLifecycle(AppLifecycleState state) {
    if (_closed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _toForeground();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _toBackground();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  /// Design §6.6: nothing said is lost, the microphone goes off, and the
  /// saves are written to disk before the app can be suspended. No
  /// notification prompt in the background.
  void _toBackground() {
    if (!_foreground) return;
    _foreground = false;
    _backgroundAt = app.now();
    if (_startTimer?.isActive ?? false) {
      _startTimer!.cancel();
      _openOnResume = true;
    }
    switch (_phase) {
      case VoicePhase.listening:
        final text = (_final ?? _partial).trim();
        _inSession = false;
        _level = 0;
        _cancelListenTimers();
        _idleTimer?.cancel();
        unawaited(engine.cancel());
        final parsed = text.isEmpty ? null : parseSpokenTask(text, app.now(), _lang);
        if (parsed != null && parsed.title.trim().isNotEmpty) {
          _heard = text;
          _preview = parsed;
          _commit(inBackground: true);
        }
        _transcript = '';
        _preview = null;
        _setPhase(VoicePhase.paused);
      case VoicePhase.preview:
        _commit(inBackground: true);
        _setPhase(VoicePhase.paused);
      default:
        // A listen asked for but not started yet must not start out of sight.
        if (_awaitingStart) {
          _awaitingStart = false;
          unawaited(engine.cancel());
          if (_phase == VoicePhase.preparing) _setPhase(VoicePhase.paused);
        }
    }
    unawaited(app.flush());
  }

  /// The microphone never comes back on by itself; after more than
  /// [VoiceTimings.backgroundClose] away the screen closes, unless a
  /// correction is being typed.
  void _toForeground() {
    if (_foreground) return;
    _foreground = true;
    final since = _backgroundAt;
    _backgroundAt = null;
    if (since != null && app.now().difference(since) > VoiceTimings.backgroundClose && _phase != VoicePhase.editing) {
      unawaited(close());
      return;
    }
    if (_openOnResume) {
      _openOnResume = false;
      _scheduleOpen();
    }
  }

  // ------------------------------------------------------------------ closing

  /// Cancels the engine and every timer. A task still in preview or in the
  /// correction draft is not saved.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _awaitingStart = false;
    _inSession = false;
    _openOnResume = false;
    _level = 0;
    _cancelTimers();
    _setPhase(VoicePhase.closed);
    // On an unsupported platform the engine is never called.
    if (engine.isSupported) await engine.cancel();
  }

  void _cancelTimers() {
    for (final t in [_startTimer, _gapTimer, _holdTimer, _idleTimer, _maxTimer]) {
      t?.cancel();
    }
  }

  void _setPhase(VoicePhase p) {
    _phase = p;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _closed = true;
    _cancelTimers();
    unawaited(_events?.cancel());
    super.dispose();
  }
}
