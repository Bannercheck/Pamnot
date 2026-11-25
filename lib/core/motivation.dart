/// Daily motivation: which line of the quote files each day gets.
library;

import 'dates.dart';

/// How many days back a line may not come again.
const motivationNoRepeatDays = 30;

/// The lines of a quote file: one per line, trimmed. Empty lines and lines
/// starting with `#` are skipped.
List<String> parseQuotes(String fileText) => [
      for (final raw in fileText.split('\n'))
        if (raw.trim() case final line when line.isNotEmpty && !line.startsWith('#')) line,
    ];

/// Quote indices for [days] days starting at [from]. A day already in
/// [history] (dayKey → index) keeps its pick. A newly picked index appears on
/// none of the [motivationNoRepeatDays] days before that day, nor on a day
/// within as many days after it that [history] already fixes. The result
/// depends only on the arguments.
Map<String, int> planQuotes(DateTime from, int days, Map<String, int> history, int count) {
  if (count <= 0 || days <= 0) return {};
  final start = dateOnly(from);
  final picks = <String, int>{
    for (final e in history.entries)
      if (e.value >= 0 && e.value < count) e.key: e.value,
  };
  final out = <String, int>{};
  for (var d = 0; d < days; d++) {
    final day = addDays(start, d);
    final key = dayKey(day);
    final kept = picks[key];
    if (kept != null) {
      out[key] = kept;
      continue;
    }
    final taken = <int>{};
    for (var k = 1; k <= motivationNoRepeatDays; k++) {
      final before = picks[dayKey(addDays(day, -k))];
      if (before != null) taken.add(before);
      final after = picks[dayKey(addDays(day, k))];
      if (after != null) taken.add(after);
    }
    final free = [for (var i = 0; i < count; i++) if (!taken.contains(i)) i];
    // With fewer lines than the window, repeats can't be avoided: the
    // spread then simply follows the day.
    final pool = free.isEmpty ? [for (var i = 0; i < count; i++) i] : free;
    final pick = pool[_hash(key) % pool.length];
    picks[key] = pick;
    out[key] = pick;
  }
  return out;
}

/// FNV-1a: stable across runs and platforms, unlike [String.hashCode].
int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}
