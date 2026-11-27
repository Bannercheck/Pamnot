# Pamnot v3 — tasarım

Tarih: 2026-11-27 · Dal: `claude/pamnot-v3` (taban: `claude/pamnot-v2` f95c2c8)

## 1. Amaç ve neden

Sahip v2'yi TestFlight'ta kullandıktan sonra üç şey istedi:

1. **Takvim görünümleri:** gün, hafta ve ay; telefon ve Outlook etkinlikleri ile — isteğe bağlı — Pamnot
   görevleri aynı takvimde.
2. **Toplantı notu:** PC'de Teams toplantısındayken telefon masada dinler, yazıya döker; sahip önemli
   kısımları planlarına ekler.
3. **iCloud:** cihazlar arası eşitleme ve ortak listeler. Sahibin sözüyle "bizde fark yaratacak kısım
   burası". Örnek kullanım: anne baba, çocuklarının "Okul" listesindeki ödevleri ve etkinlikleri takip
   eder, çocuk da saatleriyle girer; aile "Alışveriş" listesini paylaşır.

Sahibin genel isteği: temiz kod, güvenli kod; performans ve güvenlik önerilerine dikkat.

## 2. Kapsam

1. Takvim: gün / hafta / ay görünümü ve "Pamnot görevleri" açma kapama düğmesi (§3).
2. Toplantı notu: ayrı mikrofon, ayrı kestirme, canlı transkript, plana ekleme, öneriler (§4).
3. iCloud eşitleme ve liste paylaşımı, gruplar, görev atama (§5).
4. Kılavuzdaki boş video kaldırılır (§6).

**Hedef dışı:** Mac uygulamasında eşitleme ve yeni özellikler (bu sürüm iPhone ve iPad); Android ve diğer platformlarda yeni özellik (oralarda bozulmamaları yeterli); kendi
sunucumuz, hesap açma, giriş ekranı; takvim etkinliği oluşturma ya da düzenleme (takvime yazma izni
yok); toplantının ses dosyasını saklamak; tek bir not, görev ya da toplantı notunu ayrı paylaşmak
(paylaşım birimi listedir); kılavuz videolarının yeniden çekilmesi (sahip daha sonra kendi ekran
kayıtlarını gönderecek).

**Anti-hedefler:**
- Paylaşılmayan hiçbir veri başkasına görünmez. Sahibin sözüyle: "Benim iş görevlerimi falan neden
  görsünler." Varsayılan özeldir.
- Eşitleme veri kaybettirmez: çakışmada ya da hatada yerel veri silinmez.
- Arayüz eşitleme ya da transkript yüzünden takılmaz.
- Mevcut sesli görev akışı (söyledin, ekledi, bitti; R10) değişmez.

## 3. Takvim görünümleri

### 3.1 Bugünkü durum

`lib/ui/planner/planner_page.dart` Plan sekmesidir: "Ajanda" ve "Anımsatıcılar" bölümleri; ajandada
hafta ve ay şeridi (`_month`) ile seçili günün listesi. Veri `AppController.agenda(day)` ile gelir
(`AgendaKind.task | reminder | event`), etkinlikler `lib/services/calendar/` üzerinden EventKit'ten
okunur (Outlook hesabı telefona eklenmişse dahil).

### 3.2 Görünümler

Ajandanın üstünde cam bir segment: **Gün · Hafta · Ay**.

```
 ┌ Kasım 2026 ─────────────── [Pamnot ●] [Bugün] ┐
 │        [ Gün | Hafta | Ay ]                     │
 └─────────────────────────────────────────────────┘
 Gün:   saat ızgarası 00–24, şimdi çizgisi, tüm gün şeridi üstte
        09:00 ┃ ▇ Ekip toplantısı (Outlook, mavi)
        10:30 ┃   ▇ Rapor gönder (İş listesi rengi)  ← sürüklenebilir
 Hafta: 7 sütun saat ızgarası (iPhone dikeyde 3 gün + yatay kaydırma, iPad'de 7 gün)
 Ay:    6×7 hücre, hücrede en çok 3 nokta/çizgi; dokununca o günün Gün görünümü
```

- Kendi Flutter widget'larımız; dış paket yok. Ölçek: saat ızgarası `CustomPaint` ile tek katman,
  kartlar yalnız görünen saat aralığında kurulur (lazy). 2.0 metin ölçeğinde taşma yok, dokunma alanları
  ≥ 44 pt, Reduce Motion'da animasyon yok.
- Seçili görünüm `AppSettings.calendarView` ile hatırlanır. Kaydırma ile gün/hafta/ay ileri-geri.
- Etkinlikler kendi takviminin rengiyle, Pamnot görevleri ve anımsatıcılar liste rengiyle; renk tek
  ayırt edici değildir: Pamnot öğelerinde liste simgesi, etkinliklerde takvim simgesi.
- Çakışan öğeler yan yana sütunlara bölünür (en çok 3 sütun, fazlası "+n").

### 3.3 "Pamnot görevleri" düğmesi

- Üst çubukta açma kapama düğmesi (`AppSettings.calendarShowPamnot`, ilk açılışta **açık**, son hali
  hatırlanır).
- Kapalı: yalnız telefon/Outlook etkinlikleri. Açık: saatli görevler, tarihli görevler (tüm gün
  şeridinde) ve anımsatıcılar da.

### 3.4 Sürükleme

- Yalnız Pamnot görevi ve anımsatıcısı sürüklenir; 15 dakikalık adımlara oturur, uzun basınca başlar,
  bırakınca saat değişir ve alarm/bildirim yeniden kurulur. Geri al çubuğu çıkar.
- Görevlerin süre alanı yok: ızgarada sabit 30 dakikalık kutu olarak çizilir (süre alanı eklenmez).
- Yinelenen anımsatıcı sürüklenince serinin saati değişir (gün değişmez); tek tekrar için ayrık kayıt yok.
- Telefon/Outlook etkinlikleri yalnız gösterilir; dokununca ayrıntı sayfası (salt okunur).

## 4. Toplantı notu

### 4.1 Akış

1. Notlar sekmesinin üstünde **Notlar · Toplantılar** segmenti. Toplantılar'da "Dinlemeyi başlat"
   mikrofon düğmesi. Ayrıca App Intent **"Toplantıyı dinle"** (Kestirmeler, Eylem Düğmesi, Siri);
   intent uygulamayı açar ve dinlemeyi başlatır. Görev mikrofonu ve kestirmesi aynen kalır.
2. Dinleme ekranı: canlı transkript (paragraflar, zaman damgalı), geçen süre, büyük **Bitir** düğmesi,
   **Duraklat**. Ekran kilitlenince dinleme sürer (arka plan ses kipi; iOS'un mikrofon göstergesi açık).
3. Bitirince toplantı notu kaydedilir ve **sonuç ekranı** açılır:
   - Başlık (varsayılan: "Toplantı — 27 Kas 14:00", düzenlenebilir), süre, transkript.
   - **Önerilen görevler** (Apple Intelligence varsa): her biri tek dokunuşla eklenir; liste/kutu ve
     varsa saat önerisiyle gelir, kullanıcı ekleme sırasında değiştirebilir.
   - Her paragrafta / seçilen metinde **Plana ekle**: sesli eklemedeki liste ve kutu seçim akışı.
4. Toplantılar listesinde her toplantı bir kart; aranabilir.

Onay hatırlatması **yok** (sahip: toplantılar Teams içinde zaten rızayla kaydediliyor).

### 4.2 Teknik

- **iOS 26:** `SpeechAnalyzer` + `SpeechTranscriber` (uzun kayıt, cihaz üzerinde); `SpeechTranscriber`
  bu cihazda kullanılamıyorsa (`isAvailable == false`) `DictationTranscriber` yedeği. Dil: dinleme
  ekranında dil seçici, varsayılanı uygulamanın dili (`AppSettings.language`), seçim hatırlanır;
  `supportedLocale(equivalentTo:)` ile eşlenir; model yoksa `AssetInventory` ile
  indirilir, inmezse açık bir mesaj ("Bu dil için yazıya dökme modeli indirilemedi").
- iOS 26 altında toplantı özelliği görünür ama "iOS 26 gerekir" der.
- **Öneriler:** Foundation Models (`SystemLanguageModel.default`), `availability == .available` ve
  `supportsLocale` doğruysa. Transkript bölümler halinde (bağlam penceresine sığacak kadar) işlenir;
  çıktı `@Generable` yapı: `[{title, dueHint?, quadrantHint}]`. Model yoksa öneri bölümü gizlenir.
- Ses hiçbir zaman diske yazılmaz; yalnız metin saklanır. Ağ isteği yok.
- Swift köprüsü: `app.pamnot/meeting` kanalı (`start`, `pause`, `resume`, `stop`, `suggest`) ve
  olay akışı (`partial`, `final`, `level`, `error`, `interrupted`). Kesinti (telefon çağrısı) gelirse
  dinleme duraklar, kullanıcı devam ettirir; o ana kadarki metin korunur.
- Süre hedefi 2 saat; 30 dakikada bir transkript ara kaydı (çökme olursa kayıp ≤ 30 sn hedefi için
  kesinleşen her paragraf anında kaydedilir). Pil %20 altındaysa uyarı.

### 4.3 Veri

`Meeting {id, title, startedAt, duration, locale, segments:[{start, text}], addedTaskIds, updatedAt,
deleted}`; anahtar `meetings`. iCloud ile eşitlenir (§5), paylaşılmaz.

## 5. iCloud: eşitleme ve ortak listeler

### 5.1 Yaklaşım (sahip seçti: A)

CloudKit + Apple'ın senkron motoru `CKSyncEngine` (Swift). Dart tarafındaki veri katmanı (JSON
belgeleri, `KeyValueStore`) aynen kalır ve tek doğruluk kaynağı olarak arayüzü besler; Swift köprüsü
değişiklikleri iCloud'a gönderir ve iCloud'dan geleni Dart'a verir.

Değerlendirilip seçilmeyenler: Core Data + `NSPersistentCloudKitContainer` (bütün veri katmanının
Swift'e taşınması ve her okumanın köprüden geçmesi; büyük yeniden yazım, arayüz yavaşlar); kendi sunucu
(Firebase vb.; hesap, maliyet, veri Apple dışına çıkar).

**En düşük iOS 16 → 17** (`CKSyncEngine` 17 ister; widget zaten 17).

### 5.2 Ne eşitlenir

- Listeler, görevler, notlar (mürekkep dahil), anımsatıcılar, alışkanlıklar, toplantı notları.
- Eşitlenmez: ayarlar (cihaza özel), sesli kayıt günlüğü, widget önbelleği, alarm kimlikleri.

### 5.3 Veri modeli değişiklikleri

- Eşitlenen her kayıt: `updatedAt` (UTC), `deleted` (silme işareti; 30 gün sonra temizlenir),
  `changeTag` (CloudKit sistem alanları, köprüde saklanır).
- Göç: mevcut kayıtlara `updatedAt = createdAt ya da şimdi`, `deleted = false`. Bir kez çalışır.
- Hazır listelerin sabit kimlikleri (`personal`, `work`, …) cihazlar arasında aynıdır; eşitlemede
  birleşir. Paylaşımda kimlik **taşınmaz** (bölge adı değiştirilemez, taşıma atomik değil). Alıcı
  tarafta paylaşılan listenin yerel kimliği ad alanlıdır: `shared:<sahipKayıtAdı>:<listeId>`; böylece
  alıcının kendi `shopping` listesiyle çakışmaz.
- Görev yeni alanlar: `assigneeId?`, `assignedBy?`, `createdBy?`, `completedBy?` — hepsi katılımcının
  CloudKit kullanıcı kaydı adı. Köprü açılışta kendi kaydını (`CKContainer.userRecordID`) alır ve
  `__defaultOwner__` görünümünü gerçek adla eşler; "Bana atananlar" bu adla karşılaştırır.
- Atama yalnız daveti kabul etmiş katılımcılara yapılabilir; bekleyen davetliler listede soluk ve
  "Daveti bekliyor" etiketiyle görünür.
- Mürekkepli notlar: çizim verisi kayıt alanına değil `CKAsset` olarak gider (`CKRecord` 1 MB sınırı).

### 5.4 CloudKit yerleşimi

- Kapsayıcı: `iCloud.app.pamnot` (Xcode'da iCloud yeteneği, CloudKit). Uygulama kimliği değişmez.
- **Özel veritabanı:** her liste kendi kayıt bölgesinde (`list-<id>`) — liste kaydı + görevleri.
  Notlar, anımsatıcılar, alışkanlıklar, toplantılar `personal` bölgesinde.
- **Paylaşım:** bir liste paylaşılınca o bölge için bölge çapında `CKShare` oluşur; katılımcılar
  **paylaşılan veritabanından** okur ve yazar. Başka bölgeler görünmez → paylaşılmayan veri hiçbir
  koşulda görünmez.
- Çakışma: alan düzeyinde değil kayıt düzeyinde "son yazan kazanır" (`updatedAt`), tek istisna:
  `done` ve alt görevler birleşir (biri tamamladıysa tamamlanmış kalır, ta ki biri açıkça geri alana
  kadar — geri alma da `updatedAt`'li bir yazımdır). Sunucu sürümü kazanırsa kaybeden sürüm atılmaz:
  yerel "çakışma kopyası" günlüğe yazılır (son 50), Ayarlar > iCloud'da görülebilir.

### 5.5 Paylaşım ve davet

- Liste düzenleyicisinde ve liste sekmesinin menüsünde **Paylaş**. iOS'un sistem paylaşım ekranı
  (`UICloudSharingController` + `CKShare`) açılır: iMessage, WhatsApp, Mail, rehberden
  kişi. İzin: **okuma + yazma**. Davet bağlantısı "yalnız davet edilenler" kipindedir (herkese açık
  bağlantı yok).
- Daveti kabul eden: Pamnot açılır, liste "Benimle paylaşılan" olarak liste çubuğuna kişi simgesiyle
  eklenir. Pamnot yüklü değilse App Store'a gider.
- **Gruplar:** Ayarlar > iCloud > Gruplar. "Aile" gibi bir grup = adlandırılmış katılımcı kümesi
  (uygulama tarafı kolaylık). Paylaşırken grup seçilirse grubun kişileri e-posta/telefonlarıyla
  paylaşıma katılımcı olarak eklenir (`CKFetchShareParticipantsOperation`), sonra paylaşım ekranı tek
  bağlantıyı gönderir — örneğin ailenin WhatsApp grubuna. Bağlantıyı yalnız eklenen kişiler açabilir. Kişiler rehberden
  (`CNContactPicker`, yalnız seçilen kişinin e-posta/telefonu okunur; rehber izni gerekmez) ya da
  önceki paylaşımlardaki katılımcılardan seçilir.
- Yetkiler: katılan herkes görev ekler, düzenler, tamamlar, atar. Kişi çıkarmak, paylaşımı durdurmak ve
  listeyi silmek yalnız sahipte. Katılımcı "Listeden ayrıl" diyebilir.
- Paylaşım durunca liste katılımcıların cihazından kalkar; sahibinde aynen kalır.

### 5.6 Atama

- Paylaşımlı listede görev düzenleyicisinde **Atanan kişi** (katılımcılar + "Kimse"). Kartta avatar
  (baş harfler, katılımcı rengi; erişilebilir etiket "Atanan: Ayşe").
- Alarm/bildirim: atanmışsa yalnız atananın cihazında; atanmamışsa yalnız kuranın (`createdBy`)
  cihazında. Her cihaz, eşitlemeden sonra kendine düşen alarmları kurar ve düşmeyenleri kaldırır.
- Matris üst çubuğunda **Bana atananlar** süzgeci (paylaşımlı liste seçiliyken).
- Bildirimler (yerel, eşitleme sonrası üretilir): "Size bir görev atandı: …" (atanana), "Atadığınız
  görev tamamlandı: …" (`assignedBy`'a). Ayarlar'dan kapatılabilir.

### 5.7 Eşitleme davranışı

- Kurulum yok: iCloud hesabı varsa açılışta otomatik. Ayarlar > iCloud: durum (Açık / iCloud'a giriş
  yapılmadı / Depolama dolu / Son eşitleme 2 dk önce), "Şimdi eşitle", eşitlemeyi kapat.
- Tetikleyiciler: uygulama öne gelince, yerel değişiklikten 2 sn sonra (toplu), CloudKit sessiz
  itme bildirimi (özel ve paylaşılan veritabanında `CKDatabaseSubscription`; kullanıcıdan bildirim
  izni istenmez), arka plan yenileme (`BGAppRefreshTask`).
- Gerekenler (sahip Xcode'da bir kez açar): iCloud (CloudKit, `iCloud.app.pamnot`), Push Notifications
  (`aps-environment`), Background Modes: `remote-notification` ve `fetch`;
  `BGTaskSchedulerPermittedIdentifiers`; `CKSharingSupported = YES`; davet kabulü
  `SceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)` ile.
- Dart → Swift: değişen kayıtların kimlikleri ve JSON'u (yalnız değişenler). Bugün her dilim tek JSON
  belgesi olarak yazılıyor; kayıt düzeyinde değişiklik takibi (kirli kimlik kümesi) yeni bir katmandır
  (`lib/features/sync/`), yerel saklama biçimi değişmez. Swift → Dart: gelen
  kayıtlar topluca, tek `_changed` ile; arayüz bir kez yeniden çizilir.
- Çevrim dışı: değişiklikler kuyrukta kalır (`CKSyncEngine` durumu diske yazılır), bağlantı gelince
  gider.

### 5.8 Güvenlik ve gizlilik

- Veri yalnız kullanıcının iCloud'unda (özel + paylaşılan veritabanı); sunucumuz yok. Herkese açık
  veritabanı **kullanılmaz**.
- Gelen her kayıt Dart'a geçmeden doğrulanır: tür, alan uzunlukları (başlık ≤ 500, not ≤ 100 000
  karakter, alt görev ≤ 200), sayılar ve tarihler aralıkta; bozuk kayıt atlanır ve günlüğe yazılır,
  uygulama çökmez. Paylaşılan veritabanından gelen kayıt, yalnız kendi bölgesindeki listeye yazabilir
  (`listId` bölgeden türetilir, kayıttaki değere güvenilmez).
- `pamnot://` bağlantıları ve davet bağlantısı açılınca hiçbir şey kendiliğinden silinmez ya da
  paylaşılmaz; paylaşım yalnız kullanıcı dokunuşuyla başlar.
- Gizlilik etiketleri ve `PrivacyInfo.xcprivacy` güncellenir: kullanıcı içeriği iCloud'da, izlenme
  yok, üçüncü tarafa veri yok. Uyum belgesine (2026-11-23-app-store-compliance.md) iCloud, paylaşım ve
  toplantı bölümleri eklenir.
- Günlüklere kullanıcı metni yazılmaz (yalnız kimlik ve sayılar).

### 5.9 Performans

- Eşitleme ana iş parçacığında JSON ayrıştırmaz: büyük gelen toplu veri `Isolate.run` ile ayrıştırılır.
- Tek liste değişikliği yalnız o bölgeyi gönderir; tüm belge yeniden yazılmaz.
- 5 000 görev ve 1 000 notla ilk eşitleme hedefi: arayüz 60 fps'te kalır, ilk açılış < 1 sn ek gecikme.

## 6. Kılavuz videosu

`assets/guide/*.mp4` ve PiP oynatma kılavuzdan kaldırılır; "Ayarlar'ı aç" yalnız Ayarlar'ı açar.
`UIBackgroundModes` içindeki `audio` toplantı dinlemesi için kalır (gerekçe uyum belgesinde
güncellenir). PiP eklentisi kodda kalır ama kullanılmaz; sahibin ekran kayıtları gelince yeniden
bağlanır. Varlıklar paketten çıkar (boyut).

## 7. Kod ilkeleri (sahibin "temiz kod, güvenli kod" isteği)

- Her özellik kendi klasöründe: `lib/features/calendar/`, `lib/features/meetings/`,
  `lib/features/sync/` (yeni kod); `AppController` büyümez — yeni durumlar ayrı denetleyicilerde.
- Swift köprülerinde her kanal metodu argümanı doğrular, bilinmeyen metoda `FlutterMethodNotImplemented`
  döner, hata kodları sabit ve belgeli; zorla açma (`!`) yok.
- TDD: Dart tarafı birim ve widget testleri; Swift tarafı için python/ruby kaynak denetimleri genişler.
- Yeni bağımlılık eklenmez (yalnız Apple çerçeveleri).

## 8. Teslim sırası

1. Ortak temel: model alanları (`updatedAt`, `deleted`, atama), göç, iOS 17'ye geçiş, boş videonun
   kaldırılması.
2. Takvim görünümleri.
3. Toplantı notu.
4. iCloud eşitleme (özel veritabanı).
5. Paylaşım, gruplar, atama, bildirimler.
6. Uyum belgesi, gizlilik, TESTING.md cihaz listeleri, güvenlik denetimi. Tek derleme.

## 9. Kararlarım (sahip kontrol etsin)

- Toplantılar, Notlar sekmesinde segment olarak durur (alt menüye beşinci sekme eklenmez).
- Hafta görünümü iPhone dikeyde 3 gün gösterir, yana kaydırılır.
- Çakışmada "son yazan kazanır", tamamlanma birleşir; kaybeden sürüm günlüğe yazılır.
- Silinen kayıt 30 gün işaretli tutulur.
- Gruplar uygulama tarafında; Apple Aile Paylaşımı grubu otomatik çekilmez (CloudKit buna izin vermez).
- En düşük iOS 17.

## 10. Riskler

- Türkçe `SpeechTranscriber` modeli bazı cihazlarda inmeyebilir (Apple forumlarında başka diller için
  bildirildi) — cihazda denenir; olmazsa açık mesaj.
- Swift kodu yalnız sahibin Mac'inde derlenir; CloudKit şeması ilk çalıştırmada geliştirme ortamında
  oluşur, App Store'a çıkmadan önce CloudKit Console'da **üretime aktarılmalı** (adım TESTING.md'ye).
- Paylaşım testi iki ayrı Apple Kimliği ve iki cihaz ister.
