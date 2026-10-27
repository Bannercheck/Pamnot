/// Text helpers that respect Turkish casing rules (I/ı, İ/i) and diacritic
/// folding, so "gorusme" can match "görüşme" and "ISIK" lowercases to "ışık".
library;

const _trLower = {'I': 'ı', 'İ': 'i'};
const _trUpper = {'i': 'İ', 'ı': 'I'};

const _fold = {
  'ç': 'c',
  'ğ': 'g',
  'ı': 'i',
  'ö': 'o',
  'ş': 's',
  'ü': 'u',
  'â': 'a',
  'î': 'i',
  'û': 'u',
};

/// Lowercases [s]. With [turkish], dotted/dotless I map the Turkish way.
String lower(String s, {bool turkish = true}) {
  if (!turkish || (!s.contains('I') && !s.contains('İ'))) return s.toLowerCase();
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_trLower[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

/// Uppercases [s]. With [turkish], i → İ and ı → I.
String upper(String s, {bool turkish = true}) {
  if (!turkish || (!s.contains('i') && !s.contains('ı'))) return s.toUpperCase();
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_trUpper[ch] ?? ch.toUpperCase());
  }
  return b.toString();
}

/// Uppercases only the first character.
String capitalize(String s, {bool turkish = true}) {
  if (s.isEmpty) return s;
  final first = String.fromCharCode(s.runes.first);
  return upper(first, turkish: turkish) + s.substring(first.length);
}

/// Removes Turkish diacritics from an already lowercased string.
String fold(String lowercased) {
  final b = StringBuffer();
  for (final r in lowercased.runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

/// Characters that only appear in Turkish among the two app languages.
bool hasTurkishLetters(String s) => RegExp('[çğıöşüÇĞİÖŞÜ]').hasMatch(s);

/// A word character: any letter (incl. Turkish), digit or an apostrophe that
/// sits inside a word (English contractions).
final RegExp wordChar = RegExp(r"[\p{L}\p{N}']", unicode: true);

final RegExp _token = RegExp(r"[\p{L}\p{N}']+|[.!?\n;:]", unicode: true);

/// Splits [text] into words. Sentence boundaries are emitted as `null` so
/// callers building bigrams don't connect words across sentences.
List<String?> tokenize(String text) {
  final out = <String?>[];
  for (final m in _token.allMatches(text)) {
    var w = m[0]!;
    if (w.length == 1 && '.!?\n;:'.contains(w)) {
      if (out.isNotEmpty && out.last != null) out.add(null);
      continue;
    }
    var start = 0, end = w.length;
    while (start < end && w.codeUnitAt(start) == 0x27) {
      start++;
    }
    while (end > start && w.codeUnitAt(end - 1) == 0x27) {
      end--;
    }
    if (start == end) continue;
    if (start > 0 || end < w.length) w = w.substring(start, end);
    out.add(w);
  }
  return out;
}
