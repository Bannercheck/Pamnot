import '../core/dates.dart';

class Habit {
  const Habit({
    required this.id,
    required this.name,
    this.emoji = '🌿',
    this.colorIndex = 2,
    this.targetPerWeek = 7,
    this.checkins = const {},
    required this.createdAt,
  });

  final String id;
  final String name;
  final String emoji;
  final int colorIndex;

  /// 1..7 days a week.
  final int targetPerWeek;

  /// Day keys (yyyy-MM-dd) the habit was done.
  final Set<String> checkins;
  final DateTime createdAt;

  bool doneOn(DateTime day) => checkins.contains(dayKey(day));

  int countInWeek(DateTime weekStart) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (doneOn(addDays(weekStart, i))) n++;
    }
    return n;
  }

  /// Consecutive days done, ending today, or ending yesterday when today is
  /// still open (so the streak doesn't look broken in the morning).
  int streak(DateTime today) {
    var d = dateOnly(today);
    if (!doneOn(d)) d = addDays(d, -1);
    var n = 0;
    while (doneOn(d)) {
      n++;
      d = addDays(d, -1);
    }
    return n;
  }

  Habit toggled(DateTime day) {
    final k = dayKey(day);
    final next = {...checkins};
    if (!next.remove(k)) next.add(k);
    return copyWith(checkins: next);
  }

  Habit copyWith({
    String? name,
    String? emoji,
    int? colorIndex,
    int? targetPerWeek,
    Set<String>? checkins,
  }) =>
      Habit(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        colorIndex: colorIndex ?? this.colorIndex,
        targetPerWeek: targetPerWeek ?? this.targetPerWeek,
        checkins: checkins ?? this.checkins,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': colorIndex,
        'target': targetPerWeek,
        'checkins': (checkins.toList()..sort()),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Habit.fromJson(Map<String, Object?> j) => Habit(
        id: j['id']! as String,
        name: (j['name'] as String?) ?? '',
        emoji: (j['emoji'] as String?) ?? '🌿',
        colorIndex: (j['color'] as num?)?.toInt() ?? 2,
        targetPerWeek: ((j['target'] as num?)?.toInt() ?? 7).clamp(1, 7),
        checkins: ((j['checkins'] as List?) ?? const []).cast<String>().toSet(),
        createdAt: DateTime.parse(j['createdAt']! as String),
      );
}
