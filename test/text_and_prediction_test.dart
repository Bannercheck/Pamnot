import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/core/turkish_text.dart' as tt;
import 'package:pamnot/prediction/lexicon.dart';
import 'package:pamnot/prediction/word_predictor.dart';

WordPredictor _real() {
  List<String> lines(String p) => File(p).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  return WordPredictor(
    lexicons: {
      PLang.tr: Lexicon(lines('assets/lexicon/tr.txt')),
      PLang.en: Lexicon(lines('assets/lexicon/en.txt')),
    },
    phrases: {
      PLang.tr: lines('assets/lexicon/tr_phrases.txt'),
      PLang.en: lines('assets/lexicon/en_phrases.txt'),
    },
  );
}

void main() {
  group('Turkish text', () {
    test('casing follows Turkish rules', () {
      expect(tt.lower('IŞIK İSTANBUL'), 'ışık istanbul');
      expect(tt.upper('ışık istanbul'), 'IŞIK İSTANBUL');
      expect(tt.capitalize('istanbul'), 'İstanbul');
      expect(tt.lower('Idea', turkish: false), 'idea');
    });

    test('fold removes diacritics', () {
      expect(tt.fold('görüşme çağrı'), 'gorusme cagri');
    });

    test('tokenize marks sentence ends', () {
      expect(tt.tokenize("Bugün toplantı var. Don't forget!"), ['Bugün', 'toplantı', 'var', null, "Don't", 'forget', null]);
    });
  });

  group('WordContext', () {
    test('finds prefix and previous word', () {
      final c = WordContext.of('yarın sabah top');
      expect(c.prefix, 'top');
      expect(c.previous, 'sabah');
      expect(c.prefixStart, 12);
    });

    test('after a space the prefix is empty', () {
      final c = WordContext.of('alışveriş ');
      expect(c.prefix, '');
      expect(c.previous, 'alışveriş');
    });

    test('sentence start after a full stop', () {
      final c = WordContext.of('Bitti. ');
      expect(c.previous, isNull);
      expect(c.sentenceStart, isTrue);
    });
  });

  group('WordPredictor', () {
    final p = _real();

    test('completes Turkish words', () {
      expect(p.suggest('Yarın sabah topl', lang: PLang.tr), contains('toplantı'));
    });

    test('matches without diacritics', () {
      expect(p.suggest('gorus', lang: PLang.tr), contains('görüşme'));
    });

    test('completes English words', () {
      expect(p.suggest('Schedule a meet', lang: PLang.en), contains('meeting'));
    });

    test('keeps the capital of the typed prefix', () {
      final s = p.suggest('Topl', lang: PLang.tr);
      expect(s, isNotEmpty);
      expect(s.every((w) => w.startsWith('T')), isTrue);
    });

    test('Turkish capital of i is İ', () {
      final s = p.suggest('İç', lang: PLang.tr);
      expect(s, isNotEmpty);
      expect(s.every((w) => w.startsWith('İ')), isTrue);
    });

    test('next word from seed phrases', () {
      expect(p.suggest('alışveriş ', lang: PLang.tr), contains('listesi'));
      expect(p.suggest('shopping ', lang: PLang.en), contains('list'));
    });

    test('tolerates a one-letter typo', () {
      expect(p.suggest('toplnatı', lang: PLang.tr), isNotEmpty);
    });

    test('detects the language', () {
      expect(p.detect('bugün akşam arkadaşlarla buluşacağım'), PLang.tr);
      expect(p.detect('I will meet my friends tonight', fallback: PLang.tr), PLang.en);
    });

    test('learns from the user and ranks their words first', () async {
      final fresh = _real();
      await fresh.learn(['Pamukkale gezisi planı', 'Pamukkale gezisi için otel', 'Pamukkale gezisi bütçe']);
      expect(fresh.suggest('Pamu', lang: PLang.tr).first, 'Pamukkale');
      expect(fresh.suggest('Pamukkale ', lang: PLang.tr).first, 'gezisi');
    });

    test('reinforce boosts a picked word immediately', () {
      final fresh = _real();
      fresh.reinforce('kahve', 'molası', PLang.tr);
      expect(fresh.suggest('kahve ', lang: PLang.tr), contains('molası'));
    });

    test('is fast enough for every keystroke', () {
      final inputs = ['t', 'to', 'top', 'g', 'gö', 'yarın sabah ', 'a', 'me', 'meet', 'the '];
      final sw = Stopwatch()..start();
      var n = 0;
      for (var r = 0; r < 100; r++) {
        for (final i in inputs) {
          p.suggest(i);
          n++;
        }
      }
      sw.stop();
      final perCall = sw.elapsedMicroseconds / n;
      // ignore: avoid_print
      print('suggest(): ${perCall.toStringAsFixed(1)} µs per call');
      // One frame at 120 Hz is 8333 µs; a suggestion must cost a sliver.
      expect(perCall, lessThan(1500), reason: '$perCall µs per suggestion');
    });
  });
}
