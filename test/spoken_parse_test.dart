import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/core/spoken/normalize.dart';
import 'package:pamnot/core/spoken/parse.dart';
import 'package:pamnot/core/spoken/spoken_task.dart';

final _line = RegExp(r'^([A-Z]\d\d) "(.*)" => "(.*)" \| (null|(?:\d{4}-)?\d\d-\d\d(?: \d\d:\d\d)?)(?: \[(.*)\])?$');

DateTime _stamp(String s) {            // "11-24", "11-24 10:00", "2027-01-03", "2027-01-01 10:00"
  final parts = s.split(' ');
  final d = parts[0].split('-').map(int.parse).toList();
  final y = d.length == 3 ? d[0] : 2026;
  final t = parts.length > 1 ? parts[1].split(':').map(int.parse).toList() : [0, 0];
  return DateTime(y, d[d.length - 2], d[d.length - 1], t[0], t[1]);
}

void main() {
  final lines = File('docs/superpowers/specs/2026-11-23-voice-task-capture-vectors.txt')
      .readAsLinesSync().where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

  test('vektör dosyası 156 satır ve hepsi biçime uyuyor', () {
    expect(lines.length, 156);
    expect(lines.where((l) => !_line.hasMatch(l)), isEmpty);
  });

  for (final l in lines) {
    final m = _line.firstMatch(l)!;
    final tags = (m[5] ?? '').split(',').map((t) => t.trim()).toList();
    final nowTag = tags.where((t) => t.startsWith('now=')).firstOrNull;
    final now = nowTag == null ? DateTime(2026, 11, 23, 9) : _stamp(nowTag.substring(4));
    test('vektör ${m[1]} "${m[2]}"', () {
      final r = parseSpokenTask(m[2]!, now, tags.contains('en') ? 'en' : 'tr');
      expect(r.title, m[3]);
      expect(r.due, m[4] == 'null' ? isNull : _stamp(m[4]!));
      expect(r.hasTime, m[4]!.contains(':'));
      expect(r.remind, tags.contains('remind'));
      expect(r.isNote, tags.contains('note'));
    });
  }

  final now = DateTime(2026, 11, 23, 9);
  SpokenTask tr(String s) => parseSpokenTask(s, now, 'tr');

  group('normalizeSpoken', () {
    test('kesme işaretlerini birleştirir, sondaki noktalamayı atar', () {
      expect(normalizeSpoken('Süt al.', 'tr').text, 'Süt al');
      expect(normalizeSpoken('10’da', 'tr').text, "10'da");
      expect(normalizeSpoken('10`da', 'tr').text, "10'da");
    });
    test('dolgu ve hatırlatma kalıbı', () {
      expect(normalizeSpoken('Görev ekle süt ve ekmek al', 'tr').text, 'süt ve ekmek al');
      final r = normalizeSpoken('annemi aramayı hatırlat', 'tr');
      expect((r.text, r.remind), ('annemi ara', true));
      final e = normalizeSpoken('Remind me to call Ali', 'en');
      expect((e.text, e.remind), ('call Ali', true));
    });
    test('not öneki', () {
      final r = normalizeSpoken('not al: süt bitmiş', 'tr');
      expect((r.text, r.isNote), ('süt bitmiş', true));
    });
    test('saat bağlamı dışındaki sayılara dokunmaz', () {
      for (final s in ['ikide bir su iç', 'on kişilik rezervasyon yap', 'defter onda kaldı geri iste', '3 ekmek al']) {
        expect(normalizeSpoken(s, 'tr').text, s);
      }
    });
  });

  group('ambiguousHour', () {
    test('yalın 1-11 işaretlenir', () {
      for (final s in ["saat 3'te dişçi", "8'de ilacını iç", 'yarın 10:00 toplantı', 'sekizde ilaç']) {
        expect(tr(s).ambiguousHour, isTrue, reason: s);
      }
      expect(parseSpokenTask('Dentist at 3', now, 'en').ambiguousHour, isTrue);
    });
    test('açık saatler işaretlenmez', () {
      for (final s in ['akşam yedide annemi ara', "saat 15'te toplantı", "saat 12'de öğle yemeği", '08.30 toplantı',
          '1 saat sonra fırını kapat', 'yarın sabah doktoru ara', 'kitap oku']) {
        expect(tr(s).ambiguousHour, isFalse, reason: s);
      }
      expect(parseSpokenTask('Call mom tomorrow at 6 PM.', now, 'en').ambiguousHour, isFalse);
    });
    test('başında sıfır olan saat olduğu gibi alınır', () {
      final r = tr('08.30 toplantı');
      expect((r.title, r.due, r.hasTime), ('Toplantı', DateTime(2026, 11, 24, 8, 30), true)); // 09:00'da geçmiş → yarın
    });
  });

  group('diğer diller', () {
    test('yalnız rakamla saat tanınır, gerisi başlıktır', () {
      final r = parseSpokenTask('Besprechung 14:30', now, 'de');
      expect((r.title, r.due, r.hasTime), ('Besprechung', DateTime(2026, 11, 23, 14, 30), true));
      final t = parseSpokenTask('morgen Zahnarzt', now, 'de');
      expect((t.title, t.due), ('Morgen Zahnarzt', null));
    });
    test('İngilizcede büyük harf Türkçe kuralıyla yapılmaz', () {
      expect(parseSpokenTask('invite Sam', now, 'en').title, 'Invite Sam');
      expect(tr('ilaç al').title, 'İlaç al');
    });
  });

  group('vektör dışı Türkçe kalıplar', () {
    test('"bu akşam", "bu gece", "bu öğleden sonra": "bu" başlıkta kalmaz', () {
      final r = tr("bu akşam 8'de annemi ara");
      expect((r.title, r.due, r.ambiguousHour), ('Annemi ara', DateTime(2026, 11, 23, 20), false));
      final g = parseSpokenTask("bu gece 2'de yedek al", DateTime(2026, 11, 23, 23), 'tr');
      expect((g.title, g.due), ('Yedek al', DateTime(2026, 11, 24, 2)));
      final o = tr('bu öğleden sonra bankaya git');
      expect((o.title, o.due), ('Bankaya git', DateTime(2026, 11, 23, 15)));
    });
    test('saatten sonraki "kadar" başlıkta kalmaz', () {
      final r = parseSpokenTask('saat dokuza kadar raporu bitir', DateTime(2026, 11, 23, 7), 'tr');
      expect((r.title, r.due), ('Raporu bitir', DateTime(2026, 11, 23, 9)));
    });
    test('tutar ve ölçü saat sayılmaz', () {
      for (final s in ['2.50 liraya ekmek al', '1.25 kg peynir al']) {
        final r = tr(s);
        expect((r.title, r.due), (s, null), reason: s);
      }
    });
    test('"birde" ve "onda" yalnız saat sözcüğüyle saat olur', () {
      final also = tr('yarın birde süt al');
      expect((also.title, also.hasTime), ('Birde süt al', false));
      final ten = tr('saat onda toplantı');
      expect((ten.title, ten.due), ('Toplantı', DateTime(2026, 11, 23, 10)));
    });
  });

  group('F9: saatten ya da günden sonraki "gibi", "civarı", "sularında" başlıkta kalmaz', () {
    test('verilen dört cümle', () {
      for (final (s, lang, title, due) in [
        ('saat 5 gibi ara', 'tr', 'Ara', DateTime(2026, 11, 23, 17)),
        ('yarın 10 sularında toplantı', 'tr', 'Toplantı', DateTime(2026, 11, 24, 10)),
        ('akşam 7 civarı annemi ara', 'tr', 'Annemi ara', DateTime(2026, 11, 23, 19)),
        ('call mom around 5', 'en', 'Call mom', DateTime(2026, 11, 23, 17)),
      ]) {
        final r = parseSpokenTask(s, now, lang);
        expect((r.title, r.due, r.hasTime), (title, due, true), reason: s);
      }
    });
    test('öbür biçimler', () {
      for (final (s, lang, title, due, hasTime) in [
        ("saat 3'te gibi dişçi", 'tr', 'Dişçi', DateTime(2026, 11, 23, 15), true),
        ('yarın 9 civarında rapor', 'tr', 'Rapor', DateTime(2026, 11, 24, 9), true),
        ('saat beş gibi ara', 'tr', 'Ara', DateTime(2026, 11, 23, 17), true),
        ('beş gibi ara', 'tr', 'Ara', DateTime(2026, 11, 23, 17), true),
        ('akşam gibi annemi ara', 'tr', 'Annemi ara', DateTime(2026, 11, 23, 19), true),
        ('yarın gibisi faturayı öde', 'tr', 'Faturayı öde', DateTime(2026, 11, 24), false),
        ('cuma civarı raporu bitir', 'tr', 'Raporu bitir', DateTime(2026, 11, 27), false),
        ('call mom at 5ish', 'en', 'Call mom', DateTime(2026, 11, 23, 17), true),
        ('call mom 5ish', 'en', 'Call mom', DateTime(2026, 11, 23, 17), true),
        ('call mom at 5 or so', 'en', 'Call mom', DateTime(2026, 11, 23, 17), true),
        ('call mom around 5 pm', 'en', 'Call mom', DateTime(2026, 11, 23, 17), true),
        ('call mom around five', 'en', 'Call mom', DateTime(2026, 11, 23, 17), true),
        ('pay rent tomorrow or so', 'en', 'Pay rent', DateTime(2026, 11, 24), false),
      ]) {
        final r = parseSpokenTask(s, now, lang);
        expect((r.title, r.due, r.hasTime), (title, due, hasTime), reason: s);
      }
    });
    test('saat ya da gün yoksa sözcük yerinde kalır', () {
      for (final (s, lang) in [
        ('annem gibi yemek yap', 'tr'),
        ('ev civarında yürüyüş', 'tr'),
        ('10 civarı kilo ver', 'tr'),
        ('walk around the park', 'en'),
        ('buy 5 or so apples', 'en'),
      ]) {
        final r = parseSpokenTask(s, now, lang);
        expect((r.due, r.hasTime), (null, false), reason: s);
        expect(r.title.toLowerCase(), s, reason: s);
      }
    });
  });

  group('İngilizce başlıkta edat yalnız tarih ya da saatle gider', () {
    SpokenTask en(String s) => parseSpokenTask(s, now, 'en');
    test('tarih ya da saat yoksa sondaki edat başlıkta kalır', () {
      for (final (s, title) in [
        ('log in', 'Log in'),
        ('turn the heater on', 'Turn the heater on'),
        ('what is this for', 'What is this for'),
      ]) {
        final r = en(s);
        expect((r.title, r.due), (title, null), reason: s);
      }
    });
    test('tarihe ya da saate ait olmayan edat başlıkta kalır', () {
      for (final (s, title, due, hasTime) in [
        ('sign in tomorrow', 'Sign in', DateTime(2026, 11, 24), false),
        ('check in at 3', 'Check in', DateTime(2026, 11, 23, 15), true),
        ('log in at noon', 'Log in', DateTime(2026, 11, 23, 12), true),
        ('turn the heater on tomorrow', 'Turn the heater on', DateTime(2026, 11, 24), false),
      ]) {
        final r = en(s);
        expect((r.title, r.due, r.hasTime), (title, due, hasTime), reason: s);
      }
    });
    test('tarihi ya da saati getiren edat onunla birlikte çıkar', () {
      for (final (s, title, due, hasTime) in [
        ('pay rent until friday', 'Pay rent', DateTime(2026, 11, 27), false),
        ('send invoice until tomorrow', 'Send invoice', DateTime(2026, 11, 24), false),
        ('prepare slides for monday', 'Prepare slides', DateTime(2026, 11, 30), false),
        ('file taxes by december 15', 'File taxes', DateTime(2026, 12, 15), false),
        ('clean up at the weekend', 'Clean up', DateTime(2026, 11, 28), false),
        ('finish report by 5 pm', 'Finish report', DateTime(2026, 11, 23, 17), true),
        ('finish report by 14:30', 'Finish report', DateTime(2026, 11, 23, 14, 30), true),
        ('dinner for 7pm', 'Dinner', DateTime(2026, 11, 23, 19), true),
      ]) {
        final r = en(s);
        expect((r.title, r.due, r.hasTime), (title, due, hasTime), reason: s);
      }
    });
  });

  group('gün söylenince yalın saat çevrilmez (tasarım §6.4)', () {
    test('"bugün" ile geçmiş yalın saat akşama dönmez, olduğu gibi kalır', () {
      for (final h in [9, 10]) {
        final r = parseSpokenTask("bugün 8'de ilaç", DateTime(2026, 11, 23, h), 'tr');
        expect((r.title, r.due, r.hasTime, r.ambiguousHour), ('İlaç', DateTime(2026, 11, 23, 8), true, true),
            reason: '$h:00');
      }
      final e = parseSpokenTask('take pills today at 8', DateTime(2026, 11, 23, 10), 'en');
      expect((e.title, e.due, e.ambiguousHour), ('Take pills', DateTime(2026, 11, 23, 8), true));
    });
    test('"bugün" ile henüz gelmemiş yalın saat bugünün o saatidir', () {
      final r = parseSpokenTask("bugün 8'de ilaç", DateTime(2026, 11, 23, 7), 'tr');
      expect(r.due, DateTime(2026, 11, 23, 8));
    });
    test('gün söylenmezse geçmiş 7-9 akşama döner', () {
      final r = parseSpokenTask("8'de ilaç", DateTime(2026, 11, 23, 10), 'tr');
      expect((r.due, r.ambiguousHour), (DateTime(2026, 11, 23, 20), true));
    });
  });

  group('istisna atmaz', () {
    test('vektörlerin her ön ve son parçası, üç dilde, gece yarısı ve gün ortasında', () {
      final nows = [DateTime(2026, 11, 23, 0, 30), DateTime(2026, 2, 28, 23, 59), now];
      for (final l in lines) {
        final input = _line.firstMatch(l)![2]!;
        for (var i = 0; i <= input.length; i++) {
          for (final lang in ['tr', 'en', 'de']) {
            for (final n in nows) {
              expect(() => parseSpokenTask(input.substring(0, i), n, lang), returnsNormally);
              expect(() => parseSpokenTask(input.substring(i), n, lang), returnsNormally);
            }
          }
        }
      }
    });
  });

  group('Review Focus 2: boş ve dolgu metinler', () {
    test('başlık boş döner, istisna yok', () {
      for (final s in ['', '   ', '.', 'Bir görev ekle.', 'hatırlat', 'not al', 'Remind me to']) {
        final r = parseSpokenTask(s, now, s.startsWith('Remind') ? 'en' : 'tr');
        expect(r.title, '', reason: '"$s"');
        expect(r.due, isNull, reason: '"$s"');
      }
    });
  });

  group('Review Focus 3: olmayan tarih ve saatler', () {
    test('ayın 31\'i 30 günlük ayda bir sonraki 31\'e gider', () {
      expect(tr("ayın 31'inde kira").due, DateTime(2026, 12, 31));
    });
    test('29 şubat bir sonraki artık yıla gider', () {
      expect(tr('29 şubat sınav').due, DateTime(2028, 2, 29));
    });
    test('geçersiz saat tarih üretmez ve çökmeye yol açmaz', () {
      for (final s in ["saat 25'te toplantı", '99:99 deneme', "0'da", '32 ocak', 'saat', "saat 3'te"]) {
        final r = tr(s);
        if (s == "saat 3'te") { expect(r.title, ''); continue; }   // yalnız saat: başlık yok
        if (s == 'saat' || s == "0'da") continue;                    // yalnız "atmıyor" denetlenir
        expect(r.due, isNull, reason: s);
        expect(r.title, isNotEmpty, reason: s);
      }
    });
    test('yıl sonu ve yaz saati sınırında gün kayması yok', () {
      expect(parseSpokenTask('3 gün sonra kontrol', DateTime(2026, 12, 30, 23, 30), 'tr').due, DateTime(2027, 1, 2));
      expect(parseSpokenTask('yarın kontrol', DateTime(2027, 3, 27, 23, 59), 'tr').due, DateTime(2027, 3, 28));
    });
  });
}
