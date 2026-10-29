import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../core/quick_parse.dart';
import '../data/store.dart';
import '../l10n/strings.dart';
import '../models/habit.dart';
import '../models/ink.dart';
import '../models/note.dart';
import '../models/reminder.dart';
import '../models/settings.dart';
import '../models/task.dart';
import '../prediction/word_predictor.dart';
import '../services/handwriting.dart';
import '../services/reminder_scheduler.dart';
import '../services/widget_sync.dart';
import '../theme/pamnot_theme.dart';
import 'sample_data.dart';

/// Parts of the state a screen can subscribe to; a change to one slice only
/// rebuilds the widgets that asked for it.
enum Slice { notes, tasks, reminders, habits, settings }

enum AgendaKind { task, reminder }

class AgendaEntry {
  const AgendaEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.time,
    required this.done,
    required this.colorIndex,
    this.repeat = Repeat.none,
  });

  final AgendaKind kind;
  final String id;
  final String title;

  /// Null for all-day entries.
  final DateTime? time;
  final bool done;
  final int colorIndex;
  final Repeat repeat;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    ReminderScheduler? scheduler,
    WidgetSync? widgetSync,
    HandwritingRecognizer? handwriting,
    DateTime Function()? clock,
    this.saveDelay = const Duration(milliseconds: 400),
  })  : scheduler = scheduler ?? NoopScheduler(),
        widgetSync = widgetSync ?? NoopWidgetSync(),
        handwriting = handwriting ?? UnsupportedRecognizer(),
        now = clock ?? DateTime.now;

  final KeyValueStore store;
  final ReminderScheduler scheduler;
  final WidgetSync widgetSync;
  final HandwritingRecognizer handwriting;
  final DateTime Function() now;
  final Duration saveDelay;
  static const _uuid = Uuid();

  String newId() => _uuid.v4();

  List<Note> _notes = [];
  List<TaskItem> _tasks = [];
  List<Reminder> _reminders = [];
  List<Habit> _habits = [];
  AppSettings _settings = const AppSettings();
  WordPredictor? _predictor;
  bool _loaded = false;

  UnmodifiableListView<Note> get notes => UnmodifiableListView(_notes);
  UnmodifiableListView<TaskItem> get tasks => UnmodifiableListView(_tasks);
  UnmodifiableListView<Reminder> get reminders => UnmodifiableListView(_reminders);
  UnmodifiableListView<Habit> get habits => UnmodifiableListView(_habits);
  AppSettings get settings => _settings;
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

  Future<void> load() async {
    final keys = ['settings', 'notes', 'tasks', 'reminders', 'habits'];
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
    _inkPending.addAll([for (final j in noteJson) if (j['hasInk'] == true) j['id']! as String]);
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
      _changed(Slice.values.toSet(), persist: false);
    }
    unawaited(_loadInk());
    _scheduleMidnight();
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
    if (_dirty.isEmpty && _dirtyInk.isEmpty) return;
    final dirty = {..._dirty};
    final inkIds = {..._dirtyInk};
    _dirty.clear();
    _dirtyInk.clear();
    final done = Completer<void>();
    _saving = done.future;
    try {
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
      Slice.settings => const [],
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
      _dirty.addAll(slices);
      _scheduleSave();
    }
    if (slices.contains(Slice.tasks) || slices.contains(Slice.reminders) || slices.contains(Slice.settings)) {
      _alertTimer?.cancel();
      _alertTimer = Timer(const Duration(milliseconds: 800), () => unawaited(syncAlerts()));
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
        if (r.enabled) Alert(key: 'r:${r.id}', title: r.title, body: r.note.isEmpty ? s.reminder : r.note, at: r.at, repeat: r.repeat),
      for (final t in _tasks)
        if (!t.done && t.remindAt != null)
          Alert(key: 't:${t.id}', title: t.title, body: t.notes.isEmpty ? s.task : t.notes, at: t.remindAt!),
    ];
  }

  Future<void> syncAlerts() => scheduler.sync(alerts());

  Future<void> syncWidget() => widgetSync.push(todaySummary());

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

  TaskItem draftTask({DateTime? due, bool hasTime = false}) =>
      TaskItem(id: newId(), title: '', due: due, hasTime: hasTime, createdAt: now());

  void upsertTask(TaskItem t) {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _tasks[i] = t;
    } else {
      _tasks.add(t);
    }
    _changed({Slice.tasks});
  }

  /// Creates a task from a quick-capture line ("yarın 10:00 toplantı").
  TaskItem? addQuickTask(String text) {
    final r = quickParse(text, now());
    if (r.title.isEmpty) return null;
    final t = draftTask(due: r.due, hasTime: r.hasTime).copyWith(title: r.title);
    upsertTask(t);
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

  void restoreTask(TaskItem t) => upsertTask(t);

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
    _settings = s;
    _changed({Slice.settings});
  }

  // ----------------------------------------------------------------- agenda

  List<AgendaEntry> agenda(DateTime day) {
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
    }
    return out;
  }

  /// The JSON the home-screen widgets render.
  Map<String, Object?> todaySummary() {
    final s = strings;
    final t = now();
    final entries = agenda(t);
    final ordered = [...entries.where((e) => !e.done), ...entries.where((e) => e.done)];
    final (done, total) = progressOn(t);
    final next = upcomingReminders(limit: 1);
    String hex(int i) => '#${(pastelAt(i).accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
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
            'color': hex(e.colorIndex),
          },
      ],
      'nextReminder': next.isEmpty || !isSameDay(next.first.$2, t)
          ? null
          : {'title': next.first.$1.title, 'time': hhmm(next.first.$2)},
    };
  }

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
