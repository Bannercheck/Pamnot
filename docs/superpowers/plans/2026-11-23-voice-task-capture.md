# Sesle Görev Ekleme ve App Store Uyumu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhone'da Kestirmeler eylemi, `pamnot://ses` bağlantısı ya da uygulama içi mikrofon düğmesiyle açılan tam ekran "Sesle ekle" ekranı; söylenen tek cümle doğru gün, saat ve hatırlatmayla göreve dönüşür. Aynı dalda, depoda kod/ayar değişikliğiyle kapanan App Store engelleri ve iPhone kalite maddeleri de giderilir.

**Architecture:** Mantığın tamamı Dart'ta: saf bir ayrıştırıcı (`lib/core/spoken/`), tek konuşmalık `SpeechEngine` arayüzü (`speech_to_text` uyarlayıcısı + test sahtesi), bütün zamanlamayı tutan `VoiceCaptureController` durum makinesi ve onu çizen `VoiceCapturePage`. iOS tarafı incedir: bir App Intent + App Shortcut, bekleyen tek eylemi Dart'a "çekme" modeliyle veren `PamnotLaunchBridge`, Info.plist anahtarları ve gizlilik bildirimi. Paylaşılan sözleşmeler (metinler, ayar alanları, arayüzler) ilk görevde konur; sonraki görevler ayrık dosyalara dokunur ve paralel yürür.

**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7, `speech_to_text` 7.5.0 (sabit), `url_launcher` ^6.3.3, `flutter_local_notifications` 22.3.3, Swift (App Intents, iOS 16.0+), `xcodeproj` Ruby gem 1.28.1, python3 `plistlib`.

**Spec:**
- Tasarım: `docs/superpowers/specs/2026-11-23-voice-task-capture-design.md`
- Kabul vektörleri (156): `docs/superpowers/specs/2026-11-23-voice-task-capture-vectors.txt`
- App Store uyumu: `docs/superpowers/specs/2026-11-23-app-store-compliance.md`
- Araştırma ve atılacak prototipler: `docs/superpowers/plans/2026-11-23-voice-task-capture-reference/` (README dosyaları listeler; kod birebir kopyalanmaz, test önce yazılır)

## Global Constraints

Ortam ve komutlar

- Depo: `/home/user/wt/voice`, dal `claude/voice-capture`. Her komuttan önce: `export PATH=/opt/flutter-sdk/flutter/bin:$PATH; cd /home/user/wt/voice`.
- Her görevin sonunda `flutter analyze` çıktısı `No issues found!` olmalı ve `flutter test` (tüm paket) geçmeli. Başlangıçta 47 test var; hiçbiri silinmez, yalnız Görev 11'de adı verilen üçü güncellenir.
- Mac yok. Swift, plist, pbxproj, storyboard ve `.strings` burada derlenemez. Doğrulama: `python3` (`plistlib`, `xml.etree`) ve `ruby` + `xcodeproj` gem'i. `plutil` Linux'ta yoktur, kullanılmaz. Gem: `export GEM_HOME=/tmp/claude-0/-home-user/8bed75ce-f409-56cc-a847-c9a160392e81/scratchpad/gems` (xcodeproj 1.28.1 kurulu; yoksa `gem install xcodeproj -v 1.28.1 --install-dir "$GEM_HOME"`). Gerçek derleme denetimi CI macOS işidir; onu görev değil, orkestratör en sonda çalıştırır.
- `project.pbxproj` elle düzenlenmez; yalnız `tool/ios/add_voice_files.rb` yazar. `objectVersion = 54` korunur.
- Commit: görev başına bir commit. Mesajın son iki satırı tam olarak şudur (başka imza satırı eklenmez):
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014hDRsedd7kgRjRGi89xc4v
  ```
  `ios/` altına dokunan görevlerin (5, 6, 13) commit başlığı `[full-build]` içerir. Push yapılmaz.
- Depo kuralları (`CLAUDE.md`): önce test (TDD), "bitti" demeden çıktıyı kendin gör; arayüz işlerinde `.claude/skills/ui-ux-pro-max/SKILL.md` ve uyum belgesinin §3 ve §4.1 maddeleri uygulanır; dış font, CDN, harici görsel eklenmez.

Tasarımdan birebir değerler

- iOS en düşük sürüm **16.0**. Yeni yetki (entitlement), Siri yeteneği, `UIBackgroundModes`, `NSSiriUsageDescription`, `NSAppIntents*`, `NSUserActivityTypes`, `NSUserNotificationsUsageDescription`, `UIRequiresFullScreen` **eklenmez**.
- Zamanlamalar yalnız Dart'ta: konuşma sonu **1,6 sn**, önizleme **2 sn**, yeniden dinlemede sessizlik **6 sn**, tek oturum **30 sn**, arka planda **5 dk**.
- Ses özelliği bu sürümde yalnız iOS'ta "destekleniyor" der. Diğer platformlarda mikrofon düğmesi gizlidir ve `speech_to_text` eklentisi **hiç çağrılmaz**.
- Mikrofon ve konuşma tanıma izni yalnız Sesle ekle ekranı açıldığında istenir; `main()` içinde, uygulama açılışında ya da düğme görünürken istenmez. Reddedilince sistem uyarısı yeniden tetiklenmez; tek yol "Ayarlar'ı Aç" (`app-settings:`).
- `pamnot://` bağlantısı yalnız ekranı açar; içindeki metin ya da parametreyle görev yazılmaz.
- Yazarak hızlı ekleme değişmez: `lib/core/quick_parse.dart` ve `test/models_test.dart` içindeki 7 `quickParse` testi dokunulmadan kalır (`git diff --stat` bu iki dosya için boş).
- Ses dosyası hiçbir yere yazılmaz. "Son tanınanlar" günlüğü yalnız kullanıcı Ayarlar'daki anahtarı açınca tutulur (varsayılan **kapalı**, son 20 kayıt, yalnız cihazda).
- Tanıma dili telefonun dilidir (`PlatformDispatcher.instance.locales`), uygulamanın TR/EN ayarı değil; yerel ayar motora her zaman açıkça verilir.

Metin ve arayüz kuralları

- Kullanıcıya görünen her metin `lib/l10n/strings.dart` içindeki `S` getter'ından gelir (TR ve EN birlikte). Görev 1 bütün yeni getter'ları ekler; sonraki görevler `strings.dart`, `settings.dart` ve `pubspec.yaml` dosyalarına **dokunmaz** (eksik bir metin fark edilirse görev durur ve bildirir).
- Apple adları: "Kestirmeler", "Eylem düğmesi", "Arkaya Dokunma", "Sesle Denetim". "Yan tuş" hiçbir metinde geçmez. Eylem adı TR "Sesle Görev Ekle", EN **"Add Voice Task"**.
- Yeni arayüzde simge olarak emoji kullanılmaz (Material ikonları). Her durum ikon + yazıyla gösterilir, yalnız renkle değil.
- Dokunma hedefi ≥ 44×44 pt, hedefler arası ≥ 8 pt; her denetim etiketli; metin kontrastı ≥ 4,5:1, ikon ve kenar ≥ 3:1 (açık ve koyu tema); metin ölçeği 2,0'da ve 375 pt genişlikte taşma yok.
- Renkler `Theme.of(context).colorScheme` ve `lib/ui/common/soft.dart` bileşenlerinden: gövde metni `onSurface`, çipler `primaryContainer`/`onPrimaryContainer`, hata `errorContainer`/`onErrorContainer`.

## Review Focus

Tasarımın ima ettiği ama vektörlerin ve akış testlerinin kendiliğinden yakalamadığı, kullanıcıyı en çok ısıracak beş durum. Her birinin testi sahibi olan göreve yazıldı.

1. **Tanıyıcı olayları beklenmedik sırada gelir** (Final gelmeden `Stopped`; yeni oturum başladıktan sonra geç gelen `Final`): görev bir kez kaydedilir, kaybolmaz, çift oluşmaz. → Görev 7, Adım 9.
2. **Boş ya da yalnız dolgu/noktalama içeren metin** ("Bir görev ekle.", "hatırlat", "   "): başlığı boş görev kaydedilmez, ekran hata göstermez. → Görev 2, Adım 7; Görev 7, Adım 9.
3. **Olmayan tarih ve saatler** ("ayın 31'inde" 30 günlük ayda, "29 şubat", "saat 25'te", "99:99"): çökme yok; geçersiz saat metinde kalır, tarih bir sonraki geçerli güne gider. → Görev 2, Adım 7.
4. **Üst üste ve yarım kalan eylemler** (izin penceresi beklenirken ekranı kapatmak, ekran açıkken ikinci tetikleme, başka yerden silinmiş görevi geri almak): kapanan ekrandan sonra mikrofon açık kalmaz, ikinci ekran açılmaz, hata olmaz. → Görev 7, Adım 9; Görev 9, Adım 5.
5. **Çok uzun konuşma** (30 sn, 500+ karakter, satır sonu içeren metin): ekran taşmaz, kaydırılır; başlık kesilmeden kaydedilir. → Görev 8, Adım 7.

## Execution lanes

| Sıra | Görevler | Koşul |
| --- | --- | --- |
| 1 | **Görev 1** | Tek başına, ilk. Paylaşılan dosyaların (metinler, ayarlar, `pubspec`, arayüzler) tek sahibi. |
| 2 (paralel, ayrık dosyalar) | **Görev 2**, **Görev 3**, **Görev 4**, **Görev 5**, **Görev 6**, **Görev 11** | Hepsi yalnız Görev 1'e bağlı. Birbirlerinin koduna ihtiyaç duymaz, ortak dosyaları yoktur. |
| 3 | **Görev 7** | Görev 2 ve 4 birleştikten sonra. |
| 3 (paralel) | **Görev 10** | Görev 4 birleştikten sonra; Görev 7, 8, 9 ile paralel (yalnız `lib/ui/settings/` ve kendi testi). |
| 4 | **Görev 8** | Görev 7 ve 11'den sonra (Görev 11'in renklerini ve `reduceMotionOf` yardımcısını kullanır). |
| 5 | **Görev 9** | Görev 3 ve 8'den sonra. |
| 6 (paralel) | **Görev 12**, **Görev 13** | Görev 12: 9, 10 ve 11 birleştikten sonra (birçok arayüz dosyasına ve `lib/app.dart`'a dokunur). Görev 13: 5, 6, 9 ve 10'dan sonra (yalnız CI ve belgeler). İkisi ayrık dosyalara dokunur. |

Sırayla zorunlu zincir: 1 → (2, 4) → 7 → (11 ile birlikte) 8 → 9 → 12. Orkestratör en sonda dalı iter; en üstteki commit mesajı `[full-build]` içermelidir (Görev 13'ün commit'i bunu taşır; son birleşen o değilse orkestratör boş bir `[full-build]` commit'i ekler).

## Dosya haritası

| Dosya | Sorumluluk | Görev |
| --- | --- | --- |
| `lib/core/spoken/spoken_task.dart` | Ayrıştırma sonucu (`SpokenTask`) | 1 |
| `lib/services/speech/speech_engine.dart` | `SpeechEngine` arayüzü, olaylar, `UnsupportedSpeechEngine` | 1 |
| `lib/services/links.dart` | Gizlilik/destek adresleri, dış bağlantı ve `app-settings:` açıcı | 1 |
| `test/support/fake_speech_engine.dart` | Testlerin "duyduğu" şeyi belirleyen sahte motor | 1 |
| `lib/core/spoken/normalize.dart`, `parse.dart` | Konuşma metni → `SpokenTask` | 2 |
| `lib/services/speech/stt_speech_engine.dart` | `speech_to_text` uyarlayıcısı, çağrı sırası, hata eşlemesi | 3 |
| `lib/models/voice_log.dart` | "Son tanınanlar" kaydı | 4 |
| `lib/state/app_controller.dart`, `lib/services/reminder_scheduler.dart` | `addSpokenTask`, `addSpokenNote`, bildirim izni durumu, günlük | 4 |
| `ios/Runner/*.swift`, `Info.plist`, `*.lproj/*.strings`, `PrivacyInfo.xcprivacy`, `tool/ios/*` | Kestirme, köprü, izin metinleri, gizlilik bildirimi, proje betiği | 5 |
| `ios/Runner/Assets.xcassets/**`, `LaunchScreen.storyboard`, `ios/PamnotWidget/**`, `tool/icons/*` | Simge, açılış ekranı, widget gizlilik bildirimi | 6 |
| `lib/ui/voice/voice_capture_controller.dart` | Durum makinesi, zamanlayıcılar, arka plan kuralları | 7 |
| `lib/ui/voice/voice_capture_page.dart` | Ekran, erişilebilirlik, özet | 8 |
| `lib/services/launch_actions.dart`, `lib/app.dart`, `lib/ui/home_shell.dart`, `lib/main.dart`, `lib/ui/tasks/task_editor.dart` | Giriş noktaları | 9 |
| `lib/ui/settings/voice_settings.dart`, `settings_page.dart` | Ayarlar: Sesle ekleme, bildirimler, Hakkında | 10 |
| `lib/state/sample_data.dart`, `lib/theme/pamnot_theme.dart`, `lib/ui/common/soft.dart` | Örnek veri, kontrast, hareket yardımcıları | 11 |
| Mevcut arayüz dosyaları | Dokunma hedefi, etiket, Dynamic Type, dokunsal | 12 |
| `.github/workflows/build.yml`, `TESTING.md`, `README.md`, `PRIVACY.md`, `ios/PamnotWidget/README.md` | CI korumaları ve belgeler | 13 |

---

### Task 1: Ortak temel — metinler, ayar alanları, paketler, arayüzler

**Files:**
- Modify: `pubspec.yaml:31-47`, `pubspec.lock`
- Modify: `lib/models/settings.dart:7-82`
- Modify: `lib/l10n/strings.dart:184-195`
- Modify: `lib/state/app_controller.dart:55-72`
- Create: `lib/core/spoken/spoken_task.dart`, `lib/services/speech/speech_engine.dart`, `lib/services/links.dart`, `test/support/fake_speech_engine.dart`
- Test: `test/foundation_test.dart`

**Interfaces:**
- Consumes: yok.
- Produces:

```dart
// lib/core/spoken/spoken_task.dart
class SpokenTask {
  const SpokenTask({required this.title, this.due, this.hasTime = false, this.remind = false,
      this.ambiguousHour = false, this.isNote = false});
  final String title;        // isNote ise notun gövdesi
  final DateTime? due;       // hasTime false ise yalnız gün
  final bool hasTime, remind, ambiguousHour, isNote;
}

// lib/services/speech/speech_engine.dart
enum SpeechAvailability { ready, permissionDenied, unsupportedLocale, unavailable, unsupportedPlatform }
enum SpeechErrorKind { noMatch, permission, dictationDisabled, interrupted, network, unknown }
sealed class SpeechEvent { const SpeechEvent(); }
class SpeechStarted extends SpeechEvent { const SpeechStarted(); }
class SpeechPartial extends SpeechEvent { const SpeechPartial(this.text); final String text; }
class SpeechFinal extends SpeechEvent { const SpeechFinal(this.text); final String text; }
class SpeechLevel extends SpeechEvent { const SpeechLevel(this.level); final double level; } // 0..1
class SpeechStopped extends SpeechEvent { const SpeechStopped(); }
class SpeechFailure extends SpeechEvent {
  const SpeechFailure(this.kind, {this.permanent = true});
  final SpeechErrorKind kind; final bool permanent;
}
abstract class SpeechEngine {
  bool get isSupported;                                   // eklentiye dokunmaz
  Stream<SpeechEvent> get events;                         // broadcast
  Future<String?> resolveLocale(List<Locale> preferred);  // izin istemez
  Future<SpeechAvailability> prepare(String localeId);    // izinleri ister
  Future<void> start(String localeId);                    // bir konuşma
  Future<void> stop();                                    // Final + Stopped
  Future<void> cancel();                                  // yalnız Stopped
  Future<void> dispose();
}
class UnsupportedSpeechEngine implements SpeechEngine { /* isSupported false, prepare → unsupportedPlatform */ }

// lib/services/links.dart
const privacyPolicyUrl = 'https://github.com/Bannercheck/Pamnot/blob/main/PRIVACY.md';
const supportUrl = 'https://github.com/Bannercheck/Pamnot/issues';
typedef UrlOpener = Future<bool> Function(Uri uri);
UrlOpener openExternal;                 // varsayılan: launchUrl(uri, mode: LaunchMode.externalApplication); testler değiştirir
Future<bool> openAppSettings();         // openExternal(Uri.parse('app-settings:'))

// lib/models/settings.dart — iki yeni alan (constructor, copyWith, toJson, fromJson)
final bool keepVoiceLog;        // varsayılan false; JSON 'keepVoiceLog' == true
final bool notificationsAsked;  // varsayılan false; JSON 'notificationsAsked' == true

// lib/state/app_controller.dart
AppController({..., SpeechEngine? speech});   // varsayılan UnsupportedSpeechEngine()
final SpeechEngine speech;

// test/support/fake_speech_engine.dart
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.supported = true, this.availability = SpeechAvailability.ready,
      this.supportedLocales = const ['tr-TR', 'en-US']});
  bool supported; SpeechAvailability availability; final List<String> supportedLocales;
  final List<String> calls;        // 'resolve', 'prepare:<id>', 'start:<id>', 'stop', 'cancel'
  bool listening;
  bool finalOnStop = true;         // false: stop() yalnız Stopped gönderir
  Completer<void>? prepareGate;    // doluysa prepare() tamamlanmasını bekler
  void say(String text);           // sözcük sözcük SpeechPartial
  void sendFinal(String text);     // dinlemeden bağımsız, tek başına SpeechFinal
  void level(double v);
  void fail(SpeechErrorKind kind, {bool permanent = true}); // SpeechFailure + SpeechStopped, listening=false
}
```

`S` içine eklenecek getter'lar (adlar ve metinler birebir; `aboutText` dışında mevcut getter değişmez):

| Getter | TR | EN |
| --- | --- | --- |
| `voiceTitle` | Sesle ekle | Add by voice |
| `voiceMicTooltip` | Sesle görev ekle | Add a task by voice |
| `voicePreparing` | Hazırlanıyor… | Getting ready… |
| `voiceListening` | Dinliyorum… | Listening… |
| `voicePaused` | Duraklatıldı | Paused |
| `voiceTapToContinue` | Devam etmek için dokun | Tap to continue |
| `voiceSaved` | Kaydedildi | Saved |
| `voiceFix` | Düzelt | Fix |
| `voiceDraftHint` | Görevi düzelt | Fix the task |
| `voiceStartListening` | Dinlemeyi başlat | Start listening |
| `voiceStopListening` | Dinlemeyi durdur | Stop listening |
| `voiceAdded` | Eklenenler | Added |
| `voiceSavedOnLock` | Kilitlenirken kaydedildi | Saved while locking |
| `voiceUndoItem(String title)` | $title görevini geri al | Undo $title |
| `voiceUndatedRemindHint` | Tarihsiz · hatırlatma için gün söyle | No date · say a day to get a reminder |
| `voiceReminderOn` | hatırlatma açık | reminder on |
| `voiceTimeGuess` | saat tahmini | time is a guess |
| `voiceNoteChip` | Not | Note |
| `voiceCountdown(int n)` | $n sn | $n s |
| `voiceSummary(int n)` | $n kayıt eklendi | n == 1 ? 1 item added : $n items added |
| `voiceErrorGeneric` | Şu anda dinleyemiyorum. Bağlantını kontrol edip tekrar dene. | I can’t listen right now. Check your connection and try again. |
| `voiceRetry` | Tekrar dene | Try again |
| `voicePermissionDenied` | Mikrofon ya da Konuşma Tanıma izni kapalı. Sesle eklemek için Ayarlar’dan ikisini de aç. Yazarak eklemeye devam edebilirsin. | Microphone or Speech Recognition access is off. Turn both on in Settings to add by voice. You can still add tasks by typing. |
| `openSettings` | Ayarlar’ı Aç | Open Settings |
| `voiceDictationOff` | Dikte kapalı. Ayarlar > Genel > Klavye > Dikte’yi aç, sonra tekrar dene. | Dictation is off. Turn on Settings > General > Keyboard > Enable Dictation, then try again. |
| `voiceUnsupportedLocale` | Telefonunun dili için konuşma tanıma yok. | Speech recognition isn’t available for your phone’s language. |
| `voiceUnsupportedPlatform` | Sesle ekleme bu cihazda henüz yok. | Adding by voice isn’t available on this device yet. |
| `voiceSettings` | Sesle ekleme | Add by voice |
| `voiceSetupReady` | “Sesle Görev Ekle” eylemi Kestirmeler’de, Spotlight’ta ve Eylem düğmesi ayarlarında hazır. | “Add Voice Task” is ready in Shortcuts, Spotlight and the Action button settings. |
| `voiceSiriHint` | Siri’ye “Pamnot ile görev ekle” de. | Say “Add a task in Pamnot” to Siri. |
| `voiceBackTapTitle` | Arkaya Dokunma | Back Tap |
| `voiceBackTapSteps` | 1. Kestirmeler’de + ile yeni bir kestirme oluştur ve Pamnot > Sesle Görev Ekle eylemini ekle.\n2. Ayarlar > Erişilebilirlik > Dokunma > Arkaya Dokunma’da bu kestirmeyi seç. | 1. In Shortcuts, tap + to create a shortcut and add the Pamnot > Add Voice Task action.\n2. In Settings > Accessibility > Touch > Back Tap, choose that shortcut. |
| `voiceVoiceControlTitle` | Sesle Denetim | Voice Control |
| `voiceVoiceControlSteps` | 1. Kestirmeler’de tek eylemli bir kestirme oluştur: Pamnot > Sesle Görev Ekle.\n2. Ayarlar > Erişilebilirlik > Sesle Denetim > Komutlar > Yeni Komut Yarat > Eylem > Kestirmeyi Çalıştır’da bu kestirmeyi seç. | 1. In Shortcuts, create a shortcut with one action: Pamnot > Add Voice Task.\n2. In Settings > Accessibility > Voice Control > Commands > Create New Command > Action > Run Shortcut, choose that shortcut. |
| `voiceKeepLog` | Tanınan metinleri sakla | Keep recognised text |
| `voiceKeepLogSub` | Son 20 metin, yalnız bu cihazda. Tarih ve saat tanımayı iyileştirmeye yarar. | The last 20, on this device only. Helps improve date and time recognition. |
| `voiceRecent` | Son tanınanlar | Recently recognised |
| `voiceRecentEmpty` | Henüz kayıt yok. | Nothing yet. |
| `voiceClearLog` | Temizle | Clear |
| `voicePrivacyNote` | Konuşman Apple’ın konuşma tanımasıyla yazıya çevrilir. Çevrimiçiyken sesin, klavyedeki dikte gibi Apple’a gidebilir. Pamnot ses kaydı saklamaz. | Your speech is turned into text by Apple’s speech recognition. When you’re online, your voice may be sent to Apple, like keyboard dictation. Pamnot doesn’t save audio. |
| `notificationsAllow` | Bildirimlere izin ver | Allow notifications |
| `notificationsDenied` | Bildirimler kapalı — Ayarlar’ı aç | Notifications are off — open Settings |
| `notificationsOn` | Bildirimler açık | Notifications are on |
| `privacyPolicy` | Gizlilik Politikası | Privacy Policy |
| `support` | Destek | Support |
| `licenses` | Açık kaynak lisansları | Open-source licences |
| `dataNote` | Sesle eklerken konuşman Apple’a, el yazısı tanımada kişisel olmayan kullanım ölçümleri Google’a gidebilir. Ayrıntılar Gizlilik Politikası’nda. | When you add by voice, your speech may go to Apple; handwriting recognition may send non-personal usage metrics to Google. Details are in the Privacy Policy. |
| `aboutText` (değişir) | Pamnot — yumuşacık notlar, planlar ve anımsatıcılar. Notların ve görevlerin yalnızca cihazında saklanır. | Pamnot — soft notes, plans and reminders. Your notes and tasks stay on your device. |
| `handwritingPrivacyNote` | El yazısı cihazında yazıya çevrilir; yazdıkların Google’a gönderilmez. Google ML Kit, tanıma modelini indirir ve Google’a kişisel olmayan kullanım ve performans ölçümleri gönderir. | Handwriting is converted to text on your device; what you write is not sent to Google. Google ML Kit downloads the recognition model and sends non-personal usage and performance metrics to Google. |
| `handwritingDownloadTitle` | El yazısı modeli indirilsin mi? | Download the handwriting model? |
| `handwritingDownloadBody` | Yaklaşık 20 MB. | About 20 MB. |
| `colorName(int i)` | krem, şeftali, nane, lavanta, gök mavisi, tereyağı, gül, adaçayı (i = 0..7) | cream, peach, mint, lavender, sky, butter, rose, sage |
| `previous` | Önceki | Previous |
| `next` | Sonraki | Next |
| `removeSubtask` | Alt görevi kaldır | Remove subtask |
| `clearSearch` | Aramayı temizle | Clear search |
| `overdueLabel` | Gecikti | Overdue |
| `inkColor(int n)` | Renk $n | Colour $n |
| `strokeWidth(int n)` | Kalınlık $n | Width $n |

- [ ] **Step 1: Paketleri ekle**

Run: `flutter pub add speech_to_text:7.5.0 'url_launcher:^6.3.3'`
Expected: `pubspec.yaml` içinde `speech_to_text: 7.5.0` (şapkasız, sabit) ve `url_launcher: ^6.3.3`; `flutter pub get` hatasız. (7.5.0, 2026-11-23'te pub.dev'deki en güncel kararlı sürümdür; 7.6.0 hâlâ beta.)

- [ ] **Step 2: Başarısız testi yaz** — `test/foundation_test.dart`

```dart
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
  expect([for (var i = 0; i < 8; i++) S.tr.colorName(i)].toSet().length, 8);
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
```

- [ ] **Step 3: Testin başarısız olduğunu gör**

Run: `flutter test test/foundation_test.dart`
Expected: derleme hatası (`keepVoiceLog`, `SpeechEngine`, `openExternal` tanımsız).

- [ ] **Step 4: Uygula**

Yukarıdaki Interfaces bloğunu ve metin tablosunu birebir yaz. `strings.dart` içinde yeni getter'lar `// Voice`, `// Voice settings`, `// Privacy and about`, `// Accessibility` başlıkları altında `// Misc` bloğundan önce durur. `FakeSpeechEngine` için başlangıç noktası `docs/superpowers/plans/2026-11-23-voice-task-capture-reference/fake_speech_engine.dart.txt`; `resolveLocale` önce tam etiketi (`tr-TR`), sonra aynı dil kodunu arar. `AppController` yapıcısına yalnız `speech` parametresi eklenir; başka satır değişmez.

- [ ] **Step 5: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; 53 test geçer (47 + 6).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/models/settings.dart lib/l10n/strings.dart lib/state/app_controller.dart \
  lib/core/spoken/spoken_task.dart lib/services/speech/speech_engine.dart lib/services/links.dart \
  test/support/fake_speech_engine.dart test/foundation_test.dart
git commit -m "Sesle ekleme: ortak temel (metinler, ayar alanları, SpeechEngine arayüzü, paketler)" -m "<Global Constraints'teki iki satır>"
```

---

### Task 2: Konuşma normalleştirici ve ayrıştırıcı (156 vektör)

**Files:**
- Create: `lib/core/spoken/normalize.dart`, `lib/core/spoken/parse.dart`
- Test: `test/spoken_parse_test.dart`
- Dokunulmaz: `lib/core/quick_parse.dart`, `test/models_test.dart`

**Interfaces:**
- Consumes: `SpokenTask` (Görev 1); `lib/core/dates.dart` (`dateOnly`, `addDays`, `daysInMonth`), `lib/core/turkish_text.dart` (`lower`, `capitalize`).
- Produces:

```dart
// lib/core/spoken/normalize.dart
class NormalizedSpeech {
  const NormalizedSpeech(this.text, {this.remind = false, this.isNote = false});
  final String text; final bool remind, isNote;
}
/// Saatten bağımsız metin işi. [lang]: 'tr', 'en' ya da başka bir dil kodu.
NormalizedSpeech normalizeSpoken(String transcript, String lang);

// lib/core/spoken/parse.dart
/// [now]: konuşmanın bittiği an (yerel saat). Hiçbir girdi için istisna atmaz.
SpokenTask parseSpokenTask(String transcript, DateTime now, String lang);
```

Kurallar tasarım §6.4'tedir; kabul ölçütü vektör dosyasıdır. `normalize.dart` şunları yapar: kesme işaretlerini (’ ‘ ` ´ ʼ) `'` yapar, baştaki/sondaki noktalamayı atar, dolgu kalıplarını ("bir görev ekle", "görev ekle", "add a task to") ve hatırlatma kalıbını ("…mayı/meyi hatırlat", "… diye hatırlat", "bana … hatırlat", "remind me to …") çıkarır ve başlığı emir kipine çevirir, not önekini ("not al", "not:", "note") tanır, sayı sözcüklerini ve buçuk/çeyrek/geçe/kala/yarım kalıplarını **yalnız saat bağlamında** rakama çevirir. Ara metnin biçimi sana aittir; onu yalnız `parse.dart` tüketir. Tarih/saat hesabı (`now` isteyen her şey) `parse.dart` içindedir. Başvuru: `…-reference/spoken_parse.dart.txt` ilk 145 vektörü geçer; körlemesine kopyalama, önce testi yaz.

`ambiguousHour` (tasarım §8.4, bu planın kararı): saat, gün bölümü/am/pm olmadan söylenen yalın **1–11** değerinden çıkarıldıysa `true`; 0, 12, 13–23, başında sıfır olan ("08.30"), gün bölümüyle söylenen ("akşam 7'de"), am/pm'li ve göreli ("2 saat sonra") saatlerde `false`.

- [ ] **Step 1: Vektör testini yaz** — `test/spoken_parse_test.dart`

Vektörler dosyadan okunur; elle kopyalanmaz.

```dart
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
}
```

- [ ] **Step 2: Başarısız olduğunu gör**

Run: `flutter test test/spoken_parse_test.dart`
Expected: derleme hatası (`parseSpokenTask` tanımsız).

- [ ] **Step 3: A ve B gruplarını geçir** (yazılı biçimler, rakam + ek, kesme işareti türleri, yalın saat kuralı)

Run: `flutter test test/spoken_parse_test.dart --name 'vektör [AB]\d\d'`
Expected: 21 test geçer.

- [ ] **Step 4: C, D, E gruplarını geçir** (sayı sözcükleri, buçuk/çeyrek/geçe/kala, gün bölümleri, bileşik isimler)

Run: `flutter test test/spoken_parse_test.dart --name 'vektör [CDE]\d\d'`
Expected: 34 test geçer.

- [ ] **Step 5: F, G, H, K gruplarını geçir** (göreli tarihler, ay/gün, "…'e kadar", tarih sayılmayanlar, dolgu ve hatırlatma, not)

Run: `flutter test test/spoken_parse_test.dart --name 'vektör [FGHK]\d\d'`
Expected: 52 test geçer.

- [ ] **Step 6: I ve N gruplarını geçir** (İngilizce; farklı "şimdi" değerleri)

Run: `flutter test test/spoken_parse_test.dart --name 'vektör'`
Expected: 157 test geçer (156 vektör + sayım testi).

- [ ] **Step 7: Vektör dışı testleri ekle ve geçir** (aynı dosyaya)

```dart
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
```

Run: `flutter test test/spoken_parse_test.dart`
Expected: hepsi geçer.

- [ ] **Step 8: Yazarak eklemenin değişmediğini doğrula**

Run: `flutter analyze && flutter test && git diff --stat HEAD -- lib/core/quick_parse.dart test/models_test.dart`
Expected: `No issues found!`; tüm testler geçer; `git diff --stat` çıktısı boş.

- [ ] **Step 9: Commit**

```bash
git add lib/core/spoken/normalize.dart lib/core/spoken/parse.dart test/spoken_parse_test.dart
git commit -m "Sesle ekleme: konuşma ayrıştırıcı ve 156 kabul vektörü" -m "<iki satır>"
```

---

### Task 3: `speech_to_text` uyarlayıcısı

**Files:**
- Create: `lib/services/speech/stt_speech_engine.dart`
- Test: `test/stt_speech_engine_test.dart`

**Interfaces:**
- Consumes: `SpeechEngine` ve olay sınıfları (Görev 1); `package:speech_to_text/speech_to_text.dart`, `package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart` (`SpeechToTextPlatform`, `SpeechListenOptions`, `ListenMode`).
- Produces:

```dart
class SttSpeechEngine implements SpeechEngine {
  SttSpeechEngine({SpeechToText? stt});      // varsayılan SpeechToText()
}
/// iOS'ta SttSpeechEngine, diğer her yerde (web dahil) UnsupportedSpeechEngine.
SpeechEngine createSpeechEngine();
/// Saf yardımcılar (test edilir):
String? pickLocale(List<Locale> preferred, List<String> supported); // '-' ve '_' eşdeğer; tam eşleşme, sonra dil kodu
SpeechFailure mapSttError(String errorMsg, {required bool permanent});
double normalizeLevel(double db);            // ((db + 50) / 50).clamp(0, 1)
```

Davranış (tasarım §6.3):

- `prepare`: `stt.initialize(onError:, onStatus:)`. `false` dönerse `permissionDenied`; `PlatformException` → `unavailable`; yerel ayar `stt.locales()` içinde yoksa `unsupportedLocale`; aksi halde `ready`. İkinci çağrıda eklenti yeniden başlatılmaz.
- `start`: `stt.listen(onResult:, onSoundLevelChange:, listenOptions: SpeechListenOptions(partialResults: true, onDevice: false, autoPunctuation: false, cancelOnError: false, listenMode: ListenMode.confirmation, localeId: localeId, listenFor: Duration(seconds: 55)))`. `pauseFor` verilmez.
- **Bütün eklenti çağrıları tek sıraya alınır** (bir `Future` zinciri). Bir oturum, eklenti `done` durumunu bildirince ya da `cancel` tamamlanınca biter; önceki oturum bitmeden `listen` çağrılmaz. Bitiş bildirimi gelmezse 3 sn sonra bitmiş sayılır (sıra kilitlenmez). Açık çökme hatası #680 tam bu döngüde olur.
- Olaylar: eklenti `listening` → `SpeechStarted`; ara sonuç → `SpeechPartial`; `finalResult` → `SpeechFinal`; oturum bitişi → `SpeechStopped` (oturum başına bir kez); ses düzeyi → `SpeechLevel(normalizeLevel(db))`.
- Hata eşlemesi:

| Eklenti `errorMsg` | `SpeechErrorKind` |
| --- | --- |
| `error_no_match`, `error_request_cancelled` | `noMatch` (kalıcı değil) |
| `error_speech_recognizer_request_not_authorized` | `permission` |
| `error_speech_recognizer_disabled` | `dictationDisabled` |
| `error_speech_recognizer_connection_interrupted`, `error_speech_recognizer_connection_invalidated` | `interrupted` |
| `error_retry`, `error_listen_failed` | `network` |
| diğerleri | `unknown` |

- [ ] **Step 1: Başarısız testleri yaz** — `test/stt_speech_engine_test.dart`

Test, `SpeechToTextPlatform.instance` yerine `SpeechToTextPlatform`'u `extends` eden bir `FakeSttPlatform` koyar (çağrıları `calls` listesine yazar; `listen` çağrısının `SpeechListenOptions` değerini saklar; `emitResult(String words, {required bool isFinal})` → `onTextRecognition!(jsonEncode(SpeechRecognitionResult([SpeechRecognitionWords(words, null, 0.9)], isFinal).toJson()))`; `emitStatus(String)`; `emitError(String msg, bool permanent)` → `onError!(jsonEncode(SpeechRecognitionError(msg, permanent).toJson()))`). Motor her testte `SttSpeechEngine(stt: SpeechToText.withMethodChannel())` ile kurulur.

```dart
test('pickLocale: tam eşleşme, sonra dil kodu, yoksa null', () {
  expect(pickLocale(const [Locale('tr', 'TR')], ['en-US', 'tr-TR']), 'tr-TR');
  expect(pickLocale(const [Locale('tr', 'TR')], ['en_US', 'tr_TR']), 'tr_TR');
  expect(pickLocale(const [Locale('en', 'TR')], ['en-GB', 'tr-TR']), 'en-GB');
  expect(pickLocale(const [Locale('de'), Locale('en', 'US')], ['en-US']), 'en-US');
  expect(pickLocale(const [Locale('de', 'DE')], ['en-US', 'tr-TR']), isNull);
});

test('mapSttError tablosu', () {
  expect(mapSttError('error_no_match', permanent: false).kind, SpeechErrorKind.noMatch);
  expect(mapSttError('error_speech_recognizer_disabled', permanent: true).kind, SpeechErrorKind.dictationDisabled);
  expect(mapSttError('error_speech_recognizer_request_not_authorized', permanent: true).kind, SpeechErrorKind.permission);
  expect(mapSttError('error_speech_recognizer_connection_interrupted', permanent: true).kind, SpeechErrorKind.interrupted);
  expect(mapSttError('error_retry', permanent: false).kind, SpeechErrorKind.network);
  expect(mapSttError('bilinmeyen', permanent: true).kind, SpeechErrorKind.unknown);
});

test('normalizeLevel 0..1 aralığında kalır', () {
  expect(normalizeLevel(-160), 0);
  expect(normalizeLevel(-25), 0.5);
  expect(normalizeLevel(10), 1);
});

test('start seçenekleri tasarımdaki gibi ve yerel ayar açık verilir', () async {
  // prepare + start sonrası:
  final o = platform.lastOptions!;
  expect((o.partialResults, o.onDevice, o.autoPunctuation, o.cancelOnError), (true, false, false, false));
  expect(o.listenMode, ListenMode.confirmation);
  expect(o.localeId, 'tr-TR');
  expect(o.pauseFor, isNull);
});

test('önceki oturum bitmeden ikinci listen çağrılmaz', () async {
  await engine.prepare('tr-TR');
  await engine.start('tr-TR');
  unawaited(engine.stop());
  final second = engine.start('tr-TR');          // sıraya girer
  await pumpEventQueue();
  expect(platform.calls.where((c) => c == 'listen').length, 1);
  platform.emitStatus('done');                    // ilk oturum bitti
  await second;
  expect(platform.calls.where((c) => c == 'listen').length, 2);
});

test('bitiş bildirimi gelmezse sıra 3 sn sonra açılır', () { /* fakeAsync: stop, elapse(3 sn), ikinci listen çağrılır */ });

test('olay sırası: Started, Partial, Final, Stopped (bir kez)', () async { /* emitStatus('listening'), emitResult('süt', isFinal:false), emitResult('süt al', isFinal:true), emitStatus('done'), emitStatus('done') */ });

test('prepare: izin reddi permissionDenied, bilinmeyen yerel ayar unsupportedLocale', () async {
  platform.initResult = false;
  expect(await engine.prepare('tr-TR'), SpeechAvailability.permissionDenied);
});

test('createSpeechEngine iOS dışında eklentiye dokunmaz', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final e = createSpeechEngine();
  expect(e, isA<UnsupportedSpeechEngine>());
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  expect(createSpeechEngine(), isA<SttSpeechEngine>());
  expect(platform.calls, isEmpty);                // kurmak eklentiyi çağırmaz
});
```

- [ ] **Step 2: Başarısız olduğunu gör**

Run: `flutter test test/stt_speech_engine_test.dart`
Expected: derleme hatası (`SttSpeechEngine` tanımsız).

- [ ] **Step 3: Uygula** — `lib/services/speech/stt_speech_engine.dart`, yukarıdaki davranış listesine göre.

- [ ] **Step 4: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer.

- [ ] **Step 5: Commit**

```bash
git add lib/services/speech/stt_speech_engine.dart test/stt_speech_engine_test.dart
git commit -m "Sesle ekleme: speech_to_text uyarlayıcısı, sıralı çağrılar ve hata eşlemesi" -m "<iki satır>"
```

---

### Task 4: `AppController` — sesle kayıt, hatırlatma, bildirim izni, günlük

**Files:**
- Create: `lib/models/voice_log.dart`
- Modify: `lib/state/app_controller.dart:129-179` (yükleme), `:438-445` sonrası (yeni yöntemler), `:573-576` (`updateSettings`)
- Modify: `lib/services/reminder_scheduler.dart:42-71` (arayüz + `NoopScheduler`), `:151-185` (izin)
- Modify: `lib/ui/tasks/task_editor.dart:97`, `lib/ui/reminders/reminder_editor.dart:71`
- Test: `test/spoken_controller_test.dart`

**Interfaces:**
- Consumes: `SpokenTask`, `AppSettings.keepVoiceLog`, `AppSettings.notificationsAsked` (Görev 1).
- Produces:

```dart
// lib/models/voice_log.dart
class VoiceLogEntry {
  const VoiceLogEntry({required this.at, required this.localeId, required this.transcript,
      required this.title, this.due, this.hasTime = false, this.remind = false, this.isNote = false});
  Map<String, Object?> toJson(); factory VoiceLogEntry.fromJson(Map<String, Object?> j);
}

// lib/services/reminder_scheduler.dart
abstract class ReminderScheduler { Future<bool> isGranted(); /* + mevcutlar */ }
class NoopScheduler {
  bool granted = false;              // requestPermission() true yapar ve true döner
  int permissionRequests = 0;
  void Function()? onRequest;        // requestPermission başında çağrılır
}

// lib/state/app_controller.dart
enum NotificationAccess { notAsked, denied, granted }
TaskItem? addSpokenTask(SpokenTask s);       // başlık boşsa ya da s.isNote ise null
Note? addSpokenNote(String text);            // boşsa null; gövde = text, başlık ''
Future<NotificationAccess> notificationAccess();
Future<bool> requestNotifications();          // notificationsAsked = true; scheduler.requestPermission()
Future<void> ensureNotificationPermission();  // yalnız notAsked ise sorar
UnmodifiableListView<VoiceLogEntry> get voiceLog;   // en yeni başta, en çok 20
void logRecognized(String transcript, SpokenTask parsed, {required String localeId});
void clearVoiceLog();
```

Kurallar (tasarım §6.5):

- `remindAt`: `hasTime` ise `due` (yalnız `due.isAfter(now())` ise). `remind && !hasTime && due != null` ise o günün **09:00**'u (gelecekteyse). Diğer durumlarda `null`.
- `remindAt != null` ise kayıttan hemen sonra `unawaited(syncAlerts())` çağrılır (800 ms'lik gecikme beklenmez; kullanıcı telefonu hemen kilitleyebilir).
- `LocalNotificationScheduler.isGranted()`: iOS/macOS `checkPermissions()?.isEnabled ?? false`; Android `areNotificationsEnabled() ?? false`; diğerleri `true`; hata olursa `false`. iOS ve macOS izin isteğinde `badge: false` (uygulama rozet kullanmıyor).
- Günlük: `store` anahtarı `voice_log` (JSON liste). `logRecognized` yalnız `settings.keepVoiceLog` açıkken yazar. `updateSettings` ile `keepVoiceLog` `true`→`false` olursa günlük silinir (`store.delete('voice_log')`). Değişiklikte `_changed({Slice.settings}, persist: false)` çağrılır ki Ayarlar yeniden çizilsin.
- `task_editor.dart:97` ve `reminder_editor.dart:71` satırlarındaki `widget.app.scheduler.requestPermission()` → `widget.app.requestNotifications()`.

- [ ] **Step 1: Başarısız testleri yaz** — `test/spoken_controller_test.dart`

Kurulum: `now = DateTime(2026, 11, 23, 9)`; `MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson())})`; `NoopScheduler`; `saveDelay: Duration.zero`.

```dart
test('saatli görev: remindAt = due ve t: uyarısı hemen eşitlenir', () async {
  final t = c.addSpokenTask(SpokenTask(title: 'Annemi ara', due: DateTime(2026, 11, 24, 19), hasTime: true))!;
  expect(t.remindAt, DateTime(2026, 11, 24, 19));
  expect(c.alerts().map((a) => a.key), contains('t:${t.id}'));
  await Future<void>.delayed(Duration.zero);
  expect(scheduler.synced.last.map((a) => a.key), contains('t:${t.id}'));
});
test('geçmiş saat bildirim kurmaz', () {
  expect(c.addSpokenTask(SpokenTask(title: 'x', due: DateTime(2026, 11, 23, 8), hasTime: true))!.remindAt, isNull);
});
test('hatırlat + gün, saat yok: o gün 09:00', () {
  final t = c.addSpokenTask(SpokenTask(title: 'Faturayı öde', due: DateTime(2026, 11, 24), remind: true))!;
  expect((t.hasTime, t.remindAt), (false, DateTime(2026, 11, 24, 9)));
});
test('hatırlat + bugün: 09:00 geçmişse bildirim yok', () {
  expect(c.addSpokenTask(SpokenTask(title: 'x', due: DateTime(2026, 11, 23), remind: true))!.remindAt, isNull);
});
test('hatırlat tarihsiz: görev tarihsiz, bildirim yok', () {
  final t = c.addSpokenTask(const SpokenTask(title: 'Annemi ara', remind: true))!;
  expect((t.due, t.remindAt), (null, null));
});
test('boş başlık ve not görev olmaz', () {
  expect(c.addSpokenTask(const SpokenTask(title: '')), isNull);
  expect(c.addSpokenTask(const SpokenTask(title: 'x', isNote: true)), isNull);
  expect(c.tasks, isEmpty);
});
test('addSpokenNote metni gövde yapar; deleteNote geri alır', () {
  final n = c.addSpokenNote('Süt bitmiş')!;
  expect((c.notes.first.id, n.body, n.title), (n.id, 'Süt bitmiş', ''));
  expect(c.addSpokenNote('  '), isNull);
  c.deleteNote(n.id);
  expect(c.notes, isEmpty);
});
test('bildirim izni yalnız bir kez sorulur ve sorulduğu kaydedilir', () async {
  expect(await c.notificationAccess(), NotificationAccess.notAsked);
  await c.ensureNotificationPermission();
  await c.ensureNotificationPermission();
  expect(scheduler.permissionRequests, 1);
  expect(c.settings.notificationsAsked, isTrue);
  expect(await c.notificationAccess(), NotificationAccess.granted);
  scheduler.granted = false;
  expect(await c.notificationAccess(), NotificationAccess.denied);
});
test('günlük varsayılan kapalı; açıkken en çok 20 kayıt, en yeni başta; kapatınca silinir', () async {
  const p = SpokenTask(title: 'Toplantı');
  c.logRecognized('toplantı', p, localeId: 'tr-TR');
  expect(c.voiceLog, isEmpty);
  c.updateSettings(c.settings.copyWith(keepVoiceLog: true));
  for (var i = 0; i < 25; i++) { c.logRecognized('metin $i', p, localeId: 'tr-TR'); }
  expect(c.voiceLog.length, 20);
  expect(c.voiceLog.first.transcript, 'metin 24');
  await c.flush(); await Future<void>.delayed(Duration.zero);
  expect(store.data['voice_log'], contains('metin 24'));
  c.updateSettings(c.settings.copyWith(keepVoiceLog: false));
  await Future<void>.delayed(Duration.zero);
  expect(c.voiceLog, isEmpty);
  expect(store.data.containsKey('voice_log'), isFalse);
});
test('günlük yeniden açılışta yüklenir; bozuk belge yok sayılır', () async { /* store 'voice_log' ile yeni AppController.load(); sonra 'voice_log': '{bozuk' ile boş liste */ });
test('yazarak hızlı ekleme hatırlatma kurmaz (değişmedi)', () {
  expect(c.addQuickTask('yarın 10:00 toplantı')!.remindAt, isNull);
});
```

- [ ] **Step 2: Başarısız olduğunu gör**

Run: `flutter test test/spoken_controller_test.dart`
Expected: derleme hatası (`addSpokenTask` tanımsız).

- [ ] **Step 3: Uygula** — yukarıdaki kurallarla. `addQuickTask` gövdesi değişmez.

- [ ] **Step 4: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer.

- [ ] **Step 5: Commit**

```bash
git add lib/models/voice_log.dart lib/state/app_controller.dart lib/services/reminder_scheduler.dart \
  lib/ui/tasks/task_editor.dart lib/ui/reminders/reminder_editor.dart test/spoken_controller_test.dart
git commit -m "Sesle ekleme: addSpokenTask/addSpokenNote, hatırlatma, bildirim izni durumu ve günlük" -m "<iki satır>"
```

---

### Task 5: iOS — kestirme, köprü, Info.plist, izin metinleri, gizlilik bildirimi

**Files:**
- Create: `ios/Runner/VoiceTaskIntent.swift`, `ios/Runner/PamnotLaunchBridge.swift`, `ios/Runner/PrivacyInfo.xcprivacy`
- Create: `ios/Runner/en.lproj/{InfoPlist,AppShortcuts,Localizable}.strings`, `ios/Runner/tr.lproj/{InfoPlist,AppShortcuts,Localizable}.strings`
- Create: `tool/ios/add_voice_files.rb`, `tool/ios/check_project.rb`, `tool/ios/check_ios_config.py`
- Modify: `ios/Runner/AppDelegate.swift:25`, `ios/Runner/Info.plist:4-69`, `ios/Runner.xcodeproj/project.pbxproj` (yalnız betikle)

**Interfaces:**
- Consumes: yok (Dart koduna bağlı değil).
- Produces: yöntem kanalı **`app.pamnot/launch`** — Dart→iOS `takePendingAction` (dönüş: `"voice"` ya da `null`, okununca temizlenir); iOS→Dart `actionAvailable` (bağımsız değişken yok). Bağlantılar: `pamnot://ses` ve `pamnot://voice` (yalnız bu iki sunucu adı sahiplenilir). Betikler: `python3 tool/ios/check_ios_config.py` ve `ruby tool/ios/check_project.rb ios/Runner.xcodeproj` (Görev 13 CI'a bağlar).

- [ ] **Step 1: Başarısız denetimleri yaz**

`tool/ios/check_ios_config.py` (yalnız standart kitaplık; her başarısızlıkta nedenini yazıp `1` ile çıkar, başarıda `ios config ok` yazar):

1. `ios/Runner/Info.plist` (`plistlib`): `CFBundleLocalizations == ['en','tr']`; `CFBundleURLTypes[0]` = `{CFBundleTypeRole: 'Editor', CFBundleURLName: 'app.pamnot.pamnot', CFBundleURLSchemes: ['pamnot']}`; `FlutterDeepLinkingEnabled is False`; `ITSAppUsesNonExemptEncryption is False`; `NSMicrophoneUsageDescription` ve `NSSpeechRecognitionUsageDescription` aşağıdaki EN metinlere eşit. Bulunmaması gerekenler: `NSSiriUsageDescription`, `UIBackgroundModes`, `NSUserActivityTypes`, `NSUserNotificationsUsageDescription`, `UIRequiresFullScreen`, `NSAppIntents` ile başlayan her anahtar.
2. `ios/Runner/PrivacyInfo.xcprivacy` (`plistlib`): `NSPrivacyTracking is False`; `NSPrivacyTrackingDomains == []`; `NSPrivacyCollectedDataTypes == []`; erişilen API'ler tam olarak `{UserDefaults: ['CA92.1','1C8F.1'], FileTimestamp: ['C617.1']}`.
3. `.strings` dosyaları (`^"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$` satırları; yorum ve boş satır dışında başka satır yok): altı dosya var; her tabloda `en` ve `tr` anahtar kümeleri aynı; `InfoPlist.strings` anahtarları tam olarak iki izin anahtarı ve değerler aşağıdaki tabloya eşit.
4. `VoiceTaskIntent.swift`: `phrases: [...]` içindeki her dize `\(.applicationName)` içerir; `\(.applicationName)` → `${applicationName}` çevrilince küme `AppShortcuts.strings` anahtarlarına eşit; ifade sayısı 4; hiçbir ifade ve çeviri "Siri" içermez; TR çevirilerde `${applicationName}` hemen ardından `'` ya da `’` gelmez (ad eksiz kalır); başlık `"Add Voice Task"` (≤ 3 sözcük) ve `Localizable.strings` içinde anahtar olarak var; dosyada `shortTitle`, `systemImageName`, `#available` geçmez.
5. `AppDelegate.swift`: `registrar(forPlugin: "PamnotLaunchBridge")` satırı var ve `setPluginRegistrantCallback {` bloğunun kapanışından **sonra**.
6. `PamnotLaunchBridge.swift`: `"app.pamnot/launch"`, `takePendingAction`, `actionAvailable`, `static let shared` ve `"ses"`, `"voice"` geçer.

`tool/ios/check_project.rb` (`xcodeproj`): Runner hedefinin kaynak aşamasında `PamnotLaunchBridge.swift` ve `VoiceTaskIntent.swift`; kaynak (resources) aşamasında `PrivacyInfo.xcprivacy`, `AppShortcuts.strings`, `Localizable.strings`, `InfoPlist.strings`; her varyant grubunda `en` ve `tr`; `known_regions` içinde `tr`; `object_version == '54'`; başvurulan her dosya diskte var. Başarıda `project ok` yazar.

- [ ] **Step 2: Başarısız olduklarını gör**

Run: `python3 tool/ios/check_ios_config.py; GEM_HOME=<Global Constraints> ruby tool/ios/check_project.rb ios/Runner.xcodeproj`
Expected: ikisi de sıfırdan farklı kodla çıkar (ilki `CFBundleLocalizations` eksik der).

- [ ] **Step 3: Swift dosyalarını yaz** (burada derlenemez; imzalar Flutter 3.47.8 motor başlıklarından ve `home_widget` 0.10.0 kaynağından doğrulandı — birebir yaz)

`ios/Runner/PamnotLaunchBridge.swift`:

```swift
import Flutter
import UIKit

/// Carries "open this screen" requests from iOS (App Intent, pamnot:// links) to Dart.
/// Holds one pending action; Dart pulls it with `takePendingAction`, so the request
/// survives whichever side is ready first.
final class PamnotLaunchBridge: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  /// The engine keeps scene delegates weakly, so the bridge must own itself.
  static let shared = PamnotLaunchBridge()

  private var channel: FlutterMethodChannel?
  private var pendingAction: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.pamnot/launch", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
    registrar.addSceneDelegate(shared)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePendingAction":
      let action = pendingAction
      pendingAction = nil
      result(action)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Call on the main thread.
  func request(_ action: String) {
    pendingAction = action
    channel?.invokeMethod("actionAvailable", arguments: nil)
  }

  /// Only pamnot://ses and pamnot://voice; home_widget's `?homeWidget` links are left alone.
  /// Nothing in the URL is ever saved as a task.
  private func claim(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "pamnot", let host = url.host?.lowercased(),
      host == "ses" || host == "voice"
    else { return false }
    request("voice")
    return true
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    var claimed = false
    for context in contexts where claim(context.url) { claimed = true }
    return claimed
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var claimed = false
    for context in URLContexts where claim(context.url) { claimed = true }
    return claimed
  }
}
```

`ios/Runner/VoiceTaskIntent.swift`:

```swift
import AppIntents

/// "Sesle Görev Ekle": opens Pamnot on the listening screen. Shown in Shortcuts, Spotlight,
/// Siri and the Action button without any setup. Needs no entitlement.
struct VoiceTaskIntent: AppIntent {
  static let title: LocalizedStringResource = "Add Voice Task"
  static let description = IntentDescription("Opens Pamnot and listens so you can add a task by voice.")

  @MainActor
  func perform() async throws -> some IntentResult {
    PamnotLaunchBridge.shared.request("voice")
    return .result()
  }
}

// openAppWhenRun is deprecated in the iOS 26 SDK (supportedModes replaces it, iOS 26+ only).
// Apple's documented way to keep supporting iOS 16 without the warning.
@available(*, deprecated)
extension VoiceTaskIntent {
  static var openAppWhenRun: Bool { true }
}

struct PamnotShortcuts: AppShortcutsProvider {
  // iOS 16 initializer on purpose: no shortTitle/systemImageName, no availability checks here.
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: VoiceTaskIntent(),
      phrases: [
        "Add a task in \(.applicationName)",
        "Add a \(.applicationName) task",
        "New task in \(.applicationName)",
        "Add a voice task in \(.applicationName)",
      ]
    )
  }
}
```

`ios/Runner/AppDelegate.swift` — 25. satırdan (`GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)`) hemen sonra, `setPluginRegistrantCallback` bloğunun **dışında**:

```swift
    // Only for the UI engine: the notification plugin's background engine must not get this.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PamnotLaunchBridge") {
      PamnotLaunchBridge.register(with: registrar)
    }
```

- [ ] **Step 4: Metin dosyalarını, Info.plist anahtarlarını ve gizlilik bildirimini yaz**

`.strings` dosyaları UTF-8, her satır `"anahtar" = "değer";`.

| Dosya | Anahtar | en | tr |
| --- | --- | --- | --- |
| `InfoPlist.strings` | `NSMicrophoneUsageDescription` | Pamnot uses the microphone to hear what you say when you add a task by voice. No audio is saved. | Pamnot, sesle görev eklerken söylediklerini duymak için mikrofonu kullanır. Ses kaydı saklanmaz. |
| `InfoPlist.strings` | `NSSpeechRecognitionUsageDescription` | Pamnot uses speech recognition to turn the task you say into text. Your voice may be sent to Apple for this. | Pamnot, söylediğin görevi yazıya çevirmek için konuşma tanımayı kullanır. Sesin bunun için Apple'a gönderilebilir. |
| `Localizable.strings` | `Add Voice Task` | Add Voice Task | Sesle Görev Ekle |
| `Localizable.strings` | `Opens Pamnot and listens so you can add a task by voice.` | (aynı) | Pamnot'u açar ve görevi sesle eklemen için dinler. |
| `AppShortcuts.strings` | `Add a task in ${applicationName}` | (aynı) | ${applicationName} ile görev ekle |
| `AppShortcuts.strings` | `Add a ${applicationName} task` | (aynı) | ${applicationName} görevi ekle |
| `AppShortcuts.strings` | `New task in ${applicationName}` | (aynı) | Yeni ${applicationName} görevi |
| `AppShortcuts.strings` | `Add a voice task in ${applicationName}` | (aynı) | ${applicationName} ile sesle görev ekle |

`ios/Runner/Info.plist` — kök `<dict>` içine (anahtarlar alfabetik yerlerine): `CFBundleLocalizations` = `[en, tr]`; `CFBundleURLTypes` = bir öğe (`CFBundleTypeRole` `Editor`, `CFBundleURLName` `app.pamnot.pamnot`, `CFBundleURLSchemes` `[pamnot]`); `FlutterDeepLinkingEnabled` = `<false/>`; `ITSAppUsesNonExemptEncryption` = `<false/>`; `NSMicrophoneUsageDescription` ve `NSSpeechRecognitionUsageDescription` = tablodaki EN metinler. Mevcut anahtarlar değişmez.

`ios/Runner/PrivacyInfo.xcprivacy` — içerik uyum belgesi §2.3'teki XML'in birebir kopyası (UserDefaults `CA92.1` + `1C8F.1`, FileTimestamp `C617.1`, izleme yok, toplanan veri yok).

- [ ] **Step 5: Proje betiğini yaz ve çalıştır**

`tool/ios/add_voice_files.rb` (2026-11-23'te projenin bir kopyasında denendi: iki kez çalıştırınca ikinci çalıştırma dosyayı değiştirmiyor, `objectVersion` 54 kalıyor):

```ruby
# Usage: ruby tool/ios/add_voice_files.rb ios/Runner.xcodeproj
# Adds the voice-capture Swift files, the privacy manifest and the en/tr .strings tables to the
# Runner target. Idempotent: running it again changes nothing.
require 'xcodeproj'

project = Xcodeproj::Project.open(ARGV.fetch(0))
target  = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target missing'
group   = project.main_group.children.find { |g| g.display_name == 'Runner' } or abort 'Runner group missing'

%w[PamnotLaunchBridge.swift VoiceTaskIntent.swift].each do |name|
  next if group.files.any? { |f| f.path == name }
  target.source_build_phase.add_file_reference(group.new_reference(name), true)
end

%w[PrivacyInfo.xcprivacy].each do |name|
  next if group.files.any? { |f| f.path == name }
  ref = group.new_reference(name)
  ref.last_known_file_type = 'text.xml'
  target.resources_build_phase.add_file_reference(ref, true)
end

%w[AppShortcuts Localizable InfoPlist].each do |table|
  name = "#{table}.strings"
  next if group.children.any? { |c| c.isa == 'PBXVariantGroup' && c.name == name }
  variant = group.new_variant_group(name)
  %w[en tr].each do |lang|
    ref = variant.new_reference("#{lang}.lproj/#{name}")
    ref.name = lang
    ref.last_known_file_type = 'text.plist.strings'
  end
  target.resources_build_phase.add_file_reference(variant, true)
end

project.root_object.known_regions |= %w[tr]
project.save
puts 'ok'
```

Run: `export GEM_HOME=<Global Constraints>; ruby tool/ios/add_voice_files.rb ios/Runner.xcodeproj && cp ios/Runner.xcodeproj/project.pbxproj /tmp/pbx.once && ruby tool/ios/add_voice_files.rb ios/Runner.xcodeproj && cmp /tmp/pbx.once ios/Runner.xcodeproj/project.pbxproj && echo idempotent`
Expected: `ok`, `ok`, `idempotent`. `git diff --stat ios/Runner.xcodeproj` yalnız `project.pbxproj` gösterir (gem ayrıca bir yorum satırını ve bir sıralamayı değiştirir; zararsızdır, geri alınmaz).

- [ ] **Step 6: Denetimlerin geçtiğini gör**

Run: `python3 tool/ios/check_ios_config.py && ruby tool/ios/check_project.rb ios/Runner.xcodeproj && grep -c 'objectVersion = 54' ios/Runner.xcodeproj/project.pbxproj && flutter analyze && flutter test`
Expected: `ios config ok`, `project ok`, `1`, `No issues found!`, tüm testler geçer.

- [ ] **Step 7: Commit**

```bash
git add ios/Runner tool/ios ios/Runner.xcodeproj/project.pbxproj
git commit -m "iOS: Sesle Görev Ekle kestirmesi, açılış köprüsü, izin metinleri ve gizlilik bildirimi [full-build]" -m "<iki satır>"
```

---

### Task 6: iOS — uygulama simgesi, açılış ekranı, widget gizlilik bildirimi

**Files:**
- Create: `tool/icons/make_app_icon.py`, `tool/ios/check_launch_assets.py`
- Create: `ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json`, `ios/PamnotWidget/PrivacyInfo.xcprivacy`
- Modify: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (15 dosya, adlar aynı), `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `ios/PamnotWidget/PamnotTodayWidget.swift:355`, `ios/PamnotWidget/README.md:8-15` ve adım 3
- Delete: `ios/Runner/Assets.xcassets/LaunchImage.imageset/` (5 dosya)

**Interfaces:**
- Consumes: yok.
- Produces: `python3 tool/ios/check_launch_assets.py` (Görev 13 CI'a bağlar).

- [ ] **Step 1: Başarısız denetimi yaz** — `tool/ios/check_launch_assets.py` (yalnız standart kitaplık; PNG başlığını `struct` ile okur)

1. `AppIcon.appiconset/Contents.json` içindeki her `filename` var; piksel boyutu `size × scale` değerine eşit; PNG renk türü **2** (RGB, alfa yok); 1024'lük dosya 1024×1024.
2. Hiçbir simge depodaki eski Flutter logosuyla aynı değil: 1024'lük dosyanın SHA-256'sı `git show HEAD:ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` çıktısınınkinden farklı (betik bu değeri sabit olarak içerir; değeri görevden önce `sha256sum` ile al).
3. `LaunchBackground.colorset/Contents.json`: iki renk; biri `appearances` içermez ve `0xFA/0xF7/0xF2`, diğeri `luminosity = dark` ve `0x1E/0x1C/0x24`.
4. `LaunchScreen.storyboard` (`xml.etree`): `imageView` ve `constraint` öğesi yok; `view` altında `color[@key='backgroundColor'][@name='LaunchBackground']`; `resources/namedColor[@name='LaunchBackground']` var; `resources/image` yok.
5. `LaunchImage.imageset` klasörü yok.
6. `ios/PamnotWidget/PrivacyInfo.xcprivacy` (`plistlib`): yalnız UserDefaults `['1C8F.1']`, izleme yok, toplanan veri yok.
7. `PamnotTodayWidget.swift` içinde `0x8C8698` geçmez, `0x6A6478` geçer.

Başarıda `launch assets ok` yazar.

Run: `python3 tool/ios/check_launch_assets.py`
Expected: sıfırdan farklı kod (ilk hata: simge eski logoyla aynı).

- [ ] **Step 2: Simgeyi üret** — `tool/icons/make_app_icon.py` (Pillow 12 kurulu)

1024×1024 ana görsel, 4096'da çizilip LANCZOS ile küçültülür; **RGB, alfa yok**, köşeler yuvarlatılmaz, yazı ve emoji yok. Zemin: sol üstten sağ alta doğrusal gradyan `#C9BCF5` → `#FBC9B4` (uygulamadaki logo, `lib/ui/home_shell.dart:152`). Ortada beyaz (`#FFFFFF`) bulut; 1024 birimde: daireler (merkez x, y, yarıçap) `(392, 560, 140)`, `(540, 470, 190)`, `(680, 580, 130)` ve köşe yarıçapı 70 olan dikdörtgen `(300, 560)–(790, 700)`. Betik `Contents.json`'daki her dosyayı ana görselden küçülterek aynı adla yazar. Renkli emoji (Apple'ın ☁️ çizimi) kullanılmaz: telif.

Run: `python3 tool/icons/make_app_icon.py`
Expected: 15 PNG yazıldı. Sonra `Icon-App-1024x1024@1x.png` dosyasını Read aracıyla aç ve gör: pastel gradyan üstünde ortalanmış, kenarlara değmeyen beyaz bulut.

- [ ] **Step 3: Açılış ekranını düzelt**

`LaunchBackground.colorset/Contents.json`:

```json
{
  "colors" : [
    { "idiom" : "universal",
      "color" : { "color-space" : "srgb", "components" : { "red" : "0xFA", "green" : "0xF7", "blue" : "0xF2", "alpha" : "1.000" } } },
    { "idiom" : "universal",
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb", "components" : { "red" : "0x1E", "green" : "0x1C", "blue" : "0x24", "alpha" : "1.000" } } }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`LaunchScreen.storyboard`: `<dependencies>` içine `<capability name="Named colors" minToolsVersion="9.0"/>`; `<view key="view" …>` altında yalnız `autoresizingMask` ve `<color key="backgroundColor" name="LaunchBackground"/>` kalır (`subviews`, `imageView`, `constraints` silinir); `<resources>` içeriği:

```xml
        <namedColor name="LaunchBackground">
            <color red="0.980" green="0.969" blue="0.949" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
        </namedColor>
```

`git rm -r ios/Runner/Assets.xcassets/LaunchImage.imageset`. Logo eklenmez (HIG Launching).

- [ ] **Step 4: Widget dosyaları**

`ios/PamnotWidget/PrivacyInfo.xcprivacy`: Runner'ınkiyle aynı yapı, erişilen API yalnız `NSPrivacyAccessedAPICategoryUserDefaults` + `1C8F.1`. `PamnotTodayWidget.swift:355`: `0x8C8698` → `0x6A6478` (5,31:1). `README.md`: dosya tablosuna `PrivacyInfo.xcprivacy` satırı; adım 3'teki üyelik listesine "`PrivacyInfo.xcprivacy` de hedef üyesi olmalı" cümlesi.

- [ ] **Step 5: Geçtiğini gör**

Run: `python3 tool/ios/check_launch_assets.py && flutter analyze && flutter test`
Expected: `launch assets ok`, `No issues found!`, tüm testler geçer.

- [ ] **Step 6: Commit**

```bash
git add -A ios/Runner/Assets.xcassets ios/Runner/Base.lproj/LaunchScreen.storyboard ios/PamnotWidget tool/icons tool/ios/check_launch_assets.py
git commit -m "iOS: Pamnot simgesi, temaya uyan açılış ekranı, widget gizlilik bildirimi [full-build]" -m "<iki satır>"
```

---

### Task 7: `VoiceCaptureController` — durum makinesi ve zamanlamalar

**Files:**
- Create: `lib/ui/voice/voice_capture_controller.dart`
- Create: `test/support/voice_harness.dart`
- Test: `test/voice_capture_controller_test.dart`

**Interfaces:**
- Consumes: `parseSpokenTask` (Görev 2); `AppController.addSpokenTask/addSpokenNote/ensureNotificationPermission/logRecognized/deleteTask/deleteNote/flush/now` (Görev 4); `SpeechEngine`, `FakeSpeechEngine` (Görev 1).
- Produces:

```dart
abstract final class VoiceTimings {
  static const startDelay = Duration(milliseconds: 300);     // Siri ses oturumu çakışmasın
  static const utteranceGap = Duration(milliseconds: 1600);
  static const previewHold = Duration(seconds: 2);
  static const idleClose = Duration(seconds: 6);
  static const maxListen = Duration(seconds: 30);
  static const backgroundClose = Duration(minutes: 5);
}
enum VoicePhase { preparing, listening, preview, editing, saved, paused, error,
    permissionDenied, dictationOff, unsupportedLocale, unsupportedPlatform, closed }
class SavedItem {
  const SavedItem({required this.id, required this.isNote, required this.title, this.due,
      this.hasTime = false, this.reminder = false, this.inBackground = false});
}
class VoiceCaptureController extends ChangeNotifier {
  VoiceCaptureController({required AppController app, required SpeechEngine engine,
      List<Locale> Function()? deviceLocales, VoidCallback? onSaved});
  VoicePhase get phase;
  String get transcript;             // canlı metin ya da düzeltme taslağı
  SpokenTask? get preview;           // canlı ya da son ayrıştırma
  double get level;                  // 0..1
  List<SavedItem> get saved;         // en yeni başta
  String? get localeId;
  bool accessible = false;           // VoiceOver / Anahtar Denetimi
  Future<void> open({AppLifecycleState? lifecycle});  // null ve resumed ön plandır
  void toggleMic();                  // dinlerken durdurur; saved/paused/error iken dinlemeyi başlatır
  void edit();                       // önizleme → düzeltme
  void updateDraft(String text);
  Future<void> saveNow();            // önizleme ya da düzeltmedeki görevi kaydeder
  void undo(SavedItem item);
  Future<void> close();              // motoru iptal eder; önizlemedeki görev kaydedilmez
  void onLifecycle(AppLifecycleState state);
}

// test/support/voice_harness.dart
class VoiceHarness {
  DateTime now;                      // değiştirilebilir saat; varsayılan 2026-11-23 09:00
  late final MemoryStore store; late final NoopScheduler scheduler; late final AppController app;
  static Future<VoiceHarness> create(WidgetTester tester, {AppSettings? settings});
  // settings varsayılanı: AppSettings(language: AppLanguage.tr, seeded: true); saveDelay sıfır
  Future<void> dispose(WidgetTester tester);   // 3 sn pump + app.dispose()
}
```

Davranış (tasarım §5, §6.3, §6.6; uyum §4.1, §4.2-3):

- **Açılış:** `engine.isSupported` değilse `unsupportedPlatform`. Ön planda değilse `resumed` beklenir. `startDelay` sonra `resolveLocale(deviceLocales())` (`null` → `unsupportedLocale`), `prepare` (`permissionDenied` → `permissionDenied`; `unavailable` → `error`), sonra `engine.start`. Ayrıştırıcı dili: yerel ayarın dil kodu (`tr-TR` → `tr`).
- **`listening` evresi `SpeechStarted` olayıyla başlar, `SpeechStopped` ile biter** (zamanlayıcıyla değil): "Dinliyorum" yazısı mikrofon kapalıyken ekranda kalamaz.
- **Ara sonuç:** `transcript` güncellenir, `preview = parseSpokenTask(text, app.now(), lang)`, 1,6 sn'lik zamanlayıcı yeniden kurulur, 6 sn'lik zamanlayıcı iptal edilir. 1,6 sn dolunca `engine.stop()`.
- **Son metin:** `SpeechFinal` metni; `SpeechStopped` geldiğinde Final gelmemişse son ara metin. Başlığı boş çıkarsa kaydedilmez. Doluysa `preview` evresi ve 2 sn'lik zamanlayıcı. Bir oturumda yalnız **ilk** son metin işlenir; oturum dışı gelen `SpeechFinal` yok sayılır.
- **Kayıt:** `isNote` → `addSpokenNote`, değilse `addSpokenTask`; `logRecognized`; `saved` başına eklenir; `onSaved` (dokunsal) çağrılır — bu anda mikrofon kapalıdır. Görevin `remindAt` değeri varsa ve uygulama ön plandaysa `await app.ensureNotificationPermission()` **yeniden dinlemeden önce**. Sonra `engine.start` (yeniden dinleme).
- **Sessizlik:** bu ekranda en az bir kayıt yapıldıktan sonraki dinlemede 6 sn hiç ara sonuç gelmezse `close()`. İlk dinlemede (henüz kayıt yokken) ekran kapanmaz; 30 sn dolunca `engine.stop()`; metin yoksa `paused`.
- **30 sn sınırı:** her dinlemede; dolunca `engine.stop()` ve akış son metinle devam eder.
- **Düzelt:** 2 sn'lik zamanlayıcı durur; `editing`; `updateDraft` her değişiklikte `preview`'u yeniler; `saveNow` kaydeder ve yeniden dinler.
- **Kapat:** her evrede çalışır; `engine.cancel()`; önizlemedeki ya da taslaktaki görev kaydedilmez; evre `closed`; bütün zamanlayıcılar iptal. `prepare` beklenirken kapatılırsa sonrasında `engine.start` çağrılmaz.
- **Hatalar:** `noMatch` hata sayılmaz (sessizlik gibi). `permission` → `permissionDenied`; `dictationDisabled` → `dictationOff`; `interrupted` → `paused`; `network`/`unknown` → `error` (`toggleMic` yeniden dener).
- **Arka plan** (`hidden` ya da `paused`; `inactive` tek başına hiçbir şeyi değiştirmez):

| O anki evre | Ne olur |
| --- | --- |
| `listening`, metin yok | `engine.cancel()`, evre `paused` |
| `listening`, metin var | Eldeki metin ayrıştırılır; başlık doluysa kaydedilir (`inBackground: true`); `engine.cancel()`; evre `paused` |
| `preview` | Hemen kaydedilir (`inBackground: true`); evre `paused` |
| `editing` | Kaydedilmez; taslak kalır |
| diğerleri | Değişmez |

  Sonra `app.flush()`. Arka planda bildirim izni sorulmaz. Dönüşte (`resumed`) mikrofon kendiliğinden açılmaz. Arka planda geçen süre (`app.now()` farkı) 5 dakikayı aşarsa ve evre `editing` değilse dönüşte `close()`.
- **Erişilebilir gezinme** (`accessible == true`): önizlemede 2 sn'lik zamanlayıcı kurulmaz (kullanıcı `saveNow` ya da `edit` seçer); 6 sn'lik kapanma kurulmaz; kayıttan sonra yeniden dinleme başlamaz, evre `saved` olur. İlk açılıştaki dinleme ve 30 sn sınırı aynen kalır.

- [ ] **Step 1: Test düzeneğini ve ilk başarısız testi yaz**

`test/support/voice_harness.dart` Interfaces'teki gibi. Testler `testWidgets` ile yazılır (zamanlayıcılar `tester.pump(süre)` ile ilerler, `tester.runAsync` yalnız `app.load()` içindir). Ortak açılış yardımcıları test dosyasında:

```dart
Future<VoiceCaptureController> start(WidgetTester tester, VoiceHarness h, FakeSpeechEngine e, {bool accessible = false}) async {
  final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('tr', 'TR')])
    ..accessible = accessible;
  unawaited(c.open());
  await tester.pump(VoiceTimings.startDelay);
  await tester.pump();
  return c;
}
int starts(FakeSpeechEngine e) => e.calls.where((c) => c.startsWith('start:')).length;

testWidgets('açılış: hazırlık, yerel ayar, izin, sonra Started ile dinleme', (tester) async {
  final h = await VoiceHarness.create(tester);
  final e = FakeSpeechEngine();
  final c = VoiceCaptureController(app: h.app, engine: e, deviceLocales: () => const [Locale('tr', 'TR')]);
  unawaited(c.open());
  expect(c.phase, VoicePhase.preparing);
  await tester.pump(VoiceTimings.startDelay);
  await tester.pump();
  expect(e.calls, ['resolve', 'prepare:tr-TR', 'start:tr-TR']);
  expect((c.phase, c.localeId), (VoicePhase.listening, 'tr-TR'));
  await c.close();
  await h.dispose(tester);
});
```

Run: `flutter test test/voice_capture_controller_test.dart`
Expected: derleme hatası (`VoiceCaptureController` tanımsız).

- [ ] **Step 2: Açılışı uygula, testi geçir**

Run: `flutter test test/voice_capture_controller_test.dart`
Expected: 1 test geçer.

- [ ] **Step 3: Ana akış testi ve uygulaması**

```dart
testWidgets('söyle → 1,6 sn → önizleme → 2 sn → kayıt → yeniden dinle → 6 sn → kapan', (tester) async {
  final h = await VoiceHarness.create(tester);
  final e = FakeSpeechEngine();
  final c = await start(tester, h, e);
  e.say('yarın akşam yedide annemi ara');
  await tester.pump();
  expect(c.transcript, 'yarın akşam yedide annemi ara');
  expect((c.preview!.title, c.preview!.due), ('Annemi ara', DateTime(2026, 11, 24, 19)));
  await tester.pump(const Duration(milliseconds: 1599));
  expect(c.phase, VoicePhase.listening);
  await tester.pump(const Duration(milliseconds: 1));
  expect(e.calls.last, 'stop');
  expect(c.phase, VoicePhase.preview);
  expect(h.app.tasks, isEmpty);
  await tester.pump(VoiceTimings.previewHold);
  final t = h.app.tasks.single;
  expect((t.title, t.due, t.hasTime, t.remindAt), ('Annemi ara', DateTime(2026, 11, 24, 19), true, DateTime(2026, 11, 24, 19)));
  expect((c.saved.single.id, c.saved.single.reminder, c.saved.single.inBackground), (t.id, true, false));
  await tester.pump();
  expect((starts(e), c.phase), (2, VoicePhase.listening));
  await tester.pump(VoiceTimings.idleClose);
  expect(c.phase, VoicePhase.closed);
  expect(e.listening, isFalse);
  await h.dispose(tester);
});

testWidgets('ilk dinlemede sessizlik ekranı kapatmaz; 30 sn sonra duraklar', (tester) async {
  // start; pump(6 sn) → listening; pump(24 sn) → paused, e.listening false; tasks boş
});
```

Run: `flutter test test/voice_capture_controller_test.dart`
Expected: 3 test geçer.

- [ ] **Step 4: Düzelt, kapat, geri al, not**

```dart
testWidgets('Düzelt geri sayımı durdurur; taslak kaydedilir ve yeniden dinlenir', (tester) async {
  // say('yarın 10 toplantı'); pump(1600ms); c.edit(); pump(5 sn) → tasks boş, phase editing
  // c.updateDraft('yarın 10:30 toplantı'); expect(c.preview!.due, DateTime(2026, 11, 24, 10, 30));
  // await c.saveNow(); tasks.single.due == 2026-11-24 10:30; pump(); starts == 2
});
testWidgets('kapatma önizlemedeki görevi kaydetmez', (tester) async {
  // say; pump(1600ms); await c.close(); pump(5 sn) → tasks boş; phase closed
});
testWidgets('geri al kaydı siler', (tester) async {
  // kayıt sonrası c.undo(c.saved.single) → tasks boş, saved boş
});
testWidgets('"not al süt bitmiş" not olur; geri al notu siler', (tester) async {
  // notes.first.body == 'Süt bitmiş'; tasks boş; saved.single.isNote; undo → notes boş
});
```

Run: `flutter test test/voice_capture_controller_test.dart` — Expected: 7 test geçer.

- [ ] **Step 5: Durumlar ve hatalar**

```dart
testWidgets('motor yoksa platform desteklenmiyor; eklenti çağrılmaz', ...);   // FakeSpeechEngine(supported: false) → calls boş
testWidgets('dil yoksa unsupportedLocale', ...);                              // deviceLocales: [Locale('de','DE')]
testWidgets('izin reddi permissionDenied; start çağrılmaz', ...);             // availability: permissionDenied
testWidgets('dikte kapalı hatası dictationOff', ...);                         // e.fail(SpeechErrorKind.dictationDisabled)
testWidgets('noMatch hata sayılmaz', ...);                                    // e.fail(noMatch, permanent: false) → phase error değil
testWidgets('ağ hatası error; toggleMic yeniden dinler', ...);                // e.fail(network) → error; c.toggleMic(); pump → starts == 2
testWidgets('kesinti duraklatır', ...);                                       // e.fail(interrupted) → paused
testWidgets('toggleMic dinlerken durdurur ve söyleneni önizler', ...);
```

Run: `flutter test test/voice_capture_controller_test.dart` — Expected: 15 test geçer.

- [ ] **Step 6: Arka plan kuralları**

```dart
testWidgets('arka plan: metin yokken mikrofon kapanır, kayıt yok', (tester) async {
  // c.onLifecycle(AppLifecycleState.hidden) → e.calls.last == 'cancel'; phase paused; tasks boş
  // c.onLifecycle(AppLifecycleState.resumed); pump(10 sn) → starts == 1 (mikrofon kendiliğinden açılmaz)
});
testWidgets('arka plan: bitmemiş konuşma kaydedilir ve diske yazılır', (tester) async {
  // say('yarın 10 toplantı'); pump(500ms); hidden → tasks.single.title == 'Toplantı';
  // saved.single.inBackground; await tester.pump(); h.store.data['tasks'] contains 'Toplantı'
});
testWidgets('arka plan: önizleme hemen kaydedilir', ...);
testWidgets('arka plan: düzeltme taslağı kaydedilmez ve yerinde kalır', ...);   // phase editing, transcript aynı
testWidgets('inactive oturumu kesmez', ...);                                     // onLifecycle(inactive) → listening, cancel yok
testWidgets('5 dakikadan uzun arka plan dönüşte kapatır; taslak varsa kapatmaz', (tester) async {
  // hidden; h.now = h.now.add(const Duration(minutes: 6)); resumed → closed
  // aynı senaryo editing evresinde → editing kalır
});
testWidgets('arka planda bildirim izni sorulmaz', ...);                          // scheduler.permissionRequests == 0
```

Run: `flutter test test/voice_capture_controller_test.dart` — Expected: 22 test geçer.

- [ ] **Step 7: Bildirim izni ve günlük**

```dart
testWidgets('bildirim izni saatli ilk görevde, mikrofon kapalıyken, bir kez sorulur', (tester) async {
  var micOnAtRequest = true;
  h.scheduler.onRequest = () => micOnAtRequest = e.listening;
  // iki saatli görev kaydet → h.scheduler.permissionRequests == 1; micOnAtRequest == false
});
testWidgets('saatsiz görev izin sormaz', ...);
testWidgets('günlük yalnız ayar açıkken yazılır', ...);   // kapalı → voiceLog boş; keepVoiceLog: true → voiceLog.single.transcript, localeId 'tr-TR'
```

Run: `flutter test test/voice_capture_controller_test.dart` — Expected: 25 test geçer.

- [ ] **Step 8: Erişilebilir gezinme (uyum §4.2-3)**

```dart
testWidgets('VoiceOver açıkken: geri sayım yok, kendiliğinden kapanma yok, yeniden dinleme yok', (tester) async {
  final c = await start(tester, h, e, accessible: true);
  e.say('yarın 10 toplantı');
  await tester.pump(VoiceTimings.utteranceGap);
  expect(c.phase, VoicePhase.preview);
  await tester.pump(const Duration(seconds: 30));
  expect((c.phase, h.app.tasks.length), (VoicePhase.preview, 0));
  await c.saveNow();
  await tester.pump(const Duration(seconds: 30));
  expect((c.phase, h.app.tasks.length, starts(e)), (VoicePhase.saved, 1, 1));
  c.toggleMic();
  await tester.pump();
  expect(starts(e), 2);
});
```

Run: `flutter test test/voice_capture_controller_test.dart` — Expected: 26 test geçer.

- [ ] **Step 9: Review Focus 1, 2 ve 4 testleri**

```dart
testWidgets('RF1: Final gelmeden Stopped — son ara metin bir kez kaydedilir', (tester) async {
  e.finalOnStop = false;
  // say('süt al'); pump(1600ms) → preview; pump(2 sn) → tasks.single.title == 'Süt al'
});
testWidgets('RF1: geç gelen Final yeni oturumu bozmaz ve çift kayıt yapmaz', (tester) async {
  // bir görev kaydedildi, yeniden dinleniyor; e.sendFinal('süt al'); pump(5 sn) → tasks.length == 1; phase listening
});
testWidgets('RF2: boş ve dolgu metin kaydedilmez, hata göstermez', (tester) async {
  // say('Bir görev ekle.'); pump(1600ms); pump(2 sn) → tasks boş; phase error değil
});
testWidgets('RF4: izin beklenirken kapatılırsa mikrofon hiç açılmaz', (tester) async {
  final e = FakeSpeechEngine()..prepareGate = Completer<void>();
  // open; pump(startDelay); await c.close(); e.prepareGate!.complete(); pump(1 sn) → starts == 0; e.listening false
});
testWidgets('RF4: başka yerden silinmiş görevi geri almak hata vermez', (tester) async {
  // kayıt; h.app.deleteTask(c.saved.single.id); c.undo(c.saved.single) → istisna yok; saved boş
});
testWidgets('kapatıldıktan sonra hiçbir zamanlayıcı ya da olay durumu değiştirmez', (tester) async {
  // close; e.say('x'); pump(40 sn) → phase closed; tasks boş
});
```

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer (bu dosyada 32).

- [ ] **Step 10: Commit**

```bash
git add lib/ui/voice/voice_capture_controller.dart test/support/voice_harness.dart test/voice_capture_controller_test.dart
git commit -m "Sesle ekleme: dinleme durum makinesi, zamanlamalar ve arka plan kuralları" -m "<iki satır>"
```

---

### Task 8: `VoiceCapturePage` — ekran ve erişilebilirlik

**Files:**
- Create: `lib/ui/voice/voice_capture_page.dart`
- Test: `test/voice_capture_page_test.dart`

**Interfaces:**
- Consumes: `VoiceCaptureController`, `VoicePhase`, `VoiceTimings`, `SavedItem` (Görev 7); `VoiceHarness` (Görev 7); `S` getter'ları, `openAppSettings` (Görev 1); `reduceMotionOf` ve yeni tema renkleri (Görev 11); `formatWhen`, `hhmm`; `SoftChip`, `SoftCard`, `ContentWidth`.
- Produces:

```dart
class VoiceCapturePage extends StatefulWidget {
  const VoiceCapturePage({super.key, this.engine});   // null → AppScope.of(context).speech
  static bool get isOpen;
  /// Kök navigatörde tam ekran açar (MaterialPageRoute(fullscreenDialog: true)).
  /// Zaten açıksa hiçbir şey yapmaz. Kapanınca kayıt varsa özet snack'i gösterir.
  static Future<void> open(BuildContext context);
}
```

Test anahtarları (`Key('…')`): `voice-close`, `voice-mic`, `voice-status`, `voice-transcript`, `voice-preview`, `voice-fix`, `voice-save`, `voice-draft`, `voice-countdown`, `voice-open-settings`, `voice-saved-<id>`, `voice-undo-<id>`.

Düzen ve davranış (tasarım §5 taslağı, §6.6; uyum §4.1 "Kayıt göstergesi" ve "Ekranın erişilebilirliği"; ui-ux-pro-max):

- `Scaffold` + `SafeArea`; gövde tek bir kaydırılabilir sütun (`SingleChildScrollView` içinde `ContentWidth(maxWidth: 560)`), yatayda ve metin ölçeği 2,0'da taşmaz. Üstte solda kapat düğmesi (`Icons.close_rounded`, tooltip `s.close`, her evrede görünür), sağda başlık `s.voiceTitle`. `PopScope` geri hareketini `controller.close()` ile aynı yola bağlar.
- Mikrofon düğmesi: 88 pt daire, `primary` zemin, `onPrimary` ikon (`Icons.mic_rounded`; mikrofon kapalıyken `Icons.mic_none_rounded`), etiket dinlerken `s.voiceStopListening`, değilken `s.voiceStartListening`. Çevresindeki halka ses düzeyiyle 1,0–1,15 arası ölçeklenir (yalnız bu öğe canlanır, 120 ms `easeOut`). `reduceMotionOf` doğruysa halka durağandır ve düzey, düğmenin altında 5 basamaklı durağan çubukla gösterilir.
- Durum satırı (`voice-status`): ikon + yazı. Evre → metin: `preparing` `s.voicePreparing`; `listening` `s.voiceListening`; `preview` yok (önizleme kartı konuşur); `saved` `s.voiceSaved`; `paused` `s.voicePaused` + alt satır `s.voiceTapToContinue`; `error` `s.voiceErrorGeneric` + `s.voiceRetry` düğmesi; `permissionDenied` `s.voicePermissionDenied` + tek düğme `s.openSettings` (`openAppSettings()`); `dictationOff` `s.voiceDictationOff`; `unsupportedLocale` `s.voiceUnsupportedLocale`; `unsupportedPlatform` `s.voiceUnsupportedPlatform`. Hata türleri `errorContainer`/`onErrorContainer` kartında. Satır `Semantics(liveRegion: true)` taşır ve **yalnız evre değişince** değişir; canlı metin (`voice-transcript`) canlı bölge değildir (VoiceOver'ın sesi mikrofona girer).
- Canlı metin: `onSurface`, `titleLarge`. Önizleme (`voice-preview`): çipler `[event gün] [schedule saat] [notifications]` + başlık. Gün çipi `formatWhen(s, due, now: app.now(), withTime: false)`; saat çipi `hhmm(due)`, `ambiguousHour` ise sonuna ` ?`; zil çipi `hasTime || (remind && due != null)` ise; `isNote` ise yalnız `s.voiceNoteChip` çipi (`Icons.sticky_note_2_outlined`); tarihsizse `s.someday`, tarihsiz + `remind` ise `s.voiceUndatedRemindHint`. Kart tek anlamlı öğedir: `Semantics(label: …)` + `ExcludeSemantics`; etiket biçimi "Annemi ara, Yarın 19:00, hatırlatma açık"; belirsiz saatte sona ", saat tahmini" eklenir ("?" okunmaz).
- `preview` evresi: `s.voiceFix` düğmesi + geri sayım (`voice-countdown`): `LinearProgressIndicator` ve yanında sayı (`s.voiceCountdown(n)`). Çubuk `Semantics(value:)` taşımaz ve her saniye duyuru yapmaz. `controller.accessible` ise geri sayım yerine `s.save` (`voice-save`, `FilledButton`) ve `s.voiceFix` yan yana.
- `editing` evresi: `TextField` (`voice-draft`, `autofocus`, ipucu `s.voiceDraftHint`), altında canlı önizleme ve `s.save` düğmesi.
- "Eklenenler" (`s.voiceAdded`): her kayıt bir satır — onay ikonu, başlık, `· formatWhen(...)` ya da `s.someday`; `inBackground` ise alt satırda `s.voiceSavedOnLock`; sağda geri al düğmesi (`Icons.undo_rounded`, tooltip `s.voiceUndoItem(title)`).
- Sayfa `controller.accessible = MediaQuery.accessibleNavigationOf(context)` değerini her derlemede iletir; `AppLifecycleListener` ile `controller.onLifecycle` çağırır; açılışta `controller.open(lifecycle: WidgetsBinding.instance.lifecycleState)`; evre `closed` olunca kendini kapatır.
- Dokunsal: `onSaved` → `HapticFeedback.lightImpact()` (o anda mikrofon kapalı).
- Özet: `open` dönmeden önce kayıt sayısı > 0 ise `ScaffoldMessenger` (itmeden önce alınır) ile `SnackBar(content: Text(s.voiceSummary(n)))`.

- [ ] **Step 1: Test düzeneği ve ilk başarısız test**

```dart
Future<FakeSpeechEngine> pumpPage(WidgetTester tester, VoiceHarness h, {FakeSpeechEngine? engine,
    Size size = const Size(390, 844), double textScale = 1, ThemeData? theme, bool accessibleNavigation = false}) async {
  // tester.view.physicalSize = size; devicePixelRatio = 1; addTearDown(tester.view.reset)
  // AppScope(controller: h.app, child: MaterialApp(locale: const Locale('tr'), supportedLocales, delegates,
  //   theme: theme ?? PamnotTheme.light(),
  //   builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale),
  //       accessibleNavigation: accessibleNavigation), child: child!),
  //   home: VoiceCapturePage(engine: e)))
  // pump(VoiceTimings.startDelay); pump();
}

testWidgets('açılınca dinler: ikon + "Dinliyorum…" ve kapat düğmesi görünür', (tester) async {
  final h = await VoiceHarness.create(tester);
  final e = await pumpPage(tester, h);
  expect(find.text('Dinliyorum…'), findsOneWidget);
  expect(find.byKey(const Key('voice-close')), findsOneWidget);
  expect(find.byTooltip('Dinlemeyi durdur'), findsOneWidget);
  expect(e.listening, isTrue);
});
```

Run: `flutter test test/voice_capture_page_test.dart`
Expected: derleme hatası (`VoiceCapturePage` tanımsız).

- [ ] **Step 2: İskeleti ve dinleme evresini uygula; testi geçir**

- [ ] **Step 3: Akış testleri ve geri kalan evreler**

```dart
testWidgets('canlı metin, önizleme çipleri, geri sayım, kayıt, Eklenenler', (tester) async {
  e.say('yarın akşam yedide annemi ara'); await tester.pump();
  expect(find.text('yarın akşam yedide annemi ara'), findsOneWidget);
  expect(find.text('Yarın'), findsOneWidget); expect(find.text('19:00'), findsOneWidget);
  await tester.pump(VoiceTimings.utteranceGap);
  expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
  expect(find.text('Düzelt'), findsOneWidget);
  expect(find.text('Dinliyorum…'), findsNothing);             // mikrofon kapalıyken yazı kalmaz
  await tester.pump(VoiceTimings.previewHold); await tester.pump();
  expect(find.text('Eklenenler'), findsOneWidget);
  expect(find.byTooltip('Annemi ara görevini geri al'), findsOneWidget);
});
testWidgets('belirsiz saat "?" ile gösterilir ve "saat tahmini" diye okunur', (tester) async {
  // say("saat 3'te dişçi") → find.text('15:00 ?'); find.bySemanticsLabel(RegExp('saat tahmini'))
});
testWidgets('önizleme tek öğe olarak okunur', (tester) async {
  // find.bySemanticsLabel('Annemi ara, Yarın 19:00, hatırlatma açık') findsOneWidget
});
testWidgets('Düzelt: metin alanı, canlı önizleme, Kaydet', (tester) async {
  // tap voice-fix → voice-draft; enterText('yarın 10:30 toplantı'); find.text('10:30 ?'); tap voice-save → tasks.single
});
testWidgets('kapat önizlemedeki görevi kaydetmez; sayfa kapanır', (tester) async { ... });
testWidgets('izin yok: yazı + tek "Ayarlar’ı Aç" düğmesi app-settings: açar', (tester) async {
  // openExternal sahtesi; FakeSpeechEngine(availability: permissionDenied);
  // tap voice-open-settings → opened.single.toString() == 'app-settings:'; mikrofon düğmesi izin istemeyi yeniden tetiklemez
});
testWidgets('dikte kapalı, dil yok, platform yok metinleri', (tester) async { ... });
testWidgets('tarihsiz hatırlatma ipucu', (tester) async {
  // say('annemi aramayı hatırlat') → find.text('Tarihsiz · hatırlatma için gün söyle')
});
testWidgets('kilitlenirken kaydedilen satır notuyla görünür', (tester) async {
  // say; tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); resumed; pump
  // find.text('Kilitlenirken kaydedildi'); find.text('Duraklatıldı'); find.text('Devam etmek için dokun')
});
testWidgets('kapanınca özet snack\'i çıkar', (tester) async {
  // home: Builder + düğme → VoiceCapturePage.open(context); bir görev kaydet; kapat → find.text('1 kayıt eklendi')
});
testWidgets('açıkken ikinci open ikinci sayfa açmaz', (tester) async {
  // open iki kez → find.byType(VoiceCapturePage) findsOneWidget; kapandıktan sonra VoiceCapturePage.isOpen false
});
```

Run: `flutter test test/voice_capture_page_test.dart` — Expected: hepsi geçer.

- [ ] **Step 4: Erişilebilir gezinme**

```dart
testWidgets('VoiceOver açıkken geri sayım yerine Kaydet ve Düzelt görünür; kendiliğinden kaydetmez', (tester) async {
  // pumpPage(accessibleNavigation: true); say; pump(utteranceGap)
  // voice-countdown findsNothing; voice-save ve voice-fix findsOneWidget; pump(10 sn) → tasks boş
});
testWidgets('durum satırı canlı bölgedir, canlı metin değildir', (tester) async {
  // tester.getSemantics(find.byKey(Key('voice-status'))) → flag isLiveRegion; transcript → değil
});
testWidgets('geri sayım çubuğu değer duyurmaz', (tester) async {
  // tester.getSemantics(find.byKey(Key('voice-countdown'))).value isEmpty
});
```

- [ ] **Step 5: Yönergeler — hedef boyutu, etiket, kontrast (açık ve koyu)**

```dart
for (final (name, theme) in [('açık', PamnotTheme.light()), ('koyu', PamnotTheme.dark())]) {
  testWidgets('yönergeler: $name tema, önizleme ve Eklenenler görünürken', (tester) async {
    final handle = tester.ensureSemantics();
    // bir görev kaydet, ikinciyi önizlemede bırak
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
```

Not: `textContrastGuideline` açık temada Görev 11'in renklerine bağlıdır (eski `primary` metin olarak 3,47:1 idi); bu yüzden bu görev Görev 11 birleştikten sonra başlar.

- [ ] **Step 6: Düzen — büyük metin, dar ekran, yatay, Hareketi Azalt**

```dart
testWidgets('metin ölçeği 2,0 ve 375×667: taşma yok', (tester) async {
  // pumpPage(size: Size(375, 667), textScale: 2); bir görev kaydet, ikinciyi önizlet; expect(tester.takeException(), isNull)
});
testWidgets('yatay 667×375: taşma yok, kapat düğmesi görünür', ...);
testWidgets('Hareketi Azalt açıkken halka ölçeklenmez, düzey çubuğu görünür', (tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  // e.level(1); pump(200ms) → Key('voice-ring') boyutu değişmedi; Key('voice-level-bar') findsOneWidget
});
```

- [ ] **Step 7: Review Focus 5 — çok uzun konuşma**

```dart
testWidgets('RF5: 600 karakterlik ve satır sonlu metin taşmaz, başlık kesilmeden kaydedilir', (tester) async {
  final long = List.filled(100, 'kelime').join(' ');            // 699 karakter
  // pumpPage(size: Size(375, 667)); e.say(long); pump → takeException isNull
  // e.say('satır bir\nsatır iki'); pump(utteranceGap + previewHold) → takeException isNull
  // uzun metinle kayıt: h.app.tasks.single.title.length == long.length (ilk harf büyük)
});
```

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/voice/voice_capture_page.dart test/voice_capture_page_test.dart
git commit -m "Sesle ekleme: tam ekran dinleme ekranı, önizleme, düzeltme ve erişilebilirlik" -m "<iki satır>"
```

---

### Task 9: Giriş noktaları — köprü, bağlantı, HomeShell, mikrofon düğmesi

**Files:**
- Create: `lib/services/launch_actions.dart`
- Modify: `lib/main.dart:16-35`, `lib/app.dart:20-44`, `lib/ui/home_shell.dart:14-52`, `lib/ui/tasks/task_editor.dart:295-356`
- Test: `test/launch_actions_test.dart`, `test/voice_entry_test.dart`

**Interfaces:**
- Consumes: `VoiceCapturePage.open`, `VoiceCapturePage.isOpen` (Görev 8); `createSpeechEngine()` (Görev 3); kanal `app.pamnot/launch` (Görev 5); `AppController.speech` (Görev 1).
- Produces:

```dart
// lib/services/launch_actions.dart
/// Sesle ekle ekranını açma isteği (kestirme, bağlantı, mikrofon düğmesi). HomeShell tüketip false yapar.
final voiceRequests = ValueNotifier<bool>(false);
abstract final class LaunchActionsBridge {
  static void start();          // yalnız iOS'ta (web değil): işleyiciyi kurar, sonra pull()
  static Future<void> pull();   // takePendingAction → 'voice' ise voiceRequests.value = true
}
// QuickAddField: yapıcı imzası değişmez.
```

Davranış (tasarım §6.2, §6.7):

- `main()`: `runApp`'ten **önce** `LaunchActionsBridge.start()`; `AppController(..., speech: createSpeechEngine())`.
- `_PamnotAppState`: `AppLifecycleListener.onResume` içinde ayrıca `unawaited(LaunchActionsBridge.pull())`. `didPushRouteInformation`: şema `pamnot` değilse `false`; `pamnot` ise sunucu adı `ses` ya da `voice` olduğunda `voiceRequests.value = true`, her durumda `true` döner (Flutter rota eklemez; sorgu parametreleri okunmaz).
- `HomeShell`: `notificationTaps` ile aynı kalıp — `initState`'te dinleyici + ilk kare sonrası denetim. İstek gelince bayrağı `false` yapar; `VoiceCapturePage.isOpen` ise yok sayar; değilse `VoiceCapturePage.open(context)`. `notificationTaps` yolu değişmez.
- `QuickAddField`: `suffixIcon` bir `Row(mainAxisSize: MainAxisSize.min)` olur: `widget.app.speech.isSupported` ise mikrofon düğmesi (`Icons.mic_none_rounded`, tooltip `s.voiceMicTooltip`, `onPressed: () => voiceRequests.value = true`), ardından mevcut gönder düğmesi (tooltip `s.add` eklenir). `_submit` ve `addQuickTask` çağrısı değişmez. Düğmeyi göstermek izin istemez ve eklentiyi çağırmaz.

- [ ] **Step 1: Köprü testleri (başarısız)** — `test/launch_actions_test.dart`

`TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app.pamnot/launch'), …)` ile yerel taraf taklit edilir; her testte `voiceRequests.value = false` ve `debugDefaultTargetPlatformOverride` sıfırlanır.

```dart
test('iOS: start bekleyen "voice" eylemini çeker', () async { /* handler 'voice' döner → voiceRequests.value true; çağrılar ['takePendingAction'] */ });
test('bekleyen eylem yoksa istek oluşmaz', ...);                 // null → false
test('bilinmeyen eylem yok sayılır', ...);                       // 'reminders' → false
test('actionAvailable gelince yeniden çeker', () async {
  // start (null döner); handler artık 'voice' döner; yerelden Dart'a:
  // binding.defaultBinaryMessenger.handlePlatformMessage('app.pamnot/launch',
  //   const StandardMethodCodec().encodeMethodCall(const MethodCall('actionAvailable')), (_) {});
  // → voiceRequests.value true
});
test('eklenti kayıtlı değilse sessizce geçer', ...);             // handler yok → istisna yok
test('iOS dışında kanal hiç çağrılmaz', ...);                    // android override → çağrı listesi boş
```

Run: `flutter test test/launch_actions_test.dart` — Expected: derleme hatası.

- [ ] **Step 2: `launch_actions.dart`'ı uygula, geçir** (başvuru: `…-reference/launch_actions.dart.txt`)

- [ ] **Step 3: Giriş testleri (başarısız)** — `test/voice_entry_test.dart`

Kurulum `test/app_smoke_test.dart:19-40`'taki `boot`/`shutdown` gibi, `AppController(..., speech: FakeSpeechEngine())` ile; rota mesajı `…-reference/deeplink_probe_test.dart.txt`'teki `push` yardımcısıyla gönderilir.

```dart
testWidgets('pamnot://ses ekranı açar; ikinci HomeShell eklenmez', (tester) async {
  await push(tester, 'pamnot://ses');
  expect(find.byType(VoiceCapturePage), findsOneWidget);
  expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
  expect(voiceRequests.value, isFalse);
});
testWidgets('pamnot://voice de açar; başka pamnot:// bağlantıları rota eklemez ve hata vermez', (tester) async {
  await push(tester, 'pamnot://x?y=1'); await push(tester, 'pamnot://today?homeWidget');
  expect(tester.takeException(), isNull);
  expect(find.byType(VoiceCapturePage), findsNothing);
  expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
});
testWidgets('bağlantıdaki metin görev yazmaz', (tester) async {
  final before = c.tasks.length;
  await push(tester, 'pamnot://ses?text=yar%C4%B1n%2010%20toplant%C4%B1');
  await tester.pump(const Duration(seconds: 10));
  expect(c.tasks.length, before);
});
testWidgets('RF4: ekran açıkken gelen ikinci istek yok sayılır', (tester) async {
  await push(tester, 'pamnot://ses'); await push(tester, 'pamnot://ses');
  voiceRequests.value = true; await tester.pump();
  expect(find.byType(VoiceCapturePage), findsOneWidget);
  expect(voiceRequests.value, isFalse);
});
testWidgets('HomeShell kurulmadan önce gelen istek ilk kareden sonra açılır', (tester) async {
  voiceRequests.value = true;   // boot'tan önce
  // boot → VoiceCapturePage findsOneWidget
});
testWidgets('mikrofon düğmesi yalnız motor destekliyorsa görünür ve ekranı açar', (tester) async {
  // FakeSpeechEngine(): find.byTooltip('Sesle görev ekle') findsOneWidget; tap → VoiceCapturePage
  // UnsupportedSpeechEngine (varsayılan): findsNothing
});
testWidgets('mikrofon düğmesini göstermek motoru çağırmaz', (tester) async {
  // boot sonrası engine.calls isEmpty
});
testWidgets('yazarak hızlı ekleme değişmedi', (tester) async {
  // "yarın 10:00 toplantı" yaz, gönder → görev 28 Ekim 10:00, remindAt null; snack '✓ Toplantı · Yarın 10:00'
});
testWidgets('bildirim dokunuşu yolu değişmedi', (tester) async {
  // notificationTaps.value = 'r:x'; pump → Anımsatıcılar sekmesi; VoiceCapturePage yok
});
```

Her test sonunda açık ekran kapatılır ve `shutdown` çağrılır (bekleyen zamanlayıcı kalmaz).

Run: `flutter test test/voice_entry_test.dart` — Expected: başarısız (ekran açılmaz, ikinci HomeShell eklenir).

- [ ] **Step 4: `app.dart`, `home_shell.dart`, `main.dart`, `task_editor.dart` değişikliklerini uygula** (başvuru: `…-reference/app_dart.diff.txt`)

- [ ] **Step 5: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer (`test/app_smoke_test.dart` dahil, değişmeden).

- [ ] **Step 6: Commit**

```bash
git add lib/services/launch_actions.dart lib/main.dart lib/app.dart lib/ui/home_shell.dart lib/ui/tasks/task_editor.dart \
  test/launch_actions_test.dart test/voice_entry_test.dart
git commit -m "Sesle ekleme: kestirme köprüsü, pamnot://ses, HomeShell ve hızlı eklemede mikrofon düğmesi" -m "<iki satır>"
```

---

### Task 10: Ayarlar — Sesle ekleme, bildirim durumu, Hakkında

**Files:**
- Create: `lib/ui/settings/voice_settings.dart`
- Modify: `lib/ui/settings/settings_page.dart:94-142`
- Test: `test/settings_page_test.dart`

**Interfaces:**
- Consumes: `AppController.speech`, `voiceLog`, `clearVoiceLog`, `notificationAccess`, `requestNotifications`, `NotificationAccess` (Görev 4); `AppSettings.keepVoiceLog`; `openExternal`, `openAppSettings`, `privacyPolicyUrl`, `supportUrl`; `S` getter'ları (Görev 1).
- Produces: `class VoiceSettingsGroup extends StatelessWidget { const VoiceSettingsGroup({super.key, required this.app}); }` — yalnız `settings_page.dart` kullanır.

Kapsam (tasarım §6.7; uyum §2.2, §2.4-A, §3.5, §4.2-2, §4.2-4, §5.4):

- **Sesle ekleme** grubu (`s.voiceSettings`), "Plan" grubundan sonra, yalnız `app.speech.isSupported` ise. Sırayla: `s.voiceSetupReady` (ikon `Icons.bolt_outlined`); `s.voiceSiriHint`; iki `ExpansionTile`: `s.voiceBackTapTitle` → `s.voiceBackTapSteps`, `s.voiceVoiceControlTitle` → `s.voiceVoiceControlSteps`; `SwitchListTile` `s.voiceKeepLog` / `s.voiceKeepLogSub` (varsayılan kapalı); anahtar açıkken `s.voiceRecent` başlığı, sağında `TextButton(s.voiceClearLog)`, altında kayıtlar (ham metin; alt satırda ayrıştırma: başlık · `formatWhen` ya da `s.someday`; not ise `s.voiceNoteChip`) ya da `s.voiceRecentEmpty`; en altta `s.voicePrivacyNote` (`bodySmall`, `onSurfaceVariant`). Eylem düğmesi için adım adım yönerge **yazılmaz**.
- **Bildirimler** grubu: ilk satır duruma göre (`app.notificationAccess()`; sayfa açılınca ve uygulama `resumed` olunca yenilenir): `notAsked` → `s.notificationsAllow`, dokununca `app.requestNotifications()`; `denied` → `s.notificationsDenied`, sonunda `Icons.open_in_new_rounded`, dokununca `openAppSettings()`; `granted` → `s.notificationsOn`, başında `Icons.check_circle_outline_rounded`, dokunulamaz. "Deneme bildirimi gönder" satırı kalır; `app.scheduler.requestPermission()` yerine `app.requestNotifications()`.
- **Apple Pencil ve kalem** grubu: `_ModelTiles`'ın altında (yalnız `app.handwriting.isSupported` ise) `s.handwritingPrivacyNote`.
- **Hakkında** grubu: mevcut satır (süs emojisi `ExcludeSemantics` içine); `s.dataNote`; `ListTile(s.privacyPolicy)` ve `ListTile(s.support)` — sonunda `Icons.open_in_new_rounded`, `openExternal(Uri.parse(...))`; `ListTile(s.licenses)` → `showLicensePage(context: context, applicationName: 'Pamnot')`.

- [ ] **Step 1: Başarısız testleri yaz** — `test/settings_page_test.dart`

Kurulum: `VoiceHarness` benzeri denetleyici (`speech:` parametresiyle), `AppScope` + `MaterialApp(locale: Locale('tr'), home: SettingsPage())`; `openExternal` sahtesi açılan adresleri toplar.

```dart
testWidgets('Sesle ekleme grubu yalnız motor destekliyorsa görünür', ...);
testWidgets('kurulum yardımı: hazır satırı ve Siri ipucu var; Eylem düğmesi adımları ve "Yan tuş" yok', (tester) async {
  expect(find.text(S.tr.voiceSetupReady), findsOneWidget);
  expect(find.text(S.tr.voiceSiriHint), findsOneWidget);
  expect(find.textContaining('Yan tuş'), findsNothing);
  expect(find.textContaining('Ayarlar > Eylem'), findsNothing);
  await tester.tap(find.text('Arkaya Dokunma')); await tester.pumpAndSettle();
  expect(find.text(S.tr.voiceBackTapSteps), findsOneWidget);
});
testWidgets('günlük anahtarı varsayılan kapalı; açınca Son tanınanlar; Temizle siler; kapatınca silinir', (tester) async {
  expect(find.text('Son tanınanlar'), findsNothing);
  // anahtarı aç → app.settings.keepVoiceLog true; app.logRecognized('yarın onda toplantı', …); pump
  // find.text('yarın onda toplantı'); tap 'Temizle' → find.text('Henüz kayıt yok.')
  // yeniden kayıt ekle; anahtarı kapat → app.voiceLog isEmpty; 'Son tanınanlar' findsNothing
});
testWidgets('gizlilik notu görünür', ...);                       // S.tr.voicePrivacyNote
testWidgets('bildirim satırı: sorulmadı → izin ister', (tester) async {
  // tap 'Bildirimlere izin ver' → scheduler.permissionRequests == 1; pumpAndSettle → 'Bildirimler açık'
});
testWidgets('bildirim satırı: reddedildi → Ayarlar\'ı açar', (tester) async {
  // settings notificationsAsked: true, scheduler.granted false → 'Bildirimler kapalı — Ayarlar’ı aç'; tap → 'app-settings:'
});
testWidgets('Hakkında: gizlilik ve destek bağlantıları, lisans sayfası', (tester) async {
  // tap 'Gizlilik Politikası' → opened.last.toString() == privacyPolicyUrl; 'Destek' → supportUrl
  // tap 'Açık kaynak lisansları' → find.byType(LicensePage)
});
testWidgets('el yazısı notu yalnız el yazısı destekleniyorsa', ...);
testWidgets('yönergeler: hedef boyutu, etiket, kontrast', (tester) async {
  // ensureSemantics; iOSTapTargetGuideline, labeledTapTargetGuideline (kontrast Görev 12'de tüm sayfalar için)
});
testWidgets('metin ölçeği 2,0 ve 375×667: taşma yok', ...);
```

Run: `flutter test test/settings_page_test.dart` — Expected: başarısız (`Sesle ekleme` bulunamaz).

- [ ] **Step 2: Uygula** — yukarıdaki kapsamla. Grup yardımcıları `settings_page.dart:21-30`'daki `group` kalıbını kullanır.

- [ ] **Step 3: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/settings/voice_settings.dart lib/ui/settings/settings_page.dart test/settings_page_test.dart
git commit -m "Ayarlar: Sesle ekleme bölümü, bildirim izni durumu, gizlilik politikası ve lisans bağlantıları" -m "<iki satır>"
```

---

### Task 11: Örnek veri, kontrast, hareket yardımcıları

**Files:**
- Modify: `lib/state/sample_data.dart:17-137`
- Modify: `lib/theme/pamnot_theme.dart:28-118`, `:160`
- Modify: `lib/ui/common/soft.dart` (dosya sonuna yardımcılar)
- Modify: `test/controller_test.dart:34-42`, `:96-105`; `test/app_smoke_test.dart:52-54`
- Test: `test/theme_contrast_test.dart`, `test/sample_data_test.dart`

**Interfaces:**
- Consumes: yok.
- Produces:

```dart
// lib/theme/pamnot_theme.dart
/// Pastel vurgu dolgusu üstündeki onay işareti (iki temada da aynı; en düşük çift lavanta 3,68:1).
const inkOnPastel = Color(0xFF3E3A4A);

// lib/ui/common/soft.dart
bool reduceMotionOf(BuildContext context);   // MediaQuery.disableAnimationsOf(context) ||
                                             // View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion
Duration motion(BuildContext context, Duration d);              // reduceMotionOf ? Duration.zero : d
Curve motionCurve(BuildContext context, Curve c);               // reduceMotionOf ? Curves.easeOut : c
```

(`MediaQuery.disableAnimations` iOS'un "Hareketi Azalt" ayarını yansıtmaz; Flutter 3.47.8 belgesi bunu açıkça söyler. Uyum belgesi §3.2'deki tek satırlık öneri bu yüzden iki kaynağı birlikte okur.)

Renk değişiklikleri (uyum §3.1; oranlar WCAG formülüyle hesaplandı):

| Belirteç | Eski | Yeni | Oran |
| --- | --- | --- | --- |
| açık `primary` | `0xFF8A78CF` | `0xFF6F5CBF` | beyazla 5,30; `surface` üstünde 4,96 |
| açık `onSurfaceVariant` | `0xFF7A7488` | `0xFF6A6478` | `surface` 5,30; `surfaceContainer` 5,08 |
| açık `error` | `0xFFD9707A` | `0xFFB9434F` | 4,94 |
| açık `tertiary` | `0xFF6DB59C` | `0xFF3F8F74` | beyaz onayla 3,89 |
| açık `outline` | `0xFFD5CFDF` | `0xFF8E879C` | 3,22 |
| koyu `outline` | `0xFF524C5E` | `0xFF7E7790` | 3,95 |
| ipucu metni (`:160`) | `onSurfaceVariant` %80 | `onSurfaceVariant` (saydamlık yok) | 5,08 |

Örnek veri (uyum §2.6): `SampleData.build` imzası aynı kalır; yalnız karşılama notu döner (`tasks`, `reminders`, `habits` boş; "Alışveriş listesi" ve "Hafta sonu fikirleri" notları da kalkar). Karşılama notundaki widget maddesi yalnız Android'de (`!kIsWeb && defaultTargetPlatform == TargetPlatform.android`) kalır. Sona sesle ekleme maddesi eklenmez (özellik yalnız iOS'ta; not her platformda aynı kalsın).

- [ ] **Step 1: Başarısız testleri yaz**

`test/theme_contrast_test.dart`:

```dart
double contrast(Color a, Color b) { /* WCAG 2.x göreli parlaklık; (L1 + 0.05) / (L2 + 0.05) */ }

for (final (name, t) in [('açık', PamnotTheme.light()), ('koyu', PamnotTheme.dark())]) {
  final c = t.colorScheme;
  test('$name tema: metin çiftleri en az 4,5:1', () {
    for (final (fg, bg) in [
      (c.onSurface, c.surface), (c.onSurfaceVariant, c.surface), (c.onSurfaceVariant, c.surfaceContainer),
      (c.onSurfaceVariant, c.surfaceContainerLow), (c.onSurfaceVariant, c.surfaceContainerLowest),
      (c.primary, c.surface), (c.primary, c.surfaceContainerLowest), (c.onPrimary, c.primary),
      (c.error, c.surface), (c.error, c.surfaceContainerLowest),
      (c.onPrimaryContainer, c.primaryContainer), (c.onErrorContainer, c.errorContainer),
      (c.onInverseSurface, c.inverseSurface),
    ]) { expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg / $bg'); }
  });
  test('$name tema: ikon ve kenar çiftleri en az 3:1', () {
    expect(contrast(c.onTertiary, c.tertiary), greaterThanOrEqualTo(3));
    expect(contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
    for (final p in pastels) { expect(contrast(inkOnPastel, p.accent), greaterThanOrEqualTo(3), reason: p.name); }
  });
  test('$name tema: ipucu metni saydam değil', () {
    expect(t.inputDecorationTheme.hintStyle!.color, c.onSurfaceVariant);
  });
}
```

`test/sample_data_test.dart`:

```dart
test('ilk açılış yalnız karşılama notunu getirir', () {
  final d = SampleData.build(S.tr, DateTime(2026, 11, 23, 9), () => 'id');
  expect(d.notes.length, 1);
  expect(d.notes.single.title, startsWith('Pamnot’a hoş geldin'));
  expect((d.tasks, d.reminders, d.habits), (isEmpty, isEmpty, isEmpty));
});
test('widget maddesi iOS\'ta yok, Android\'de var', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  expect(SampleData.build(S.tr, DateTime(2026), () => 'id').notes.single.body, isNot(contains('widget')));
  expect(SampleData.build(S.en, DateTime(2026), () => 'id').notes.single.body, isNot(contains('widget')));
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  expect(SampleData.build(S.tr, DateTime(2026), () => 'id').notes.single.body, contains('widget'));
});
test('ilk açılışta zamanlanacak uyarı yok', () async {
  // yeni AppController(MemoryStore) + load → c.alerts() isEmpty
});
```

`test/soft_motion_test.dart` gerekmez; `motion`/`motionCurve` testi `test/theme_contrast_test.dart` sonuna eklenir:

```dart
testWidgets('motion: Hareketi Azalt açıkken süre sıfır, eğri easeOut', (tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  late Duration d; late Curve k;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    d = motion(c, const Duration(milliseconds: 220)); k = motionCurve(c, Curves.easeOutBack);
    return const SizedBox();
  })));
  expect((d, k), (Duration.zero, Curves.easeOut));
});
```

Run: `flutter test test/theme_contrast_test.dart test/sample_data_test.dart`
Expected: başarısız (açık tema `onSurfaceVariant / surface` 4,20 < 4,5; `tasks` boş değil).

- [ ] **Step 2: Uygula** — renk tablosu, `inkOnPastel`, yardımcılar, `SampleData.build`.

- [ ] **Step 3: Örnek veriye dayanan üç mevcut testi güncelle**

- `test/controller_test.dart` "first launch seeds a friendly workspace and saves it": `expect(c.tasks, isNotEmpty)` → `expect(c.tasks, isEmpty)`; `c.notes` hâlâ `isNotEmpty`; kalan satırlar aynı.
- `test/controller_test.dart` "agenda orders timed entries before all-day ones": `fresh` sonrası testin kendisi iki görev ekler (`c.addQuickTask('bugün 10:00 sunum')`, `c.addQuickTask('bugün annemi ara')`); `entries` hâlâ `isNotEmpty`.
- `test/app_smoke_test.dart:54`: `find.text('Alışveriş listesi')` → `find.textContaining('hoş geldin')` (`findsOneWidget`).

- [ ] **Step 4: Geçtiğini gör**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer.

- [ ] **Step 5: Commit**

```bash
git add lib/state/sample_data.dart lib/theme/pamnot_theme.dart lib/ui/common/soft.dart \
  test/theme_contrast_test.dart test/sample_data_test.dart test/controller_test.dart test/app_smoke_test.dart
git commit -m "App Store: yalnız karşılama notu, 4,5:1 kontrast, Hareketi Azalt yardımcıları" -m "<iki satır>"
```

---

### Task 12: Erişilebilirlik taraması — hedef, etiket, hareket, büyük metin, dokunsal

**Files:**
- Modify: `lib/ui/common/soft.dart:126-166` (`PastelPicker`)
- Modify: `lib/ui/tasks/task_tile.dart:11-51`, `:66-99`
- Modify: `lib/ui/tasks/habits_view.dart:136-162`, `:251-265`
- Modify: `lib/ui/notes/ink/ink_toolbar.dart:142-200`
- Modify: `lib/ui/planner/planner_page.dart:76`, `:93`, `:300-345`
- Modify: `lib/ui/tasks/task_editor.dart:253-260`
- Modify: `lib/ui/notes/notes_page.dart:55-61`
- Modify: `lib/ui/notes/note_editor_page.dart:153-160`
- Modify: `lib/ui/home_shell.dart` (`NavigationBar` sarmalayıcı, `_Logo` emojisi)
- Modify: `lib/ui/today/today_page.dart:89-90`, `:168-170`
- Modify: `lib/app.dart` (`MaterialApp.builder`)
- Modify: `lib/theme/pamnot_theme.dart` (`bolder`)
- Test: `test/accessibility_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf`, `motion`, `motionCurve`, `inkOnPastel` (Görev 11); `S.colorName`, `S.previous`, `S.next`, `S.removeSubtask`, `S.clearSearch`, `S.overdueLabel`, `S.inkColor`, `S.strokeWidth`, `S.handwritingDownload*` (Görev 1).
- Produces: `static ThemeData PamnotTheme.bolder(ThemeData t)` — her metin stilinde 400→600, 600→700, 700→800 (800 aynı kalır).

Değişiklikler (uyum §3.2, §3.3, §3.6, §3.7, §3.8, §5.3):

| Yer | Değişiklik |
| --- | --- |
| `PastelPicker` | Her renk 44×44 pt dokunma alanı (görsel 34 pt kalır); etiket `s.colorName(i)`; `motion(...)`. |
| `SoftCheck` | Yeni zorunlu olmayan `String? label`; `Semantics(label:, checked:, button: true)`; dokunma alanı ≥ 44 pt; onay ikonu `inkOnPastel`; `motion`/`motionCurve`. `TaskTile` `label: task.title` verir. Dokununca `HapticFeedback.lightImpact()`. |
| `TaskTile` | Gecikmiş görevde tarih yanında `Icons.error_outline_rounded` ve metnin başında `s.overdueLabel` (yalnız renk değil). `Dismissible` satırı `Semantics(customSemanticsActions: {CustomSemanticsAction(label: s.delete): sil})` taşır; silmede `HapticFeedback.mediumImpact()`. |
| Alışkanlık gün halkası | 44×44 pt alan; `Semantics(button: true, checked: done, label: DateFormat('EEEE d MMMM', s.locale).format(day), enabled: !future)`; onay `inkOnPastel`; `motion`/`motionCurve`. |
| Emoji seçici | `Semantics(button: true, selected: e == _emoji, label: e)`; `motion`. |
| Mürekkep rengi / kalınlık | 44×44 pt alan; `Semantics(button: true, selected:, label: s.inkColor(n) / s.strokeWidth(n))` (n 1'den başlar); `motion`. |
| Plan gün hücresi | `Semantics(button: true, selected: isSel, label: DateFormat('EEEE d MMMM', s.locale).format(day))`; `motion`. Önceki/sonraki düğmelerine `tooltip: s.previous` / `s.next`. |
| `task_editor.dart:253`, `notes_page.dart:55` | `tooltip: s.removeSubtask` / `s.clearSearch`; alt görev düğmesinden `visualDensity: compact` kaldırılır (44 pt). |
| `home_shell.dart` `_Logo` | Emoji `ExcludeSemantics` içine. `NavigationBar` `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: …)` ile sarılır. |
| `today_page.dart` | `:90` `SizedBox(height: 196)` ve `:169-170` 74 pt halka: metin ölçeğiyle büyüyen yükseklik (`MediaQuery.textScalerOf(context).scale(…)` ya da `ConstrainedBox(minHeight:)`). |
| `app.dart` | `builder: (context, child) => MediaQuery.boldTextOf(context) ? Theme(data: PamnotTheme.bolder(Theme.of(context)), child: child!) : child!`. |
| `note_editor_page.dart:154-159` | Model hazır değilse indirmeden önce `AlertDialog`: başlık `s.handwritingDownloadTitle`, gövde `s.handwritingDownloadBody`, düğmeler `s.cancel` / `s.download`. Vazgeçilirse indirme ve tanıma yapılmaz. |

- [ ] **Step 1: Başarısız testleri yaz** — `test/accessibility_test.dart`

Kurulum: `boot` (`test/app_smoke_test.dart` kalıbı, `Size` ve `textScale` parametreli); örnek veri artık boş olduğundan test içeriği kendisi ekler: 3 görev (biri gecikmiş: `due` dün), 1 alışkanlık, 1 anımsatıcı, 2 not (biri sabitlenmiş).

```dart
for (final (name, mode) in [('açık', ThemeMode.light), ('koyu', ThemeMode.dark)]) {
  testWidgets('beş sekme yönergeleri karşılar: $name tema', (tester) async {
    final handle = tester.ensureSemantics();
    for (final tab in ['Bugün', 'Notlar', 'Takip', 'Plan', 'Hatırlatma']) {
      await tester.tap(find.text(tab).last); await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: tab);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: tab);
      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: tab);
    }
    handle.dispose();
  });
}
testWidgets('Takip > Alışkanlıklar ve alışkanlık düzenleyici yönergeleri karşılar', ...);
testWidgets('görev düzenleyici ve renk seçici yönergeleri karşılar', (tester) async {
  // find.bySemanticsLabel('lavanta') findsOneWidget; 'lavender' findsNothing (TR arayüz)
});
testWidgets('el yazısı araç çubuğu: renk ve kalınlık etiketli ve 44 pt', ...);   // 1366×1024, kalem modu
testWidgets('onay halkası görev başlığıyla okunur', (tester) async {
  // tester.getSemantics(find.byType(SoftCheck).first).label == 'Raporu bitir'
});
testWidgets('gecikmiş görev renk dışında ikon ve yazıyla da belli', (tester) async {
  // find.textContaining('Gecikti') findsOneWidget; find.byIcon(Icons.error_outline_rounded) findsOneWidget
});
testWidgets('kaydırarak silmenin VoiceOver eylemi var', (tester) async {
  // görev satırının SemanticsNode'unda 'Sil' etiketli customSemanticsAction
});
testWidgets('plan gün hücresi tam tarihi ve seçili durumunu okur', (tester) async {
  // find.bySemanticsLabel(RegExp('Salı 27 Ekim')) ; selected bayrağı
});
testWidgets('süs emojileri okunmaz', (tester) async {
  // 1366×1024 (ray, logo görünür): find.bySemanticsLabel('☁️') findsNothing
});
testWidgets('Hareketi Azalt: onay halkası sıçramaz', (tester) async {
  // accessibilityFeaturesTestValue reduceMotion; görevi işaretle; tek pump() sonrası
  // tester.widget<AnimatedContainer>(…).duration == Duration.zero
});
testWidgets('metin ölçeği 2,0 ve 375×667: beş sekmede taşma yok', (tester) async {
  // her sekmede expect(tester.takeException(), isNull)
});
testWidgets('alt çubuk etiketi 1,3 ölçekle sınırlı', (tester) async {
  // textScale 2,0 → NavigationBar altındaki MediaQuery.textScalerOf(...).scale(10) <= 13
});
testWidgets('Kalın Metin açıkken gövde ağırlığı artar', (tester) async {
  // MediaQuery boldText: true ile PamnotApp → Theme.of(ctx).textTheme.bodyMedium!.fontWeight == FontWeight.w600
});
testWidgets('görev tamamlama ve silme dokunsal geri bildirim verir', (tester) async {
  // SystemChannels.platform sahte işleyici: 'HapticFeedback.vibrate' çağrıları
  // işaretle → 'HapticFeedbackType.lightImpact'; kaydırıp sil → 'HapticFeedbackType.mediumImpact'
});
testWidgets('el yazısı modeli boyut söylenip sorulmadan inmez', (tester) async {
  // isSupported true, isModelReady false dönen sahte HandwritingRecognizer; "Yazıya çevir" →
  // find.text('El yazısı modeli indirilsin mi?'); find.text('Yaklaşık 20 MB.'); 'Vazgeç' → prepare çağrılmadı
  // yeniden; 'İndir' → prepare bir kez çağrıldı
});
```

Run: `flutter test test/accessibility_test.dart`
Expected: başarısız (ilk hata `iOSTapTargetGuideline`: 34 pt hedefler).

- [ ] **Step 2: Tablodaki değişiklikleri dosya dosya uygula; her dosyadan sonra testi çalıştır**

Run: `flutter test test/accessibility_test.dart`
Expected: son dosyadan sonra hepsi geçer. Bir yönerge testi tabloda olmayan bir denetimi gösterirse aynı kuralla (44 pt alan, `Semantics` etiketi ya da `tooltip`) onu da düzelt ve commit mesajında an.

- [ ] **Step 3: Tümünü doğrula**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; tüm testler geçer (`test/voice_capture_page_test.dart` ve `test/settings_page_test.dart` dahil).

- [ ] **Step 4: Commit**

```bash
git add lib test/accessibility_test.dart
git commit -m "Erişilebilirlik: 44 pt hedefler, VoiceOver etiketleri, Hareketi Azalt, büyük ve kalın metin, dokunsal" -m "<iki satır>"
```

---

### Task 13: CI korumaları ve belgeler

**Files:**
- Modify: `.github/workflows/build.yml:32-34` (checks), `:109-119` (ios)
- Modify: `TESTING.md`, `README.md`, `ios/PamnotWidget/README.md:17-21`
- Create: `PRIVACY.md`, `tool/ci/check_docs.py`

**Interfaces:**
- Consumes: `tool/ios/check_ios_config.py` (Görev 5), `tool/ios/check_launch_assets.py` (Görev 6); `privacyPolicyUrl` (Görev 1) `PRIVACY.md` dosyasını gösterir.
- Produces: yok.

- [ ] **Step 1: Başarısız denetimi yaz** — `tool/ci/check_docs.py` (standart kitaplık; `PyYAML` varsa iş akışını da ayrıştırır, yoksa metin araması yapar)

1. `.github/workflows/build.yml`: `checks` işinde `python3 tool/ios/check_ios_config.py` ve `python3 tool/ios/check_launch_assets.py` adımları; `ios` işinde `flutter build ios` adımından **önce** `plutil -lint`, **sonra** `extract.actionsdata` ve `PrivacyInfo.xcprivacy` denetimleri.
2. `PRIVACY.md` var; hem "Gizlilik Politikası" hem "Privacy Policy" başlığı; "Apple", "Google ML Kit", "20" (son 20 metin) geçer; iletişim satırı var.
3. `TESTING.md`: "Sesle görev ekleme" ve "Yayın" başlıkları var; "Yan tuş" geçmez.
4. `ios/PamnotWidget/README.md`: "FlutterDeepLinkingEnabled" ve "pamnot://ses" geçer.

Run: `python3 tool/ci/check_docs.py`
Expected: sıfırdan farklı kod.

- [ ] **Step 2: İş akışını güncelle**

`checks` işine, `flutter test` adımından sonra:

```yaml
      - name: iOS ayar ve varlık denetimleri
        run: |
          python3 tool/ios/check_ios_config.py
          python3 tool/ios/check_launch_assets.py
```

`ios` işinde, `flutter build ios` adımından önce:

```yaml
      - name: Plist ve metin dosyalarını denetle
        run: |
          plutil -lint ios/Runner.xcodeproj/project.pbxproj ios/Runner/Info.plist \
            ios/Runner/PrivacyInfo.xcprivacy ios/Runner/*.lproj/*.strings
```

`flutter build ios` adımından sonra:

```yaml
      # Kestirme sessizce kaybolmasın: App Intents meta verisi çıkarılmış olmalı.
      - name: Kestirme ve gizlilik bildirimi derlemede var mı
        run: |
          f=$(find build/ios -name extract.actionsdata | head -1)
          test -n "$f" && grep -q VoiceTaskIntent "$f"
          test -f build/ios/iphoneos/Runner.app/PrivacyInfo.xcprivacy
```

Widget tür denetimi adımı aynen kalır.

- [ ] **Step 3: Belgeleri yaz** (Türkçe; `PRIVACY.md` TR + EN)

- `PRIVACY.md` (uyum §5.2, seçenek A): veriler cihazda, sunucu yok; sesle ekleme (ses Apple'ın konuşma tanımasına gidebilir, Pamnot ses kaydı saklamaz, "Tanınan metinleri sakla" açıksa son 20 metin cihazda tutulur ve Ayarlar'dan silinir); Google ML Kit (el yazısı cihazda işlenir; Google'a kişisel olmayan kullanım/performans ölçümleri gider; `https://policies.google.com/privacy` bağlantısı); bildirimler yerel; silme (uygulamayı silmek tüm veriyi siler; izinler iOS Ayarlar'dan geri alınır); iletişim: `https://github.com/Bannercheck/Pamnot/issues`.
- `TESTING.md` — "Neyi denemeli" altına **Sesle görev ekleme (iPhone)** listesi: Kestirmeler'de "Sesle Görev Ekle" görünüyor mu; Eylem düğmesine atanınca ekran açılıp dinliyor mu; Arkaya Dokunma (önce tek eylemli kestirme) çalışıyor mu; `pamnot://ses` Safari'den ekranı açıyor mu ve ikinci ana ekran açılmıyor mu; "yarın akşam yedide annemi ara" → Yarın 19:00 + zil; "saat üçte dişçi" → 15:00 ?; Düzelt; ✕ önizlemede kaydetmiyor; söyleyip telefonu kilitleyince görev kaydediliyor ve dönüşte "Kilitlenirken kaydedildi" görünüyor, mikrofon kendiliğinden açılmıyor; izin reddedilince "Ayarlar'ı Aç"; Dikte kapalıyken yönlendirme; VoiceOver açıkken geri sayım yok; Ayarlar > Sesle ekleme > "Tanınan metinleri sakla" açılıp birkaç gerçek örnek toplanıyor (saatlerin nasıl yazıldığı). Not: `main`'e birleştirmeden önce bu liste cihazda geçilir. Ayrıca yeni **Yayın (App Store)** bölümü: uyum §5.6'daki altı adım ve "Xcode > Product > Archive > Generate Privacy Report ile ML Kit bildirimlerini doğrula".
- `README.md`: özellik tablosuna "Sesle ekleme" satırı; `flutter test` yanındaki test sayısını gerçek sayıyla güncelle; "Veriler yalnızca cihazda saklanır." cümlesini `PRIVACY.md` bağlantısıyla değiştir.
- `ios/PamnotWidget/README.md:17-21`: "`pamnot` şeması artık `pamnot://ses` için kayıtlı (`CFBundleURLTypes`); widget bağlantıları yine `?homeWidget` ile `home_widget` tarafından sahiplenilir. `FlutterDeepLinkingEnabled = false` bilerek ayarlandı: açık olursa sahiplenilmeyen `pamnot://` bağlantısı ikinci bir ana ekran açar."

- [ ] **Step 4: Geçtiğini gör**

Run: `python3 tool/ci/check_docs.py && python3 tool/ios/check_ios_config.py && python3 tool/ios/check_launch_assets.py && flutter analyze && flutter test`
Expected: üç betik `ok` yazar; `No issues found!`; tüm testler geçer.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/build.yml TESTING.md README.md PRIVACY.md ios/PamnotWidget/README.md tool/ci/check_docs.py
git commit -m "CI korumaları, gizlilik politikası ve cihazda deneme listesi [full-build]" -m "<iki satır>"
```

---

## Not in this plan

Kod dışı ya da başka platform; ürün sahibinin işi ya da ayrı plan.

App Store Connect ve imzalama (uyum §2.5, §2.8, §2.9, §5)

- Apple Developer Program üyeliği, Team seçimi, `CODE_SIGN_ENTITLEMENTS`/`DEVELOPMENT_TEAM`, App Group kaydı, widget hedefinin Xcode'da kurulması.
- Arşivin Xcode 26 / iOS 26 SDK ile alınması ve yüklenmesi; Privacy Report ile ML Kit çatılarının kendi bildirimlerinin doğrulanması (bu makinede doğrulanamadı).
- App Privacy yanıtları (seçenek A eşlemesi), yaş anketi, kategori, ad/alt başlık, ekran görüntüleri, telif, destek ve gizlilik URL alanları, inceleme notu (uyum §5.5 taslağı hazır), AB tacir beyanı, Erişilebilirlik Etiketleri.
- Gizlilik politikasının herkese açık bir adreste yayımlanması: uygulama `PRIVACY.md`'nin GitHub adresine bağlanır; depo özel ise ya da GitHub Pages tercih edilirse `lib/services/links.dart` içindeki iki sabit değiştirilir.
- ML Kit'i ilk mağaza sürümünden çıkarma (seçenek B). Bu plan seçenek A'yı uygular (özellik kalır, beyan ve uygulama içi not eklenir).

Bu sürümde yapılmayan kalite maddeleri

- `highContrastTheme` / `highContrastDarkTheme` (yeni renkler 4,5:1'i zaten sağlıyor).
- Katmanlı Icon Composer simgesi, koyu/tek renk simge varyantları; macOS, Android ve web simgelerinin yenilenmesi.
- `CupertinoDatePicker`, `SwitchListTile.adaptive`, dinleme başı/sonu sistem sesi.
- iOS 26+ için `supportedModes`'a geçiş; en düşük sürümü iOS 17'ye çıkarıp kısa başlık ve simgeli kestirme.
- Yazarak hızlı eklemeyi yeni ayrıştırıcıya geçirmek; arka planda çalışan eylem; Denetim Merkezi düğmesi; bir cümlede birden çok görev.

iPad ve Mac (uyum §5.7, §5.8; tasarım §11)

- iPad: ses ekranı için yatay özel düzen, pencereli modda 320 pt genişlik testi, ⌘ kısayol listesi, Apple Pencil üzerine gelme ve çift dokunma.
- Mac: `com.apple.security.device.audio-input`, iki izin metni, URL şeması, App Intents eylemi, `LSApplicationCategoryType`, menü çubuğu, Mac App Store.
- Android: ses özelliği, `intent-filter`.

## Self-review

- **Kapsam:** Tasarım §6.1 → Görev 5; §6.2 → 9; §6.3 → 1, 3; §6.4 → 2; §6.5 → 4; §6.6 → 7, 8; §6.7 → 9, 10; §6.8 → 1, 5; §6.9 → 13; §7 test planındaki her satır 2, 4, 7, 8, 9'da adıyla var. Uyum §2.1 → 6; §2.2 → 1, 10, 13; §2.3 → 5, 6; §2.4-A → 1, 10, 13; §2.6 → 11; §2.7 → 5; §3.1 → 6, 11; §3.2 → 8, 11, 12; §3.3 → 12; §3.4 → 6; §3.5 → 4, 10; §3.6 → 12; §3.7 → 12; §3.8 (dokunsal, lisans, Yayın bölümü) → 10, 12, 13; §4.1 → 5, 7, 8; §4.2-1 → 5; §4.2-2 → 1, 10; §4.2-3 → 7, 8; §4.2-4 → 4, 10; §4.3 → 5, 13. §2.5, §2.8, §2.9, §5 → "Not in this plan".
- **Tür tutarlılığı:** `SpokenTask`, `SpeechEngine`, `FakeSpeechEngine`, `VoicePhase`, `SavedItem`, `voiceRequests` (bool), `NotificationAccess`, `reduceMotionOf` adları tanımlandıkları görevle kullanıldıkları görevlerde aynı. `reduceMotionOf` yalnız `soft.dart`'ta tanımlıdır (Görev 11); Görev 8 ve 12 onu kullanır.
- **Review Focus:** beş satırın her birinin testi sahibi görevde, adı "RF" ile başlıyor.
