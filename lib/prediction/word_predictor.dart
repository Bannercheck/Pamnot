import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show AssetBundle;

import '../core/turkish_text.dart' as tt;
import 'lexicon.dart';

export 'lexicon.dart' show PLang;

/// Where the cursor is, in word terms.
class WordContext {
  const WordContext({
    required this.prefix,
    required this.prefixStart,
    required this.previous,
    required this.sentenceStart,
  });

  /// The partial word right before the cursor ('' after a space).
  final String prefix;

  /// Offset in the text where [prefix] starts.
  final int prefixStart;

  /// The word before [prefix] in the same sentence, if any.
  final String? previous;
  final bool sentenceStart;

  static WordContext of(String textBeforeCursor) {
    final t = textBeforeCursor;
    var i = t.length;
    while (i > 0 && tt.wordChar.hasMatch(t[i - 1])) {
      i--;
    }
    final prefix = t.substring(i);
    var j = i;
    while (j > 0 && (t[j - 1] == ' ' || t[j - 1] == '\t')) {
      j--;
    }
    String? previous;
    var sentenceStart = j == 0;
    if (j > 0 && tt.wordChar.hasMatch(t[j - 1])) {
      var k = j;
      while (k > 0 && tt.wordChar.hasMatch(t[k - 1])) {
        k--;
      }
      previous = t.substring(k, j).replaceAll("'", '').isEmpty ? null : t.substring(k, j);
    } else if (j > 0 && '.!?\n'.contains(t[j - 1])) {
      sentenceStart = true;
    }
    return WordContext(
      prefix: prefix,
      prefixStart: i,
      previous: previous,
      sentenceStart: sentenceStart,
    );
  }
}

class _Counts {
  final Map<String, int> unigrams = {};
  final Map<String, Map<String, int>> bigrams = {};

  /// How the user writes a word when it isn't plain lowercase ("SAP", "Ankara").
  final Map<String, String> display = {};
  Lexicon _index = Lexicon(const []);

  void add(String? prev, String word, [int by = 1]) {
    unigrams[word] = (unigrams[word] ?? 0) + by;
    if (prev != null) {
      final m = bigrams.putIfAbsent(prev, () => {});
      m[word] = (m[word] ?? 0) + by;
    }
  }

  void index() => _index = Lexicon(unigrams.keys);

  Iterable<String> withPrefix(String p) => _index.withPrefix(p);

  Iterable<String> withFoldedPrefix(String p) => _index.withFoldedPrefix(p);
}

WordPredictor _buildPredictor(List<String> files) {
  List<String> lines(String s) =>
      s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  return WordPredictor(
    lexicons: {PLang.tr: Lexicon.parse(files[0]), PLang.en: Lexicon.parse(files[1])},
    phrases: {PLang.tr: lines(files[2]), PLang.en: lines(files[3])},
  );
}

class _LearnJob {
  const _LearnJob(this.texts, this.lexicons, this.fallback);

  final List<String> texts;
  final Map<PLang, Lexicon> lexicons;
  final PLang fallback;
}

/// Runs on a background isolate: tokenising every note must not cost frames.
_Counts _buildCounts(_LearnJob job) {
  final c = _Counts();
  for (final t in job.texts) {
    if (t.trim().isEmpty) continue;
    _learnText(c, t, _detect(t, job.lexicons, job.fallback));
  }
  c.index();
  return c;
}

String _lower(String s, PLang lang) => tt.lower(s, turkish: lang == PLang.tr);

final RegExp _digits = RegExp(r'^\d+$');

void _learnText(_Counts into, String text, PLang lang) {
  String? prev;
  for (final tok in tt.tokenize(text)) {
    if (tok == null) {
      prev = null;
      continue;
    }
    final w = _lower(tok, lang);
    if (w.length < 2 || _digits.hasMatch(w)) {
      prev = null;
      continue;
    }
    if (tok != w && tok != tt.capitalize(w, turkish: lang == PLang.tr)) {
      into.display[w] = tok;
    }
    into.add(prev, w);
    prev = w;
  }
}

PLang _detect(String text, Map<PLang, Lexicon> lex, PLang fallback) {
  final words = tt.tokenize(text).whereType<String>().toList();
  final recent = words.length > 30 ? words.sublist(words.length - 30) : words;
  var tr = 0.0, en = 0.0;
  for (final w in recent) {
    if (tt.hasTurkishLetters(w)) tr += 2;
    if (lex[PLang.tr]?.contains(_lower(w, PLang.tr)) ?? false) tr += 1;
    if (lex[PLang.en]?.contains(_lower(w, PLang.en)) ?? false) en += 1;
  }
  if ((tr - en).abs() < 1) return fallback;
  return tr > en ? PLang.tr : PLang.en;
}

/// On-device word prediction for Turkish and English.
///
/// Combines a ranked seed lexicon per language, seed phrases for next-word
/// hints, and a model learned from the user's own notes and tasks, so the
/// words and phrases someone actually writes rise to the top.
class WordPredictor {
  WordPredictor({
    required Map<PLang, Lexicon> lexicons,
    Map<PLang, List<String>> phrases = const {},
  }) : _lex = lexicons {
    for (final e in phrases.entries) {
      final seed = _seed.putIfAbsent(e.key, _Counts.new);
      for (final line in e.value) {
        _learnText(seed, line, e.key);
      }
      seed.index();
    }
  }

  static Future<WordPredictor> load(AssetBundle bundle) async {
    Future<String> read(String path) async {
      try {
        return await bundle.loadString(path);
      } catch (_) {
        return '';
      }
    }

    final results = await Future.wait([
      read('assets/lexicon/tr.txt'),
      read('assets/lexicon/en.txt'),
      read('assets/lexicon/tr_phrases.txt'),
      read('assets/lexicon/en_phrases.txt'),
    ]);
    // Parsing and indexing the lexicons happens off the UI isolate.
    return compute(_buildPredictor, results);
  }

  final Map<PLang, Lexicon> _lex;
  final Map<PLang, _Counts> _seed = {};
  _Counts _user = _Counts()..index();

  Lexicon? lexicon(PLang lang) => _lex[lang];

  /// Rebuilds the personal model from everything the user has written, on
  /// a background isolate.
  Future<void> learn(List<String> texts, {PLang fallback = PLang.tr}) async {
    _user = await compute(_buildCounts, _LearnJob(texts, _lex, fallback));
  }

  /// Called when the user picks a suggestion, so it ranks higher right away.
  void reinforce(String? previous, String word, PLang lang) {
    final w = _lower(word, lang);
    final p = previous == null ? null : _lower(previous, lang);
    final isNew = !_user.unigrams.containsKey(w);
    _user.add(p, w, 2);
    if (isNew) _user.index();
  }

  /// Guesses the language of [text] from its last words.
  PLang detect(String text, {PLang fallback = PLang.tr}) => _detect(text, _lex, fallback);

  /// Up to [max] suggestions for the text before the cursor: completions of
  /// the partial word, or next-word hints right after a space.
  List<String> suggest(String textBeforeCursor,
      {PLang? lang, PLang fallback = PLang.tr, int max = 3}) {
    final ctx = WordContext.of(textBeforeCursor);
    final l = lang ?? detect(textBeforeCursor, fallback: fallback);
    final prev = ctx.previous == null ? null : _lower(ctx.previous!, l);
    final raw = ctx.prefix.isEmpty
        ? _nextWords(prev, l, max)
        : _completions(_lower(ctx.prefix, l), prev, l, max);
    return [for (final w in raw) _cased(w, ctx, l)];
  }

  List<String> _nextWords(String? prev, PLang lang, int max) {
    if (prev == null) return const [];
    final scores = <String, double>{};
    _user.bigrams[prev]?.forEach((w, c) => scores[w] = (scores[w] ?? 0) + 2.0 * c);
    _seed[lang]?.bigrams[prev]?.forEach((w, c) => scores[w] = (scores[w] ?? 0) + c);
    return _top(scores, max);
  }

  List<String> _completions(String prefix, String? prev, PLang lang, int max) {
    final lex = _lex[lang];
    final other = _lex[lang == PLang.tr ? PLang.en : PLang.tr];
    final folded = tt.fold(prefix);
    final foldOnly = folded == prefix;
    final scores = <String, double>{};

    void consider(String w, double factor) {
      if (w.length <= prefix.length) return;
      final s = _score(w, prev, lang, lex, other) * factor;
      if (s > (scores[w] ?? 0)) scores[w] = s;
    }

    if (lex != null) {
      for (final w in lex.withPrefix(prefix)) {
        consider(w, 1);
      }
      if (foldOnly) {
        for (final w in lex.withFoldedPrefix(folded)) {
          consider(w, 0.85);
        }
      }
    }
    for (final w in _user.withPrefix(prefix)) {
      consider(w, 1);
    }
    if (foldOnly) {
      for (final w in _user.withFoldedPrefix(folded)) {
        consider(w, 0.85);
      }
    }

    // A small typo budget: one edit inside the typed part.
    if (scores.length < max && prefix.length >= 3 && lex != null) {
      for (final w in lex.withFoldedPrefix(folded.substring(0, 1))) {
        if (scores.containsKey(w)) continue;
        final fw = tt.fold(w);
        if (fw.length <= prefix.length) continue;
        final head = fw.substring(0, math.min(fw.length, folded.length));
        if (_editDistanceAtMostOne(folded, head)) consider(w, 0.45);
      }
    }
    return _top(scores, max);
  }

  double _score(String w, String? prev, PLang lang, Lexicon? lex, Lexicon? other) {
    final rank = lex?.rankOf(w);
    var s = rank == null ? 0.0 : 1.0 / (1 + rank / 40.0);
    final userCount = _user.unigrams[w] ?? 0;
    if (userCount > 0) s += 0.35 + 0.25 * math.log(1 + userCount);
    if (prev != null) {
      final b = 2 * (_user.bigrams[prev]?[w] ?? 0) + (_seed[lang]?.bigrams[prev]?[w] ?? 0);
      if (b > 0) s += 1.5 * math.log(1 + b);
    }
    final seedCount = _seed[lang]?.unigrams[w] ?? 0;
    if (seedCount > 0) s += 0.1;
    // A word only the other language knows is likely a different-language hit.
    if (rank == null && userCount == 0 && (other?.contains(w) ?? false)) s *= 0.3;
    return s;
  }

  String _cased(String w, WordContext ctx, PLang lang) {
    final turkish = lang == PLang.tr;
    final p = ctx.prefix;
    final hasLetters = RegExp(r'\p{L}', unicode: true).hasMatch(p);
    if (p.length >= 2 && hasLetters && p == tt.upper(p, turkish: turkish) && p != tt.lower(p, turkish: turkish)) {
      return tt.upper(w, turkish: turkish);
    }
    final shown = _user.display[w] ?? w;
    if (p.isNotEmpty && p[0] != tt.lower(p[0], turkish: turkish)) {
      return tt.capitalize(shown, turkish: turkish);
    }
    if (p.isEmpty && ctx.sentenceStart) return tt.capitalize(shown, turkish: turkish);
    if (lang == PLang.en && (w == 'i' || w.startsWith("i'"))) return tt.capitalize(w, turkish: false);
    return shown;
  }

  static List<String> _top(Map<String, double> scores, int max) {
    final entries = scores.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.length.compareTo(b.key.length);
      });
    return [for (final e in entries.take(max)) e.key];
  }

  static bool _editDistanceAtMostOne(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      // Adjacent swap ("teh" → "the") counts as one edit.
      if (i + 1 < a.length && j + 1 < b.length && a[i] == b[j + 1] && a[i + 1] == b[j]) {
        i += 2;
        j += 2;
      } else if (a.length > b.length) {
        i++;
      } else if (a.length < b.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
