import '../core/turkish_text.dart' as tt;

enum PLang { tr, en }

/// A seed vocabulary ranked by frequency (rank 0 is the most common word),
/// indexed for prefix lookups with and without Turkish diacritics.
class Lexicon {
  Lexicon(Iterable<String> wordsByRank) {
    var rank = 0;
    for (final raw in wordsByRank) {
      final w = raw.trim();
      if (w.isEmpty || _rank.containsKey(w)) continue;
      _rank[w] = rank++;
    }
    _byWord = _rank.keys.toList()..sort();
    _byFold = [for (final w in _rank.keys) (tt.fold(w), w)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
  }

  factory Lexicon.parse(String text) => Lexicon(text.split('\n'));

  final Map<String, int> _rank = {};
  late final List<String> _byWord;
  late final List<(String, String)> _byFold;

  int get length => _rank.length;

  bool contains(String word) => _rank.containsKey(word);

  int? rankOf(String word) => _rank[word];

  /// Words starting with [prefix] (already lowercased), in no particular order.
  Iterable<String> withPrefix(String prefix) sync* {
    for (var i = _lowerBound(_byWord, prefix, (w) => w);
        i < _byWord.length && _byWord[i].startsWith(prefix);
        i++) {
      yield _byWord[i];
    }
  }

  /// Words whose diacritic-free form starts with [foldedPrefix].
  Iterable<String> withFoldedPrefix(String foldedPrefix) sync* {
    for (var i = _lowerBound(_byFold, foldedPrefix, (e) => e.$1);
        i < _byFold.length && _byFold[i].$1.startsWith(foldedPrefix);
        i++) {
      yield _byFold[i].$2;
    }
  }

  static int _lowerBound<T>(List<T> list, String key, String Function(T) keyOf) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (keyOf(list[mid]).compareTo(key) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
