/// Reads a day and a time out of one spoken sentence (design §6.4). The
/// clock-free clean-up lives in `normalize.dart`; everything here needs `now`.
library;

import '../dates.dart';
import '../turkish_text.dart' as tt;
import 'normalize.dart';
import 'spoken_task.dart';

/// [now]: konuşmanın bittiği an (yerel saat). Hiçbir girdi için istisna atmaz.
SpokenTask parseSpokenTask(String transcript, DateTime now, String lang) {
  final tr = lang == 'tr', en = lang == 'en';
  final spoken = normalizeSpoken(transcript, lang);
  if (spoken.isNote) {
    return SpokenTask(title: tt.capitalize(spoken.text, turkish: tr), isNote: true);
  }

  final s = _Sentence(spoken.text, turkish: tr);
  final duration = tr ? _durationTr(s) : en ? _durationEn(s) : null;
  if (duration != null) {
    final at = now.add(duration);
    return SpokenTask(
      title: _title(s, tr: tr, en: en),
      due: DateTime(at.year, at.month, at.day, at.hour, at.minute),
      hasTime: true,
      remind: spoken.remind,
    );
  }

  final clock = tr ? _clockTr(s) : en ? _clockEn(s) : _clockDigits(s);
  final day = _day(s, dateOnly(now), tr ? _dayRulesTr : en ? _dayRulesEn : const []) ??
      ((clock?.today ?? false) ? _Day(dateOnly(now), isToday: true) : null);
  final partOfDay = clock?.partOfDay ?? day?.partOfDay ?? (tr ? _partOfDayTr(s) : en ? _partOfDayEn(s) : null);
  final title = _title(s, tr: tr, en: en);
  if (clock == null && partOfDay == null) {
    return SpokenTask(title: title, due: day?.date, remind: spoken.remind);
  }
  final (due, ambiguous) = _resolve(clock, partOfDay, day, now);
  return SpokenTask(title: title, due: due, hasTime: true, remind: spoken.remind, ambiguousHour: ambiguous);
}

// ---------------------------------------------------------------- sentence

/// The normalized sentence and its lowercase copy (same length). Matches are
/// found in [low]; cutting one blanks it, so earlier offsets stay valid.
class _Sentence {
  _Sentence(String text, {required bool turkish})
      : low = ' ${tt.lower(text, turkish: turkish)} ',
        _text = ' $text ' {
    if (low.length != _text.length) _text = low;
  }

  String _text;
  String low;

  void cut(Match m) => low = low.replaceRange(m.start, m.end, ' ' * (m.end - m.start));

  /// The spoken text without what was cut.
  String get rest {
    final b = StringBuffer();
    for (var i = 0; i < _text.length; i++) {
      b.write(low.codeUnitAt(i) == 0x20 ? ' ' : _text[i]);
    }
    return b.toString();
  }
}

String _title(_Sentence s, {required bool tr, required bool en}) {
  var t = s.rest
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'\s+([,;:])'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'([,;:])(?:\s*[,;:])+'), (m) => m[1]!)
      .replaceAll(RegExp(r'^[\s,;:.\-]+|[\s,;:.\-]+$'), '');
  if (en) t = t.replaceAll(RegExp(r'\s+(?:at|on|by|in|for|until)$'), '');
  return tt.capitalize(t, turkish: tr);
}

// Dart's \b only knows ASCII letters; these treat every Unicode letter as a
// word character.
const _b = r'(?<![\p{L}\p{N}])';
const _e = r'(?![\p{L}\p{N}])';

RegExp _re(String body) => RegExp('$_b(?:$body)$_e', unicode: true);

// ---------------------------------------------------------------- vocabulary

const _weekdaysTr = ['pazartesi', 'salı', 'çarşamba', 'perşembe', 'cuma', 'cumartesi', 'pazar'];
const _weekdaysEn = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const _monthsTr = [
  'ocak', 'şubat', 'mart', 'nisan', 'mayıs', 'haziran', 'temmuz', 'ağustos', 'eylül', 'ekim', 'kasım', 'aralık', //
];
const _monthsEn = [
  'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november',
  'december', //
];

/// Hour a part of day stands for when no hour is said (design §8.3).
const _partOfDayHours = {
  'sabah': 9, 'öğle': 12, 'öğlen': 12, 'öğleyin': 12, 'öğleden sonra': 15, 'akşam': 19, 'gece': 22, //
  'morning': 9, 'afternoon': 15, 'evening': 19, 'tonight': 19, 'night': 22,
};
const _partsTr = 'öğleden sonra|öğleyin|öğlen|öğle|sabah|akşam|gece';
const _partsEn = 'morning|afternoon|evening|night';

/// Nouns that make a part of day part of a name: "akşam yemeği" is dinner,
/// not 19:00.
const _compound = r'yemeğ\p{L}*|yemek\p{L}*|kahvaltı\p{L}*|kahve\p{L}*|koşu\p{L}*|yürüyüş\p{L}*|namaz\p{L}*|'
    r'haber\p{L}*|kremi|lambası|vardiya\p{L}*|mesai\p{L}*|toplantısı|dersi|sporu|arası|tatil\p{L}*|uyku\p{L}*';
const _notCompound = '(?!\\s+(?:$_compound)$_e)';
const _partTailTr = '(?:\\s+($_partsTr)$_notCompound)?';
const _partTailEn = '(?:\\s+($_partsEn))?';

// ---------------------------------------------------------------- durations

final _halfHourTr = _re(r'yarım\s+saat\s+sonra');
final _laterTr = _re(r'(\d{1,3})(\s+buçuk)?\s+(saat|dakika|dk)\s+sonra');
final _halfHourEn = _re(r'in\s+half\s+an\s+hour');
final _laterEn = _re(r'in\s+(\d{1,3}|an?)\s+(hours?|minutes?|mins?)');

Duration? _durationTr(_Sentence s) {
  final half = _halfHourTr.firstMatch(s.low);
  if (half != null) {
    s.cut(half);
    return const Duration(minutes: 30);
  }
  final m = _laterTr.firstMatch(s.low);
  if (m == null) return null;
  s.cut(m);
  final n = int.parse(m[1]!);
  return m[3] == 'saat' ? Duration(minutes: n * 60 + (m[2] != null ? 30 : 0)) : Duration(minutes: n);
}

Duration? _durationEn(_Sentence s) {
  final half = _halfHourEn.firstMatch(s.low);
  if (half != null) {
    s.cut(half);
    return const Duration(minutes: 30);
  }
  final m = _laterEn.firstMatch(s.low);
  if (m == null) return null;
  s.cut(m);
  final n = int.tryParse(m[1]!) ?? 1;
  return m[2]!.startsWith('h') ? Duration(hours: n) : Duration(minutes: n);
}

// ---------------------------------------------------------------- time of day

/// How the hour was said, which decides how it is read (design §6.4).
enum _HourKind {
  /// 1–12 with nothing else: guessed by the bare-hour rule.
  bare,

  /// 0, 13–24 or with a leading zero ("08.30"): taken as is.
  literal,

  /// With am/pm, noon/midnight or a part of day: taken as is.
  explicit,
}

class _Clock {
  const _Clock(this.hour, this.minute, this.kind, {this.partOfDay, this.today = false});

  final int hour, minute;
  final _HourKind kind;
  final String? partOfDay;

  /// Said as "bu akşam 8'de": the day is today.
  final bool today;
}

_Clock? _fromDigits(String hourText, String? minuteText, {String? partOfDay, bool today = false}) {
  final h = int.parse(hourText), m = minuteText == null ? 0 : int.parse(minuteText);
  if (m > 59 || h > 24 || (h == 24 && m > 0)) return null;
  final literal = h == 0 || h > 12 || hourText.startsWith('0');
  return _Clock(h, m, literal ? _HourKind.literal : _HourKind.bare, partOfDay: partOfDay, today: today);
}

final _clockTrRe = _re("(?:(bu\\s+)?($_partsTr)\\s+)?(saat\\s+)?(\\d{1,2})(?:[:.](\\d{2}))?"
    "(?:('\\s?|\\s)?(de|da|te|ta|ye|ya|e|a)(?!\\p{L})(?:\\s+kadar)?)?");
final _fractionNext = RegExp(r'^\s+(?:bir|biri|birini|birde|1)(?![\p{L}\p{N}])', unicode: true);
final _unitNext = RegExp(r'^\s+(?:lira|liraya|tl|kuruş|dolar|euro|avro|kilo|kg|gram|gr|litre|lt|metre|m|cm|km)(?!\p{L})',
    unicode: true);
final _dative = RegExp(r'^y?[ae]$');

/// "saat 3'te", "akşam 8'de", "19.30'da", "saat 14", "10:00". A bare number
/// is never a time ("3 ekmek al", "10 sayfa oku"), nor is an amount
/// ("2.50 lira", "3'te 1").
_Clock? _clockTr(_Sentence s) {
  for (final m in _clockTrRe.allMatches(s.low)) {
    final partOfDay = m[2], saat = m[3] != null, hasMinute = m[5] != null;
    final sep = m[6], suffix = m[7];
    // A dative ("9'a") needs its apostrophe; a suffix after a space ("3 te")
    // needs "saat" or a part of day in front.
    final suffixOk = suffix != null &&
        (_dative.hasMatch(suffix)
            ? (sep?.startsWith("'") ?? false)
            : (sep == null || sep.startsWith("'") || saat || partOfDay != null));
    if (!(saat || hasMinute || suffixOk) || (suffix != null && !suffixOk)) continue;
    // "3'te 1", "üçte bir": a fraction, not a time.
    if (!saat && partOfDay == null) {
      final after = s.low.substring(m.end);
      if (_fractionNext.hasMatch(after) || (suffix == null && _unitNext.hasMatch(after))) continue;
    }
    final clock = _fromDigits(m[4]!, m[5], partOfDay: partOfDay, today: m[1] != null);
    if (clock == null) continue;
    s.cut(m);
    return clock;
  }
  return null;
}

final _ampmRe = _re(r"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|o'?clock)");
final _noonRe = _re(r'(?:at\s+)?(noon|midnight)');
final _atRe = _re(r'at\s+(\d{1,2})(?::(\d{2}))?');
final _colonRe = _re(r'(\d{1,2}):(\d{2})');

_Clock? _clockEn(_Sentence s) {
  for (final m in _ampmRe.allMatches(s.low)) {
    final suffix = m[3]!;
    if (suffix.startsWith('o')) {
      final clock = _fromDigits(m[1]!, m[2]);
      if (clock == null) continue;
      s.cut(m);
      return clock;
    }
    var h = int.parse(m[1]!);
    final minute = m[2] == null ? 0 : int.parse(m[2]!);
    if (h < 1 || h > 12 || minute > 59) continue;
    if (suffix.startsWith('p') && h < 12) h += 12;
    if (suffix.startsWith('a') && h == 12) h = 0;
    s.cut(m);
    return _Clock(h, minute, _HourKind.explicit);
  }
  final noon = _noonRe.firstMatch(s.low);
  if (noon != null) {
    s.cut(noon);
    return _Clock(noon[1] == 'noon' ? 12 : 24, 0, _HourKind.explicit);
  }
  for (final m in _atRe.allMatches(s.low)) {
    final clock = _fromDigits(m[1]!, m[2]);
    if (clock == null) continue;
    s.cut(m);
    return clock;
  }
  return _clockDigits(s);
}

/// "14:30" — the only time read in languages other than Turkish and English.
_Clock? _clockDigits(_Sentence s) {
  for (final m in _colonRe.allMatches(s.low)) {
    final clock = _fromDigits(m[1]!, m[2]);
    if (clock == null) continue;
    s.cut(m);
    return clock;
  }
  return null;
}

// ---------------------------------------------------------------- day

class _Day {
  const _Day(this.date, {this.isToday = false, this.partOfDay});

  final DateTime date;

  /// "bugün", "bu akşam", "tonight": the day was said, and it is today.
  final bool isToday;
  final String? partOfDay;
}

/// A pattern and what its match means; a null result (a date that does not
/// exist, like "32 ocak") leaves the words in the title.
typedef _DayRule = (RegExp, _Day? Function(Match m, DateTime today));

_Day? _day(_Sentence s, DateTime today, List<_DayRule> rules) {
  for (final (re, read) in rules) {
    for (final m in re.allMatches(s.low)) {
      final day = read(m, today);
      if (day == null) continue;
      s.cut(m);
      return day;
    }
  }
  return null;
}

int _weekday(String name) =>
    (_weekdaysTr.contains(name) ? _weekdaysTr.indexOf(name) : _weekdaysEn.indexOf(name)) + DateTime.monday;

/// The weekday in the coming calendar week ("haftaya salı", "next friday").
DateTime _nextWeek(DateTime today, int weekday) => addDays(startOfWeek(today), 7 + weekday - DateTime.monday);

/// The next such weekday; said on that very day, the one a week later.
DateTime _comingWeekday(DateTime today, int weekday) {
  final delta = (weekday - today.weekday) % 7;
  return addDays(today, delta == 0 ? 7 : delta);
}

/// "bu cuma": this week's day, today if said on it.
DateTime _thisWeekday(DateTime today, int weekday) => addDays(today, (weekday - today.weekday) % 7);

/// Saturday, or today when said on Saturday or Sunday.
DateTime _weekend(DateTime today) =>
    today.weekday >= DateTime.saturday ? today : addDays(today, DateTime.saturday - today.weekday);

DateTime _monthEnd(DateTime today) => DateTime(today.year, today.month, daysInMonth(today.year, today.month));

/// [n] days, weeks or months after today; a month later keeps the day, or
/// takes the month's last day when that month is shorter.
DateTime _later(DateTime today, int n, String unit) {
  if (unit == 'ay' || unit.startsWith('month')) {
    final last = daysInMonth(today.year, today.month + n);
    return DateTime(today.year, today.month + n, today.day > last ? last : today.day);
  }
  return addDays(today, unit == 'hafta' || unit.startsWith('week') ? 7 * n : n);
}

/// The next [day] of [month] from today on, skipping years where it does
/// not exist (29 Feb); null when it never does ("32 ocak").
DateTime? _nextDate(DateTime today, int month, int day) {
  for (var y = today.year; y <= today.year + 8; y++) {
    if (day < 1 || day > daysInMonth(y, month)) continue;
    final d = DateTime(y, month, day);
    if (!d.isBefore(today)) return d;
  }
  return null;
}

/// The next [day] of a month from today on, skipping months too short for it
/// ("ayın 31'i" in November → 31 December).
DateTime? _dayOfMonth(DateTime today, int day) {
  if (day < 1 || day > 31) return null;
  for (var i = 0; i < 12; i++) {
    if (day > daysInMonth(today.year, today.month + i)) continue;
    final d = DateTime(today.year, today.month + i, day);
    if (!d.isBefore(today)) return d;
  }
  return null;
}

_Day? _dayOf(DateTime? date) => date == null ? null : _Day(date);

const _weekdayTr = 'pazartesi|salı|çarşamba|perşembe|cuma|cumartesi|pazar';
const _weekdayEn = 'monday|tuesday|wednesday|thursday|friday|saturday|sunday';
const _nextWeekTr = r'(?:haftaya|gelecek\s+hafta|önümüzdeki\s+hafta)';

final _dayRulesTr = <_DayRule>[
  (_re(r'(\d{1,3})\s+(gün|hafta|ay)\s+sonra'), (m, t) => _Day(_later(t, int.parse(m[1]!), m[2]!))),
  (
    _re("(\\d{1,2})\\s+(${_monthsTr.join('|')})(?:'?(?:ta|da|te|de|ya|ye|a|e))?(?:\\s+kadar)?"),
    (m, t) => _dayOf(_nextDate(t, _monthsTr.indexOf(m[2]!) + 1, int.parse(m[1]!))),
  ),
  (_re(r"(?:ayın\s+)?(\d{1,2})'?s?[ıiuü]n(?:da|de|[ae]\s+kadar)"), (m, t) => _dayOf(_dayOfMonth(t, int.parse(m[1]!)))),
  (_re(r"ayın\s+(\d{1,2})'?s?[ıiuü]"), (m, t) => _dayOf(_dayOfMonth(t, int.parse(m[1]!)))),
  (
    _re('$_nextWeekTr\\s+($_weekdayTr)(?:\\s?(?:günü|ya|ye|a|e))?(?:\\s+kadar)?$_partTailTr'),
    (m, t) => _Day(_nextWeek(t, _weekday(m[1]!)), partOfDay: m[2]),
  ),
  (_re('$_nextWeekTr\\s+hafta\\s?sonu(?:na|nda)?'), (m, t) => _Day(_nextWeek(t, DateTime.saturday))),
  (_re('bu\\s+($_weekdayTr)$_partTailTr'), (m, t) => _Day(_thisWeekday(t, _weekday(m[1]!)), partOfDay: m[2])),
  (_re(r'(?:bu\s+)?hafta\s?sonu(?:na|nda)?(?:\s+kadar)?'), (m, t) => _Day(_weekend(t))),
  (_re(r'ay\s+sonu(?:na|nda)?(?:\s+kadar)?|ayın\s+sonunda'), (m, t) => _Day(_monthEnd(t))),
  (_re('(?:öbür\\s+gün|yarından\\s+sonra)$_partTailTr'), (m, t) => _Day(addDays(t, 2), partOfDay: m[1])),
  (_re('bu\\s+($_partsTr)$_notCompound'), (m, t) => _Day(t, isToday: true, partOfDay: m[1])),
  (_re('bugün$_partTailTr'), (m, t) => _Day(t, isToday: true, partOfDay: m[1])),
  (_re('yarın(?:a\\s+kadar|ki)?$_partTailTr'), (m, t) => _Day(addDays(t, 1), partOfDay: m[1])),
  (_re(_nextWeekTr), (m, t) => _Day(addDays(t, 7))),
  // "pazara git" is "go to the market": a weekday takes a dative only
  // before "kadar".
  (
    _re('($_weekdayTr)(?:\\s?(?:ya|ye|a|e)(?=\\s+kadar))?(?:\\s?günü)?(?:\\s+kadar)?$_partTailTr'),
    (m, t) => _Day(_comingWeekday(t, _weekday(m[1]!)), partOfDay: m[2]),
  ),
];

final _dayRulesEn = <_DayRule>[
  (_re(r'in\s+(\d{1,3}|an?)\s+(days?|weeks?|months?)'), (m, t) => _Day(_later(t, int.tryParse(m[1]!) ?? 1, m[2]!))),
  (
    _re("(?:on\\s+)?(${_monthsEn.join('|')})\\s+(\\d{1,2})(?:st|nd|rd|th)?"),
    (m, t) => _dayOf(_nextDate(t, _monthsEn.indexOf(m[1]!) + 1, int.parse(m[2]!))),
  ),
  (
    _re("(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(${_monthsEn.join('|')})"),
    (m, t) => _dayOf(_nextDate(t, _monthsEn.indexOf(m[2]!) + 1, int.parse(m[1]!))),
  ),
  (_re(r'(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)'), (m, t) => _dayOf(_dayOfMonth(t, int.parse(m[1]!)))),
  (
    _re('next\\s+(?:week\\s+)?($_weekdayEn)$_partTailEn'),
    (m, t) => _Day(_nextWeek(t, _weekday(m[1]!)), partOfDay: m[2]),
  ),
  (_re(r'next\s+weekend'), (m, t) => _Day(_nextWeek(t, DateTime.saturday))),
  (_re('this\\s+($_weekdayEn)$_partTailEn'), (m, t) => _Day(_thisWeekday(t, _weekday(m[1]!)), partOfDay: m[2])),
  (_re(r'(?:this\s+|the\s+|by\s+the\s+)?weekend'), (m, t) => _Day(_weekend(t))),
  (_re(r'(?:by\s+the\s+|at\s+the\s+)?end\s+of\s+(?:the\s+)?month'), (m, t) => _Day(_monthEnd(t))),
  (_re('day\\s+after\\s+tomorrow$_partTailEn'), (m, t) => _Day(addDays(t, 2), partOfDay: m[1])),
  (_re(r'this\s+(morning|afternoon|evening)|(tonight)'), (m, t) => _Day(t, isToday: true, partOfDay: m[1] ?? m[2])),
  (_re('today$_partTailEn'), (m, t) => _Day(t, isToday: true, partOfDay: m[1])),
  (_re('(?:by\\s+|for\\s+)?tomorrow$_partTailEn'), (m, t) => _Day(addDays(t, 1), partOfDay: m[1])),
  (_re(r'next\s+week'), (m, t) => _Day(addDays(t, 7))),
  (
    _re('(?:on\\s+|by\\s+)?($_weekdayEn)$_partTailEn'),
    (m, t) => _Day(_comingWeekday(t, _weekday(m[1]!)), partOfDay: m[2]),
  ),
];

// ---------------------------------------------------------------- part of day

final _partStartTr = RegExp('^\\s*($_partsTr|akşamleyin|sabahleyin)$_notCompound$_e', unicode: true);
final _partAnywhereTr = _re('(öğleden sonra|akşamleyin|sabahleyin)');
final _partEndTr = RegExp('$_b($_partsTr)\\s*\$', unicode: true);
final _partEn = _re(r'in\s+the\s+(morning|afternoon|evening)|at\s+(night)');

/// A part of day on its own: "akşam annemi ara", "annemi ara akşam".
String? _partOfDayTr(_Sentence s) {
  final m = _partStartTr.firstMatch(s.low) ?? _partAnywhereTr.firstMatch(s.low) ?? _partEndTr.firstMatch(s.low);
  if (m == null) return null;
  s.cut(m);
  return m[1]!.replaceFirst('leyin', '');
}

String? _partOfDayEn(_Sentence s) {
  final m = _partEn.firstMatch(s.low);
  if (m == null) return null;
  s.cut(m);
  return m[1] ?? m[2];
}

// ---------------------------------------------------------------- resolve

/// An hour said with a part of day: "akşam 8" → 20, "gece 2" → 26 (02:00
/// the next morning), "gece 12" → 24 (the coming midnight).
int _withPartOfDay(int h, String partOfDay) {
  if (h == 0 || h > 12) return h;
  return switch (partOfDay) {
    'sabah' || 'morning' => h == 12 ? 0 : h,
    'öğle' || 'öğlen' || 'öğleyin' => h <= 6 ? h + 12 : h,
    'gece' || 'night' => h == 12 ? 24 : (h <= 5 ? h + 24 : h + 12),
    _ => h < 12 ? h + 12 : h, // öğleden sonra, akşam, afternoon, evening, tonight
  };
}

/// The moment the task is due and whether its hour was guessed.
(DateTime, bool) _resolve(_Clock? clock, String? partOfDay, _Day? day, DateTime now) {
  final base = day?.date ?? dateOnly(now);
  final daySaid = day != null, todaySaid = day?.isToday ?? false;
  DateTime at(int h, int m) => DateTime(base.year, base.month, base.day, h, m);

  final minute = clock?.minute ?? 0;
  var kind = clock?.kind ?? _HourKind.explicit;
  var hour = clock?.hour ?? _partOfDayHours[partOfDay] ?? 12;
  if (clock != null && partOfDay != null && kind != _HourKind.explicit) {
    hour = _withPartOfDay(hour, partOfDay);
    kind = _HourKind.explicit;
  }
  // "gece 2'de" said between midnight and 05:00 means the coming 02:00,
  // which is still today.
  if (hour > 24 && (!daySaid || todaySaid) && now.hour < 5) hour -= 24;

  if (kind == _HourKind.bare) {
    // 1–6 afternoon, 7–11 morning, 12 noon; once passed, 7–9 turn to the
    // evening and the rest to tomorrow — unless a day was said.
    var due = at(hour <= 6 ? hour + 12 : hour, minute);
    if (!due.isAfter(now) && (!daySaid || todaySaid)) {
      final evening = at(hour + 12, minute);
      if (hour >= 7 && hour <= 9 && evening.isAfter(now)) {
        due = evening;
      } else if (!daySaid) {
        due = addDays(due, 1);
      }
    }
    return (due, hour <= 11);
  }
  var due = at(hour, minute);
  if (!due.isAfter(now) && !daySaid) due = addDays(due, 1);
  return (due, false);
}
