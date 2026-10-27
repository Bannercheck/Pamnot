/// Calendar helpers. Days are local and compared without time.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Adds [days] calendar days, staying at the same wall-clock time across DST.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// First day of the week containing [d]; Monday unless [mondayFirst] is false.
DateTime startOfWeek(DateTime d, {bool mondayFirst = true}) {
  final day = dateOnly(d);
  final offset = mondayFirst ? (day.weekday - DateTime.monday) : (day.weekday % 7);
  return addDays(day, -offset);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
