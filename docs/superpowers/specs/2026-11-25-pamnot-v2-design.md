# Pamnot v2 — tasarım

Tarih: 2026-11-25 · Dal: `claude/pamnot-v2` (taban: `claude/voice-capture` 1dec309)

## 1. Amaç ve neden

TestFlight'taki ilk sürümü kullanan sahip şunları istedi: işlerini listelere ayırıp her listeyi
Eisenhower matrisiyle yönetmek, iOS 26 hissi veren cam (Liquid Glass) görünüm, gönderdiği tasarımdaki
gibi alt menü, ana ekran widget'ı, telefon ve Outlook takvimini görmek, hatırlatmaların gerçek alarm
gibi çalması, her gün bir motivasyon bildirimi, kestirme kurulumunu anlatan bir kılavuz ve sesle
eklerken görevin nereye gideceğini seçebilmek. Öncelik iPhone; iPad ve Mac aynı kodu kullanacak.

## 2. Kapsam

Bu belge yedi parçayı tanımlar; teslim sırası §11'de.

1. Listeler ve her listenin kendi Eisenhower matrisi (ana ekran).
2. Cam görünüm (Liquid Glass benzeri) ve yeni alt menü.
3. Sabitlenen notu kaldırma.
4. Sesle eklemede liste ve kutu seçimi.
5. Hatırlatma alarmı (AlarmKit) ve günlük motivasyon bildirimi.
6. Task listesi widget'ı (küçük, orta, büyük).
7. Takvim erişimi (iPhone takvimi; Outlook dahil).
8. Kestirme kurulum kılavuzu (adım kartları, düğmeler, PiP video).

Hedef dışı: iCloud eşitlemesi (ayrı tasarım, sonra), hesap ve giriş, Microsoft girişiyle Outlook
API'si, Android/Windows'ta yeni özellikler (oralarda bozulmamaları yeterli), panolar dalının
(`claude/boards`) ortak çalışma özelliği.

Anti-hedefler: mevcut görev, not ve hatırlatıcıların kaybolması; ana ekranın takılması (matris
yüzlerce kartta akıcı kalmalı); kullanıcıyı bildirim ve alarm izniyle ilk açılışta bunaltmak.

## 3. Listeler ve Eisenhower matrisi

### 3.1 Veri

- Yeni model `TaskList {id, name, colorIndex, icon, order, builtIn}`; kalıcı anahtar `lists`.
- Hazır listeler (ilk açılışta oluşur, `builtIn: true`): **Kişisel, İş, Okul, Alışveriş, Ev**
  (EN: Personal, Work, School, Shopping, Home). Yeniden adlandırılabilir, renk/simge değişebilir,
  silinebilir; en az bir liste her zaman kalır.
- `TaskItem` iki alan kazanır: `listId` ve `quadrant` (`enum Quadrant { doNow, plan, delegate, later }`).
- Göç: eski görevlerin hepsi `Kişisel` listesine ve `plan` kutusuna gider. `Priority.high` olanlar
  `doNow`'a. Göç bir kez çalışır, eski JSON okunabilir kalır.

### 3.2 Kutu başlıkları (sahibin isteği: "yap" gibi emir kipi değil)

| Kutu | TR başlık | EN başlık | Alt satır (TR) |
| --- | --- | --- | --- |
| `doNow` | **Önemli · Acil** | Important · Urgent | Bugün ilgilen |
| `plan` | **Önemli · Planlı** | Important · Planned | Zamanını belirle |
| `delegate` | **Acil · Önemsiz** | Urgent · Less important | Kısa tut ya da paylaş |
| `later` | **Sonra · Belki** | Later · Maybe | Gerekirse dön |

### 3.3 Ana ekran (Takip sekmesinin yerine "Matris")

```
 ┌ cam üst çubuk ───────────────────────────────┐
 │ [Kişisel] [İş] [Okul] [Alışveriş] [Ev] [ + ] │  ← kaydırılabilir cam sekmeler
 └───────────────────────────────────────────────┘
 ┌──── Önemli · Acil ────┐┌──── Önemli · Planlı ──┐
 │ kart  kart            ││ kart                  │   her kutu cam panel,
 │ + ekle                ││ + ekle                │   kendi içinde kaydırılır
 └───────────────────────┘└───────────────────────┘
 ┌──── Acil · Önemsiz ───┐┌──── Sonra · Belki ────┐
 │ …                     ││ …                     │
 └───────────────────────┘└───────────────────────┘
```

- Telefonda 2×2 ızgara; dar ekranda ve büyük yazıda kutular alt alta tek sütun.
- Kart: başlık, varsa tarih/saat çipi, alt görev sayısı, bitti onay kutusu. Dokununca mevcut görev
  düzenleyici açılır.
- Sürükle-bırak: kart başka kutuya taşınır (uzun basınca kalkar, dokunsal geri bildirim). Kutu içi
  sıra korunur (`order` alanı).
- Uzun basma menüsü: "Başka listeye taşı…", "Bitti", "Sil".
- Biten görevler kutunun altında katlanmış "Biten (n)" bölümünde.
- Liste yönetimi: sekmelerde **+** yeni liste; sekmeye uzun basınca adlandır/renk/simge/sil.
- Bugün ekranı tüm listelerden bugünün görevlerini gösterir, her satırda küçük liste rengi noktası.
- Alışkanlıklar mevcut yerinde kalır (Takip sekmesindeki "Alışkanlıklar" Matris ekranının üst
  sağ menüsüne taşınır).

## 4. Cam görünüm ve alt menü

- Flutter'da iOS 26'nın sistem camı yok; yaklaşık görünüm: `BackdropFilter` bulanıklığı (σ≈20),
  yarı saydam beyaz/koyu dolgu, ince parlak kenar çizgisi ve üstte hafif ışık geçişi. Tek bir
  `GlassPanel` bileşeni; Matris kutuları, sekmeler, üst çubuk ve alt menü bunu kullanır.
- Performans: aynı anda en fazla birkaç bulanık katman; kartlar düz renkli (cam değil) kalır.
  "Saydamlığı Azalt" açıksa (iOS erişilebilirlik) cam yerine düz yüzey.
- Alt menü, sahibin gönderdiği tasarımın orta (açık) satırı + alt satırının orta düğmesi:
  - Sekmeler: **Bugün, Notlar, [mikrofon], Matris, Plan**. Hatırlatmalar Plan'ın içine, Ayarlar üst
    sağ simgeye.
  - Seçili sekme dolu ikon + mor yazı; seçili olmayanlar çizgi ikon + gri yazı.
  - Ortada yükseltilmiş mor yuvarlak düğme: Sesle ekle ekranını açar (iOS'ta), diğer platformlarda
    yeni görev düzenleyicisini açar.
  - Menü cam panel üzerinde, ekranın altında yüzer; içerik arkasından görünür.
  - Koyu tema: tasarımın koyu satırı.

## 5. Sabitlenen notu kaldırma

Bugün ekranında ve Notlar'da sabitli kartta uzun basma menüsü: "Sabitlemeyi kaldır"; ayrıca not
düzenleyicinin raptiye simgesi aç/kapa olarak kalır. Geri al snack'i.

## 6. Sesle eklemede liste ve kutu seçimi

- Konuşma bitince önizleme kartında otomatik 2 sn kayıt **yerine** seçim satırları gelir:
  - "Liste": liste çipleri (son kullanılan önde seçili).
  - "Kutu": dört kutu çipi (varsayılan `plan`; söylenen saat bugünse `doNow`).
  - "Ekle" düğmesi. Bir liste çipine dokunmak tek başına da kaydeder (hızlı yol).
- Cümlede liste adı geçiyorsa ("alışveriş listesine ekmek ekle", "işe toplantı notu") ayrıştırıcı
  listeyi seçili getirir ve başlıktan adı siler.
- Kestirmeden açılan oturumda da aynı akış. Eller serbest kullanım için: 8 sn içinde seçim
  yapılmazsa son kullanılan listeye ve varsayılan kutuya kaydedilir (bu süre Ayarlar'da kapatılabilir).
- Kilitleme kuralı (önceki tasarım §6.6) aynen: arka plana gidince son kullanılan listeye kaydedilir.
- "Düzelt"te liste ve kutu satırları kalır: seçim yalnız seçer (sayaç yok), metinde yeni geçen liste adı
  seçimi yeniden eşleştirir; "Kaydet" kaydeder.
- Kayıttan sonra (liste çipi, "Ekle", 8 sn, "Düzelt" sonrası "Kaydet") mikrofon **yeniden açılmaz**
  (sahibin kararı R10). Ekran ~1,2 sn "Eklendi" (başlık ve liste) gösterir, kapanır, özet snack'i çıkar.
  Bu arada "Bir tane daha" düğmesi dinlemeyi yeniden başlatır; tek yol budur. VoiceOver açıkken ekran
  kendiliğinden kapanmaz. Ayrıntı: önceki tasarım §5 adım 5-7.

## 7. Hatırlatma alarmı ve motivasyon bildirimi

### 7.1 Alarm (iOS 26+)

- Görev ya da hatırlatıcı düzenleyicisinde "Uyarı türü": **Bildirim** (varsayılan) / **Alarm**.
- Alarm seçilirse AlarmKit ile Saat uygulamasının alarmı gibi çalar: sessiz modda da sesli, kilit
  ekranında tam ekran, "Ertele" ve "Kapat" düğmeleri. Ses: sistemin standart alarm sesi (iOS
  uygulamalara diğer sistem seslerini seçtirmez).
- İzin (AlarmKit yetkisi) ilk kez Alarm seçildiğinde istenir; reddedilirse bildirime düşer.
- iOS 26 altında Alarm seçeneği gizli. Swift tarafı küçük bir yerel eklenti (iOS ve ileride macOS).

### 7.2 Günlük motivasyon bildirimi

- Ayarlar > Bildirimler: "Günlük motivasyon" anahtarı (varsayılan **açık**, ilk planlı bildirim
  izni verildikten sonra), saat seçimi (varsayılan 09:00).
- Uygulamayla gelen 120 kısa, yumuşak TR/EN cümleden biri; aynı cümle 30 gün tekrar etmez. Mevcut
  bildirim zamanlayıcısına ayrı bir anahtarla (`m:yyyy-mm-dd`) eklenir; önümüzdeki 7 gün kurulur.
- Bildirime dokununca Bugün ekranı açılır.

## 8. Widget'lar

- WidgetKit uzantısı (mevcut `ios/PamnotWidget` kaynakları genişletilir). Aileler: küçük, orta,
  büyük; kilit ekranı aileleri mevcut haliyle kalır.
- Yapılandırma (App Intent): hangi liste ve hangi kutular ("Tümü" ya da tek kutu).
  - Küçük: liste adı + en önemli 3 görev + kalan sayısı.
  - Orta: iki sütun (Önemli · Acil ve Önemli · Planlı), sütun başına 3 görev.
  - Büyük: 2×2 mini matris, kutu başına 3 görev.
- Satıra dokunmak (iOS 17+ etkileşimli widget) görevi bitti yapar; başka yere dokunmak o listeyi açar.
- Veri: App Group (`group.app.pamnot.shared`) içinde liste başına özet JSON; uygulama her değişiklikte
  yazar. Ücretli hesap olduğu için App Group artık kullanılabilir.
- Xcode'da widget hedefinin bir kez eklenmesi gerekir (hedef pbxproj'a betikle eklenebiliyorsa
  betikle; değilse adım adım kılavuz). Widget'lar iOS 26'da sistem cam görünümünü kendiliğinden alır.

## 9. Takvim

- iPhone takvimi EventKit ile okunur. Outlook hesabı iPhone Ayarlar > Takvim > Hesaplar'a eklenmişse
  Outlook etkinlikleri de buradan gelir; Microsoft girişi gerekmez. Kılavuz bunu tek adımla anlatır.
- İzin: tam erişim (iOS 17+ `requestFullAccessToEvents`), Plan ekranında "Takvimi göster"e ilk
  dokunuşta istenir. Purpose string TR/EN.
- Plan ekranı günlük/haftalık görünümde takvim etkinliklerini görevlerin yanında, takvim renginde,
  salt okunur gösterir. Ayarlar'da hangi takvimlerin görüneceği seçilir.
- Yazma (etkinlik oluşturma) bu sürümde yok.

## 10. Kestirme kurulum kılavuzu

- Ayarlar > "Kestirmeler ve Siri" ve ilk sesli kullanımdan sonra bir kez gösterilen kart.
- Adım kartları (sahibin gönderdiği LockDay örneği gibi): başlık, "Yapılacak/Tamam" rozeti, açılır
  içerik, numaralı adımlar, telefon + dokunan el animasyonu (Flutter'da çizilmiş, video değil), ve
  düğmeler:
  1. **Sesli görev kestirmesi** — "Kısayolu ekle" (iCloud paylaşım bağlantısı; sahibin bir kez
     oluşturacağı kestirme), "Kısayolu çalıştır" (`shortcuts://run-shortcut?name=…`). Kestirme Pamnot'u
     açınca adım "Tamam" olur.
  2. **Eylem düğmesi** — "Ayarlar'ı aç". Elle "Tamam" işaretlenir.
  3. **Arkaya Dokunma** — "Ayarlar'ı aç". Elle "Tamam".
  4. **Outlook takvimi** — "Ayarlar'ı aç" (Takvim > Hesaplar). Elle "Tamam".
- "Ayarlar'ı aç"a basınca kısa kılavuz videosu Resim içinde Resim (PiP) olarak sağ alt köşede oynamaya
  devam eder (AVPictureInPictureController, yerel eklenti). Videolar uygulamayla gelir (her biri
  ≤ 20 sn, H.264). İlk sürümde videolar, kılavuzdaki animasyondan üretilmiş ekran kayıtlarıdır;
  sahip gerçek iPhone kaydı verirse onlarla değiştirilir.
- PiP için `UIBackgroundModes: audio` gerekir (Apple video PiP için kabul eder); ses kapalı oynatılır.

## 11. Teslim sırası

1. Cam bileşeni + yeni alt menü + sabitlemeyi kaldırma.
2. Listeler + Matris ekranı + göç + sesle eklemede liste/kutu seçimi.
3. Günlük motivasyon bildirimi + alarm (AlarmKit).
4. Takvim.
5. Widget'lar.
6. Kestirme kılavuzu + PiP.

Her adım ayrı commit dizisi, testler geçer, CI'da iOS derlemesi doğrulanır; her adımdan sonra
TestFlight için derleme numarası artırılır.

## 12. Kararlarım

1. Hazır listeler: Kişisel, İş, Okul, Alışveriş, Ev; silinebilir.
2. Kutu adları: Önemli · Acil / Önemli · Planlı / Acil · Önemsiz / Sonra · Belki.
3. Yeni görev varsayılan kutusu "Önemli · Planlı"; bugüne saatli görev "Önemli · Acil".
4. Sesle eklemede 8 sn içinde seçim yoksa son kullanılan liste (eller serbest kullanım için).
5. Motivasyon bildirimi varsayılan açık, 09:00.
6. Alarm yalnız iOS 26+; ses sistemin standart alarm sesi.
7. Outlook, iPhone takvim hesabı üzerinden; ayrı giriş yok.
8. Takvim salt okunur.
9. Kılavuz animasyonu çizim, videolar animasyondan üretilir.
10. Sesle eklemede kayıttan sonra mikrofon kendiliğinden açılmaz; ~1,2 sn "Eklendi", sonra ekran kapanır;
    yalnız "Bir tane daha" yeniden dinletir (R10, önceki "kaydet ve yeniden dinle" döngüsünün yerine).

## 13. Riskler

- Cam efekti eski iPhone'larda pahalı olabilir; bulanık katman sayısı sınırlı, gerekirse düşük
  kalite moduna düşülür.
- AlarmKit ve PiP Swift kodu yalnız CI ve sahibin Mac'inde derlenir.
- Widget hedefi pbxproj'a elle eklenmezse widget görünmez; ilk adımda betikle denenir.
- Takvimde çok etkinlik: sorgu yalnız görünen hafta için yapılır.
