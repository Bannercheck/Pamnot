# Sesle görev ekleme — tasarım

Tarih: 2026-11-23 · Dal: `claude/voice-capture` (taban: `main` d895fc4)

## 1. Amaç ve neden

Kullanıcı görevlerini ve planlarını sesle ekleyebilsin: telefonu eline alıp ya da bir tuşa/erişilebilirlik
hareketine basıp tek cümle söylesin, görev doğru gün ve saatle Pamnot'a girsin. Yazarak hızlı ekleme
("yarın 10:00 toplantı") zaten var; bu özellik aynı işi sesle, uygulamada gezinmeden yapar.

Öncelik iPhone. iPad ve Mac sonra gelecek; o yüzden mantığın tamamı Flutter tarafında, platforma özel
kısım ince tutulur.

Kullanıcının kararları (konuşmadan):

- Görevler **tek tek** söylenir: bir konuşma = bir görev.
- Giriş yolu: **Kestirmeler (Shortcuts) üzerinden Pamnot'u dinleme ekranında açan eylem.** Eller serbest
  Siri'nin arka planda kaydetmesi yerine bu seçildi, çünkü kaydetmeden önce ne anlaşıldığı görülür.
- Eylem bir **erişilebilirlik aracına** bağlanabilmeli (Arkaya Dokunma, Sesle Denetim).
- Tanıma dili **telefonun dili**.

## 2. Hedefler, hedef dışı, anti-hedefler

Hedefler

1. Kestirmeler'de kendiliğinden görünen "Sesle Görev Ekle" eylemi; yan tuş (Action Button), Spotlight,
   Siri, Arkaya Dokunma ve Sesle Denetim'den çalıştırılabilir. Pamnot'u açar, mikrofon hemen dinler.
2. Uygulama içinden aynı ekran: hızlı ekleme alanındaki mikrofon düğmesi ve `pamnot://ses` bağlantısı.
3. Konuşma Türkçesini ve İngilizcesini anlayan tarih/saat ayrıştırıcı ("akşam yedide", "dokuz buçukta",
   "yarın sabah", "2 gün sonra", "15 Aralık", "at 6:30 PM", "remind me to…").
4. Saat söylenmişse o saatte bildirim (hatırlatma) kurulur.
5. Ekran açıldıktan sonra dinlemeye başlama 1 saniyenin altında; hiçbir adımda donma yok.

Hedef dışı (bu sürümde yok)

- Uygulama açılmadan arka planda kaydetme (yaklaşım 2).
- Bir cümlede birden fazla görev; konuşmayı "ilgili nota" yönlendirme.
- Sesle görev tamamlama, silme, düzenleme; "Hey Pamnot" gibi uyandırma sözcüğü; ses kaydı saklama.
- Denetim Merkezi düğmesi (widget hedefinin Xcode'da bir kez elle kurulmasını bekliyor).
- iOS dışındaki platformlar. Bu sürümde motor yalnız iOS'ta "destekleniyor" der; Android, Windows, web ve
  macOS'ta mikrofon düğmesi gizlidir ve eklenti hiç çağrılmaz (macOS'ta ses girişi yetkisi olmadan çağrı
  çökebilir). Mac ve iPad §11'de.
- Yazarak hızlı eklemenin davranışını değiştirmek (bkz. §11).

Anti-hedefler (çalışsa bile başarısızlık sayılır)

- Yanlış gün/saatle görevi **sessizce** kaydetmek. Her kayıttan önce önizleme görünür ve düzeltilebilir.
- Uygulamanın takılması ya da çökmesi (eklentideki bilinen çökme için bkz. §6.3).
- Söylenen görevin kaybolması (ör. ekran kapanırken).
- Kullanıcının bilmediği bir yere ses gitmesi: izin metni ve Ayarlar açıkça söyler.
- `pamnot://` bağlantısıyla dışarıdan görev yazdırılabilmesi (bağlantı yalnız ekranı açar).

## 3. Kısıtlar

- Flutter 3.47.8 / Dart 3.13.7; iOS en düşük sürüm **16.0** (Podfile ve pbxproj).
- Geliştirici **ücretsiz Apple ID** ile imzalıyor: App Groups yok, ücretli yetenek yok, kurulum 7 günde
  bir yenilenir. App Intents ve App Shortcuts yetki (entitlement) istemez; Siri yeteneği gerekmez.
- Geliştirme ortamında Mac yok: Swift yalnızca GitHub Actions macOS işinde derlenir. Kullanıcının Mac'i ve
  Xcode'u var: cihaza kurulum ve cihazda deneme orada, `TESTING.md`'deki Xcode adımlarıyla yapılır
  (ücretsiz Apple ID ile imzalama). Ek dağıtım yolu (IPA, Sideloadly) gerekmez. iOS işi `main`, etiketler, elle başlatma
  ya da commit mesajında `[full-build]` olunca çalışır.
- iOS projesi klasik `objectVersion 54`; CI'da CocoaPods (ML Kit) da çalışıyor.
- `ios/Runner` UIScene kullanıyor (`FlutterSceneDelegate`, `FlutterImplicitEngineDelegate`).
- Depo kuralları (`CLAUDE.md`): superpowers akışı (plan → TDD → doğrulama), arayüzde ui-ux-pro-max
  kuralları, her push'tan sonra güvenlik denetimi.

## 4. Yaklaşımlar

| Yaklaşım | Artısı | Eksisi |
| --- | --- | --- |
| **1. Pamnot'u dinleme ekranında açan kestirme** (seçilen) | Kaydetmeden önce önizleme ve düzeltme; hatırlatma hemen kurulur; mantık Dart'ta, test edilebilir, iPad/Mac'e taşınır | Uygulama açılır; telefonun kilidi açık olmalı |
| 2. Arka planda çalışan eylem ("Metni Dikte Et" → "Pamnot'a Görev Ekle") | En hızlısı, uygulama açılmaz | Önizleme yok; Pamnot kapalıysa görev bir sonraki açılışa kadar işlenmez, o zamana dek hatırlatma kurulmaz; düzeltmek için ayrıştırıcının Swift kopyası gerekir |
| 3. İkisi birden | Her iki kullanım | En çok iş; 2'nin hatırlatma sorunu kalır |

Kullanıcı 1'i seçti: tarih/saatin yanlış kaydedilmesi bu uygulamada en pahalı hata.

## 5. Kullanıcı akışı

1. Kullanıcı tetikler: yan tuş, Arkaya Dokunma (kendi tek eylemli kestirmesi üzerinden), Sesle Denetim
   komutu, Spotlight, Siri ("Pamnot ile görev ekle"), uygulamadaki mikrofon düğmesi ya da `pamnot://ses`.
2. Pamnot açılır (ya da öne gelir) ve tam ekran **Sesle ekle** ekranını gösterir. Uygulama ön plana
   geldiğinde dinleme başlar (Siri ile açılışta ses oturumu çakışmasın diye kısa bir gecikmeyle).
3. Kullanıcı konuşur; yazı canlı görünür, altında canlı önizleme (gün, saat, başlık).
4. Son değişiklikten **1,6 sn** sonra konuşma bitmiş sayılır. Son metin ayrıştırılır, önizleme **2 sn**
   gösterilir ("Düzelt" düğmesi ve geri sayım çubuğuyla).
5. Süre dolunca görev kaydedilir, "Eklenenler" listesine düşer (geri alınabilir), dinleme yeniden başlar.
6. Yeniden dinlemede **6 sn** hiçbir şey söylenmezse ekran kendiliğinden kapanır. Tek oturum en fazla
   **30 sn** dinler.
7. "Düzelt"e dokunulursa geri sayım durur; metin düzenlenebilir alana geçer, önizleme yazdıkça güncellenir;
   "Kaydet" ile kaydedilir, sonra dinleme yeniden başlar.
8. Kapatma (✕, geri hareketi) her durumda çalışır; önizlemedeki görev **kaydedilmez** (açıkça "Kaydet"
   denmedikçe): kullanıcı ekrana bakarak vazgeçmiştir. Kaydedilen her görev "Eklenenler"de kalır ve ekran
   kapanınca bir özet snack'i çıkar.
9. Uygulama arka plana giderse (telefonu kilitlemek, başka uygulamaya geçmek) davranış §6.6'daki
   "Arka plan" kurallarına uyar: söylenmiş görev kaybolmaz, mikrofon kendiliğinden yeniden açılmaz.

Ekran taslağı:

```
┌──────────────────────────────────────┐
│ ✕                        Sesle ekle  │
│                                      │
│              ╭──────╮                │
│              │  🎙  │  ← ses düzeyiyle │
│              ╰──────╯    hafif büyür  │
│            Dinliyorum…               │
│                                      │
│   "yarın akşam yedide annemi ara"    │  canlı yazı
│                                      │
│   [📅 Yarın] [🕖 19:00] [🔔]          │  önizleme çipleri
│   Annemi ara                         │  başlık
│                                      │
│   [ Düzelt ]   ▬▬▬▬▬▬▬▬▬▬░░░  2 sn    │
│                                      │
│   Eklenenler                         │
│   ✓ Toplantı · Yarın 10:00      ↶    │
└──────────────────────────────────────┘
```

(Simgeler gerçek uygulamada Material ikonlarıdır; emoji kullanılmaz.)

Durumlar: hazırlanıyor · dinliyor · önizleme · düzeltme · kaydedildi · hata · izin yok · dikte kapalı ·
dil desteklenmiyor · platform desteklenmiyor. Her durum metin + ikonla gösterilir, yalnız renkle değil.

## 6. Bileşenler

### 6.1 iOS: kestirme ve köprü (`ios/Runner`)

- `VoiceTaskIntent.swift`: `struct VoiceTaskIntent: AppIntent`, başlık "Sesle Görev Ekle"/"Add Tasks by
  Voice". `perform()` (`@MainActor`) köprüye `voice` isteği bırakır ve `.result()` döner.
  `openAppWhenRun = true`, iOS 26 SDK'deki kullanımdan kaldırma uyarısı için
  `@available(*, deprecated) extension` içinde tanımlanır.
- `PamnotShortcuts: AppShortcutsProvider`: **tek** `AppShortcut`, iOS 16 başlatıcısı
  `AppShortcut(intent:phrases:)` (shortTitle/systemImageName yok, `if #available` yok — bu ikisi iOS 16
  hedefiyle derlenmiyor ya da ifade çıkarmayı bozuyor).
- İfadeler: her ifade `\(.applicationName)` içerir; Türkçede uygulama adı eksiz kalır ("Pamnot ile görev
  ekle", "Yeni Pamnot görevi", "Pamnot ile sesle görev ekle"…). `en.lproj`/`tr.lproj`
  `AppShortcuts.strings` ile birebir çeviri; başlık/açıklama `Localizable.strings` içinde.
- `PamnotLaunchBridge.swift`: tekil (singleton) `FlutterPlugin` + scene yaşam döngüsü temsilcisi.
  `app.pamnot/launch` kanalı; tek bir bekleyen eylem tutar. Dart `takePendingAction` ile çeker; sıcak
  açılışta yerel taraf `actionAvailable` gönderir. Hangi taraf önce hazır olursa olsun istek bir kez
  teslim edilir, kaybolmaz. Yalnızca `pamnot://ses` ve `pamnot://voice` bağlantılarını sahiplenir
  (home_widget'ın `?homeWidget` bağlantılarına dokunmaz).
- Kayıt: `AppDelegate.didInitializeImplicitFlutterEngine` içinde,
  `engineBridge.pluginRegistry.registrar(forPlugin: "PamnotLaunchBridge")` ile; bildirim eklentisinin
  arka plan motoru geri çağrısının **içine konmaz**.
- `Info.plist`: `CFBundleURLTypes` (`pamnot`), `FlutterDeepLinkingEnabled = false` (yoksa
  `pamnot://ses` ikinci bir HomeShell açar), `NSMicrophoneUsageDescription`,
  `NSSpeechRecognitionUsageDescription` (TR/EN `InfoPlist.strings`), `CFBundleLocalizations [en, tr]`.
  Siri anahtarı, arka plan ses modu, `NSAppIntents*` anahtarları **eklenmez**.
- `project.pbxproj`: yeni dosyalar CocoaPods'un da kullandığı `xcodeproj` gem'iyle, tekrar
  çalıştırılabilir bir betikle eklenir (`tool/ios/add_voice_files.rb`); `objectVersion 54` korunur,
  `knownRegions`'a `tr` eklenir.

### 6.2 Dart: açılış istekleri

- `lib/services/launch_actions.dart`: kanalı dinler, `main()` içinde `runApp`'ten önce başlar; ilk kare
  sonrası ve her `resume`'da bekleyen eylemi çeker. Sonuç tek amaçlı bir bildirici: `voiceRequests`.
- `_PamnotAppState.didPushRouteInformation`: `pamnot` şemasını yakalar (`ses` → `voiceRequests`), Flutter'ın
  rota eklemesini engeller (Android'de olduğu gibi).
- `HomeShell`: `notificationTaps` gibi `voiceRequests`'i dinler (dinleyici + ilk kare sonrası kontrol) ve
  ekranı kök navigatörle tam ekran açar. Ekran zaten açıksa yeni istek ikinci bir ekran açmaz:
  mikrofonun dokunuş beklediği durumlarda (duraklatıldı, kaydedildi, hata) mikrofona dokunulmuş gibi
  dinlemeye başlar; hazırlanırken, dinlerken, önizlemede, düzeltmede ve bildirim izni sorulurken yok
  sayılır.
- Bağlantı yalnızca ekranı açar; içinde metin olsa bile görev yazmaz. Her uygulama ve sayfa bağlantı
  açabildiği için ekran duraklatılmış açılır (köprüde `voice-link`, Dart'ta `VoiceRequest.link`):
  dinlemek için Pamnot içinde dokunmak gerekir; ekran açıkken gelen bağlantı hiçbir şeyi değiştirmez.

### 6.3 Konuşma tanıma motoru

- Arayüz `SpeechEngine` (`lib/services/speech/`): bir oturum = bir konuşma. Olay akışı (mühürlü sınıflar):
  `Started`, `Partial(text)`, `Final(text)`, `Level(db)`, `Stopped`, `Failure(kind)`; yöntemler
  `availability()`, `resolveLocale()`, `prepare()` (izinler), `start(locale)`, `stop()`, `cancel()`,
  `dispose()`. Zamanlamaların hepsi Dart'ta (1,6 sn / 2 sn / 6 sn / 30 sn).
- Uygulama: `speech_to_text` (csdcorp) eklentisi, sabit sürüm. Seçenekler: `partialResults: true`,
  `onDevice: false` (çevrimdışıyken iOS yine cihazda tanır; cihaz içi modun bilinen "2 sn duraksamada metin
  sıfırlanır" hatasından kaçınır), `autoPunctuation: false`, `cancelOnError: false`, dinleme modu
  varsayılan (dictation ipucu "Dikte kapalı" hatasına bağlanıyor).
- **Bütün eklenti çağrıları tek sıraya** alınır; önceki oturum bitmeden `listen()` çağrılmaz (açık çökme
  hatası #680 tam olarak yeniden dinleme döngüsünde oluyor).
- Dinleme yalnız uygulama ön plandayken (`resumed`) başlar. Uygulama gerçekten arka plana geçince
  (`hidden`/`paused`) oturum durdurulur. Kısa süreli `inactive` (Denetim Merkezi'ni indirmek, bildirim
  izni penceresi, gelen arama uyarısı) tek başına oturumu kesmez; eklenti bir kesinti hatası bildirirse
  ekran "duraklatıldı" durumuna geçer. Ekran davranışı §6.6'da.
- Dil: `PlatformDispatcher.instance.locales` (telefonun dil listesi) → eklentinin `locales()` listesinde
  tam eşleşme → aynı dil kodu → yoksa "dil desteklenmiyor". Yerel ayar her zaman açıkça verilir.
- Hata eşlemesi: izin yok → Ayarlar'a yönlendir; `error_speech_recognizer_disabled` (201) → "Ayarlar >
  Genel > Klavye > Dikte'yi aç" yönlendirmesi; boş/eşleşme yok → boşta say; ağ/kısıtlama → "Tekrar dene".
  Konuşma duyulduktan sonra gelen kesinti, ağ ya da bilinmeyen hata cümleyi atmaz: duyulan metin
  önizlemeye gider ve elle "Kaydet" ile kaydedilir (§6.6); hata yalnız hiçbir şey duyulmadıysa gösterilir.
- `FakeSpeechEngine` (testler): `say()`, `level()`, `fail()`; widget testleri gerçek zamanı `pump` ile
  sürer.
- Uygulama motorun varsayılanı olarak `UnsupportedSpeechEngine` alır; mevcut testler değişmez.

### 6.4 Konuşma ayrıştırıcı

- Yazarak hızlı ekleme (`quickParse`) ve 7 testi **değişmez**.
- `lib/core/spoken/normalize.dart` — saatten bağımsız metin işi: kesme işaretlerini (’ ‘ ` ´ ʼ → ')
  birleştir, baş/son noktalama, dolgu ve hatırlatma kalıpları ("bir görev ekle", "…mayı hatırlat",
  "remind me to"), sayı sözcükleri → rakam (yalnız saat bağlamında), buçuk/çeyrek/geçe/kala/yarım → `h.mm`.
- `lib/core/spoken/parse.dart` — `parseSpokenTask(transcript, now, lang)` →
  `SpokenTask {title, due, hasTime, remind, ambiguousHour, isNote}`.
- Kurallar. Kabul ölçütü `2026-11-23-voice-task-capture-vectors.txt` dosyasındaki 156 vektördür
  (145'i araştırmadan, 11'i tasarım incelemesinden); testlere birebir taşınır:
  - **Yalın saat** (sabah/akşam/am/pm yok): 0, 13–23 ve başında sıfır olanlar ("08.30") olduğu gibi;
    1–6 → öğleden sonra (13–18), 7–11 → sabah, 12 → öğle. Gün söylenmemişse ve saat geçmişse 7–9 akşama
    (19–21) döner, diğerleri yarına. Gün söylenmişse çevirme yok. Bu durumda `ambiguousHour` işaretlenir,
    önizlemede saat çipi "?" ile gösterilir.
  - **Gün bölümü**: sabah 09:00, öğle/öğlen 12:00, öğleden sonra 15:00, akşam 19:00, gece 22:00 (İng.
    morning 9, noon 12, afternoon 15, evening/tonight 19, night 22). Saatle birlikte: akşam/öğleden sonra
    +12; gece 1–5 "bu gece"nin o saati: akşamdan söylenirse ertesi gün, gece yarısından sonra 05:00'e kadar
    söylenirse aynı gün ("gece 2'de" 00:30'da → bugün 02:00); gece 12 → yaklaşan gece yarısı (ertesi gün
    00:00). Bileşik isimlerde ("akşam yemeği", "sabah kahvesi"…) saat sayılmaz.
  - **Tarihler**: bugün, yarın, öbür gün, haftaya (+7), "haftaya salı"/"next friday" (sonraki haftanın
    günü), "bu cuma", hafta sonu (Cumartesi), ay sonu, "N gün/hafta sonra", "N saat/dakika sonra", "yarım
    saat sonra", "in 2 hours", "15 Aralık"/"December 15th" (geçmişse gelecek yıl), "ayın 15'i"/"15'inde"/
    "on the 15th". "…'e kadar" son günü verir, saat koymaz ("cumaya kadar" → o Cuma). "bu cuma" o gün
    söylenirse bugün; "hafta sonu" Cumartesi ya da Pazar söylenirse bugün; yalın gün adı aynı gün
    söylenirse bir sonraki hafta.
  - **Tarih sayılmayanlar**: "3 ekmek al", "10 sayfa oku", "2 saat çalış", "ikide bir", "üçte bir",
    "pazara git", "bir de süt al"…
  - **Hatırlatma kalıbı**: "…mayı/meyi hatırlat" → başlık emir kipine döner ("annemi aramayı hatırlat" →
    "Annemi ara"), `remind = true`. Gün de saat de yoksa görev tarihsiz kaydedilir, bildirim kurulmaz;
    önizleme bunu gösterir ("Tarihsiz · hatırlatma için gün söyle").
  - **Not**: "not al …"/"not: …"/"note …" ile başlıyorsa `isNote = true` (görev yerine not). Notun
    metninde tarih ayrıştırılmaz; kalan metin olduğu gibi (ilk harf büyük) notun gövdesi olur.
  - Dil: `tr` kuralları Türkçe, `en` kuralları İngilizce; diğer dillerde yalnız rakamla saat, gerisi başlık.
    Büyük harf kuralı dile göre (İngilizcede "invite" → "Invite", "İnvite" değil).
- Canlı önizleme her ara sonuçta çalışır; kayıt yalnız son metinden, `now` = konuşmanın bittiği an.

### 6.5 Kaydetme ve hatırlatma (`AppController`)

- `addSpokenTask(SpokenTask)`: görevi `due`/`hasTime` ile ekler.
  - `hasTime` ise `remindAt = due` (gelecekteyse).
  - `remind` var ama saat yoksa `remindAt` = o gün **09:00** (geçmişse yok).
  - Bildirim izni henüz istenmemişse, saatli ilk görevde **mikrofon kapalıyken** istenir.
- `isNote` ise `addSpokenNote(text)`: metni gövde yapan yeni bir not.
- Geri alma: kaydedilen görev/not "Eklenenler"de ↶ ile silinir (mevcut `deleteTask`/not silme yolu).
- Ayrıştırma ve kayıt ana izolatta kalır (kısa metin, milisaniyenin altında); dosya yazımı mevcut
  gecikmeli kayıtla olur.

### 6.6 Ekran (`lib/ui/voice/voice_capture_page.dart`)

- Tam ekran rota, `MaterialPageRoute(fullscreenDialog: true)`; tema renkleri `ColorScheme` ve
  `soft.dart` bileşenleri. Kontrast ölçümlerine göre: metin `onSurface`, çipler
  `primaryContainer`/`onPrimaryContainer`, hata `errorContainer`/`onErrorContainer`.
- Yalnız mikrofon halkası ses düzeyiyle hafifçe canlanır; iOS'ta "Hareketi Azalt" açıksa
  (`AccessibilityFeatures.reduceMotion`) durağan.
- Dokunma hedefleri ≥ 44 pt, aralar ≥ 8 pt; ✕ her zaman görünür; VoiceOver etiketleri; durum metni
  `Semantics(liveRegion: true)`, hazırlanırken ve dinlerken hariç: VoiceOver'ın sesi mikrofona girip
  tanınan metne karışmasın (uyumluluk belgesi §4.1).
- Tanıyıcı konuşma duyulduktan sonra hatayla durursa cümle atılmaz: önizleme geri sayım olmadan açılır,
  "Düzelt" ya da elle "Kaydet" ile kaydedilir; kayıttan sonra mikrofon kendiliğinden açılmaz. Hiçbir şey
  duyulmadıysa hata ya da "duraklatıldı" gösterilir.
- Dokunsal geri bildirim yalnız kayıt anında ve mikrofon kapalıyken (kayıt sırasında iOS titreşimi
  susturur).
- Dikey ve yatay, Dynamic Type, koyu tema çalışır; 375 pt genişlikte taşma yok.

Arka plan (uygulama `hidden`/`paused` olunca):

| O anki durum | Ne olur |
| --- | --- |
| Dinliyor, henüz bir şey söylenmedi | Mikrofon kapanır; dönüşte "Devam etmek için dokun" |
| Dinliyor, metin var (bitmemiş konuşma) | Eldeki son metin ayrıştırılır ve **kaydedilir** (başlık boş değilse) |
| Önizleme geri sayımı sürüyor | Hemen **kaydedilir** (geri sayımın bitmesi gibi) |
| Düzelt'te düzenleniyor | Kaydedilmez; taslak ekranda kalır, dönüşte aynı yerden devam |
| Kaydedildi / hata / izin yok | Değişmez |

- Neden: yan tuşla "söyle ve telefonu kilitle" doğal kullanım; görevin kaybolması, önizlemenin
  görülmemesinden daha kötü. Arka planda kaydedilenler dönüşte "Eklenenler"de "Kilitlenirken kaydedildi"
  notuyla ve geri al düğmesiyle görünür.
- Dönüşte mikrofon **kendiliğinden açılmaz** (gizlilik); kullanıcı mikrofon düğmesine dokunur.
- Uygulama 5 dakikadan uzun arka planda kaldıysa dönüşte ekran kendiliğinden kapanır (taslak varsa
  kapanmaz) ve özet snack'i gösterilir.
- Kayıt dosyaya mevcut gecikmeli kayıtla yazılır; arka plana geçişte `AppController.flush()` çağrılır ki
  uygulama askıya alınsa da görev diskte olsun.

### 6.7 Uygulama içi giriş noktaları

- `QuickAddField`: gönder düğmesinin yanına mikrofon düğmesi (yalnız motor destekliyse görünür).
- Ayarlar > **Sesle ekleme** bölümü:
  - Kurulum yardımı: Yan tuş (Ayarlar > Eylem Düğmesi > Kestirme > Pamnot > Sesle Görev Ekle); Arkaya
    Dokunma ve Sesle Denetim için önce Kestirmeler'de tek eylemli kestirme yapılır, sonra seçilir.
  - "Son tanınanlar": son 20 ham metin ve ayrıştırma sonucu, yalnız cihazda, "Temizle" ile silinir.
    Gerçek cihazda Türkçe tanımanın saati nasıl yazdığı bilinmediği için ayrıştırıcıyı buna göre
    ayarlamaya yarar.
  - Gizlilik notu: Konuşma Apple'ın konuşma tanımasıyla yazıya çevrilir; çevrimiçiyken ses, klavyedeki
    dikte gibi Apple'a gidebilir.

### 6.8 Metinler

- Tüm yeni metinler `S` içinde TR/EN getter olarak (eksik çeviri derleme hatası olur).
- iOS tarafı: `InfoPlist.strings`, `AppShortcuts.strings`, `Localizable.strings` (en, tr).

### 6.9 CI ve belgeler

- iOS işine: derlemeden önce `plutil -lint` (pbxproj, Info.plist, `.strings`); derlemeden sonra
  `extract.actionsdata` içinde `VoiceTaskIntent` var mı kontrolü (kestirmenin sessizce kaybolmasını yakalar).
- Swift'e dokunan commit'ler `[full-build]` taşır.
- `TESTING.md`: cihazda deneme adımları, kurulum yolları, "Son tanınanlar"dan örnek toplama.
- `ios/PamnotWidget/README.md`: `pamnot` şeması artık kayıtlı ve derin bağlantı kapalı notu.

## 7. Test planı

- Birim: 145 ayrıştırıcı vektörü (§6.4), normalleştirici; mevcut `quickParse` testleri aynen geçer.
- Denetleyici: `addSpokenTask` → `remindAt`, `alerts()` içinde `t:` uyarısı; hatırlatma kalıbı + gün →
  09:00; not yolu.
- Widget (FakeSpeechEngine ile): aç → dinle → ara sonuç → 1,6 sn → önizleme → 2 sn → kayıt → yeniden
  dinle → 6 sn → kapan; Düzelt; ✕ önizlemede kaydetmez; izin yok; dikte kapalı; dil desteklenmiyor;
  ekran açıkken gelen yeni istek; uygulama arka plana gidince iptal.
- Derin bağlantı: `pamnot://ses` ikinci HomeShell açmaz, ekranı açar; `?homeWidget` bağlantıları değişmez.
- Erişilebilirlik: etiketler, hedef boyutları, metin ölçeği 2.0'da taşma yok.
- iOS: CI'da derleme + metadata kontrolü. Cihazda elle: TESTING.md listesi; kullanıcı Mac'inde Xcode ile
  kurar. Siri ifadeleri, Xcode > Product > App Shortcuts Preview ile de denenebilir.
- **`main`'e birleştirmeden önce cihazda deneme yapılır**: kestirme Kestirmeler'de görünüyor mu, yan tuş /
  Arkaya Dokunma ekranı açıyor mu, Türkçe tanıma çalışıyor mu, "Son tanınanlar"dan birkaç gerçek örnek
  (saatlerin nasıl yazıldığı) toplanır ve gerekirse ayrıştırıcı bunlara göre düzeltilir.

## 8. Kararlarım (kullanıcının kontrol etmesi için)

1. iOS en düşük sürüm 16.0 kalır; kestirme kutucuğu özel simge/kısa başlık göstermez (bunun için iOS 17
   gerekir).
2. Tanıma `onDevice: false`: en iyi Türkçe doğruluk, çevrimdışı da çalışır; çevrimiçiyken ses Apple'a
   gidebilir (klavye diktesiyle aynı).
3. Gün bölümü saatleri: sabah 09, öğle 12, öğleden sonra 15, akşam 19, gece 22.
4. Yalın saat kuralı: 1–6 öğleden sonra, 7–11 sabah; önizlemede "?" ile gösterilir.
5. "hatırlat" + gün, saat yok → 09:00'da bildirim.
6. "haftaya" = 7 gün sonra (yazarak eklemedeki gibi).
7. Ekran ✕ ile kapatılırken önizlemedeki görev kaydedilmez; uygulama arka plana giderken ise kaydedilir.
8. Siri ifadelerinde uygulama adı eksiz: "Pamnot ile görev ekle".
9. "Son tanınanlar" günlüğü yalnız cihazda, son 20 kayıt.
10. Bu sürüm yalnız iOS; diğer platformlarda mikrofon düğmesi gizli.
11. "gece 1–5" gece yarısından sonra söylenirse aynı gün; "hatırlat" tarihsizse bildirim yok.
12. Ekran açıkken gelen yeni sesli istek duraklatıldı, kaydedildi ve hata durumlarında dinlemeye başlar;
    hazırlanırken, dinlerken, önizlemede, düzeltmede ve bildirim izni sorulurken yok sayılır.
13. Durum metni hazırlanırken ve dinlerken canlı bölge değildir; VoiceOver mikrofona konuşmaz.
14. Konuşma duyulduktan sonra gelen tanıyıcı hatası cümleyi atmaz: önizleme elle "Kaydet" ile kaydedilir;
    hata yalnız hiçbir şey duyulmadıysa gösterilir.

## 9. Builder'a kalanlar

Dosya ve sınıf adları, animasyon ayrıntısı, ifade listesinin son hali (≤ 10 kestirme kuralı içinde),
hata metinlerinin tam ifadesi, `speech_to_text` sürümünün uygulama günü en güncel kararlı sürüm olarak
seçilmesi (beta değil), sayı sözcüğü kapsamının vektörleri geçecek şekilde genişletilmesi.

## 10. Riskler

- Türkçe tanımanın saati nasıl yazdığı ("10'da" mı "onda" mı) belgelenmemiş; ayrıştırıcı ikisini de kabul
  eder, "Son tanınanlar" ile cihazdan örnek toplanır.
- Swift burada derlenemiyor; ilk gerçek test CI macOS işi.
- Türkçe Siri ifadelerinin eşleşmesi doğrulanmadı (iOS 16'da birebir eşleşme). Kestirmeler, yan tuş ve
  Arkaya Dokunma ifadeye bağlı değil.
- Sesle Denetim kendi mikrofonunu tutuyor; tetikleyici olarak cihazda denenmeli.
- Ücretsiz Apple ID: 7 günde bir yeniden kurulum; uygulama silinip kurulursa kullanıcının kişisel
  kestirmesi yeniden seçilmeli.
- Eklenti tek bakımcılı; Apple `SFSpeechRecognizer`'ı geriletirse yerel `DictationTranscriber` (iOS 26+)
  arka ucu eklenir — motor arayüzü bunun için var.

## 11. Sonra

- iPad: aynı kod; yatay düzen ve klavye kısayolu.
- Mac: `macos/Runner` için ses girişi yetkisi (`com.apple.security.device.audio-input`), iki izin metni,
  URL şeması ve App Intents eylemi (macOS'ta App Shortcuts yok, eylem Kestirmeler'de kullanılır).
- Denetim Merkezi düğmesi: widget hedefi Xcode'da kurulunca.
- Yazarak hızlı eklemeyi yeni ayrıştırıcıya geçirmek (bugünkü hatalar: "at 6:30 PM", ’ işareti,
  "haftaya salı", "pazara git") — ayrı karar.
