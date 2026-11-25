import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../core/motivation.dart';
import '../core/quick_parse.dart';
import '../core/spoken/spoken_task.dart';
import '../data/store.dart';
import '../l10n/strings.dart';
import '../models/habit.dart';
import '../models/ink.dart';
import '../models/note.dart';
import '../models/reminder.dart';
import '../models/settings.dart';
import '../models/task.dart';
import '../models/task_list.dart';
import '../models/voice_log.dart';
import '../prediction/word_predictor.dart';
import '../services/alarm_scheduler.dart';
import '../services/calendar/calendar_source.dart';
import '../services/pip_player.dart';
import '../services/handwriting.dart';
import '../services/reminder_scheduler.dart';
import '../services/speech/speech_engine.dart';
import '../services/widget_sync.dart';
import '../theme/pamnot_theme.dart';
import 'sample_data.dart';

/// Parts of the state a screen can subscribe to; a change to one slice only
/// rebuilds the widgets that asked for it. A slice's name is also the key
/// its document is stored under.
/// [calendar] is never saved; it only tells screens that the device
/// calendar's events changed.
enum Slice { notes, tasks, reminders, habits, settings, lists, calendar }

enum AgendaKind { task, reminder, event }

/// Where the notification permission stands: never asked by the app, asked
/// and refused (only the system Settings can change it now), or allowed.
enum NotificationAccess { notAsked, denied, granted }

class AgendaEntry {
  const AgendaEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.time,
    required this.done,
    required this.colorIndex,
    this.repeat = Repeat.none,
    this.color,
    this.end,
  });

  final AgendaKind kind;
  final String id;
  final String title;

  /// Null for all-day entries.
  final DateTime? time;
  final bool done;
  final int colorIndex;
  final Repeat repeat;

  /// The calendar's colour (ARGB); only for [AgendaKind.event].
  final int? color;

  /// When a timed calendar event ends; null otherwise.
  final DateTime? end;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    ReminderScheduler? scheduler,
    WidgetSync? widgetSync,
    HandwritingRecognizer? handwriting,
    SpeechEngine? speech,
    AlarmScheduler? alarms,
    CalendarSource? calendar,
    PipPlayer? pip,
    DateTime Function()? clock,
    this.saveDelay = const Duration(milliseconds: 400),
  })  : scheduler = scheduler ?? NoopScheduler(),
        widgetSync = widgetSync ?? NoopWidgetSync(),
        handwriting = handwriting ?? UnsupportedRecognizer(),
        speech = speech ?? UnsupportedSpeechEngine(),
        alarms = alarms ?? NoopAlarmScheduler(),
        calendar = calendar ?? NoCalendarSource(),
        pip = pip ?? NoPipPlayer(),
        now = clock ?? DateTime.now;

  final KeyValueStore store;
  final ReminderScheduler scheduler;
  final WidgetSync widgetSync;
  final HandwritingRecognizer handwriting;
  final SpeechEngine speech;
  final AlarmScheduler alarms;
  final CalendarSource calendar;

  /// Plays the guide videos in Picture in Picture (iOS only).
  final PipPlayer pip;
  final DateTime Function() now;
  final Duration saveDelay;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  List<Note> _notes = [];
  List<TaskItem> _tasks = [];
  List<Reminder> _reminders = [];
  List<Habit> _habits = [];
  List<TaskList> _lists = [];
  AppSettings _settings = const AppSettings();
  List<VoiceLogEntry> _voiceLog = [];
  WordPredictor? _predictor;
  bool _loaded = false;

  UnmodifiableListView<Note> get notes => UnmodifiableListView(_notes);
  UnmodifiableListView<TaskItem> get tasks => UnmodifiableListView(_tasks);
  UnmodifiableListView<Reminder> get reminders => UnmodifiableListView(_reminders);
  UnmodifiableListView<Habit> get habits => UnmodifiableListView(_habits);
  AppSettings get settings => _settings;

  /// Recently recognised sentences, newest first (at most [voiceLogLimit]).
  /// Empty unless [AppSettings.keepVoiceLog] is on.
  UnmodifiableListView<VoiceLogEntry> get voiceLog => UnmodifiableListView(_voiceLog);
  WordPredictor? get predictor => _predictor;
  bool get loaded => _loaded;

  final Map<Slice, int> _revs = {for (final s in Slice.values) s: 0};

  /// Snapshot of every slice's revision; [AppScope] compares these.
  Map<Slice, int> get revisions => Map.of(_revs);

  // ---------------------------------------------------------------- language

  /// The language the UI is shown in.
  bool get isTurkish => switch (_settings.language) {
        AppLanguage.tr => true,
        AppLanguage.en => false,
        AppLanguage.system => PlatformDispatcher.instance.locales
            .map((l) => l.languageCode)
            .firstWhere((c) => c == 'tr' || c == 'en', orElse: () => 'en') ==
            'tr',
      };

  S get strings => isTurkish ? S.tr : S.en;

  PLang get _uiLang => isTurkish ? PLang.tr : PLang.en;

  PLang? get _fixedPredictionLang => switch (_settings.predictionLanguage) {
        PredictionLanguage.auto => null,
        PredictionLanguage.tr => PLang.tr,
        PredictionLanguage.en => PLang.en,
      };

  // ------------------------------------------------------------- persistence

  final Set<Slice> _dirty = {};
  final Set<String> _dirtyInk = {};
  final Set<String> _inkPending = {};
  final Map<String, Completer<void>> _inkWaiters = {};
  Timer? _saveTimer;
  Future<void>? _saving;

  /// The voice log has to be written (or, when empty, deleted).
  bool _voiceLogDirty = false;
  static const _voiceLogKey = 'voice_log';
  static const voiceLogLimit = 20;

  /// The daily motivation picks (dayKey → quote index) have to be written.
  bool _motivationDirty = false;
  static const _motivationKey = 'motivation';

  Future<void> load() async {
    final keys = ['settings', 'notes', 'tasks', 'reminders', 'habits', _voiceLogKey, 'lists', _motivationKey];
    final raw = await Future.wait(keys.map(store.read));
    List<Map<String, Object?>> items(String? doc) {
      if (doc == null) return const [];
      try {
        final j = jsonDecode(doc);
        final list = (j is Map ? j['items'] : j) as List? ?? const [];
        return [for (final e in list) (e as Map).cast<String, Object?>()];
      } catch (e) {
        debugPrint('Unreadable document: $e');
        return const [];
      }
    }

    T? tryParse<T>(Map<String, Object?> j, T Function(Map<String, Object?>) f) {
      try {
        return f(j);
      } catch (e) {
        debugPrint('Skipped a damaged item: $e');
        return null;
      }
    }

    if (raw[0] != null) {
      try {
        _settings = AppSettings.fromJson((jsonDecode(raw[0]!) as Map).cast<String, Object?>());
      } catch (_) {}
    }
    final noteJson = items(raw[1]);
    _notes = [for (final j in noteJson) ?tryParse(j, Note.fromJson)];
    _tasks = [for (final j in items(raw[2])) ?tryParse(j, TaskItem.fromJson)];
    _reminders = [for (final j in items(raw[3])) ?tryParse(j, Reminder.fromJson)];
    _habits = [for (final j in items(raw[4])) ?tryParse(j, Habit.fromJson)];
    final repaired = <Slice>{};
    final seenListIds = <String>{};
    _lists = [
      for (final j in items(raw[6]))
        if (tryParse(j, TaskList.fromJson) case final l? when l.id.isNotEmpty && seenListIds.add(l.id)) l,
    ];
    if (_lists.isEmpty) {
      // First start, an install from before lists existed, or a document
      // with nothing usable in it. Written once; afterwards the saved
      // document is the truth.
      _lists = TaskList.defaults(tr: isTurkish);
      repaired.add(Slice.lists);
    }
    _sortLists();
    final listIds = {for (final l in _lists) l.id};
    for (var i = 0; i < _tasks.length; i++) {
      if (!listIds.contains(_tasks[i].listId)) {
        _tasks[i] = _tasks[i].copyWith(listId: _lists.first.id);
        repaired.add(Slice.tasks);
      }
    }
    if (raw[7] != null) {
      try {
        _motivationPicks = {
          for (final e in (jsonDecode(raw[7]!) as Map).entries)
            if (e.key is String && e.value is int) e.key as String: e.value as int,
        };
      } catch (e) {
        debugPrint('Unreadable motivation picks: $e');
      }
    }
    _inkPending.addAll([for (final j in noteJson) if (j['hasInk'] == true) j['id']! as String]);
    if (_settings.keepVoiceLog) {
      _voiceLog = [for (final j in items(raw[5])) ?tryParse(j, VoiceLogEntry.fromJson)].take(voiceLogLimit).toList();
    } else if (raw[5] != null) {
      // Left behind when the switch was turned off; it must not come back.
      _voiceLogDirty = true;
      _scheduleSave();
    }
    _loaded = true;

    if (!_settings.seeded) {
      final sample = SampleData.build(strings, now(), newId);
      _notes = sample.notes;
      _tasks = sample.tasks;
      _reminders = sample.reminders;
      _habits = sample.habits;
      _settings = _settings.copyWith(seeded: true);
      _changed(Slice.values.toSet());
    } else {
      if (repaired.isNotEmpty) {
        _dirty.addAll(repaired);
        _scheduleSave();
      }
      _changed(Slice.values.toSet(), persist: false);
    }
    unawaited(_loadInk());
    _scheduleMidnight();
    await refreshAlarmAccess();
    await applyWidgetCompletions();
  }

  Timer? _midnight;

  /// Re-renders date-dependent screens: after midnight and on resume.
  void refreshDay() {
    _changed(Slice.values.toSet(), persist: false);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final t = now();
    final next = DateTime(t.year, t.month, t.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(t), refreshDay);
  }

  Future<void> _loadInk() async {
    for (final id in _inkPending.toList()) {
      try {
        final text = await store.read('ink_$id');
        final strokes = text == null
            ? const <InkStroke>[]
            : text.length > 200000
                ? await compute(InkCodec.decode, text)
                : InkCodec.decode(text);
        final i = _notes.indexWhere((n) => n.id == id);
        if (i >= 0 && _notes[i].ink.isEmpty) _notes[i] = _notes[i].copyWith(ink: strokes);
      } catch (e) {
        debugPrint('Ink for $id unreadable: $e');
      }
      _inkPending.remove(id);
      _inkWaiters.remove(id)?.complete();
    }
    _changed({Slice.notes}, persist: false);
  }

  /// Completes once the note's ink is in memory (it loads after startup).
  Future<void> ensureInk(String id) {
    if (!_inkPending.contains(id)) return Future.value();
    return _inkWaiters.putIfAbsent(id, Completer.new).future;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  /// Writes everything that changed. Called after a short pause in editing
  /// and when the app goes to the background.
  Future<void> flush() async {
    _saveTimer?.cancel();
    while (_saving != null) {
      await _saving;
    }
    if (_dirty.isEmpty && _dirtyInk.isEmpty && !_voiceLogDirty && !_motivationDirty) return;
    final dirty = {..._dirty};
    final inkIds = {..._dirtyInk};
    final voiceLog = _voiceLogDirty;
    final motivation = _motivationDirty;
    _dirty.clear();
    _dirtyInk.clear();
    _voiceLogDirty = false;
    _motivationDirty = false;
    final done = Completer<void>();
    _saving = done.future;
    try {
      if (voiceLog) {
        if (_voiceLog.isEmpty) {
          await store.delete(_voiceLogKey);
        } else {
          await store.write(_voiceLogKey, jsonEncode([for (final e in _voiceLog) e.toJson()]));
        }
      }
      if (motivation) await store.write(_motivationKey, jsonEncode(_motivationPicks));
      for (final s in dirty) {
        await store.write(s.name, _encode(s));
      }
      for (final id in inkIds) {
        final note = _noteById(id);
        if (note == null || note.ink.isEmpty) {
          await store.delete('ink_$id');
        } else {
          final strokes = note.ink;
          final points = strokes.fold<int>(0, (n, s) => n + s.length);
          await store.write('ink_$id', points > 20000 ? await compute(InkCodec.encode, strokes) : InkCodec.encode(strokes));
        }
      }
    } catch (e) {
      debugPrint('Save failed, will retry: $e');
      _dirty.addAll(dirty);
      _dirtyInk.addAll(inkIds);
      _voiceLogDirty |= voiceLog;
      _motivationDirty |= motivation;
      _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(flush()));
    } finally {
      _saving = null;
      done.complete();
    }
  }

  String _encode(Slice s) {
    List<Map<String, Object?>> list = switch (s) {
      Slice.notes => [for (final n in _notes) n.toJson()],
      Slice.tasks => [for (final t in _tasks) t.toJson()],
      Slice.reminders => [for (final r in _reminders) r.toJson()],
      Slice.habits => [for (final h in _habits) h.toJson()],
      Slice.lists => [for (final l in _lists) l.toJson()],
      Slice.settings || Slice.calendar => const [],
    };
    if (s == Slice.settings) return jsonEncode(_settings.toJson());
    return jsonEncode({'v': 1, 'items': list});
  }

  // ------------------------------------------------------------ side effects

  Timer? _alertTimer, _widgetTimer, _learnTimer, _ticker;
  DateTime? _lastTick;

  void _changed(Set<Slice> slices, {bool persist = true}) {
    for (final s in slices) {
      _revs[s] = _revs[s]! + 1;
    }
    if (persist) {
      _dirty.addAll(slices.where((s) => s != Slice.calendar));
      _scheduleSave();
    }
    if (slices.contains(Slice.tasks) || slices.contains(Slice.reminders) || slices.contains(Slice.settings)) {
      _alertTimer?.cancel();
      _alertTimer = Timer(const Duration(milliseconds: 800), () => unawaited(syncAlerts()));
    }
    if (slices.contains(Slice.tasks) ||
        slices.contains(Slice.reminders) ||
        slices.contains(Slice.settings) ||
        slices.contains(Slice.lists)) {
      _widgetTimer?.cancel();
      _widgetTimer = Timer(const Duration(milliseconds: 600), () => unawaited(syncWidget()));
    }
    if (slices.contains(Slice.notes) || slices.contains(Slice.tasks)) {
      _learnTimer?.cancel();
      _learnTimer = Timer(const Duration(seconds: 2), () => unawaited(_relearn()));
    }
    notifyListeners();
  }

  void attachPredictor(WordPredictor p) {
    _predictor = p;
    unawaited(_relearn());
    _changed({Slice.settings}, persist: false);
  }

  Future<void> _relearn() async {
    final p = _predictor;
    if (p == null) return;
    final texts = <String>[
      for (final n in _notes) ...[n.title, n.body],
      for (final t in _tasks) ...[t.title, t.notes, for (final s in t.subtasks) s.title],
      for (final r in _reminders) r.title,
    ];
    await p.learn(texts, fallback: _uiLang);
  }

  List<Alert> alerts() {
    final s = strings;
    return [
      for (final r in _reminders)
        if (r.enabled)
          Alert(
            key: 'r:${r.id}',
            title: r.title,
            body: r.note.isEmpty ? s.reminder : r.note,
            at: r.at,
            repeat: r.repeat,
            alarm: r.alertKind == AlertKind.alarm,
          ),
      for (final t in _tasks)
        if (!t.done && t.remindAt != null)
          Alert(
            key: 't:${t.id}',
            title: t.title,
            body: t.notes.isEmpty ? s.task : t.notes,
            at: t.remindAt!,
            alarm: t.alertKind == AlertKind.alarm,
          ),
      ...motivationAlerts(),
    ];
  }

  // ------------------------------------------------------------- motivation

  List<String> _quotesTr = const [], _quotesEn = const [];

  /// dayKey → quote index; the same index is the same line in both files.
  Map<String, int> _motivationPicks = {};

  /// How many days ahead are scheduled, and how long a pick is remembered.
  static const motivationDays = 7;
  static const motivationKeepDays = 60;

  /// Hands over the quote files' lines (read after the first frame). The
  /// caller syncs the alerts afterwards.
  void attachQuotes({required List<String> tr, required List<String> en}) {
    _quotesTr = List.unmodifiable(tr);
    _quotesEn = List.unmodifiable(en);
  }

  /// One gentle line a day at [AppSettings.motivationMinutes], for the next
  /// [motivationDays] days; today only while its time is still ahead. Empty
  /// when the setting is off or the lines are not loaded. Never asks for
  /// notification permission: without it the system simply shows nothing.
  /// New picks are remembered (and those older than [motivationKeepDays]
  /// dropped) so a day keeps its line; the change is saved like any other.
  List<Alert> motivationAlerts() {
    final quotes = isTurkish ? _quotesTr : _quotesEn;
    if (!_settings.dailyMotivation || quotes.isEmpty) return const [];
    final t = now();
    final today = dateOnly(t);
    final minutes = _settings.motivationMinutes;
    DateTime at(DateTime day) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    final first = at(today).isAfter(t) ? today : addDays(today, 1);
    final plan = planQuotes(first, motivationDays, _motivationPicks, quotes.length);

    final oldest = dayKey(addDays(today, -motivationKeepDays));
    final picks = {
      for (final e in _motivationPicks.entries)
        if (e.key.compareTo(oldest) >= 0) e.key: e.value,
      ...plan,
    };
    if (!mapEquals(picks, _motivationPicks)) {
      _motivationPicks = picks;
      _motivationDirty = true;
      _scheduleSave();
    }
    return [
      for (final e in plan.entries)
        Alert(key: 'm:${e.key}', title: 'Pamnot', body: quotes[e.value], at: at(parseDayKey(e.key))),
    ];
  }

  Future<void>? _alertSync;
  bool _alertSyncAgain = false;

  /// Installs [alerts]: alarms through [alarms] while alarm access is
  /// authorized, everything else (alarms included when it is not) through
  /// [scheduler]; an alert never goes to both. Calls never overlap: one made
  /// while a sync is running waits for it, and one more run then installs
  /// the newest list.
  Future<void> syncAlerts() async {
    _alertSyncAgain = true;
    if (_alertSync case final running?) return running;
    final done = Completer<void>();
    _alertSync = done.future;
    try {
      while (_alertSyncAgain) {
        _alertSyncAgain = false;
        await _syncAlertsOnce();
      }
    } finally {
      _alertSync = null;
      done.complete();
    }
  }

  Future<void> _syncAlertsOnce() async {
    final access = _alarmAccess;
    final useAlarms = access == AlarmAccess.authorized;
    final t = now();
    final notifications = <Alert>[], rings = <Alert>[];
    for (final a in alerts()) {
      if (!a.alarm || !useAlarms) {
        notifications.add(a);
        continue;
      }
      // The bridge installs `at` as given, so a repeating alarm carries its
      // next occurrence; a one-off in the past is set nowhere.
      final probe = Reminder(id: a.key, title: a.title, at: a.at, repeat: a.repeat, createdAt: t);
      final next = probe.nextOccurrence(t);
      if (next == null) continue;
      rings.add(next == a.at
          ? a
          : Alert(key: a.key, title: a.title, body: a.body, at: next, repeat: a.repeat, alarm: true));
    }
    await scheduler.sync(notifications);
    if (access != AlarmAccess.unsupported) await alarms.sync(rings);
  }

  Future<void> syncWidget() async {
    await widgetSync.push(todaySummary());
    await widgetSync.pushLists(listsSummary());
  }

  /// Finishes the tasks ticked on the list widget while the app was away.
  /// Ids of deleted or already finished tasks are skipped. When anything was
  /// waiting, the widgets get a fresh summary at once.
  Future<void> applyWidgetCompletions() async {
    final ids = await widgetSync.takePendingDone();
    if (ids.isEmpty) return;
    final t = now();
    var changed = false;
    for (final id in ids) {
      final i = _tasks.indexWhere((x) => x.id == id);
      if (i < 0 || _tasks[i].done) continue;
      _tasks[i] = _tasks[i].copyWith(done: true, completedAt: () => t);
      changed = true;
    }
    if (changed) _changed({Slice.tasks});
    await syncWidget();
  }

  /// Web can't schedule in the background, so remind while the app is open.
  void startInAppTicker() {
    if (scheduler.schedulesInBackground || _ticker != null) return;
    _lastTick = now();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      final t = now();
      final from = _lastTick ?? t;
      _lastTick = t;
      for (final a in alerts()) {
        final probe = Reminder(id: a.key, title: a.title, at: a.at, repeat: a.repeat, createdAt: t);
        final next = probe.nextOccurrence(from.subtract(const Duration(milliseconds: 1)));
        if (next != null && !next.isAfter(t)) unawaited(scheduler.showNow(a.title, a.body));
      }
    });
  }

  @override
  void dispose() {
    for (final t in [_saveTimer, _alertTimer, _widgetTimer, _learnTimer, _ticker, _midnight]) {
      t?.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ notes

  Note? _noteById(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Note? noteById(String id) => _noteById(id);

  Note draftNote({bool handwriting = false}) {
    final t = now();
    final used = _notes.isEmpty ? 0 : _notes.first.colorIndex;
    return Note(
      id: newId(),
      colorIndex: (used + 1) % pastels.length,
      paper: handwriting ? PaperStyle.lined : PaperStyle.blank,
      createdAt: t,
      updatedAt: t,
    );
  }

  void upsertNote(Note n, {bool inkChanged = false}) {
    final i = _notes.indexWhere((x) => x.id == n.id);
    if (i >= 0) {
      _notes[i] = n;
    } else {
      _notes.insert(0, n);
    }
    if (inkChanged) _dirtyInk.add(n.id);
    _changed({Slice.notes});
  }

  Note? deleteNote(String id) {
    final i = _notes.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final n = _notes.removeAt(i);
    _dirtyInk.add(id);
    _changed({Slice.notes});
    return n;
  }

  void restoreNote(Note n) => upsertNote(n, inkChanged: n.ink.isNotEmpty);

  void togglePin(String id) {
    final n = _noteById(id);
    if (n != null) upsertNote(n.copyWith(pinned: !n.pinned));
  }

  /// Pinned first, then most recently edited.
  List<Note> sortedNotes({String query = ''}) {
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? [..._notes]
        : _notes.where((n) => n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q)).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  // ------------------------------------------------------------------ tasks

  /// A new, unsaved task in [listId] (default: [currentListId]) and
  /// [quadrant] (default: [defaultQuadrant]), placed at the end of its box.
  TaskItem draftTask({DateTime? due, bool hasTime = false, String? listId, Quadrant? quadrant}) {
    final list = listById(listId ?? currentListId).id;
    final box = quadrant ?? defaultQuadrant(due: due, hasTime: hasTime);
    return TaskItem(
      id: newId(),
      title: '',
      due: due,
      hasTime: hasTime,
      createdAt: now(),
      listId: list,
      quadrant: box,
      order: _nextOrder(list, box),
    );
  }

  /// A task added with a time today goes to "do now", anything else to "plan".
  Quadrant defaultQuadrant({DateTime? due, bool hasTime = false}) =>
      hasTime && due != null && isSameDay(due, now()) ? Quadrant.doNow : Quadrant.plan;

  /// Saves [t]. A task whose list no longer exists goes to the first list; a
  /// new task's list becomes the one new tasks go to next.
  void upsertTask(TaskItem t) {
    final listId = listById(t.listId).id;
    if (listId != t.listId) t = t.copyWith(listId: listId);
    final i = _tasks.indexWhere((x) => x.id == t.id);
    final slices = {Slice.tasks};
    if (i >= 0) {
      _tasks[i] = t;
    } else {
      _tasks.add(t);
      if (_settings.lastListId != listId) {
        _settings = _settings.copyWith(lastListId: listId);
        slices.add(Slice.settings);
      }
    }
    _changed(slices);
  }

  /// Creates a task from a quick-capture line ("yarın 10:00 toplantı").
  TaskItem? addQuickTask(String text, {String? listId, Quadrant? quadrant}) {
    final r = quickParse(text, now());
    if (r.title.isEmpty) return null;
    final t = draftTask(due: r.due, hasTime: r.hasTime, listId: listId, quadrant: quadrant).copyWith(title: r.title);
    upsertTask(t);
    return t;
  }

  /// Creates a task from a spoken sentence. Returns null for an empty title
  /// or when the sentence asked for a note (see [addSpokenNote]).
  ///
  /// A spoken time is also a reminder; "remind me" with a day but no time
  /// reminds at 09:00 that day. Reminders in the past are not set.
  TaskItem? addSpokenTask(SpokenTask s, {String? listId, Quadrant? quadrant}) {
    final title = s.title.trim();
    if (s.isNote || title.isEmpty) return null;
    final due = s.due;
    final hasTime = s.hasTime && due != null;
    final at = due == null
        ? null
        : hasTime
            ? due
            : s.remind
                ? DateTime(due.year, due.month, due.day, 9)
                : null;
    final remindAt = at != null && at.isAfter(now()) ? at : null;
    final t = draftTask(due: due, hasTime: hasTime, listId: listId, quadrant: quadrant)
        .copyWith(title: title, remindAt: () => remindAt);
    upsertTask(t);
    // Schedule now rather than after the usual pause: the phone may be locked
    // right after speaking.
    if (remindAt != null) unawaited(syncAlerts());
    return t;
  }

  void toggleTask(String id) {
    final i = _tasks.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final t = _tasks[i];
    _tasks[i] = t.copyWith(done: !t.done, completedAt: () => t.done ? null : now());
    _changed({Slice.tasks});
  }

  void toggleSubtask(String taskId, String subId) {
    final i = _tasks.indexWhere((x) => x.id == taskId);
    if (i < 0) return;
    final t = _tasks[i];
    _tasks[i] = t.copyWith(subtasks: [
      for (final s in t.subtasks) s.id == subId ? s.copyWith(done: !s.done) : s,
    ]);
    _changed({Slice.tasks});
  }

  TaskItem? deleteTask(String id) {
    final i = _tasks.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final t = _tasks.removeAt(i);
    _changed({Slice.tasks});
    return t;
  }

  /// Puts back a deleted task (Undo). Unlike [upsertTask] it does not make
  /// the task's list the current one: the Matrix keeps showing its list.
  void restoreTask(TaskItem t) {
    final listId = listById(t.listId).id;
    if (listId != t.listId) t = t.copyWith(listId: listId);
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _tasks[i] = t;
    } else {
      _tasks.add(t);
    }
    _changed({Slice.tasks});
  }

  List<TaskItem> tasksDueOn(DateTime day) =>
      _tasks.where((t) => t.due != null && isSameDay(t.due!, day)).toList()..sort(_byTime);

  List<TaskItem> overdueTasks() {
    final today = dateOnly(now());
    return _tasks.where((t) => !t.done && t.due != null && dateOnly(t.due!).isBefore(today)).toList()..sort(_byTime);
  }

  static int _byTime(TaskItem a, TaskItem b) {
    if (a.hasTime != b.hasTime) return a.hasTime ? -1 : 1;
    final c = a.due!.compareTo(b.due!);
    if (c != 0) return c;
    return b.priority.index.compareTo(a.priority.index);
  }

  /// (done, total) for tasks planned today.
  (int, int) progressOn(DateTime day) {
    final list = tasksDueOn(day);
    return (list.where((t) => t.done).length, list.length);
  }

  /// Tasks of one box of one list: by [TaskItem.order], then creation time.
  List<TaskItem> tasksIn(String listId, Quadrant q, {bool done = false}) =>
      _tasks.where((t) => t.listId == listId && t.quadrant == q && t.done == done).toList()..sort(_byOrder);

  static int _byOrder(TaskItem a, TaskItem b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

  int _nextOrder(String listId, Quadrant q) => _tasks
      .where((t) => t.listId == listId && t.quadrant == q)
      .fold(0, (n, t) => t.order >= n ? t.order + 1 : n);

  /// Moves a task to another list, another box, or another place in its box
  /// ([index], default the end). The target box is renumbered 0..n.
  void moveTask(String id, {String? listId, Quadrant? quadrant, int? index}) {
    final i = _tasks.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final t = _tasks[i];
    final list = listById(listId ?? t.listId).id;
    final box = quadrant ?? t.quadrant;
    final others = tasksIn(list, box, done: t.done)..removeWhere((x) => x.id == id);
    final at = (index ?? others.length).clamp(0, others.length);
    others.insert(at, t.copyWith(listId: list, quadrant: box));
    for (var n = 0; n < others.length; n++) {
      final j = _tasks.indexWhere((x) => x.id == others[n].id);
      _tasks[j] = others[n].copyWith(order: n);
    }
    _changed({Slice.tasks});
  }

  // ------------------------------------------------------------------ lists

  /// Every list, by [TaskList.order]. Never empty.
  UnmodifiableListView<TaskList> get lists => UnmodifiableListView(_lists);

  /// The list with [id]; the first list when there is none.
  TaskList listById(String id) => _lists.firstWhere((l) => l.id == id, orElse: () => _lists.first);

  /// The list new tasks go to: the last one used or chosen, while it exists.
  String get currentListId => listById(_settings.lastListId).id;

  void selectList(String id) {
    if (!_lists.any((l) => l.id == id) || _settings.lastListId == id) return;
    _settings = _settings.copyWith(lastListId: id);
    _changed({Slice.settings});
  }

  void _sortLists() => mergeSort(_lists, compare: (a, b) => a.order.compareTo(b.order));

  /// Adds a list after the others. Throws [ArgumentError] for a blank name.
  TaskList addList(String name, {int? colorIndex, String icon = 'list'}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be blank');
    final l = TaskList(
      id: newId(),
      name: trimmed,
      colorIndex: colorIndex ?? (_lists.last.colorIndex + 1) % pastels.length,
      icon: icon,
      order: _lists.fold(0, (n, l) => l.order >= n ? l.order + 1 : n),
    );
    _lists.add(l);
    _changed({Slice.lists});
    return l;
  }

  void updateList(TaskList l) {
    final i = _lists.indexWhere((x) => x.id == l.id);
    if (i < 0) return;
    _lists[i] = l;
    _sortLists();
    _changed({Slice.lists});
  }

  /// The last list is not deleted (null). Otherwise its tasks move to the
  /// first remaining list; returns the deleted list and the moved task ids
  /// for [restoreList].
  ({TaskList list, List<String> movedTaskIds})? deleteList(String id) {
    final i = _lists.indexWhere((x) => x.id == id);
    if (i < 0 || _lists.length < 2) return null;
    final list = _lists.removeAt(i);
    final target = _lists.first.id;
    final moved = <String>[];
    for (var j = 0; j < _tasks.length; j++) {
      if (_tasks[j].listId == id) {
        _tasks[j] = _tasks[j].copyWith(listId: target);
        moved.add(_tasks[j].id);
      }
    }
    _changed({Slice.lists, Slice.tasks});
    return (list: list, movedTaskIds: moved);
  }

  /// Undoes [deleteList]: puts [l] back and moves [taskIds] into it again.
  void restoreList(TaskList l, List<String> taskIds) {
    _lists
      ..removeWhere((x) => x.id == l.id)
      ..add(l);
    _sortLists();
    final ids = taskIds.toSet();
    for (var j = 0; j < _tasks.length; j++) {
      if (ids.contains(_tasks[j].id)) _tasks[j] = _tasks[j].copyWith(listId: l.id);
    }
    _changed({Slice.lists, Slice.tasks});
  }

  // ------------------------------------------------------------ voice capture

  /// Creates a note whose body is [text]. Returns null when [text] is blank.
  Note? addSpokenNote(String text) {
    final body = text.trim();
    if (body.isEmpty) return null;
    final n = draftNote().copyWith(body: body);
    upsertNote(n);
    return n;
  }

  /// Adds a recognised sentence to [voiceLog] when the user keeps one.
  void logRecognized(String transcript, SpokenTask parsed, {required String localeId}) {
    if (!_settings.keepVoiceLog) return;
    _voiceLog.insert(
      0,
      VoiceLogEntry(
        at: now(),
        localeId: localeId,
        transcript: transcript,
        title: parsed.title,
        due: parsed.due,
        hasTime: parsed.hasTime,
        remind: parsed.remind,
        isNote: parsed.isNote,
      ),
    );
    if (_voiceLog.length > voiceLogLimit) _voiceLog.removeRange(voiceLogLimit, _voiceLog.length);
    _voiceLogChanged();
  }

  void clearVoiceLog() {
    _voiceLog.clear();
    _voiceLogChanged();
  }

  void _voiceLogChanged() {
    _voiceLogDirty = true;
    _scheduleSave();
    // Settings shows the log.
    _changed({Slice.settings}, persist: false);
  }

  // ------------------------------------------------------------------ alarms

  AlarmAccess _alarmAccess = AlarmAccess.unsupported;

  /// The last known alarm permission; read after [load] and on every resume.
  AlarmAccess get alarmAccess => _alarmAccess;

  /// Whether the "Alert type" choice is offered (iOS 26+).
  bool get alarmSupported => alarmAccess != AlarmAccess.unsupported;

  /// Whether an alert of [kind] is installed as an alarm right now.
  bool ringsAsAlarm(AlertKind kind) => kind == AlertKind.alarm && _alarmAccess == AlarmAccess.authorized;

  /// Reads the alarm permission without asking; a change re-installs the
  /// alerts (a revoked permission turns alarms into notifications).
  Future<void> refreshAlarmAccess() async {
    _setAlarmAccess(await alarms.access());
  }

  /// Asks for alarm permission only while it was never decided. True when
  /// alarms may be set.
  Future<bool> ensureAlarmAccess() async {
    await refreshAlarmAccess();
    if (_alarmAccess == AlarmAccess.notDetermined) _setAlarmAccess(await alarms.requestAccess());
    return _alarmAccess == AlarmAccess.authorized;
  }

  void _setAlarmAccess(AlarmAccess a) {
    if (a == _alarmAccess) return;
    _alarmAccess = a;
    _changed({Slice.settings}, persist: false);
  }

  // ----------------------------------------------------------- notifications

  Future<NotificationAccess> notificationAccess() async {
    if (await scheduler.isGranted()) return NotificationAccess.granted;
    return _settings.notificationsAsked ? NotificationAccess.denied : NotificationAccess.notAsked;
  }

  /// Asks the OS for notification permission (it prompts only the first
  /// time) and remembers that the app has asked.
  Future<bool> requestNotifications() {
    if (!_settings.notificationsAsked) updateSettings(_settings.copyWith(notificationsAsked: true));
    return scheduler.requestPermission();
  }

  /// Asks for notifications only if the app has never asked and they are
  /// not already allowed.
  Future<void> ensureNotificationPermission() async {
    if (_settings.notificationsAsked) return;
    final access = await notificationAccess();
    // A second caller may have asked while this one waited.
    if (access != NotificationAccess.notAsked || _settings.notificationsAsked) return;
    await requestNotifications();
  }

  // -------------------------------------------------------------- reminders

  Reminder draftReminder({DateTime? at}) {
    final t = now();
    final next = at ?? DateTime(t.year, t.month, t.day, t.hour + 1);
    return Reminder(id: newId(), title: '', at: next, createdAt: t);
  }

  void upsertReminder(Reminder r) {
    final i = _reminders.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      _reminders[i] = r;
    } else {
      _reminders.add(r);
    }
    _changed({Slice.reminders});
  }

  Reminder? deleteReminder(String id) {
    final i = _reminders.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final r = _reminders.removeAt(i);
    _changed({Slice.reminders});
    return r;
  }

  void restoreReminder(Reminder r) => upsertReminder(r);

  void toggleReminder(String id) {
    final i = _reminders.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _reminders[i] = _reminders[i].copyWith(enabled: !_reminders[i].enabled);
    _changed({Slice.reminders});
  }

  /// Next occurrences after now, soonest first.
  List<(Reminder, DateTime)> upcomingReminders({int limit = 5}) {
    final t = now();
    final list = <(Reminder, DateTime)>[
      for (final r in _reminders)
        if (r.enabled)
          if (r.nextOccurrence(t) case final next?) (r, next),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return list.take(limit).toList();
  }

  // ----------------------------------------------------------------- habits

  void upsertHabit(Habit h) {
    final i = _habits.indexWhere((x) => x.id == h.id);
    if (i >= 0) {
      _habits[i] = h;
    } else {
      _habits.add(h);
    }
    _changed({Slice.habits});
  }

  void toggleHabit(String id, DateTime day) {
    final i = _habits.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _habits[i] = _habits[i].toggled(day);
    _changed({Slice.habits});
  }

  Habit? deleteHabit(String id) {
    final i = _habits.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final h = _habits.removeAt(i);
    _changed({Slice.habits});
    return h;
  }

  void restoreHabit(Habit h) => upsertHabit(h);

  // --------------------------------------------------------------- settings

  void updateSettings(AppSettings s) {
    final dropVoiceLog = _settings.keepVoiceLog && !s.keepVoiceLog;
    final calendarOff = _settings.showCalendar && !s.showCalendar;
    _settings = s;
    if (calendarOff) _clearCalendar();
    if (dropVoiceLog) {
      _voiceLog.clear();
      _voiceLogDirty = true; // the next save deletes the stored log
    }
    _changed({Slice.settings});
  }

  // ------------------------------------------------------------------ guide

  static String _knownStep(String step) {
    if (!AppSettings.guideSteps.contains(step)) throw ArgumentError.value(step, 'step', 'Unknown guide step');
    return step;
  }

  /// Whether the guide step [step] (one of [AppSettings.guideSteps]) is done.
  bool guideStepDone(String step) => _settings.guideDone.contains(_knownStep(step));

  /// Marks the guide step [step] done (or not done); saves only on a change.
  void markGuideStep(String step, {bool done = true}) {
    if (guideStepDone(step) == done) return;
    final next = done ? [..._settings.guideDone, step] : _settings.guideDone.where((s) => s != step).toList();
    updateSettings(_settings.copyWith(guideDone: List.unmodifiable(next)));
  }

  // --------------------------------------------------------------- calendar

  /// Last known calendar access; read from the system on the first week load,
  /// on [enableCalendar] and on [refreshCalendar]. Never prompts by itself.
  late CalendarAccess _calendarAccess =
      calendar.isSupported ? CalendarAccess.notAsked : CalendarAccess.unsupported;
  bool _calendarAccessRead = false;
  List<DeviceCalendarInfo> _deviceCalendars = const [];

  /// Events of the loaded week only; never stored (Slice.calendar).
  List<CalendarEvent> _calendarEvents = const [];

  /// The start of the week [_calendarEvents] belongs to.
  DateTime? _calendarWeek;

  /// The week a screen asked for last, loaded once the calendar is on.
  DateTime? _wantedCalendarWeek;
  DateTime? _loadingCalendarWeek;

  /// Bumped by every load and by [_clearCalendar]; an older load's answer is
  /// dropped.
  int _calendarGeneration = 0;
  Future<void>? _calendarLoad;

  CalendarAccess get calendarAccess => _calendarAccess;

  /// The system access was read and the user was never asked, e.g. settings
  /// restored to a new device with the calendar on. Plan then offers
  /// "Show calendar" again; [enableCalendar] asks.
  bool get calendarNeedsAccess => _calendarAccessRead && _calendarAccess == CalendarAccess.notAsked;
  UnmodifiableListView<DeviceCalendarInfo> get deviceCalendars => UnmodifiableListView(_deviceCalendars);

  bool get _calendarShown => _settings.showCalendar && _calendarAccess == CalendarAccess.granted;

  DateTime _weekOf(DateTime day) => startOfWeek(day, mondayFirst: _settings.mondayFirst);

  /// Asks for calendar access (only while it was never decided) when the user
  /// turns the calendar on. On success shows the calendar and loads the
  /// calendars and the wanted week.
  Future<bool> enableCalendar() async {
    if (!calendar.isSupported) return false;
    var a = await _readAccess();
    if (a == CalendarAccess.notAsked) a = await calendar.request();
    _setCalendarAccess(a);
    if (a != CalendarAccess.granted) {
      _changed({Slice.calendar}, persist: false);
      return false;
    }
    if (!_settings.showCalendar) updateSettings(_settings.copyWith(showCalendar: true));
    await _loadDeviceCalendars();
    await loadCalendarWeek(_wantedCalendarWeek ?? now());
    _changed({Slice.calendar}, persist: false);
    return true;
  }

  /// Loads the events of [day]'s week, [week start, +7 days). Does nothing when
  /// that week is already loaded or loading, or while the calendar is off.
  Future<void> loadCalendarWeek(DateTime day) => _requestWeek(_weekOf(day));

  /// [force] reads the week again even when it is loaded; the loaded events
  /// stay on screen until the new ones arrive.
  Future<void> _requestWeek(DateTime week, {bool force = false}) async {
    _wantedCalendarWeek = week;
    if (!calendar.isSupported || !_settings.showCalendar) return;
    if (!force) {
      if (week == _calendarWeek) return;
      if (week == _loadingCalendarWeek && _calendarLoad != null) return _calendarLoad;
    }
    _loadingCalendarWeek = week;
    final load = _loadWeek(week, ++_calendarGeneration);
    _calendarLoad = load;
    try {
      await load;
    } finally {
      if (identical(_calendarLoad, load)) {
        _calendarLoad = null;
        _loadingCalendarWeek = null;
      }
    }
  }

  Future<void> _loadWeek(DateTime week, int generation) async {
    if (!_calendarAccessRead) {
      _setCalendarAccess(await _readAccess());
      if (_calendarAccess == CalendarAccess.granted && _deviceCalendars.isEmpty) await _loadDeviceCalendars();
    }
    if (_calendarAccess != CalendarAccess.granted) {
      _clearCalendar();
      _changed({Slice.calendar}, persist: false);
      return;
    }
    List<CalendarEvent> events;
    try {
      events = await calendar.events(week, addDays(week, 7));
    } catch (e) {
      // The week stays loaded (empty) so screens do not ask again and again;
      // the next resume tries again.
      debugPrint('Calendar events failed: $e');
      events = const [];
    }
    // A newer load, a revoked access or the switch turned off won meanwhile.
    if (generation != _calendarGeneration || !_calendarShown) return;
    _calendarEvents = List.unmodifiable(events);
    _calendarWeek = week;
    _changed({Slice.calendar}, persist: false);
  }

  /// Reads the access again (it may have changed in the system Settings) and
  /// reloads the loaded week. Called on every resume.
  Future<void> refreshCalendar() async {
    if (!calendar.isSupported) return;
    _setCalendarAccess(await _readAccess());
    if (!_calendarShown) {
      _clearCalendar();
      _changed({Slice.calendar}, persist: false);
      return;
    }
    await _loadDeviceCalendars();
    // The week a screen wants now; usually the loaded one.
    final week = _wantedCalendarWeek ?? _calendarWeek;
    if (week != null) await _requestWeek(week, force: true);
    _changed({Slice.calendar}, persist: false);
  }

  /// The visible events touching [day] (from the loaded week): all-day ones
  /// first, then by start time. Empty without access.
  List<CalendarEvent> eventsOn(DateTime day) {
    final week = _calendarWeek;
    if (_calendarAccess != CalendarAccess.granted || week == null) return const [];
    final d = dateOnly(day);
    if (d.isBefore(week) || !d.isBefore(addDays(week, 7))) return const [];
    final hidden = _settings.hiddenCalendarIds.toSet();
    return [
      for (final e in _calendarEvents)
        if (!hidden.contains(e.calendarId) && e.occursOn(d)) e,
    ]..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
  }

  /// Shows or hides one calendar's events (Settings).
  void setCalendarHidden(String id, bool hidden) {
    final ids = [..._settings.hiddenCalendarIds]..remove(id);
    if (hidden) ids.add(id);
    updateSettings(_settings.copyWith(hiddenCalendarIds: List.unmodifiable(ids)));
    _changed({Slice.calendar}, persist: false);
  }

  Future<CalendarAccess> _readAccess() async {
    try {
      return await calendar.access();
    } catch (e) {
      debugPrint('Calendar access failed: $e');
      return CalendarAccess.denied;
    } finally {
      // Only once the answer is in: until then [calendarNeedsAccess] must not
      // take the initial notAsked for a read one.
      _calendarAccessRead = true;
    }
  }

  Future<void> _loadDeviceCalendars() async {
    try {
      _deviceCalendars = List.unmodifiable(await calendar.calendars());
    } catch (e) {
      debugPrint('Calendars failed: $e');
      _deviceCalendars = const [];
    }
  }

  void _setCalendarAccess(CalendarAccess a) {
    _calendarAccess = a;
    if (a != CalendarAccess.granted) _clearCalendar();
  }

  /// Forgets every event and calendar read from the device.
  void _clearCalendar() {
    _calendarGeneration++;
    _calendarEvents = const [];
    _calendarWeek = null;
    _loadingCalendarWeek = null;
    _calendarLoad = null;
    if (_calendarAccess != CalendarAccess.granted) _deviceCalendars = const [];
  }

  // ----------------------------------------------------------------- agenda

  /// Tasks, reminders and (when the calendar is shown) calendar events on
  /// [day]: timed entries by time, all-day ones last.
  List<AgendaEntry> agenda(DateTime day) => _agenda(day, withEvents: true);

  List<AgendaEntry> _agenda(DateTime day, {required bool withEvents}) {
    // A timed event that began on an earlier day shows from this day's 00:00.
    final dayStart = dateOnly(day);
    final entries = <AgendaEntry>[
      for (final t in tasksDueOn(day))
        AgendaEntry(
          kind: AgendaKind.task,
          id: t.id,
          title: t.title,
          time: t.hasTime ? t.due : null,
          done: t.done,
          colorIndex: t.colorIndex,
        ),
      for (final r in _reminders)
        if (r.enabled)
          if (r.occurrenceOn(day) case final at?)
            AgendaEntry(
              kind: AgendaKind.reminder,
              id: r.id,
              title: r.title,
              time: at,
              done: false,
              colorIndex: r.colorIndex,
              repeat: r.repeat,
            ),
      if (withEvents && _calendarShown)
        for (final e in eventsOn(day))
          AgendaEntry(
            kind: AgendaKind.event,
            id: e.id,
            title: e.title,
            time: e.allDay ? null : (e.start.isBefore(dayStart) ? dayStart : e.start),
            end: e.allDay ? null : e.end,
            done: false,
            colorIndex: 0,
            color: e.color,
          ),
    ];
    entries.sort((a, b) {
      if ((a.time == null) != (b.time == null)) return a.time == null ? 1 : -1;
      if (a.time != null) return a.time!.compareTo(b.time!);
      return 0;
    });
    return entries;
  }

  /// How many agenda entries each day in [from, from + days) has.
  Map<String, int> busyDays(DateTime from, int days) {
    final out = <String, int>{};
    final start = dateOnly(from);
    for (final t in _tasks) {
      if (t.due == null) continue;
      final d = dateOnly(t.due!);
      final diff = d.difference(start).inHours;
      if (diff >= 0 && diff < days * 24 + 2) out.update(dayKey(d), (v) => v + 1, ifAbsent: () => 1);
    }
    for (var i = 0; i < days; i++) {
      final d = addDays(start, i);
      for (final r in _reminders) {
        if (r.enabled && r.occursOn(d)) out.update(dayKey(d), (v) => v + 1, ifAbsent: () => 1);
      }
      if (_calendarShown) {
        final n = eventsOn(d).length;
        if (n > 0) out.update(dayKey(d), (v) => v + n, ifAbsent: () => n);
      }
    }
    return out;
  }

  /// The JSON the home-screen widgets render. Calendar events stay out: they
  /// are shown only in Plan.
  Map<String, Object?> todaySummary() {
    final s = strings;
    final t = now();
    final entries = _agenda(t, withEvents: false);
    final ordered = [...entries.where((e) => !e.done), ...entries.where((e) => e.done)];
    final (done, total) = progressOn(t);
    final next = upcomingReminders(limit: 1);
    return {
      'updatedAt': t.toIso8601String(),
      'lang': s.locale,
      'title': s.today,
      'dateLabel': DateFormat('d MMMM EEEE', s.locale).format(t),
      'done': done,
      'total': total,
      'progressLabel': s.progressLabel(done, total),
      'emptyText': s.nothingToday,
      'items': [
        for (final e in ordered.take(6))
          {
            'title': e.title,
            'time': e.time == null ? '' : hhmm(e.time!),
            'kind': e.kind.name,
            'done': e.done,
            'color': _hexColor(e.colorIndex),
          },
      ],
      'nextReminder': next.isEmpty || !isSameDay(next.first.$2, t)
          ? null
          : {'title': next.first.$1.title, 'time': hhmm(next.first.$2)},
    };
  }

  /// The JSON the iOS list widget renders (`pamnot_lists`): every list with,
  /// per box, the number of open tasks and the first six in matrix order.
  /// Finished tasks stay out. The field names are read by the widget.
  Map<String, Object?> listsSummary() {
    final s = strings;
    final t = now();
    String time(TaskItem x) {
      if (x.due == null || !x.hasTime) return '';
      final at = hhmm(x.due!);
      return isSameDay(x.due!, t) ? at : '${DateFormat('d MMM', s.locale).format(x.due!)} $at';
    }

    return {
      'updatedAt': t.toIso8601String(),
      'lang': s.locale,
      'labels': {'all': s.widgetAll, 'empty': s.widgetEmpty, 'appName': 'Pamnot'},
      'boxes': {for (final q in Quadrant.values) q.name: s.quadrantTitle(q)},
      'lists': [
        for (final l in _lists)
          {
            'id': l.id,
            'name': l.name,
            'color': _hexColor(l.colorIndex),
            'boxes': {
              for (final q in Quadrant.values)
                q.name: () {
                  final open = tasksIn(l.id, q);
                  return {
                    'count': open.length,
                    'items': [
                      for (final x in open.take(6)) {'id': x.id, 'title': x.title, 'time': time(x)},
                    ],
                  };
                }(),
            },
          },
      ],
    };
  }

  static String _hexColor(int i) =>
      '#${(pastelAt(i).accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // ------------------------------------------------------------- prediction

  List<String> suggest(String textBeforeCursor) {
    final p = _predictor;
    if (p == null || !_settings.prediction) return const [];
    return p.suggest(textBeforeCursor, lang: _fixedPredictionLang, fallback: _uiLang);
  }

  void acceptedSuggestion(String textBeforeCursor, String word) {
    final p = _predictor;
    if (p == null) return;
    final ctx = WordContext.of(textBeforeCursor);
    final lang = _fixedPredictionLang ?? p.detect(textBeforeCursor, fallback: _uiLang);
    p.reinforce(ctx.previous, word, lang);
  }

  /// "tr" or "en", for handwriting recognition and date formats.
  String get writingLanguage => isTurkish ? 'tr' : 'en';
}
