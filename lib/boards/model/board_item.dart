/// One piece of board content with per-field values (`f`), per-field HLCs
/// (`h`) and the set of fields not yet confirmed by the server (`d`).
library;

enum ItemKind { meta, column, card, sticky, ink }

ItemKind? itemKindFromName(String? name) {
  for (final k in ItemKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// Field names, so a typo is a compile error.
abstract final class F {
  static const title = 'title';
  static const colorIndex = 'colorIndex';
  static const laneX = 'laneX';
  static const laneY = 'laneY';
  static const isDone = 'isDone';
  static const order = 'order';
  static const deleted = 'deleted';
  static const notes = 'notes';
  static const columnId = 'columnId';
  static const due = 'due';
  static const subtasks = 'subtasks';
  static const assigneeId = 'assigneeId';
  static const x = 'x';
  static const y = 'y';
  static const z = 'z';
  static const text = 'text';
  static const strokes = 'strokes';
}

class CardSubtask {
  const CardSubtask({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  CardSubtask copyWith({String? title, bool? done}) =>
      CardSubtask(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'done': done};

  static CardSubtask? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    return CardSubtask(id: id, title: (j['title'] as String?) ?? '', done: j['done'] == true);
  }
}

class BoardItem {
  BoardItem({
    required this.id,
    required this.kind,
    Map<String, Object?>? f,
    Map<String, String>? h,
    Set<String>? d,
  })  : f = f ?? {},
        h = h ?? {},
        d = d ?? {};

  final String id;
  final ItemKind kind;

  /// Field values. JSON-safe only: num, String, bool, null, List, Map.
  final Map<String, Object?> f;

  /// Field HLCs.
  final Map<String, String> h;

  /// Dirty fields: edited here, not yet acknowledged by the server.
  final Set<String> d;

  bool get deleted => f[F.deleted] == true;
  bool get live => !deleted;

  String get title => _str(F.title);
  String get notes => _str(F.notes);
  String get text => _str(F.text);
  String? get columnId => f[F.columnId] as String?;
  String? get assigneeId => f[F.assigneeId] as String?;
  String? get strokes => f[F.strokes] as String?;
  bool get isDone => f[F.isDone] == true;
  int get colorIndex => (f[F.colorIndex] as num?)?.toInt() ?? 0;
  double get order => _num(F.order);
  double get x => _num(F.x);
  double get y => _num(F.y);
  double get z => _num(F.z);
  double get laneX => _num(F.laneX);
  double get laneY => _num(F.laneY);

  /// Due date as `yyyy-MM-dd`, or null.
  String? get due => f[F.due] as String?;

  DateTime? get dueDate {
    final s = due;
    if (s == null || s.length != 10) return null;
    return DateTime.tryParse(s);
  }

  List<CardSubtask> get subtasks {
    final raw = f[F.subtasks];
    if (raw is! List) return const [];
    return [for (final e in raw) ?CardSubtask.fromJson(e)];
  }

  String _str(String k) => (f[k] as String?) ?? '';
  double _num(String k) => (f[k] as num?)?.toDouble() ?? 0;

  BoardItem copy() => BoardItem(id: id, kind: kind, f: {...f}, h: {...h}, d: {...d});

  /// The local document form. Ink strokes are stored separately, so they
  /// are left out here; their HLC stays.
  Map<String, Object?> toJson() => {
        'k': kind.name,
        'f': {for (final e in f.entries) if (e.key != F.strokes) e.key: e.value},
        'h': h,
        if (d.isNotEmpty) 'd': d.toList()..sort(),
      };

  static BoardItem? fromJson(String id, Object? j) {
    if (j is! Map) return null;
    final kind = itemKindFromName(j['k'] as String?);
    if (kind == null) return null;
    final f = (j['f'] as Map?)?.cast<String, Object?>() ?? {};
    final h = <String, String>{
      for (final e in ((j['h'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    final d = {for (final e in ((j['d'] as List?) ?? const [])) if (e is String) e};
    return BoardItem(id: id, kind: kind, f: {...f}, h: h, d: d);
  }
}

/// Date helper for the `due` field.
String dueKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
