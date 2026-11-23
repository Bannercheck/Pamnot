import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';

import 'support/fake_speech_engine.dart';

void main() {
  test('AppSettings: yeni alanlar varsayılan kapalı ve JSON ile gidip gelir', () {
    const a = AppSettings();
    expect(a.keepVoiceLog, isFalse);
    expect(a.notificationsAsked, isFalse);
    final b = AppSettings.fromJson(a.copyWith(keepVoiceLog: true, notificationsAsked: true).toJson());
    expect(b.keepVoiceLog, isTrue);
    expect(b.notificationsAsked, isTrue);
    expect(AppSettings.fromJson(const {}).keepVoiceLog, isFalse); // eski kayıt
  });

  test('AppController varsayılan olarak desteklenmeyen motoru alır', () {
    final c = AppController(store: MemoryStore());
    expect(c.speech.isSupported, isFalse);
    c.dispose();
  });

  test('UnsupportedSpeechEngine hiçbir şey dinlemez', () async {
    final e = UnsupportedSpeechEngine();
    expect(await e.resolveLocale(const [Locale('tr', 'TR')]), isNull);
    expect(await e.prepare('tr-TR'), SpeechAvailability.unsupportedPlatform);
  });

  test('FakeSpeechEngine: stop Final sonra Stopped gönderir, cancel yalnız Stopped', () async {
    final e = FakeSpeechEngine();
    final seen = <String>[];
    e.events.listen((ev) => seen.add(ev.runtimeType.toString()));
    expect(await e.resolveLocale(const [Locale('tr')]), 'tr-TR');
    expect(await e.resolveLocale(const [Locale('de', 'DE')]), isNull);
    await e.start('tr-TR');
    e.say('süt al');
    await e.stop();
    await e.start('tr-TR');
    e.say('x');
    await e.cancel();
    expect(seen, ['SpeechStarted', 'SpeechPartial', 'SpeechPartial', 'SpeechFinal', 'SpeechStopped',
        'SpeechStarted', 'SpeechPartial', 'SpeechStopped']);
    expect(e.calls, ['resolve', 'resolve', 'start:tr-TR', 'stop', 'start:tr-TR', 'cancel']);
  });

  test('metinler: Apple adları ve HIG kuralları', () {
    for (final s in [S.tr, S.en]) {
      final all = [s.voiceSetupReady, s.voiceSiriHint, s.voiceBackTapSteps, s.voiceVoiceControlSteps,
          s.voicePermissionDenied, s.voiceDictationOff, s.voicePrivacyNote, s.dataNote].join(' ');
      expect(all, isNot(contains('Yan tuş')));
      expect(all, isNot(contains('side button')));
    }
    expect(S.tr.voiceSetupReady, contains('Eylem düğmesi'));
    expect(S.tr.voiceSetupReady, contains('Kestirmeler'));
    expect(S.en.voiceSetupReady, contains('Add Voice Task'));
    expect(S.tr.openSettings, 'Ayarlar’ı Aç');
    expect(S.tr.voiceSummary(2), '2 kayıt eklendi');
    expect(S.en.voiceSummary(1), '1 item added');
    expect(S.en.voiceSummary(3), '3 items added');
    expect({for (var i = 0; i < 8; i++) S.tr.colorName(i)}.length, 8);
    expect(S.tr.aboutText, isNot(contains('Verilerin yalnızca')));
  });

  test('bağlantılar https ve app-settings açıcısı değiştirilebilir', () async {
    expect(Uri.parse(privacyPolicyUrl).scheme, 'https');
    expect(Uri.parse(supportUrl).scheme, 'https');
    final opened = <Uri>[];
    final old = openExternal;
    openExternal = (u) async { opened.add(u); return true; };
    addTearDown(() => openExternal = old);
    expect(await openAppSettings(), isTrue);
    expect(opened.single.toString(), 'app-settings:');
  });
}
