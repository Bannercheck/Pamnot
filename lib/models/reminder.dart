import '../core/dates.dart';

enum Repeat { none, daily, weekly, monthly, yearly }

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    this.note = '',
    required this.at,
    this.repeat = Repeat.none,
    this.enabled = true,
    this.colorIndex = 1,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String note;

  /// First occurrence. Repeating reminders recur from here.
  final DateTime at;
  final Repeat repeat;
  final bool enabled;
  final int colorIndex;
  final DateTime createdAt;

  /// Whether the reminder fires on [day] (any time that day).
  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    final start = dateOnly(at);
    if (d.isBefore(start)) return false;
    return switch (repeat) {
      Repeat.none => isSameDay(d, start),
      Repeat.daily => true,
      Repeat.weekly => d.weekday == start.weekday,
      Repeat.monthly => d.day == start.day,
      Repeat.yearly => d.day == start.day && d.month == start.month,
    };
  }

  /// The occurrence on [day], or null when it doesn't fire that day.
  DateTime? occurrenceOn(DateTime day) =>
      occursOn(day) ? DateTime(day.year, day.month, day.day, at.hour, at.minute) : null;

  /// The first occurrence strictly after [from], or null for a past one-off.
  /// Monthly reminders on the 29th–31st skip months without that day, which
  /// matches how iOS and Android repeat calendar notifications.
  DateTime? nextOccurrence(DateTime from) {
    if (!at.isAfter(from) && repeat == Repeat.none) return null;
    if (at.isAfter(from)) return at;
    switch (repeat) {
      case Repeat.none:
        return null;
      case Repeat.daily:
        var c = DateTime(from.year, from.month, from.day, at.hour, at.minute);
        if (!c.isAfter(from)) c = addDays(c, 1);
        return c;
      case Repeat.weekly:
        var c = DateTime(from.year, from.month, from.day, at.hour, at.minute);
        c = addDays(c, (at.weekday - c.weekday) % 7);
        if (!c.isAfter(from)) c = addDays(c, 7);
        return c;
      case Repeat.monthly:
        var y = from.year, m = from.month;
        for (var i = 0; i < 48; i++) {
          if (at.day <= daysInMonth(y, m)) {
            final c = DateTime(y, m, at.day, at.hour, at.minute);
            if (c.isAfter(from)) return c;
          }
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
        }
        return null;
      case Repeat.yearly:
        for (var y = from.year; y < from.year + 9; y++) {
          if (at.day <= daysInMonth(y, at.month)) {
            final c = DateTime(y, at.month, at.day, at.hour, at.minute);
            if (c.isAfter(from)) return c;
          }
        }
        return null;
    }
  }

  Reminder copyWith({
    String? title,
    String? note,
    DateTime? at,
    Repeat? repeat,
    bool? enabled,
    int? colorIndex,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        at: at ?? this.at,
        repeat: repeat ?? this.repeat,
        enabled: enabled ?? this.enabled,
        colorIndex: colorIndex ?? this.colorIndex,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (note.isNotEmpty) 'note': note,
        'at': at.toIso8601String(),
        'repeat': repeat.name,
        'enabled': enabled,
        'color': colorIndex,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, Object?> j) => Reminder(
        id: j['id']! as String,
        title: (j['title'] as String?) ?? '',
        note: (j['note'] as String?) ?? '',
        at: DateTime.parse(j['at']! as String),
        repeat: Repeat.values.firstWhere((r) => r.name == j['repeat'],
            orElse: () => Repeat.none),
        enabled: j['enabled'] != false,
        colorIndex: (j['color'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.parse(j['createdAt']! as String),
      );
}
