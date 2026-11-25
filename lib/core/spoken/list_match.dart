/// Finds a list named in a spoken task title ("alışveriş listesine ekmek
/// ekle", "işe toplantı notu", "add milk to the shopping list").
///
/// Kept apart from the spoken parser (`parse.dart`), which stays unchanged:
/// this runs on its output title.
library;

import '../../models/task_list.dart';
import '../turkish_text.dart' as tt;

// Same Unicode word boundaries as `parse.dart`.
const _b = r'(?<![\p{L}\p{N}])';
const _e = r'(?![\p{L}\p{N}])';

const _listTr = '(?:listesine|listeme|listesinde|listemde)';
const _verbTr = '(?:ekle|yaz|koy)';
const _tail = r'[\s,;:.!?\-]*$';

final _trailingVerbTr = RegExp('\\s+$_verbTr$_tail', unicode: true);
final _leadingAddEn = RegExp('^\\s*add$_e', unicode: true);
final _edges = RegExp(r'^[\s,;:.!?\-]+|[\s,;:.!?\-]+$');
final _space = RegExp(r'\s+');

/// [title] bir SpokenTask başlığıdır (parseSpokenTask çıktısı). Liste adı geçiyorsa listeyi ve
/// (yalnız açık biçimde) addan arındırılmış başlığı döndürür; geçmiyorsa listId null, başlık aynen.
({String title, String? listId}) matchSpokenList(String title, List<TaskList> lists, {required bool turkish}) {
  final none = (title: title, listId: null);
  final named = [
    for (final l in lists)
      if (l.name.trim().isNotEmpty) (list: l, name: _pattern(l.name, turkish)),
  ]..sort((a, b) => b.list.name.trim().length.compareTo(a.list.name.trim().length));
  if (named.isEmpty) return none;

  final low = _lowerSameLength(title, turkish);

  // Explicit form: the list phrase is cut out of the title.
  for (final n in named) {
    final hit = turkish ? _explicitTr(title, low, n.name) : _explicitEn(title, low, n.name);
    if (hit == null) continue;
    if (hit.isEmpty) return none;
    return (title: hit, listId: n.list.id);
  }

  // Bare dative at the start ("işe …", "okula …"): the title is kept as is.
  if (turkish) {
    for (final n in named) {
      final suffix = _dative(_lowerSameLength(n.list.name.trim(), true));
      if (suffix == null) continue;
      if (RegExp("^\\s*${n.name}'?$suffix$_e", unicode: true).hasMatch(low)) {
        return (title: title, listId: n.list.id);
      }
    }
  }
  return none;
}

/// `<ad> listesine …` at the start (an `ekle|yaz|koy` right after goes too) or
/// `… <ad> listesine (ekle|yaz|koy)?` at the end; a trailing `ekle|yaz|koy`
/// left in the rest is cut as well. Null when the form is absent; '' when
/// nothing is left of the title.
String? _explicitTr(String title, String low, String name) {
  final start = RegExp('^\\s*$name\\s+$_listTr$_e(?:\\s+$_verbTr$_e)?', unicode: true).firstMatch(low);
  final end = start == null
      ? RegExp('$_b$name\\s+$_listTr(?:\\s+$_verbTr)?$_tail', unicode: true).firstMatch(low)
      : null;
  final m = start ?? end;
  if (m == null) return null;
  var (rest, restLow) = _cut(title, low, m.start, m.end);
  final verb = _trailingVerbTr.firstMatch(restLow);
  if (verb != null) (rest, restLow) = _cut(rest, restLow, verb.start, verb.end);
  return _finish(title, rest, cutAtStart: start != null, turkish: true);
}

/// `(add )?… (to|on|in) (the|my)? <name> list` at the end, or the same phrase
/// at the start; a leading "add" in the rest is cut as well.
String? _explicitEn(String title, String low, String name) {
  const phrase = r'(?:to|on|in)\s+(?:(?:the|my)\s+)?';
  final start =
      RegExp('^\\s*(?:add\\s+)?$phrase$name\\s+list$_e', unicode: true).firstMatch(low);
  final end = start == null ? RegExp('$_b$phrase$name\\s+list$_tail', unicode: true).firstMatch(low) : null;
  final m = start ?? end;
  if (m == null) return null;
  var (rest, restLow) = _cut(title, low, m.start, m.end);
  final add = _leadingAddEn.firstMatch(restLow);
  if (add != null) (rest, restLow) = _cut(rest, restLow, add.start, add.end);
  return _finish(title, rest, cutAtStart: start != null || add != null, turkish: false);
}

(String, String) _cut(String s, String low, int from, int to) =>
    (s.replaceRange(from, to, ' '), low.replaceRange(from, to, ' '));

/// Trims the rest and, when its old first word was cut and the title began
/// in sentence case (the parser capitalizes), capitalizes the new start.
/// An all-caps first word ("İŞ LİSTESİNE rapor") leaves the rest as is.
String _finish(String title, String rest, {required bool cutAtStart, required bool turkish}) {
  final t = rest.replaceAll(_edges, '').replaceAll(_space, ' ');
  if (t.isEmpty || !cutAtStart) return t;
  final first = title.trim().split(_space).first;
  final lowFirst = tt.lower(first, turkish: turkish);
  final sentenceCase = first != lowFirst && first == tt.capitalize(lowFirst, turkish: turkish);
  return sentenceCase ? tt.capitalize(t, turkish: turkish) : t;
}

/// Regex body for a list name: escaped words joined by any whitespace.
String _pattern(String name, bool turkish) =>
    _lowerSameLength(name.trim(), turkish).split(_space).map(RegExp.escape).join(r'\s+');

/// Turkish dative ending of a lowercased name: -a after a back vowel
/// (a ı o u), -e after a front one (e i ö ü), with a buffer y after a final
/// vowel; no consonant softening. Null when the name has no vowel.
String? _dative(String name) {
  final vowels = RegExp('[aıoueiöü]').allMatches(name);
  if (vowels.isEmpty) return null;
  final suffix = 'aıou'.contains(vowels.last[0]!) ? 'a' : 'e';
  return vowels.last.end == name.length ? 'y$suffix' : suffix;
}

/// Lowercases rune by rune, keeping a rune whose lowercase would change the
/// string length (e.g. 'İ' outside Turkish), so match offsets in the lowered
/// text are valid in the original.
String _lowerSameLength(String s, bool turkish) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final l = tt.lower(ch, turkish: turkish);
    b.write(l.length == ch.length ? l : ch);
  }
  return b.toString();
}
