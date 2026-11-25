import 'dart:async';
import 'dart:ui' show AppLifecycleState, Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import '../../core/spoken/list_match.dart';
import '../../core/spoken/parse.dart';
import '../../core/spoken/spoken_task.dart';
import '../../models/task_list.dart';
import '../../services/speech/speech_engine.dart';
import '../../state/app_controller.dart';

/// Every timing of the voice screen (design §5). They live in Dart only.
abstract final class VoiceTimings {
  /// Wait before the first listen so Siri's audio session is released.
  static const startDelay = Duration(milliseconds: 300);

  /// No new partial result for this long ends the utterance.
  static const utteranceGap = Duration(milliseconds: 1600);

  /// How long the preview waits for a list or a box before it is saved
  /// (Settings > Add by voice can turn the timed save off).
  static const previewHold = Duration(seconds: 8);

  /// Silence in a listen asked for with "Add another" closes the screen.
  static const idleClose = Duration(seconds: 6);

  /// How long "Added" shows after a save before the screen closes by itself
  /// (not with VoiceOver; "Add another" stops it).
  static const savedClose = Duration(milliseconds: 1200);

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
    this.listName,
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

  /// The name of the list the task went to; null for a note.
  final String? listName;
}

/// The voice screen's state machine (design §5, §6.3, §6.6): listens, shows
/// the parsed task, saves it after a short preview, shows "Added" and closes.
/// The microphone never re-opens by itself after a save: only "Add another"
/// (or a tap on the microphone, or a new voice request) opens it. All timing
/// lives here; the [SpeechEngine] only reports what it heard.
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
  Timer? _startTimer, _gapTimer, _holdTimer, _idleTimer, _maxTimer, _doneTimer;
  bool _closed = false;
  bool _disposed = false;

  /// engine.start was called and its [SpeechStarted] has not come yet.
  bool _awaitingStart = false;

  /// Between this screen's [SpeechStarted] and the matching [SpeechStopped].
  bool _inSession = false;

  /// The user tapped the microphone to stop the current listen; it must not
  /// restart by itself. Cleared on the next [SpeechStarted].
  bool _stopRequested = false;

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

  /// A voice request came while the app was in the background: listen once
  /// it is back in the foreground.
  bool _listenOnResume = false;

  /// [_startTimer] waits to listen for a voice request, not to open.
  bool _startIsRequest = false;

  /// A task with a reminder was saved in the background: ask for
  /// notifications once the app is back in the foreground.
  bool _askOnResume = false;

  /// The notification prompt is up; the microphone stays off meanwhile.
  bool _asking = false;

  /// The list named in the sentence being previewed, if any.
  String? _spokenListId;

  /// The list and the box the user picked for the preview; they outlive a
  /// correction of the text.
  String? _pickedListId;
  Quadrant? _pickedQuadrant;

  /// The latest save, shown in [VoicePhase.saved]; null once undone.
  SavedItem? _lastSaved;

  VoicePhase get phase => _phase;

  /// The live transcript, or the correction draft while editing.
  String get transcript => _transcript;

  /// The live or the last parse of [transcript].
  SpokenTask? get preview => _preview;

  /// Input level, 0..1.
  double get level => _level;

  /// Saved this time the screen was open, newest first.
  List<SavedItem> get saved => List.unmodifiable(_saved);

  /// What the "Added" state shows: the latest save, unless it was undone.
  SavedItem? get lastSaved => _lastSaved;

  String? get localeId => _localeId;

  /// The list the preview goes to: the one picked, else the one named in the
  /// sentence, else the last used one ([AppController.currentListId]). A list
  /// deleted meanwhile falls back to the last used one.
  String get listId {
    final id = _pickedListId ?? _spokenListId;
    return id != null && app.lists.any((l) => l.id == id) ? id : app.currentListId;
  }

  /// The box the preview goes to: the one picked, else the default (a time
  /// said for today is "do now", anything else "plan").
  Quadrant get quadrant {
    final p = _preview;
    return _pickedQuadrant ?? app.defaultQuadrant(due: p?.due, hasTime: p?.hasTime ?? false);
  }

  bool get _picking => (_phase == VoicePhase.preview || _phase == VoicePhase.editing) && !(_preview?.isNote ?? true);

  /// Picks the box of the preview or of the correction; a running countdown
  /// starts again.
  void pickQuadrant(Quadrant q) {
    if (!_picking) return;
    _pickedQuadrant = q;
    if (_holdTimer?.isActive ?? false) _armHold();
    _notify();
  }

  /// Picks the list. In the preview it saves at once (the quick path); while
  /// correcting it only selects, and "Save" saves.
  Future<void> pickList(String id) async {
    if (!_picking) return;
    if (!app.lists.any((l) => l.id == id)) return;
    _pickedListId = id;
    if (_phase == VoicePhase.editing) return _notify();
    await _save();
  }

  /// The preview is saved when [VoiceTimings.previewHold] runs out; false
  /// when the timed save is turned off in Settings, with VoiceOver and after
  /// a recogniser error, where it is saved by hand.
  bool get previewOnTimer => _phase == VoicePhase.preview && (_holdTimer?.isActive ?? false);

  /// VoiceOver or Switch Control is on (compliance §4.2-3): the preview is not
  /// saved on a timer, and the screen does not close on silence nor by itself
  /// after a save.
  bool get accessible => _accessible;
  set accessible(bool value) {
    if (value == _accessible) return;
    _accessible = value;
    if (value) {
      _holdTimer?.cancel();
      _idleTimer?.cancel();
      _doneTimer?.cancel();
    } else {
      // "Added" kept open for VoiceOver closes as it would have without it.
      _armDoneClose();
    }
  }

  // ------------------------------------------------------------------ opening

  /// Starts listening once the app is in the foreground ([lifecycle] null or
  /// resumed), after [VoiceTimings.startDelay]. Permissions are asked here,
  /// by the engine's prepare(), and nowhere else.
  ///
  /// [autoListen] false (opened by a pamnot:// link, which any app or web
  /// page can open): the screen waits for a tap in [VoicePhase.paused], and
  /// neither the permission check nor the microphone runs before it.
  Future<void> open({AppLifecycleState? lifecycle, bool autoListen = true}) async {
    if (_closed || _events != null) return;
    _events = engine.events.listen(_onEvent);
    if (!engine.isSupported) return _setPhase(VoicePhase.unsupportedPlatform);
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!autoListen) return _setPhase(VoicePhase.paused);
    if (_foreground) {
      _scheduleOpen();
    } else {
      _openOnResume = true;
    }
  }

  void _scheduleOpen() {
    _startTimer?.cancel();
    _startIsRequest = false;
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
    _stopRequested = false;
    _transcript = '';
    _preview = null;
    _maxTimer = Timer(VoiceTimings.maxListen, _stopListening);
    _armIdleClose();
    _setPhase(VoicePhase.listening);
  }

  /// After a save, a listen (only ever asked for with "Add another", a tap or
  /// a voice request) with nothing said closes the screen. The timer keeps
  /// running across a listen that ended without text.
  void _armIdleClose() {
    if (_saved.isEmpty || _accessible || (_idleTimer?.isActive ?? false)) return;
    _idleTimer = Timer(VoiceTimings.idleClose, () => unawaited(close()));
  }

  void _onPartial(String text) {
    if (!_inSession || _final != null) return;
    _partial = text;
    _transcript = text;
    _preview = _parse(text);
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
    final parsed = text.isEmpty ? null : _parse(text);
    if (parsed == null || parsed.title.trim().isEmpty) return _endWithoutText();
    // Before the phase changes, so the screen sees whether it is timed.
    if (!_accessible && app.settings.voiceAutoSave) _armHold();
    _showPreview(text, parsed);
  }

  void _armHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(VoiceTimings.previewHold, () => unawaited(_save()));
  }

  /// Parses [text] and takes a list named in it out of the title; the list
  /// becomes [_spokenListId]. A note has no list.
  SpokenTask _parse(String text) {
    final p = parseSpokenTask(text, app.now(), _lang);
    _spokenListId = null;
    if (p.isNote) return p;
    final m = matchSpokenList(p.title, app.lists, turkish: _lang == 'tr');
    _spokenListId = m.listId;
    if (m.title == p.title) return p;
    return SpokenTask(
      title: m.title,
      due: p.due,
      hasTime: p.hasTime,
      remind: p.remind,
      ambiguousHour: p.ambiguousHour,
      isNote: p.isNote,
    );
  }

  void _showPreview(String heard, SpokenTask parsed) {
    _pickedListId = null;
    _pickedQuadrant = null;
    _heard = heard;
    _transcript = heard;
    _preview = parsed;
    _setPhase(VoicePhase.preview);
  }

  /// A failure ends the session as far as this screen is concerned, and the
  /// session's own [SpeechStopped] is ignored. When an interruption, a
  /// network or an unknown error comes after words were heard, the words are
  /// kept: they are previewed and saved by hand (design §2: a spoken task is
  /// not lost), and the error is not shown. "Nothing recognised" is not a
  /// failure; the listen just ends empty.
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
    final heard = _inSession ? (_final ?? _partial).trim() : '';
    _awaitingStart = false;
    _inSession = false;
    _level = 0;
    _cancelListenTimers();
    _idleTimer?.cancel();
    // The plugin stops by itself on iOS; this makes sure the microphone is
    // off whatever the screen shows next.
    unawaited(_cancelEngine());
    final keep =
        kind == SpeechErrorKind.interrupted || kind == SpeechErrorKind.network || kind == SpeechErrorKind.unknown;
    final parsed = keep && heard.isNotEmpty ? _parse(heard) : null;
    if (parsed != null && parsed.title.trim().isNotEmpty) return _showPreview(heard, parsed);
    _setPhase(phase);
  }

  Future<void> _cancelEngine() async {
    try {
      await engine.cancel();
    } catch (e) {
      debugPrint('Voice capture could not cancel the engine: $e');
    }
  }

  /// A listen ended with nothing to save: before the first save, or when the
  /// user stopped it, the screen waits for a tap; otherwise (a listen asked
  /// for after a save) it listens again and closes on silence.
  void _endWithoutText() {
    _transcript = '';
    _preview = null;
    if (_saved.isEmpty || _accessible || _stopRequested) {
      _idleTimer?.cancel();
      return _setPhase(VoicePhase.paused);
    }
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

  /// While listening: stops and previews what was said; with nothing said
  /// the microphone stays off. After a save: as [addAnother]. After a pause
  /// or an error: listens again. Not prepared yet (opened by a link, or
  /// preparing failed): the opening steps run first.
  void toggleMic() {
    switch (_phase) {
      case VoicePhase.listening:
        _stopRequested = true;
        _stopListening();
      case VoicePhase.error || VoicePhase.paused when !_prepared:
        _setPhase(VoicePhase.preparing);
        unawaited(_prepareAndListen());
      case VoicePhase.saved:
        addAnother();
      case VoicePhase.paused || VoicePhase.error:
        unawaited(_listen());
      default:
    }
  }

  /// "Add another" in the "Added" state: the screen no longer closes by
  /// itself and listens again. The only way the microphone opens after a
  /// save besides the user's own tap or voice request.
  void addAnother() {
    if (_closed || _asking || _phase != VoicePhase.saved) return;
    _doneTimer?.cancel();
    // The microphone is off until the engine reports the start.
    _setPhase(VoicePhase.preparing);
    unawaited(_listen());
  }

  /// Phases in which the microphone is off and waits for a tap.
  static const _waitingPhases = {VoicePhase.paused, VoicePhase.saved, VoicePhase.error};

  /// A new voice request while this screen is open (the shortcut run again):
  /// where the microphone waits for a tap it listens, as a tap would, after
  /// [VoiceTimings.startDelay] (Siri may still hold the audio); while
  /// listening, previewing or editing it is ignored. From the background it
  /// listens once the app is back in the foreground.
  void onVoiceRequest() {
    if (_closed || _asking || !_waitingPhases.contains(_phase)) return;
    // The screen must not close before the request listens.
    _doneTimer?.cancel();
    if (!_foreground) {
      _listenOnResume = true;
      return;
    }
    _scheduleRequestedListen();
  }

  void _scheduleRequestedListen() {
    _startTimer?.cancel();
    _startIsRequest = true;
    _startTimer = Timer(VoiceTimings.startDelay, () {
      if (_closed || _asking || !_foreground || !_waitingPhases.contains(_phase)) return;
      toggleMic();
    });
  }

  // ---------------------------------------------------------- preview and edit

  /// Preview → correction: the countdown stops and [transcript] becomes the
  /// draft.
  void edit() {
    if (_phase != VoicePhase.preview) return;
    _holdTimer?.cancel();
    _setPhase(VoicePhase.editing);
  }

  /// The correction draft changed; the preview follows it, and a list named
  /// anew in the text takes over from one picked before.
  void updateDraft(String text) {
    if (_phase != VoicePhase.editing) return;
    final spokenBefore = _spokenListId;
    _transcript = text;
    _preview = _parse(text);
    if (_spokenListId != null && _spokenListId != spokenBefore) _pickedListId = null;
    _notify();
  }

  /// Saves the task in preview or in the draft now; the microphone stays off.
  Future<void> saveNow() async {
    if (_phase != VoicePhase.preview && _phase != VoicePhase.editing) return;
    await _save();
  }

  /// Deletes a saved task or note; one already deleted elsewhere is fine.
  /// Undoing the save "Added" shows stops the screen from closing by itself:
  /// it waits for a tap instead.
  void undo(SavedItem item) {
    if (item.isNote) {
      app.deleteNote(item.id);
    } else {
      app.deleteTask(item.id);
    }
    _saved.removeWhere((s) => s.id == item.id);
    if (_lastSaved?.id == item.id) {
      _lastSaved = null;
      if (_phase == VoicePhase.saved) {
        _doneTimer?.cancel();
        return _setPhase(VoicePhase.paused);
      }
    }
    _notify();
  }

  // ------------------------------------------------------------------- saving

  /// Saves the preview in the foreground and shows "Added": the microphone
  /// is off and stays off (owner ruling R10). A task with a reminder asks for
  /// notifications first; then the screen closes after
  /// [VoiceTimings.savedClose], unless VoiceOver is on.
  Future<void> _save() async {
    final item = _commit();
    if (item == null) return;
    _lastSaved = item;
    _setPhase(VoicePhase.saved);
    onSaved?.call();
    if (item.reminder && _foreground) await _askNotifications();
    _armDoneClose();
  }

  /// In the foreground, without VoiceOver, "Added" closes the screen after
  /// [VoiceTimings.savedClose].
  void _armDoneClose() {
    _doneTimer?.cancel();
    if (_closed || _accessible || !_foreground || _phase != VoicePhase.saved) return;
    _doneTimer = Timer(VoiceTimings.savedClose, () => unawaited(close()));
  }

  /// Asks for notification permission if it was never asked (design §6.5),
  /// with the microphone off.
  Future<void> _askNotifications() async {
    _asking = true;
    try {
      await app.ensureNotificationPermission();
    } finally {
      _asking = false;
    }
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
      final t = app.addSpokenTask(p, listId: listId, quadrant: quadrant);
      if (t == null) return null;
      item = SavedItem(
        id: t.id,
        isNote: false,
        title: t.title,
        due: t.due,
        hasTime: t.hasTime,
        reminder: t.remindAt != null,
        inBackground: inBackground,
        listName: app.listById(t.listId).name,
      );
    }
    app.logRecognized(_heard, parseSpokenTask(_heard, app.now(), _lang), localeId: locale);
    // The first save by voice brings the one-time guide card to Today.
    if (!app.settings.voiceUsed) app.updateSettings(app.settings.copyWith(voiceUsed: true));
    // Saved out of sight: the notification prompt waits for the foreground.
    if (inBackground && item.reminder) _askOnResume = true;
    _saved.insert(0, item);
    _transcript = '';
    _preview = null;
    _spokenListId = _pickedListId = null;
    _pickedQuadrant = null;
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
    // Out of sight, only the five-minute rule closes the screen.
    _idleTimer?.cancel();
    _doneTimer?.cancel();
    // A start still waiting resumes the same way on return: a voice
    // request as a tap would, the opening through its steps.
    if (_startTimer?.isActive ?? false) {
      _startTimer!.cancel();
      if (_startIsRequest) {
        _listenOnResume = true;
      } else {
        _openOnResume = true;
      }
    }
    switch (_phase) {
      case VoicePhase.listening:
        final text = (_final ?? _partial).trim();
        _inSession = false;
        _level = 0;
        _cancelListenTimers();
        unawaited(engine.cancel());
        final parsed = text.isEmpty ? null : _parse(text);
        if (parsed != null && parsed.title.trim().isNotEmpty) {
          _pickedListId = null;
          _pickedQuadrant = null;
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

  /// The microphone never comes back on by itself (only a listen asked for
  /// before or while away starts); after more than
  /// [VoiceTimings.backgroundClose] away the screen closes, unless a
  /// correction is being typed or a new voice request came. A task with a
  /// reminder saved while away asks for notifications first, with the
  /// microphone off.
  void _toForeground() {
    if (_foreground) return;
    _foreground = true;
    final since = _backgroundAt;
    _backgroundAt = null;
    final ask = _askOnResume, open = _openOnResume, listen = _listenOnResume;
    _askOnResume = _openOnResume = _listenOnResume = false;
    if (since != null &&
        app.now().difference(since) > VoiceTimings.backgroundClose &&
        _phase != VoicePhase.editing &&
        !listen) {
      unawaited(close());
      if (ask) unawaited(app.ensureNotificationPermission());
      return;
    }
    unawaited(_resume(ask: ask, open: open, listen: listen));
  }

  Future<void> _resume({required bool ask, required bool open, required bool listen}) async {
    if (ask) await _askNotifications();
    if (_closed) return;
    if (!_foreground) {
      // Away again while the prompt was up.
      _openOnResume |= open;
      _listenOnResume |= listen;
      return;
    }
    if (open) {
      _scheduleOpen();
    } else if (listen) {
      _scheduleRequestedListen();
    } else {
      // "Added" left on screen while away closes as it would have.
      _armDoneClose();
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
    for (final t in [_startTimer, _gapTimer, _holdTimer, _idleTimer, _maxTimer, _doneTimer]) {
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
