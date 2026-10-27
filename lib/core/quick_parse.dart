import 'dates.dart';
import 'turkish_text.dart' as tt;

class QuickParseResult {
  const QuickParseResult(this.title, this.due, this.hasTime);

  final String title;
  final DateTime? due;
  final bool hasTime;
}

const _weekdaysTr = ['pazartesi', 'salı', 'çarşamba', 'perşembe', 'cuma', 'cumartesi', 'pazar'];
const _weekdaysEn = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

// Dart's \b only knows ASCII letters, so "salı" would never end on a
// boundary. These look-arounds treat every Unicode letter as a word char.
const _b = r'(?<![\p{L}\p{N}])';
const _e = r'(?![\p{L}\p{N}])';

RegExp _re(String body) => RegExp('$_b$body$_e', unicode: true);

/// Pulls a date and time out of a quick-capture line in Turkish or English:
/// "yarın 10:00 toplantı", "cuma saat 14 sunum", "call mom tomorrow 6pm".
/// What is left becomes the title.
QuickParseResult quickParse(String input, DateTime now) {
  var text = ' ${input.trim()} ';
  final low = tt.lower(text);
  DateTime? day;
  int? hour, minute;

  String cut(String s, Match m) => s.replaceRange(m.start, m.end, ' ');

  // Times first, so "10:30" isn't read as anything else.
  final time = _re(r"(?:saat\s+|at\s+)?(\d{1,2})[:.](\d{2})(?:'?(?:de|da|te|ta))?").firstMatch(low) ??
      _re(r"saat\s+(\d{1,2})(?:'?(?:de|da|te|ta))?").firstMatch(low) ??
      _re(r'(\d{1,2})\s?(am|pm)').firstMatch(low) ??
      _re(r'at\s+(\d{1,2})').firstMatch(low);
  var work = low;
  if (time != null) {
    var h = int.parse(time.group(1)!);
    var m = 0;
    final g2 = time.groupCount >= 2 ? time.group(2) : null;
    if (g2 == 'am' || g2 == 'pm') {
      if (g2 == 'pm' && h < 12) h += 12;
      if (g2 == 'am' && h == 12) h = 0;
    } else if (g2 != null) {
      m = int.parse(g2);
    }
    if (h < 24 && m < 60) {
      hour = h;
      minute = m;
      text = cut(text, time);
      work = cut(work, time);
    }
  }

  final today = dateOnly(now);
  final dayWords = <RegExp, DateTime Function()>{
    _re('(öbür gün|yarından sonra|day after tomorrow)'): () => addDays(today, 2),
    _re('(bugün|today|tonight|bu akşam)'): () => today,
    _re('(yarın|tomorrow)'): () => addDays(today, 1),
    _re('(haftaya|gelecek hafta|next week)'): () => addDays(today, 7),
  };
  for (final e in dayWords.entries) {
    final m = e.key.firstMatch(work);
    if (m != null) {
      day = e.value();
      text = cut(text, m);
      work = cut(work, m);
      break;
    }
  }
  if (day == null) {
    for (var i = 0; i < 7; i++) {
      final m = _re('(${_weekdaysTr[i]}|${_weekdaysEn[i]})(?:\\s?(?:günü|ya|ye|a|e))?').firstMatch(work);
      if (m != null) {
        var delta = (i + 1 - today.weekday) % 7;
        if (delta == 0) delta = 7;
        day = addDays(today, delta);
        text = cut(text, m);
        work = cut(work, m);
        break;
      }
    }
  }

  if (hour != null) {
    day ??= today;
    var at = DateTime(day.year, day.month, day.day, hour, minute ?? 0);
    // "10:00" typed in the evening with no day means tomorrow morning.
    if (!at.isAfter(now) && isSameDay(day, today) && !_re('(bugün|today)').hasMatch(low)) {
      at = addDays(at, 1);
    }
    return QuickParseResult(_clean(text), at, true);
  }
  return QuickParseResult(_clean(text), day, false);
}

String _clean(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? t : tt.capitalize(t);
}
