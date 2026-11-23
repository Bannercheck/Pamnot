# App Store uyumluluk denetimi — Pamnot

Tarih: 2026-11-23 · Dal: `claude/voice-capture` · Kapsam: uygulamanın bu daldaki tamamı (iOS/iPadOS öncelikli)
ve onaylı "Sesle görev ekleme" tasarımı (`2026-11-23-voice-task-capture-design.md`).

Bu belge yalnız denetimdir; kod değiştirilmedi. Her madde bir dosyaya ya da ayara bağlanır.

**Kesinlik işaretleri**

- **[Apple]** Apple'ın kendi belgesinde yazıyor (bağlantı verildi, 2026-11-23'te okundu).
- **[Depo]** Bu depoda ya da `~/.pub-cache` içinde dosyadan doğrulandı.
- **[Google]** Google'ın ML Kit belgesinde yazıyor.
- **[Yorum]** Kuralın bu uygulamaya uygulanması benim çıkarımım; Apple'ın metni bunu birebir söylemiyor.
- **[Bellek]** Kaynağı bu oturumda açıp doğrulayamadım; App Store Connect'te kontrol edilmeli.

---

## 1. Özet

Pamnot bugünkü haliyle App Store'a **gönderilemez**; ama engellerin hiçbiri mimari değil, hepsi birkaç günlük iş.

- Yükleme aşamasında takılacak ya da incelemede reddedilecek **9 madde** var (§2). En görünenleri: uygulama
  simgesi hâlâ Flutter'ın varsayılan logosu, uygulamada ve projede gizlilik politikası bağlantısı yok, uygulamanın
  kendi `PrivacyInfo.xcprivacy` dosyası yok, ücretsiz Apple ID ile mağazaya gönderim yapılamıyor.
- "Veri toplanmıyor" beyanı bugünkü kodla **doğru olmaz**: Google ML Kit (el yazısı tanıma) Google'a kullanım
  ölçümü gönderiyor. Ya bu beyan edilir ya da ML Kit ilk mağaza sürümünden çıkarılır (§2.4).
- Kalite tarafında (§3) en önemli açıklar: açık temada birkaç renk çiftinin kontrastı 4,5:1'in altında,
  "Hareketi Azalt" hiç okunmuyor, bazı dokunma hedefleri 44 pt'ten küçük ve VoiceOver etiketsiz, açılış ekranı
  koyu modda beyaz parlıyor, ilk açılışta sahte görev/alışkanlık geçmişi geliyor.
- Onaylı ses tasarımı kurallarla büyük ölçüde uyumlu. **Dört küçük değişiklik** gerekiyor (§4.2): İngilizce eylem
  adı, Eylem Düğmesi kurulum yardımı, VoiceOver açıkken geri sayım, "Son tanınanlar" günlüğünün açık rızası.
- İyi olanlar: arka plan modu yok, izinler bağlam içinde isteniyor, iPad dört yönü ve çoklu görevi destekliyor,
  UIScene yaşam döngüsü kullanılıyor, veriler cihazda, hesap/giriş yok, reklam ve izleme yok.

---

## 2. Gönderimi engeller (must fix)

### 2.1 Uygulama simgesi Flutter'ın varsayılan logosu

- **Kural:** Guideline 2.1(a) "placeholder text, empty websites, and other temporary content should be scrubbed
  before submission"; 2.3.8 simge ve meta veri tutarlı olmalı. **[Apple]**
  https://developer.apple.com/app-store/review/guidelines/ · Simge biçimi: HIG App icons
  https://developer.apple.com/design/human-interface-guidelines/app-icons
- **Durum:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` Flutter logosu (görsel
  olarak doğrulandı). Aynı klasördeki 14 küçük boyut da şablondan. **[Depo]** Flutter logosu Google'ın markası;
  bu ayrıca 5.2.1 (başkasının markası) riskidir. **[Yorum]**
- **Düzeltme:**
  1. Pamnot simgesi tasarlanır (uygulama içindeki bulut işareti ve `lib/ui/home_shell.dart:152` gradyanı
     `#C9BCF5 → #FBC9B4` başlangıç noktası). 1024×1024 px, sRGB, **alfa kanalı yok**, köşeler yuvarlatılmaz
     (sistem maskeler), içinde yazı yok.
  2. En az iş: `AppIcon.appiconset` içindeki 15 PNG aynı adlarla değiştirilir; `Contents.json` aynen kalır.
  3. Daha iyi (iOS 26 görünümü): Xcode 26 ile gelen Icon Composer'da katmanlı `.icon` dosyası; koyu ve tek renk
     varyantları oradan gelir. Zorunlu değil. **[Apple]** HIG: "you can provide icons in one of two formats:
     nonlayered bitmap images (such as PNG) or layered Icon Composer files".
  4. `macos/Runner/Assets.xcassets/AppIcon.appiconset`, `android/app/src/main/res/mipmap-*` ve `web/icons`
     aynı tasarımla güncellenir (mağaza reddi sebebi değil, tutarlılık).

### 2.2 Gizlilik politikası yok (uygulamada ve App Store Connect'te)

- **Kural:** Guideline 5.1.1(i): "All apps must include a link to their privacy policy in the App Store Connect
  metadata field **and within the app** in an easily accessible manner." **[Apple]**
- **Durum:** `lib/` içinde hiçbir URL yok (`grep -rn "https\?://" lib` boş). Ayarlar > Hakkında yalnız
  `aboutText` gösteriyor (`lib/ui/settings/settings_page.dart:130-136`, `lib/l10n/strings.dart:185`). **[Depo]**
- **Düzeltme:**
  1. Herkese açık bir sayfa yayımlanır (ör. GitHub Pages; TR ve EN). İçerik §5.2'de.
  2. `pubspec.yaml`'a `url_launcher` eklenir (kendi gizlilik bildirimiyle gelir; önbellekteki
     `url_launcher_ios-6.4.2/.../PrivacyInfo.xcprivacy` **[Depo]**).
  3. `settings_page.dart` "Hakkında" grubuna iki satır: **Gizlilik Politikası** (`S.privacyPolicy`:
     "Gizlilik Politikası" / "Privacy Policy") ve **Destek** ("Destek" / "Support"). `Icons.open_in_new_rounded`
     ile dış bağlantı olduğu gösterilir.
  4. Aynı gruba kısa bir veri notu (bkz. §2.4): `aboutText` bugünkü haliyle ML Kit ve ses tanıma eklenince
     eksik kalıyor.

### 2.3 Uygulamanın kendi gizlilik bildirimi (`PrivacyInfo.xcprivacy`) yok

- **Kural:** "Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy
  manifest file aren't accepted by App Store Connect." Her çalıştırılabilir dosyayı içeren paket kendi
  bildirimini taşır. **[Apple]**
  https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api ·
  neden kodları:
  https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- **Durum:** `ios/` altında `PrivacyInfo.xcprivacy` yok (`find ios -name PrivacyInfo.xcprivacy` boş). **[Depo]**

  Bağımlılıkların durumu **[Depo]**:

  | Bileşen | Kendi bildirimi | Neden gerektiren API |
  | --- | --- | --- |
  | Flutter motoru (`Flutter.xcframework`) | Var: FileTimestamp `0A2A.1`, `C617.1`; SystemBootTime `35F9.1` | Dart'ın dosya işlemleri burada |
  | `flutter_local_notifications` 22.3.3 | Var: UserDefaults `CA92.1` | `NSUserDefaults standardUserDefaults` |
  | `flutter_timezone` 5.1.1 | Var (boş) | Yok |
  | `shared_preferences_foundation` 2.5.7 | Var: UserDefaults `1C8F.1` | iOS'ta Pamnot bunu çağırmıyor (`lib/data/store_web.dart` yalnız web) |
  | `path_provider_foundation` 2.6.0 | Yok; yerel kodu da yok (FFI) | Yok |
  | **`home_widget` 0.10.0** | **Yok** | `UserDefaults(suiteName:)` — `HomeWidgetPlugin.swift:109,139,218` |
  | `google_mlkit_*` eklenti sarmalayıcıları | Yok | Sarmalayıcıda yok |
  | ML Kit ikili çatıları (`GoogleMLKit` 9.0.0 → `MLKitCommon` 14, `MLKitDigitalInkRecognition` 8) | Google sürüm notlarına göre var ("added description of use of required reason APIs in the privacy manifest files") **[Google]**; bu makinede pod indirilemediği için dosya görülmedi | — |
  | `speech_to_text` 7.5.0 (eklenecek) | Yok | Kaynağında yok (`SpeechToTextPlugin.swift` tarandı) |
  | `ios/PamnotWidget` (hedef eklenince) | Yok | `UserDefaults(suiteName:)` — `PamnotTodayWidget.swift:189` |

  `home_widget` kendi bildirimini taşımadığı için uygulama grubundaki `UserDefaults` kullanımını uygulamanın
  bildirimi açıklamalı. Apple'ın kuralı SDK'nın kendi bildirimini ister; SDK'da yoksa uygulama bildirimine
  yazmak yüklemedeki ITMS-91053 uyarısını gideren yaygın yoldur. **[Yorum]**
- **Düzeltme:** `ios/Runner/PrivacyInfo.xcprivacy` oluşturulur ve Runner hedefinin "Copy Bundle Resources"
  aşamasına eklenir (ses özelliği için yazılacak `tool/ios/add_voice_files.rb` betiğine bir satır; elle pbxproj
  düzenlenmez). İçerik:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
  	<key>NSPrivacyTracking</key>
  	<false/>
  	<key>NSPrivacyTrackingDomains</key>
  	<array/>
  	<key>NSPrivacyCollectedDataTypes</key>
  	<array/>
  	<key>NSPrivacyAccessedAPITypes</key>
  	<array>
  		<dict>
  			<key>NSPrivacyAccessedAPIType</key>
  			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
  			<key>NSPrivacyAccessedAPITypeReasons</key>
  			<array>
  				<string>CA92.1</string>
  				<string>1C8F.1</string>
  			</array>
  		</dict>
  		<dict>
  			<key>NSPrivacyAccessedAPIType</key>
  			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
  			<key>NSPrivacyAccessedAPITypeReasons</key>
  			<array>
  				<string>C617.1</string>
  			</array>
  		</dict>
  	</array>
  </dict>
  </plist>
  ```

  Neden bu kodlar **[Apple]** (tanımlar Apple'ın sayfasından):
  - `CA92.1` — yalnız uygulamanın kendisinin eriştiği user defaults (bildirim eklentisinin durumu).
  - `1C8F.1` — aynı App Group üyelerinin eriştiği user defaults (`group.app.pamnot.shared`, widget verisi).
  - `C617.1` — uygulama kabındaki dosyaların zaman damgası/boyutu/üst verisi (`lib/data/store_io.dart:28,43`
    `File.exists()`; Dart bunu `stat` ile yapar).
  - SystemBootTime ve DiskSpace **eklenmez**: Runner'ın kendi kodu kullanmıyor; motorunki motorun bildiriminde.
  - `NSPrivacyCollectedDataTypes` boş: uygulamanın kendi kodu veri toplamıyor. ML Kit'in topladığı, ML Kit'in
    bildiriminde ve App Store Connect yanıtlarında beyan edilir (§2.4).
- **Widget hedefi eklendiğinde** `ios/PamnotWidget/PrivacyInfo.xcprivacy` da gerekir (yalnız UserDefaults
  `1C8F.1`); `ios/PamnotWidget/README.md` adım 3'teki üyelik listesine eklenir.
- **Doğrulama:** Xcode > Product > Archive > Organizer'da arşive sağ tık > **Generate Privacy Report**; ML Kit
  çatılarının bildirimleri raporda görünmeli. Görünmüyorsa §2.4 seçenek B uygulanır.

### 2.4 "Veri toplanmıyor" beyanı ML Kit yüzünden yanlış olur

- **Kural:** Guideline 2.3 "all your app metadata, **including privacy information** … accurately reflect";
  5.1.1(i) gizlilik politikası üçüncü taraf SDK'ları kapsamalı; App Privacy: "You need to identify all of the
  data you **or your third-party partners** collect". **[Apple]**
  https://developer.apple.com/app-store/app-privacy-details/
- **Durum:** `pubspec.yaml:40` `google_mlkit_digital_ink_recognition` → `GoogleMLKit/DigitalInkRecognition 9.0.0`.
  Google'ın beyanı **[Google]**: mürekkep verisi cihazda işlenir ("ML Kit does not send that data and the
  resultant outputs to Google servers"), ama "The ML Kit APIs also send metrics about the performance and
  utilization of the APIs in your app to Google" ve "You are responsible for informing users of your app about
  Google's processing of ML Kit metrics data". Toplananlar: cihaz bilgisi (üretici, model, OS sürümü), bundle
  ID ve uygulama sürümü, kurulum başına tanımlayıcı, gecikme gibi performans ölçümleri, API yapılandırması,
  olay türü, hata kodları; amaç "diagnostics and usage analytics".
  https://developers.google.com/ml-kit/terms · https://developers.google.com/ml-kit/ios-data-disclosure
  Uygulamadaki metin ise "Verilerin yalnızca cihazında saklanır" (`lib/l10n/strings.dart:185`) ve README
  "Veriler yalnızca cihazda saklanır" diyor; kullanıcıya ML Kit ölçümlerinden hiç söz edilmiyor. **[Depo]**
- **Düzeltme — iki seçenek, biri seçilmeli:**
  - **A (ML Kit kalır):** App Store Connect'te §5.1'deki "A" yanıtları verilir; gizlilik politikasına ve
    Ayarlar > Apple Pencil ve kalem > el yazısı modelleri altına şu not eklenir:
    - TR: "El yazısı cihazında yazıya çevrilir; yazdıkların Google'a gönderilmez. Google ML Kit, tanıma
      modelini indirir ve Google'a kişisel olmayan kullanım ve performans ölçümleri gönderir."
    - EN: "Handwriting is converted to text on your device; what you write is not sent to Google. Google ML Kit
      downloads the recognition model and sends non-personal usage and performance metrics to Google."
  - **B (ilk mağaza sürümünde ML Kit yok):** `pubspec.yaml`'dan `google_mlkit_digital_ink_recognition` çıkarılır,
    `lib/services/handwriting_mlkit.dart` yerine `UnsupportedRecognizer` kullanılır, `ios/Podfile` içindeki
    `EXCLUDED_ARCHS`/15.5 notları sadeleşir. O zaman "Data Not Collected" doğru olur, uygulama küçülür ve
    Apple Silicon simülatör sorunu kalkar. iPad'de Scribble zaten sistemden geliyor. Sonraki adım: Apple'ın
    cihaz içi tanıması (PencilKit/Vision) ile yerel bir arka uç.
  - Öneri: mağaza beyanının sade kalması isteniyorsa **B**; özellik önemliyse **A**. İkisi de kabul edilir.
    Karar ürün sahibinin.

### 2.5 Ücretsiz Apple ID ile mağazaya gönderilemez; yetki dosyası imzaya bağlı değil

- **Kural:** App Store Connect'e yükleme ve TestFlight için Apple Developer Program üyeliği (yıllık ücretli)
  gerekir; App Groups kişisel takımda yoktur. **[Bellek]** https://developer.apple.com/programs/
- **Durum:** `ios/Runner/Runner.entitlements` App Group içeriyor ama `project.pbxproj` içinde
  `CODE_SIGN_ENTITLEMENTS` ve `DEVELOPMENT_TEAM` yok (bilerek; `ios/PamnotWidget/README.md` adım 7). Widget
  hedefi projede değil. **[Depo]**
- **Düzeltme (mağaza öncesi, kullanıcının Mac'inde):**
  1. Developer Program'a katıl; Xcode'da Team seç.
  2. App Store Connect'te `app.pamnot.pamnot` ve `app.pamnot.pamnot.PamnotWidget` kimlikleri, App Group
     `group.app.pamnot.shared`.
  3. `ios/PamnotWidget/README.md` adımlarıyla widget hedefini ekle **ya da** ilk sürümü widget'sız gönder. Widget'sız
     gönderilirse README'deki ve karşılama notundaki widget cümlesi çıkarılmalı (§2.6) ve mağaza açıklamasında
     widget anılmamalı (2.3.1: sunulmayan özelliği tanıtmak ret sebebi **[Apple]**).

### 2.6 İlk açılışta sunulmayan özellik anlatılıyor ve sahte veri geliyor

- **Kural:** 2.1(a) geçici içerik temizlenmeli; 2.3.1(a) sunulmayan özellik tanıtılmaz. **[Apple]**
- **Durum:** `lib/state/sample_data.dart:28-37` karşılama notu "Ana ekranına Pamnot widget'ını ekle" diyor;
  iOS'ta widget hedefi yok. Aynı dosya 4 örnek görev, 2 anımsatıcı ve **geçmiş günlere işlenmiş alışkanlık
  kayıtları** üretiyor (`:113,122,131`). `:89-95` "Toplantıya hazırlan" anımsatıcısı etkin ve yarın 09:30'a
  kurulu: `lib/main.dart:32` `syncAlerts()` bunu ilk açılışta zamanlar; kullanıcı sonradan bildirim izni
  verirse hiç eklemediği bir şey için bildirim alır. **[Depo]**
- **Değerlendirme:** Karşılama notu sorun değil. Sahte görev/geçmiş için ret olasılığı düşük-orta **[Yorum]**;
  sahte bildirim ise gerçek bir hata.
- **Düzeltme:** `SampleData.build` yalnız karşılama notunu bırakır; görev, anımsatıcı ve alışkanlık listeleri
  boş döner (boş durum metinleri zaten var: `noTasks`, `noReminders`, `noHabits`). Karşılama notundaki widget
  maddesi yalnız widget hedefi gönderilen sürümde kalır. `test/` içinde örnek veriye dayanan testler güncellenir.

### 2.7 `Info.plist` eksikleri

`ios/Runner/Info.plist` **[Depo]**; hepsi tek dosyada:

| Anahtar | Değer | Neden |
| --- | --- | --- |
| `ITSAppUsesNonExemptEncryption` | `<false/>` | Yoksa her yüklemede ihracat anketi çıkar ve derleme "Missing Compliance"da bekler. Pamnot kendi şifrelemesini yapmıyor; yalnız işletim sisteminin HTTPS'i (ML Kit model indirme, Apple ses tanıma) kullanılıyor, bu muaf. **[Apple]** https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations |
| `CFBundleLocalizations` | `<array><string>en</string><string>tr</string></array>` | Arayüz TR/EN ama paket yalnız `en` bildiriyor (`project.pbxproj:198-203` `knownRegions = (en, Base)`). Yoksa mağaza sayfası dili yalnız İngilizce gösterir, izin metinleri Türkçeleşmez, Ayarlar'da uygulama dili seçilemez. Tasarım §6.1 zaten ekliyor. |
| `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` | §4.1'deki metinler | Yoksa ilk çağrıda **çökme** (2.1 reddi). **[Apple]** "If this key is not present, your app will crash when it calls requestAuthorization". Tasarım §6.1 ekliyor. |
| `CFBundleURLTypes` (`pamnot`) + `FlutterDeepLinkingEnabled = false` | Tasarım §6.1 | Ses bağlantısı için. |

Bildirimler için amaç metni anahtarı **yoktur**; sistem uyarısı sabittir. `NSUserNotificationsUsageDescription`
gibi bir anahtar eklenmez. **[Apple]**
https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications

### 2.8 Derleme araçları: Xcode 26 / iOS 26 SDK

- **Kural:** "Apps uploaded to App Store Connect must be built with Xcode 26 or later using an SDK for iOS 26"
  (28 Nisan 2026'dan beri). **[Apple]** https://developer.apple.com/news/upcoming-requirements/
- **Durum:** CI `macos-latest` kullanıyor (`.github/workflows/build.yml`); kullanıcının Mac'indeki Xcode sürümü
  bilinmiyor. Dağıtım hedefi 16.0 (`project.pbxproj:365,492,544`, `ios/Podfile:2`) kurala uygun.
- **Düzeltme:** Arşiv Xcode 26+ ile alınır. `flutter build ipa --release` ile üretilen arşiv Organizer ya da
  Transporter ile yüklenir. iOS 26 SDK'sında `openAppWhenRun` kullanımdan kalkıyor (tasarım §6.1 bunu
  `@available(*, deprecated)` ile susturuyor); 2.5.1 "phase out deprecated features" gereği iOS 26+ için
  `supportedModes` yoluna geçiş §5.4'e yazıldı, ret sebebi değil. **[Yorum]**

### 2.9 App Store Connect'te zorunlu alanlar (kod dışı, bunlar olmadan "Submit" açılmaz)

Gizlilik politikası URL'si, destek URL'si, App Privacy yanıtları, yaş derecelendirme anketi, ekran görüntüleri,
telif satırı, kategori, inceleme notları ve iletişim bilgisi; AB'de dağıtım için tacir (trader) beyanı.
Tam yanıtlar §5'te.

---

## 3. Yapılmalı (HIG / kalite) — iPhone öncelikli

Sıra önem sırasıdır. Bunlar tek başına ret sebebi değildir; ama 4.0 "simple, refined" beklentisini ve
Erişilebilirlik Etiketleri'nde (§5.3) dürüstçe "destekliyor" diyebilmeyi belirler.

### 3.1 Açık temada kontrast 4,5:1'in altında

- **Kural:** HIG Accessibility: en az 4,5:1; sağlanamıyorsa en azından "Kontrastı Artır" açıkken sağlanmalı.
  **[Apple]** https://developer.apple.com/design/human-interface-guidelines/accessibility
- **Durum (hesaplandı, WCAG formülü) [Depo]** — `lib/theme/pamnot_theme.dart`:

  | Çift | Oran | Nerede |
  | --- | --- | --- |
  | `onSurfaceVariant #7A7488` / `surface #FAF7F2` | 4,20 | İkincil metinler, alt çubuk etiketleri (`:72`, `:240`) |
  | ipucu metni (`onSurfaceVariant` %80) / `surfaceContainer` | 2,88 | Tüm metin alanları (`:160`) |
  | `primary #8A78CF` metin / `surface` | 3,47 | TextButton, bağlantılar |
  | beyaz / `primary` | 3,70 | FAB, FilledButton yazısı (`:54-55`) |
  | `error #D9707A` / `surface` | 3,00 | Geciken görev tarihi (`lib/ui/tasks/task_tile.dart:72`) |
  | beyaz onay / `tertiary #6DB59C` | 2,40 | Onay kutusu (`:222-223`) |
  | beyaz onay / pastel vurgu | 1,66–2,99 | Görev ve alışkanlık halkaları (`task_tile.dart:43`, `habits_view.dart:158`) |
  | `outline #D5CFDF` / `surface` | 1,42 | Onay kutusu ve çip kenarı (metin dışı ölçüt 3:1) |
  | Widget `secondary #8C8698` / `#FBF7F2` | 3,29 | `ios/PamnotWidget/PamnotTodayWidget.swift:355` |

  Koyu tema geçiyor (en düşük metin çifti 7,18).
- **Düzeltme (pastel karakteri koruyarak):**
  - `onSurfaceVariant` → `#6A6478` (5,30:1; `surfaceContainer` üstünde 5,08). İpucu metnindeki `withValues(alpha: 0.8)` kaldırılır.
  - `primary` → `#6F5CBF` (beyazla 5,30:1; `surface` üstünde 4,96); `primaryContainer` aynı kalır.
  - `error` → `#B9434F` (4,94:1). `tertiary` (onay kutusu dolgusu) → `#3F8F74` (beyaz onay işaretiyle 3,89:1; ikon için ölçüt 3:1).
  - Pastel halkalarda beyaz onay yerine `onSurface` (`#3E3A4A`) onay işareti; dolgu aynı kalır (en düşük çift lavanta 3,68:1, en yüksek tereyağı 6,64:1; ikon ölçütü 3:1).
  - `outline` → `#8E879C` (3,22:1); yalnız etkileşimli kenarlar için.
  - Widget açık tema `secondary` → `#6A6478` (5,31:1).
  - Bu oranlar aynı WCAG formülüyle hesaplandı; bir birim testiyle kilitlenir (metin çiftleri ≥ 4,5,
    ikon ve kenar çiftleri ≥ 3).
  - Ek olarak `MediaQuery.highContrastOf(context)` doğruysa `ThemeData.highContrastTheme` /
    `highContrastDarkTheme` verilir (`lib/app.dart:52-54`).

### 3.2 "Hareketi Azalt" hiç okunmuyor

- **Kural:** HIG Accessibility: ayar açıkken "reducing automatic and repetitive animations, including zooming,
  scaling". **[Apple]**
- **Durum:** `lib/` içinde `disableAnimations` / `reduceMotion` yok. **[Depo]** `Curves.easeOutBack` ile
  sıçrayan onay halkaları (`task_tile.dart:31`, `habits_view.dart:147`) ve tüm `AnimatedContainer`lar her
  koşulda oynuyor.
- **Düzeltme:** `lib/ui/common/soft.dart` içine `Duration motion(BuildContext c, Duration d) =>
  MediaQuery.disableAnimationsOf(c) ? Duration.zero : d;` ve eğri için `Curves.easeOut` yedeği; yukarıdaki
  yerler bunu kullanır. Sayfa geçişleri Cupertino olarak kalır.

### 3.3 Küçük dokunma hedefleri ve etiketsiz denetimler (VoiceOver)

- **Kural:** HIG: iOS'ta en az 44×44 pt; arayüz VoiceOver için tanımlanmalı. **[Apple]**
- **Durum [Depo]:**

  | Yer | Sorun |
  | --- | --- |
  | `lib/ui/common/soft.dart:141-150` renk seçici | 34×34 pt; etiket İngilizce ham ad (`pastels[i].name`: "cream", "peach") |
  | `lib/ui/tasks/habits_view.dart:144-150` gün halkası | 34×34 pt; `GestureDetector`, Semantics yok (hangi gün, işaretli mi okunmaz) |
  | `lib/ui/tasks/habits_view.dart:252` emoji seçici | Semantics yok |
  | `lib/ui/notes/ink/ink_toolbar.dart:150-156` mürekkep rengi | 24–30 pt; Semantics yok |
  | `lib/ui/notes/ink/ink_toolbar.dart:181-186` kalınlık | 36×36 pt; Semantics yok |
  | `lib/ui/planner/planner_page.dart:307` gün hücresi | `GestureDetector`; "seçili" ve tam tarih okunmaz |
  | `lib/ui/tasks/task_tile.dart:22-25` onay halkası | `button + checked` var, etiket yok (görev başlığı bağlanmalı) |
  | `lib/ui/tasks/task_tile.dart:81` `Dismissible` | Kaydırarak silmenin VoiceOver karşılığı yok |
  | `lib/ui/planner/planner_page.dart:76,93`, `task_editor.dart:253,345`, `notes_page.dart:55` | `IconButton` `tooltip` yok |
  | `lib/ui/home_shell.dart:155`, `settings_page.dart:132` | Süs amaçlı ☁️ emoji okunuyor |

- **Düzeltme:** Görsel boyut aynı kalabilir; her biri en az 44×44 pt'lik bir `SizedBox`/`InkResponse` içine
  alınır. `Semantics(label:, selected:/checked:, button: true)` eklenir; renk adları `S` içine TR/EN girer.
  `Dismissible` satırına `Semantics(customSemanticsActions: {CustomSemanticsAction(label: s.delete): …})`.
  Eksik `tooltip`ler eklenir (Flutter bunu VoiceOver etiketi yapar). Süs emojileri `ExcludeSemantics` içine.
  Bir widget testi `meetsGuideline(iOSTapTargetGuideline)` ve `labeledTapTargetGuideline` ile bunu kilitler.

### 3.4 Açılış ekranı koyu modda beyaz parlıyor

- **Kural:** HIG Launching: açılış ekranı ilk ekranla neredeyse aynı olmalı, "matches the device's current …
  appearance mode"; logo/yazı konmaz. **[Apple]**
  https://developer.apple.com/design/human-interface-guidelines/launching
- **Durum:** `ios/Runner/Base.lproj/LaunchScreen.storyboard:22` arka plan saf beyaz; `LaunchImage*.png` 1×1
  saydam piksel. İlk ekran açıkta `#FAF7F2`, koyuda `#1E1C24`. **[Depo]**
- **Düzeltme:** `ios/Runner/Assets.xcassets/LaunchBackground.colorset/Contents.json` (Any: `#FAF7F2`, Dark:
  `#1E1C24`). Storyboard'da `:19-20` `imageView` ve `:23-26` kısıtları silinir; `:22` satırı
  `<color key="backgroundColor" name="LaunchBackground"/>` olur; `<resources>` içine
  `<namedColor name="LaunchBackground"><color red="0.980" green="0.969" blue="0.949" alpha="1" colorSpace="custom" customColorSpace="sRGB"/></namedColor>`
  eklenir. `LaunchImage.imageset` silinir. Logo eklenmez.

### 3.5 Bildirim izni: reddedildikten sonra yol yok; gereksiz rozet izni

- **Kural:** 5.1.1(iv) izin ayarına saygı ve alternatif; HIG Managing notifications: uygulama içinden ayar
  yönetilebilmeli. **[Apple]**
- **Durum:** İzin doğru anda isteniyor (anımsatıcı kaydında `reminder_editor.dart:71`, görevde hatırlatma
  seçilince `task_editor.dart:97`) — bu iyi. Ama Ayarlar > Bildirimler > "İzin ver"
  (`settings_page.dart:116-120`) izin reddedilmişse hiçbir şey yapmıyor ve durum gösterilmiyor.
  `reminder_scheduler.dart:171` `badge: true` istiyor; uygulama rozet kullanmıyor (5.1.1(iii) veri/izin
  asgarisi). **[Depo]**
- **Düzeltme:** `ReminderScheduler`'a `Future<NotificationStatus> status()` (eklentinin
  `checkPermissions()` çağrısı). Satır duruma göre: izin sorulmadıysa "Bildirimlere izin ver" → sistem uyarısı;
  reddedildiyse "Bildirimler kapalı — Ayarlar'ı aç" → `url_launcher` ile `app-settings:`; açıksa "Bildirimler
  açık" (onay ikonuyla). `badge: false`. "Deneme bildirimi gönder" satırı kalabilir.

### 3.6 Dynamic Type: büyük metinde sabit yükseklikler

- **Kural:** HIG: metin en az %200 büyütülebilmeli; özel yazı tipi de Dynamic Type'a uymalı. **[Apple]**
- **Durum:** Flutter sistem metin ölçeğini kendiliğinden uygular (Nunito dahil) ve `lib/` içinde ölçek
  kısıtlayan kod yok — iyi. Risk sabit yüksekliklerde: `today_page.dart:90` (196), `:170` (74),
  `pamnot_theme.dart:237` alt çubuk (68), `remindersShort` tek satıra sığsın diye kısaltılmış etiketler.
  En büyük erişilebilirlik boyutunda (ölçek ≈3,1) taşma olup olmadığı test edilmemiş. **[Depo]**
- **Düzeltme:** `test/` içine ana beş sekme için `textScaler: TextScaler.linear(2.0)` ve 375×667 pt ile "taşma
  yok" widget testleri; taşan sabit yükseklikler `ConstrainedBox(minHeight:)`'e çevrilir. Alt çubukta
  `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)` yalnız çubuk etiketleri için kabul edilebilir
  (Apple'ın kendi sekme çubuğu da etiketi büyütmez, basılı tutunca büyük gösterir). **[Yorum]**
- "Kalın Metin" (`MediaQuery.boldTextOf`) Nunito'da otomatik değildir; `PamnotTheme._build` içinde açıkken
  gövde ağırlığı 400→600, 600→700 yapılır.

### 3.7 El yazısı modeli: boyut söylenmeden hücresel veriyle iniyor

- **Kural:** 4.2.3(ii) ek kaynak indirilecekse boyut bildirilip sorulur (kural ilk açılış içindir; burada
  ruhu uygulanır). **[Yorum]**
- **Durum:** `lib/services/handwriting_mlkit.dart:33` `isWifiRequired: false`; `note_editor_page.dart:155`
  yalnız "indiriliyor" snack'i gösteriyor (≈20 MB, README). **[Depo]**
- **Düzeltme (ML Kit kalırsa):** İlk kullanımda onay penceresi: "El yazısı modeli indirilsin mi? Yaklaşık
  20 MB." / "Download the handwriting model? About 20 MB." [Vazgeç] [İndir].

### 3.8 Küçük maddeler

- **Tema ayarı:** HIG Dark Mode "Avoid offering an app-specific appearance setting" **[Apple]**. Varsayılan
  zaten Sistem (`lib/models/settings.dart:10`). Kalabilir; mağaza için sorun değil.
- **Dokunsal geri bildirim:** `lib/` içinde `HapticFeedback` yok. Görev tamamlamada
  `HapticFeedback.lightImpact()`, silmede `mediumImpact()` iOS hissini verir; sistem ayarına uyar.
- **Material bileşenleri:** Saat seçici Material kadranı (`reminder_editor.dart:60`, `task_editor.dart:93`).
  Ret sebebi değil; iOS'ta `CupertinoDatePicker` içeren alt sayfa daha yerli durur. Anahtarlar için
  `SwitchListTile.adaptive`.
- **"Tümünü sil" yok:** Hesap olmadığı için 5.1.1(v) hesap silme şartı uygulanmaz. Kullanıcı uygulamayı
  silerek veriyi siler; gizlilik politikasında böyle yazılır.
- **Test metni:** `TESTING.md` ve README "ücretsiz hesapla kurulum"u anlatıyor; mağaza sürümü için ayrı bir
  "Yayın" bölümü eklenir (§5.6).

---

## 4. Sesle görev ekleme özelliği için

### 4.1 Uygulamanın karşılaması gereken şartlar

**İzin metinleri** — `ios/Runner/Info.plist` (İngilizce, temel) ve `ios/Runner/tr.lproj/InfoPlist.strings`,
`en.lproj/InfoPlist.strings`. HIG kuralı: kısa, tam, etken çatılı bir cümle; nokta ile biter; "daha iyi deneyim
için" gibi belirsiz gerekçe olmaz. Apple'ın ses tanıma belgesi: metin tanınan konuşmanın nasıl kullanılacağını
anlatmalı, veri Apple sunucularına gidebildiği için bunu söylemek güveni artırır. **[Apple]**
https://developer.apple.com/design/human-interface-guidelines/privacy ·
https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition

| Anahtar | TR | EN |
| --- | --- | --- |
| `NSMicrophoneUsageDescription` | Pamnot, sesle görev eklerken söylediklerini duymak için mikrofonu kullanır. Ses kaydı saklanmaz. | Pamnot uses the microphone to hear what you say when you add a task by voice. No audio is saved. |
| `NSSpeechRecognitionUsageDescription` | Pamnot, söylediğin görevi yazıya çevirmek için konuşma tanımayı kullanır. Sesin bunun için Apple'a gönderilebilir. | Pamnot uses speech recognition to turn the task you say into text. Your voice may be sent to Apple for this. |

"Ses kaydı saklanmaz" cümlesi doğru kalmalı: ses dosyası hiçbir yere yazılmaz (tasarım §2 hedef dışı).

**İzin zamanı** (HIG Privacy; Apple ses tanıma belgesi "delay requests until the user interacts with the
portion of your app that uses such features" **[Apple]**):

1. İzinler yalnız Sesle ekle ekranı açıldığında istenir; uygulama açılışında, `main()` içinde ya da motor
   `prepare()` çağrısı başka bir yerden yapılarak **istenmez**. Mikrofon düğmesinin görünmesi izin istemez.
2. Sıra: önce konuşma tanıma, sonra mikrofon (eklentinin sırası). Araya özel bir açıklama ekranı gerekmez;
   ekranın kendisi bağlamı veriyor. Eklenirse tek düğmesi olur ve adı "Devam"dır ("İzin ver" değil), kapatma
   düğmesi olmaz. **[Apple]** HIG Privacy, pre-alert kuralları.
3. Reddedilince: "izin yok" durumu, neyin kapalı olduğunu yazıyla söyler ve tek düğme "Ayarlar'ı Aç"
   (`app-settings:`). Sistem uyarısı yeniden tetiklenmeye çalışılmaz. Yazarak hızlı ekleme her zaman çalışır
   (5.1.1(iv) alternatif yol).
4. Bildirim izni tasarımdaki gibi: saatli ilk görev kaydedildikten sonra, mikrofon kapalıyken.

**Kayıt göstergesi** (Guideline 2.5.14: "explicit user consent and provide a clear visual and/or audible
indication when recording" **[Apple]**):

1. Mikrofon açıkken ekranda her zaman hem ikon hem yazı vardır ("Dinliyorum…"); yalnız renk ya da yalnız
   animasyon yetmez. Sistem turuncu noktayı ayrıca gösterir.
2. Mikrofon kapandığında durum yazısı aynı anda değişir ("Duraklatıldı", "Kaydedildi"). "Dinliyorum" yazısı
   mikrofon kapalıyken ekranda kalmamalı; bunun için durum, eklentinin `Started`/`Stopped` olaylarına bağlanır,
   zamanlayıcıya değil.
3. Ekran görünmezken dinleme yoktur: tasarım §6.3'teki `hidden`/`paused` durdurması zorunludur; `UIBackgroundModes`
   `audio` **eklenmez** (2.5.4). Dönüşte mikrofon kendiliğinden açılmaz (tasarımda var).
4. Dinleme başlarken ve biterken kısa sistem sesi isteğe bağlıdır; eklenirse sessiz modda çalmaz.

**App Shortcut / Siri / Eylem Düğmesi** (Guideline 2.5.11; HIG App Shortcuts, Action button **[Apple]**):
https://developer.apple.com/design/human-interface-guidelines/app-shortcuts ·
https://developer.apple.com/design/human-interface-guidelines/action-button

1. Eylem adı: büyük harfle başlayan sözcükler, fiille başlar, şimdiki zaman, tanımlık ve edat yok,
   **en çok üç sözcük**. TR "Sesle Görev Ekle" uygun (Türkçede fiil sonda). EN için §4.2-1.
2. Her ifade `\(.applicationName)` içerir; genel sözcüklerden ya da başka uygulama adlarından oluşmaz; "Hey
   Siri", "Siri" sözcüğü ifadede geçmez. Önerilen liste (≤ 10 sınırı içinde):
   - TR: "Pamnot ile görev ekle", "Pamnot ile sesle görev ekle", "Pamnot'a görev ekle", "Yeni Pamnot görevi"
   - EN: "Add a task in Pamnot", "Add a Pamnot task", "New task in Pamnot", "Add a voice task in Pamnot"
3. Eylem yalnız kendi işini yapar: Sesle ekle ekranını açar. Araya tanıtım, puanlama isteği ya da başka ekran
   girmez (2.5.11(iii)).
4. Yalnız "uygulamayı aç" yapan ikinci bir kestirme eklenmez (HIG: sistem bunu zaten sunuyor).
5. `NSSiriUsageDescription`, Siri yeteneği ve `NSUserActivityTypes` eklenmez; App Intents bunları istemez
   (tasarım §6.1 ile aynı).
6. Kullanıcıya görünen metinlerde Apple adları: "Kestirmeler" (uygulama adı, büyük harf), "Eylem düğmesi",
   "Arkaya Dokunma", "Sesle Denetim". "Yan tuş" denmez (yan tuş kilitleme tuşudur).

**Ekranın erişilebilirliği:**

1. Her denetim ≥ 44×44 pt ve etiketli: Kapat, Düzelt, Kaydet, Geri al ("Toplantı görevini geri al"), mikrofon
   ("Dinlemeyi başlat" / "Dinlemeyi durdur").
2. Önizleme tek bir anlamlı öğe olarak okunur: "Annemi ara, yarın 19:00, hatırlatma açık". Belirsiz saat "?"
   yerine "saat tahmini" diye okunur.
3. Canlı bölge (`liveRegion`) **yalnız durum değişimlerinde** duyurur (dinleme bitti → önizleme; kaydedildi;
   hata). Ara metinler duyurulmaz: VoiceOver'ın sesi mikrofona girer ve tanımayı bozar. **[Yorum]**
4. Geri sayım çubuğu renk dışında sayıyla da gösterilir (tasarımda var); `Semantics(value:)` taşımaz, her
   saniye duyuru yapmaz.
5. Hareketi Azalt açıkken mikrofon halkası durağan (tasarımda var); ses düzeyi yine de durağan bir çubukla ya
   da yazıyla belli olur.
6. Metin ölçeği 2,0'da ve 375 pt genişlikte taşma yok; ekran kaydırılabilir (tasarım §7'de test var).
7. Dokunsal geri bildirim yalnız mikrofon kapalıyken (tasarımda var; HIG Playing haptics: titreşim mikrofonu
   bozmamalı **[Apple]**).

**Gizlilik beyanı:** `onDevice: false` iken ses Apple'a gidebilir. App Privacy'de bunun için "Audio Data"
beyan edilmez: "You are not responsible for disclosing data collected by Apple" **[Apple]**. Gizlilik
politikasında ve Ayarlar > Sesle ekleme notunda yazılır (tasarım §6.7'de var).

**İnceleme notu** (2.3.1(a) yeni özellik inceleme notunda özgül anlatılmalı **[Apple]**): §5.5'teki metin.

### 4.2 Onaylı tasarımla çelişen noktalar ve en küçük değişiklik

1. **İngilizce eylem adı dört sözcük ve edat içeriyor.** Tasarım §6.1: "Add Tasks by Voice". HIG Action
   button: en çok üç sözcük, edat yok. → **"Add Voice Task"**. Türkçe ad değişmez.
2. **Eylem Düğmesi kurulum yardımı.** Tasarım §6.7 Ayarlar'da "Yan tuş (Ayarlar > Eylem Düğmesi > Kestirme >
   Pamnot…)" adımlarını yazıyor. HIG Action button: "Avoid creating content that repeats the guidance offered
   in Settings for the Action button". → Eylem düğmesi adımları çıkarılır; yerine tek satır: "Sesle Görev Ekle
   eylemi Kestirmeler'de, Spotlight'ta ve Eylem düğmesi ayarlarında hazır." ve Siri ifadesi ipucu ("Siri'ye
   'Pamnot ile görev ekle' de") kalır (HIG: App Shortcuts uygulamada keşfedilebilir olmalı). Arkaya Dokunma ve
   Sesle Denetim adımları **kalır**: sistem bunları göstermiyor. Metinde "Yan tuş" → "Eylem düğmesi".
3. **VoiceOver / Anahtar Denetimi açıkken zaman sınırları.** Tasarım §5: 2 sn sonra kendiliğinden kayıt, 6 sn
   sessizlikte kendiliğinden kapanma. HIG Accessibility: "Minimize use of time-boxed interface elements …
   Prefer dismissing views with an explicit action." 2 saniyede VoiceOver önizlemeyi okuyamaz; yanlış saatle
   sessiz kayıt tasarımın kendi anti-hedefi. → `MediaQuery.accessibleNavigationOf(context)` doğruyken:
   önizleme geri sayımı çalışmaz ("Kaydet" ve "Düzelt" düğmeleri görünür), ekran kendiliğinden kapanmaz,
   kayıttan sonra dinleme kendiliğinden yeniden başlamaz (kullanıcı mikrofon düğmesine dokunur). Diğer
   kullanıcılar için akış aynen kalır. Bir widget testi eklenir.
4. **"Son tanınanlar" günlüğü.** Tasarım §6.7 son 20 ham metni kendiliğinden saklıyor. 2.5.14 kullanıcı
   girdisinin kaydını "explicit user consent" şartına bağlıyor; mikrofon izni bu saklamayı kapsamaz. **[Yorum]**
   → Günlük bir anahtarın arkasına alınır: Ayarlar > Sesle ekleme > "Tanınan metinleri sakla (son 20, yalnız
   bu cihazda)"; varsayılan **kapalı**. Cihazda deneme sırasında geliştirici açar. Gerisi (Temizle, yalnız
   cihazda) aynı.
5. **Çelişki değil, hatırlatma:** tasarım §6.6 "arka plana giderken eldeki metni kaydet" davranışı kurallarla
   uyumlu (kayıt görünür, geri alınabilir, ses saklanmıyor). Ekran açılır açılmaz dinlemeye başlamak da uyumlu:
   kullanıcı eylemi kendisi başlattı ve Apple'ın ses tanıma örneği izni arayüz görünür olunca istiyor.

### 4.3 Ses özelliğiyle birlikte gelen dosya işleri (kontrol listesi)

- `ios/Runner/Info.plist`: §2.7 tablosundaki dört satır.
- `ios/Runner/{en,tr}.lproj/InfoPlist.strings`, `AppShortcuts.strings`, `Localizable.strings`;
  `project.pbxproj` `knownRegions`'a `tr`.
- `ios/Runner/PrivacyInfo.xcprivacy` (§2.3) aynı betikle hedefe eklenir.
- `speech_to_text` sürümü sabitlenir; kendi gizlilik bildirimi yok ve gerekmiyor (neden gerektiren API
  kullanmıyor **[Depo]**, Apple'ın "yaygın SDK" listesinde değil **[Apple]**
  https://developer.apple.com/support/third-party-SDK-requirements/).
- CI: `plutil -lint ios/Runner/PrivacyInfo.xcprivacy` ve derlenen `Runner.app` içinde dosyanın varlığı kontrolü.

---

## 5. Sonraya (App Store Connect / iPad / Mac)

### 5.1 App Privacy ("beslenme etiketi") yanıtları

Tanım **[Apple]**: "Collect" = veriyi cihaz dışına, sizin ya da ortaklarınızın isteği yanıtlamak için gerekenden
uzun süre erişebileceği biçimde göndermek. Yalnız cihazda işlenen veri toplanmış sayılmaz. Apple'ın topladığı
veri beyan edilmez.

**Seçenek B (ML Kit çıkarılırsa):** "Do you or your third-party partners collect data from this app?" → **No**.
Etiket: **Data Not Collected**. Notlar, görevler, mürekkep, tanınan metinler cihazda; ses Apple'ın sistem
hizmetine gider.

**Seçenek A (ML Kit kalırsa):** → **Yes**. Google veri türlerini Apple kategorilerine eşlemiyor; aşağıdaki
eşleme benimdir ve temkinli taraftadır. **[Yorum]**

| Apple veri türü | Seç | Amaç | Kullanıcıya bağlı mı | İzleme mi |
| --- | --- | --- | --- | --- |
| Identifiers → Device ID (kurulum başına tanımlayıcı) | Evet | Analytics | Hayır | Hayır |
| Usage Data → Product Interaction (olay türü: başlatma, model indirme, tanıma) | Evet | Analytics | Hayır | Hayır |
| Diagnostics → Performance Data (gecikme) | Evet | Analytics, App Functionality | Hayır | Hayır |
| Diagnostics → Other Diagnostic Data (hata kodları, cihaz modeli, OS sürümü) | Evet | Analytics, App Functionality | Hayır | Hayır |
| Diğer tüm türler (Contact Info, User Content, Audio Data, Location, …) | Hayır | — | — | — |

"Data Used to Track You": **yok** (reklam, veri simsarı, ATT yok; `NSPrivacyTracking = false`).

### 5.2 Gizlilik politikası (URL zorunlu) — içermesi gerekenler

5.1.1(i) üç şeyi ister: ne toplanıyor ve nasıl kullanılıyor; üçüncü taraflar; saklama/silme ve rızayı geri alma.

- Notlar, görevler, anımsatıcılar, alışkanlıklar, el yazısı ve ayarlar yalnız cihazda saklanır; geliştiricinin
  sunucusu yoktur. Cihaz yedeği (iCloud/Finder) kullanıcının Apple hesabına bağlıdır.
- Sesle ekleme: ses yazıya çevrilmek üzere Apple'ın konuşma tanıma hizmetine gönderilebilir; Pamnot ses
  kaydı saklamaz. "Tanınan metinleri sakla" açıksa son 20 metin cihazda tutulur ve Ayarlar'dan silinir.
- (Seçenek A) Google ML Kit: el yazısı cihazda işlenir; Google'a kullanım/performans ölçümleri gider; Google
  gizlilik politikasına bağlantı.
- Bildirimler yereldir; anlık bildirim sunucusu yoktur.
- Silme: uygulamayı silmek tüm veriyi siler. İzinler iOS Ayarlar'dan geri alınır.
- İletişim e-postası. Sayfa TR ve EN.

### 5.3 Erişilebilirlik Etiketleri (Accessibility Nutrition Labels)

Şimdilik gönüllü; Apple ileride zorunlu olacağını söylüyor, tarih yok. Ölçüt: kullanıcı o özellikle uygulamanın
**tüm yaygın görevlerini** (ilk açılış, ayarlar ve ana işlevler) tamamlayabilmeli. Yanlış beyan App Review
tarafından düzelttirilebilir. **[Apple]**
https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels

| Etiket | Bugün | §3 düzeltmelerinden sonra |
| --- | --- | --- |
| VoiceOver | **Hayır** (§3.3; el yazısı tuvali ayrıca erişilemez) | Cihazda VoiceOver ile beş sekme denendikten sonra Evet; el yazısı notu "yaygın görev" sayılırsa Hayır kalır — yazı notu alternatifi var **[Yorum]** |
| Voice Control | **Hayır** (etiketsiz denetimler) | §3.3 sonrası, cihazda "adları göster" ile denenip Evet |
| Larger Text | Belirsiz (§3.6) | Testler geçince Evet |
| Dark Interface | **Evet** (koyu tema var, sistem ayarını izliyor) | Evet |
| Differentiate Without Color Alone | Kısmen: öncelik ve gecikme yalnız renkle (`task_tile.dart:72`), plan noktaları | Gecikene ikon/yazı eklenince Evet |
| Sufficient Contrast | **Hayır** (§3.1) | Evet |
| Reduced Motion | **Hayır** (§3.2) | Evet |
| Captions, Audio Descriptions | Uygulanmaz (video/ses içeriği yok) | — |

Öneri: ilk gönderimde yalnız kesin olanlar işaretlenir (Dark Interface); diğerleri §3 bittikçe eklenir.

### 5.4 Yaş derecelendirme, kategori, diğer alanlar

- **Yaş anketi** (2026 sistemi: 4+, 9+, 13+, 16+, 18+ **[Apple]**
  https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions):
  tüm içerik soruları **None/No**. Yetenekler: Unrestricted Web Access **No** (gizlilik bağlantısı Safari'de
  açılır, gömülü tarayıcı yok), User-Generated Content **No** (içerik paylaşılmıyor, tanım "broad distribution"
  ister), Messaging and Chat **No**, Advertising **No**, Parental Controls **No**, Age Assurance **No**.
  Beklenen sonuç **4+**.
- **Kategori:** Productivity (birincil); ikincil Utilities ya da boş. Kids kategorisi seçilmez.
- **Ad:** "Pamnot" (≤ 30 karakter). Alt başlık örn. "Notlar, görevler, anımsatıcılar" / "Notes, tasks &
  reminders". Meta veride "Android", "Windows" gibi başka platform adları geçmez (2.3.10 **[Apple]**); README'deki
  platform listesi mağaza açıklamasına kopyalanmaz.
- **Diller:** English (U.S.) birincil, Turkish eklenir; her ikisi için açıklama, anahtar sözcükler, ekran görüntüsü.
- **Ekran görüntüleri:** iPhone 6,9" (1320×2868 ya da 1290×2796) zorunlu; uygulama iPad'i desteklediği için
  (`TARGETED_DEVICE_FAMILY = "1,2"`) iPad 13" (2064×2752) da zorunlu. **[Bellek]** — yükleme ekranındaki güncel
  boyutlar esas alınır. Görüntüler uygulamayı kullanım halinde gösterir (2.3.3), örnek içerik gerçekçi ve 4+
  olur; cihaz çerçevesinde başka platform görünmez.
- **Telif:** "© 2026 <hak sahibi adı>". **Destek URL'si** zorunlu; pazarlama URL'si isteğe bağlı.
- **İhracat uyumu:** `ITSAppUsesNonExemptEncryption = NO` eklenince soru çıkmaz.
- **İçerik hakları:** üçüncü taraf içerik yok → No. Nunito OFL 1.1 (uygulamada atıf var:
  `settings_page.dart:139`; `assets/fonts/OFL.txt`). `showLicensePage` ile "Açık kaynak lisansları" satırı
  eklenmesi iyi olur (ML Kit ve eklenti lisansları için).
- **AB tacir beyanı (DSA):** AB'de dağıtım için zorunlu **[Apple]**; bireysel ve gelir amacı yoksa "tacir
  değilim" seçilebilir. Hukuki değerlendirme sahibine aittir.
- **Fiyat:** ücretsiz, uygulama içi satın alma yok → 3.1 kapsam dışı.

### 5.5 İnceleme notları (Notes for Review) — taslak

> Pamnot is an offline notes, tasks and reminders app. No account or login. All user data stays on the device.
> New in this version: "Add Voice Task". Open the Today tab and tap the microphone button next to the quick-add
> field, or run the "Add Voice Task" action from the Shortcuts app / Spotlight. The app asks for Speech
> Recognition and Microphone permission the first time. Say e.g. "call mom tomorrow at 7 pm". A preview shows the
> parsed date and time; the task is saved after 2 seconds or when you tap Save. Listening stops when the screen
> closes or the app goes to the background; no audio is stored. Speech is transcribed by Apple's Speech
> framework. Notifications are local only (flutter_local_notifications); permission is requested when the user
> first saves a reminder.

(Seçenek A'da eklenir: "Handwriting recognition uses Google ML Kit on device; it downloads a ~20 MB model on
first use.")

### 5.6 Yayın akışı (kullanıcının Mac'inde)

1. Developer Program üyeliği; App Store Connect'te uygulama kaydı (bundle ID `app.pamnot.pamnot`).
2. `pubspec.yaml` `version:` her yüklemede artan derleme numarası (`1.0.0+2`, …).
3. Xcode 26+: `flutter build ipa --release` → Transporter ya da Organizer ile yükle.
4. Önce TestFlight (dahili test) — gerçek cihazda §3 ve §4 kontrol listeleri, Privacy Report.
5. Yukarıdaki alanlar doldurulur → Submit for Review.
6. CLAUDE.md kuralı: yayından önce `security-audit` tam denetimi çalıştırılır.

### 5.7 iPad

- Bugün iyi olanlar **[Depo]**: dört yön (`Info.plist:62-68`), `UIRequiresFullScreen` yok (çoklu görev açık;
  iPadOS 26'da bu anahtar zaten uyumluluk moduna düşürür **[Apple]**
  https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen),
  `LaunchScreen` storyboard, `UIApplicationSupportsIndirectInputEvents`, 640 pt üstünde yan ray
  (`home_shell.dart:64`), ⌘N ve ⌘1–5 kısayolları.
- Yapılacaklar: iPadOS 26 pencereli modda küçük pencere (≈320 pt genişlik) taşma testi; kısayolların ⌘ basılı
  tutunca görünen listede çıkması için `UIKeyCommand`/menü köprüsü (Flutter `PlatformMenuBar` iPadOS 26'da menü
  çubuğunu besler); Apple Pencil ile mürekkepte üzerine gelme (hover) ve çift dokunma; ses ekranı için yatay
  düzen. Eylem düğmesi iPad'de yok; App Shortcut Spotlight ve Kestirmeler'den çalışır **[Apple]**.
- Ekran görüntüleri iPad için ayrıca gerekir (§5.4).

### 5.8 Mac (Mac App Store)

`macos/Runner` **[Depo]**:

- `Info.plist`'te `LSApplicationCategoryType` yok → Mac App Store yüklemesi için eklenir:
  `public.app-category.productivity`. **[Bellek]**
- `Release.entitlements` yalnız `com.apple.security.app-sandbox` — sandbox zorunluluğu karşılanıyor. Ses
  özelliği için `com.apple.security.device.audio-input` ve iki amaç metni (tasarım §11); gizlilik bağlantısını
  açmak yetki istemez. Ağ kullanan bir şey eklenirse `com.apple.security.network.client`.
- Simge `macos/Runner/Assets.xcassets/AppIcon.appiconset` (§2.1 ile birlikte yenilenir).
- macOS'ta gizlilik bildirimindeki "neden gerektiren API" bölümü aranmaz; `NSPrivacyCollectedDataTypes`
  bölümü tüm platformlarda geçerlidir **[Apple]**. Aynı `PrivacyInfo.xcprivacy` macOS hedefine de eklenebilir.
- App Shortcuts macOS'ta yok; App Intents eylemi Kestirmeler'de kullanılır **[Apple]**.
- HIG: menü çubuğu (Dosya > Yeni Not ⌘N, Görünüm, Pencere, Yardım) `PlatformMenuBar` ile; pencere en küçük
  boyutu; "Larger Text" etiketi Mac'te yok.
- Dağıtım hedefi 12.0 (`project.pbxproj:474`); yükleme Xcode 26 ile.

---

## 6. Kaynaklar

- App Store Review Guidelines — https://developer.apple.com/app-store/review/guidelines/
- Yaklaşan gereksinimler (Xcode 26 SDK, yaş derecelendirme) — https://developer.apple.com/news/upcoming-requirements/
- Gizlilik bildirimi dosyaları — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Neden gerektiren API'ler — https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- Üçüncü taraf SDK gereksinimleri — https://developer.apple.com/support/third-party-SDK-requirements/
- App Privacy ayrıntıları — https://developer.apple.com/app-store/app-privacy-details/
- Erişilebilirlik Etiketleri — https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- Yaş derecelendirme tanımları — https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- İhracat uyumu — https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- Ses tanıma izni — https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition
- HIG: Privacy, Accessibility, Typography, Color, Dark Mode, Motion, Layout, Launching, App icons, App Shortcuts,
  Action button, Siri, Playing haptics, Managing notifications, Multitasking —
  https://developer.apple.com/design/human-interface-guidelines/
- Google ML Kit koşulları ve iOS veri beyanı — https://developers.google.com/ml-kit/terms ·
  https://developers.google.com/ml-kit/ios-data-disclosure · sürüm notları
  https://developers.google.com/ml-kit/release-notes

Doğrulanamayanlar: ML Kit çatılarındaki `PrivacyInfo.xcprivacy` dosyaları (pod bu makinede indirilemedi; arşivde
Privacy Report ile bakılacak), ekran görüntüsü boyutları, Developer Program ve `LSApplicationCategoryType`
ayrıntıları ([Bellek] işaretli).
