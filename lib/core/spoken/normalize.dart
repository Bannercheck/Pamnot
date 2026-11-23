/// Clean-up of one spoken sentence that does not depend on the clock:
/// apostrophes, outer punctuation, filler and reminder phrases, the note
/// prefix, and clock phrases in words ("saat iki buçukta") turned into digits
/// ("saat 2.30'ta"). Its output is read only by `parse.dart`.
library;

import '../turkish_text.dart' as tt;

class NormalizedSpeech {
  const NormalizedSpeech(this.text, {this.remind = false, this.isNote = false});

  /// The sentence in its spoken case, without fillers or reminder words, with
  /// clock phrases written in digits. A note's body when [isNote] is set.
  final String text;

  /// A reminder phrase was removed ("…mayı hatırlat", "remind me to").
  final bool remind;

  /// The sentence started with a note prefix ("not al", "not:", "note").
  final bool isNote;
}

/// Saatten bağımsız metin işi. [lang]: 'tr', 'en' ya da başka bir dil kodu.
NormalizedSpeech normalizeSpoken(String transcript, String lang) {
  final tr = lang == 'tr', en = lang == 'en';
  final s = _Sentence(_trimOuter(transcript.replaceAll(_apostrophes, "'")), turkish: tr);

  final note = (tr ? _noteTr : en ? _noteEn : null)?.firstMatch(s.low);
  if (note != null) {
    return NormalizedSpeech(_trimOuter(s.text.substring(note.end)), isNote: true);
  }

  var remind = false;
  if (tr) {
    remind = _dropPhrasesTr(s);
    _numberWordsTr(s);
    _clockPhrasesTr(s);
  } else if (en) {
    remind = _dropPhrasesEn(s);
    _numberWordsEn(s);
  }
  return NormalizedSpeech(_trimOuter(s.text.replaceAll(RegExp(r'\s+'), ' ')), remind: remind);
}

// ---------------------------------------------------------------- helpers

final _apostrophes = RegExp('[’‘`´ʼ]');
final _outerPunct = RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true);

String _trimOuter(String s) => s.replaceAll(_outerPunct, '');

// Dart's \b only knows ASCII letters; these treat every Unicode letter as a
// word character.
const _b = r'(?<![\p{L}\p{N}])';
const _e = r'(?![\p{L}\p{N}])';

RegExp _re(String body) => RegExp('$_b(?:$body)$_e', unicode: true);

/// The sentence as spoken and lowercased, always the same length, so a match
/// found in [low] can be edited in both.
class _Sentence {
  _Sentence(this.text, {required bool turkish}) : low = tt.lower(text, turkish: turkish) {
    // Lowercasing changed the length (rare: "İ" outside Turkish); give up
    // the spoken case rather than mismatch the two.
    if (low.length != text.length) text = low;
  }

  String text, low;

  void replace(int start, int end, String replacement) {
    text = text.replaceRange(start, end, replacement);
    low = low.replaceRange(start, end, replacement);
  }

  /// Keeps both copies' own case for the kept parts.
  void rebuild(List<(int, int)> ranges) {
    String pick(String from) => ranges.map((r) => from.substring(r.$1, r.$2)).join(' ');
    text = pick(text);
    low = pick(low);
  }
}

// ---------------------------------------------------------------- notes

final _noteTr = RegExp(r'^not(?:\s+al(?!\p{L})[\s\p{P}]*|\s*:\s*)', unicode: true);
final _noteEn = RegExp(r'^(?:take\s+a\s+)?note(?!\p{L})[\s\p{P}]*', unicode: true);

// ---------------------------------------------------------------- fillers

final _fillerTr = RegExp(
    r'^(?:bana\s+)?(?:bir\s+)?(?:yeni\s+)?görev\s+(?:ekle|oluştur)(?!\p{L})[\s\p{P}]*|^(?:yeni\s+)?görev\s*:\s*',
    unicode: true);

final _remindTr = RegExp(
    r'(?:^|\s+)(?:diye\s+)?(?:bana\s+)?(?:hatırlat|anımsat)(?:ır|ın|sana|abilir)?(?:\s+m[ıi]s[ıi]n(?:[ıi]z)?)?$',
    unicode: true);

/// A verbal noun as the object of "hatırlat": "aramayı", "içmemi",
/// "almasını". Group 1 is the stem, which is the imperative.
final _verbalNoun = RegExp(r'(?<!\p{L})(\p{L}+?)m[ae](?:y[ıi]|m[ıi]|m[ıi]z[ıi]|s[ıi]n[ıi])(?!\p{L})', unicode: true);

/// Drops "görev ekle"-style fillers and the reminder phrase; returns whether
/// the sentence asked to be reminded.
bool _dropPhrasesTr(_Sentence s) {
  final filler = _fillerTr.firstMatch(s.low);
  if (filler != null) s.replace(filler.start, filler.end, '');

  final remind = _remindTr.firstMatch(s.low);
  if (remind == null) return false;
  s.replace(remind.start, remind.end, '');
  final bana = RegExp(r'^\s*bana\s+').firstMatch(s.low);
  if (bana != null) s.replace(bana.start, bana.end, '');
  // "annemi aramayı" → "annemi ara": the reminded action becomes the title.
  final verb = _verbalNoun.allMatches(s.low).lastOrNull;
  if (verb != null) s.replace(verb.start + verb[1]!.length, verb.end, '');
  return true;
}

final _fillerEn = RegExp(
    r'^(?:please\s+)?(?:(?:add|create|make)\s+(?:a\s+)?(?:new\s+)?|new\s+)(?:task|to-?do)(?!\p{L})[\s\p{P}]*(?:to(?:\s+|$))?',
    unicode: true);
final _remindMeTo = RegExp(r'^(?:please\s+)?remind\s+me\s+to(?:\s+|$)');
final _remindMe = RegExp(r'^(?:please\s+)?remind\s+me(?:\s+about)?(?:\s+|$)');
final _remindMeWhenTo = RegExp(r'^(?:please\s+)?remind\s+me\s+(.+?)\s+to\s+(.+)$');
final _remindMePrefix = RegExp(r'^(?:please\s+)?remind\s+me\s+');

bool _dropPhrasesEn(_Sentence s) {
  final filler = _fillerEn.firstMatch(s.low);
  if (filler != null) {
    s.replace(filler.start, filler.end, '');
    return false;
  }
  final to = _remindMeTo.firstMatch(s.low);
  if (to != null) {
    s.replace(to.start, to.end, '');
    return true;
  }
  // "remind me in 2 hours to check the oven" → "check the oven in 2 hours"
  final when = _remindMeWhenTo.firstMatch(s.low);
  if (when != null) {
    final whenStart = _remindMePrefix.firstMatch(s.low)!.end;
    final whenEnd = whenStart + when[1]!.length;
    final actionStart = s.low.length - when[2]!.length;
    s.rebuild([(actionStart, s.low.length), (whenStart, whenEnd)]);
    return true;
  }
  final me = _remindMe.firstMatch(s.low);
  if (me == null) return false;
  s.replace(me.start, me.end, '');
  return true;
}

// ---------------------------------------------------------------- numbers

const _unitsTr = {
  'bir': 1, 'iki': 2, 'üç': 3, 'dört': 4, 'dörd': 4, 'beş': 5, 'altı': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9, //
};
const _tensTr = {'on': 10, 'yirmi': 20, 'otuz': 30, 'kırk': 40, 'elli': 50};
const _partsOfDayTr = {'sabah', 'öğle', 'öğlen', 'öğleyin', 'akşam', 'gece'};
const _clockWordsTr = {'buçuk', 'buçukta', 'çeyrek', 'geçe', 'kala'};
const _unitsAfterTr = {'gün', 'hafta', 'ay', 'saat', 'dakika', 'dk'};

final _numberWordTr = RegExp(
    '$_b(?:(${_tensTr.keys.join('|')})(?:\\s?(${_unitsTr.keys.join('|')}))?|(${_unitsTr.keys.join('|')}))'
    "('?(?:[dt][ae]|y?[ae]|y?[ıiuü]))?$_e",
    unicode: true);
final _locative = RegExp(r'^[dt][ae]$');
final _fractionAfter = RegExp(r'^(?:bir|biri|birini|birde|1)$');
final _digits = RegExp(r'^\d');

/// Number words become digits only where they tell a time: after "saat" or
/// a part of day, before a clock word ("buçuk", "geçe"…), in a duration
/// ("iki gün sonra"), or as a bare locative hour ("sekizde"; never "birde"
/// or "onda", which mostly mean "also" and "at him"). "ikide bir",
/// "on kişilik", "defter onda kaldı" stay words.
void _numberWordsTr(_Sentence s) {
  // Right to left, so "sekizi on geçe" sees "on" already as "10".
  for (final m in _numberWordTr.allMatches(s.low).toList().reversed) {
    final n = m[1] != null ? _tensTr[m[1]]! + (m[2] != null ? _unitsTr[m[2]]! : 0) : _unitsTr[m[3]]!;
    final suffix = m[4]?.replaceAll("'", '');
    final locative = suffix != null && _locative.hasMatch(suffix);
    final before = s.low.substring(0, m.start).trim().split(RegExp(r'\s+'));
    final after = s.low.substring(m.end).trim().split(RegExp(r'\s+'));
    final prev = before.last, prev2 = before.length > 1 ? '${before[before.length - 2]} $prev' : '';
    final next = after.first, next2 = after.length > 1 ? after[1] : '';
    final fraction = locative && _fractionAfter.hasMatch(next); // "üçte bir", "ikide bir"

    final clock = _clockWordsTr.contains(next) ||
        ((_digits.hasMatch(next) || _numberWordTr.hasMatch(next)) && (next2 == 'geçe' || next2 == 'kala'));
    final hourContext = prev == 'saat' ||
        (suffix != null && (_partsOfDayTr.contains(prev) || prev2 == 'öğleden sonra'));
    final bareHour = locative && !fraction && n != 1 && n != 10 && n <= 12;
    final duration = suffix == null && _unitsAfterTr.contains(next) && next2 == 'sonra';
    if (clock || hourContext || bareHour || duration) {
      s.replace(m.start, m.end, suffix == null ? '$n' : "$n'$suffix");
    }
  }
}

const _numbersEn = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty-five': 45, 'forty five': 45, //
};
final _numberWordEn = RegExp('$_b(${_numbersEn.keys.join('|')})$_e', unicode: true);
final _ampmAfter = RegExp(r"^(?:a\.?m\.?|p\.?m\.?|o'?clock)$");
final _unitAfterEn = RegExp(r'^(?:minutes?|mins?|hours?|days?|weeks?|months?)$');
final _halfQuarter = RegExp(
    '$_b(?:at\\s+)?(half|quarter)\\s+(past|to)\\s+(\\d{1,2}|${_numbersEn.keys.join('|')})$_e',
    unicode: true);

/// "at seven", "seven pm", "in ten minutes", "half past three" → digits.
void _numberWordsEn(_Sentence s) {
  for (final m in _halfQuarter.allMatches(s.low).toList().reversed) {
    var h = int.tryParse(m[3]!) ?? _numbersEn[m[3]]!;
    var minute = m[1] == 'half' ? 30 : 15;
    if (h < 1 || h > 12) continue;
    if (m[2] == 'to') {
      h = h == 1 ? 12 : h - 1;
      minute = 60 - minute;
    }
    s.replace(m.start, m.end, 'at $h:${minute.toString().padLeft(2, '0')}');
  }
  for (final m in _numberWordEn.allMatches(s.low).toList().reversed) {
    final n = _numbersEn[m[1]]!;
    final before = s.low.substring(0, m.start).trim().split(RegExp(r'\s+'));
    final after = s.low.substring(m.end).trim().split(RegExp(r'\s+'));
    final hour = n <= 12 && (before.last == 'at' || _ampmAfter.hasMatch(after.first));
    final duration = before.last == 'in' && _unitAfterEn.hasMatch(after.first);
    if (hour || duration) s.replace(m.start, m.end, '$n');
  }
}

// ---------------------------------------------------------------- clock

String _hm(int h, int m) => '$h.${m.toString().padLeft(2, '0')}';
int _minutes(String s) => s == 'çeyrek' ? 15 : int.parse(s);

final _past = _re(r"(\d{1,2})'?\s?(?:[ıiuü]|y[ıiuü]|y?[ae])\s+(çeyrek|\d{1,2})\s+geçe");
final _to = _re(r"(\d{1,2})'?\s?y?[ae]\s+(çeyrek|\d{1,2})\s+kala");
final _half = _re(r"(\d{1,2})\s+buçuk('?[dt][ae])?(?!\s+(?:saat|dakika|dk))");
final _halfPastNoon = _re(r"saat\s+yarım('?[dt][ae])?(?!\s+saat)");

/// "3'ü çeyrek geçe" → "3.15", "4'e çeyrek kala" → "3.45",
/// "2 buçukta" → "2.30'ta", "saat yarımda" → "saat 12.30'da".
void _clockPhrasesTr(_Sentence s) {
  for (final m in _past.allMatches(s.low).toList().reversed) {
    final h = int.parse(m[1]!), minute = _minutes(m[2]!);
    if (h > 23 || minute < 1 || minute > 59) continue;
    s.replace(m.start, m.end, _hm(h, minute));
  }
  for (final m in _to.allMatches(s.low).toList().reversed) {
    final h = int.parse(m[1]!), minute = _minutes(m[2]!);
    if (h > 24 || minute < 1 || minute > 59) continue;
    s.replace(m.start, m.end, _hm(h == 1 ? 12 : (h + 23) % 24, 60 - minute));
  }
  String suffix(String? g) => g == null ? '' : "'${g.replaceAll("'", '')}";
  for (final m in _half.allMatches(s.low).toList().reversed) {
    final h = int.parse(m[1]!);
    if (h > 23) continue;
    s.replace(m.start, m.end, '${_hm(h, 30)}${suffix(m[2])}');
  }
  for (final m in _halfPastNoon.allMatches(s.low).toList().reversed) {
    s.replace(m.start, m.end, 'saat 12.30${suffix(m[1])}');
  }
}
