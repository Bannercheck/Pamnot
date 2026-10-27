# Pamuk ☁️

Yumuşacık bir not, takip, planlama ve anımsatıcı uygulaması. Tek Flutter kod
tabanından **iPhone, iPad, macOS, Android, Windows** (ve Linux/web) üzerinde
çalışır. Arayüz Türkçe ve İngilizce.

## Özellikler

| | |
|---|---|
| **Notlar** | Yazı ve el yazısı notları, pastel renkler, sabitleme, arama, masonry ızgara. |
| **Apple Pencil / kalem** | Basınca duyarlı mürekkep, fosforlu kalem, silgi (kalemin silgi ucu da çalışır), geri al / yinele, kâğıt tipleri (düz, çizgili, kareli, noktalı). Kalem algılanınca avuç içi reddi otomatik açılır: kalem çizer, parmak kaydırır. |
| **El yazısını yazıya çevirme** | iPad, iPhone ve Android'de cihaz üstü ML Kit ile (TR ve EN modelleri). iPad'de metin alanlarına doğrudan Apple Pencil ile de yazılabilir (Karalama/Scribble). |
| **Kelime tahmini (TR + EN)** | Klavyenin üstünde 3 öneri. Kelime tamamlama, sonraki kelime önerisi, Türkçe harf katlama (`gorusme` → `görüşme`), tek harf yazım hatası toleransı, Türkçe büyük/küçük harf kuralları (i/İ, ı/I). Notlarınızdan ve görevlerinizden öğrenir. Donanım klavyesinde Tab ilk öneriyi alır. |
| **Takip** | Görevler (tarih, saat, öncelik, alt görevler, renk, hatırlatma), kaydırarak silme ve geri alma. Alışkanlıklar: haftalık hedef halkası ve seri 🔥. |
| **Hızlı ekleme** | "yarın 10:00 toplantı", "cuma saat 14 sunum", "call mom tomorrow 6pm" gibi doğal dil ile tarihli görev. |
| **Plan** | Hafta şeridi ve ay görünümü, günün zaman çizelgesi (görevler ve tekrarlayan anımsatıcılar). |
| **Anımsatıcılar** | Bir kez / her gün / her hafta / her ay / her yıl. Uygulama kapalıyken de yerel bildirim. |
| **Widget** | Ana ekran widget'ı "Bugün": iOS'ta küçük, orta, büyük ve kilit ekranı; Android'de küçük ve orta. |
| **Tema** | Krem, lavanta, şeftali ve mint tonları; Nunito yazı tipi; açık ve koyu tema. |

Veriler yalnızca cihazda saklanır.

## Performans

Akıcılık tasarımın parçası, sonradan eklenmedi:

- **Mürekkep:** Her çizgi tek bir `Float32List` olarak tutulur. Biten çizgiler önbellekli bir resme
  eklenir; sayfa ne kadar dolu olursa olsun kalem hareket ederken her karede yalnızca o an çizilen
  çizgi yeniden çizilir. Diske ikili formatta yazılır; her notun mürekkebi ayrı belgededir.
- **Kayıt:** Değişiklikler 400 ms sonra toplu yazılır, uygulama arka plana geçerken hemen yazılır.
  Dosyaya yazma atomiktir (önce geçici dosya, sonra yeniden adlandırma). Büyük mürekkep sayfaları
  arka plan isolate'ında kodlanır.
- **Kelime tahmini:** Sözlükler arka planda yüklenip indekslenir. Öneri, ikili arama ile bir
  milisaniyenin çok altında hesaplanır (testte debug VM'de tuş başına ~0,1 ms). Kullanıcı modeli
  arka plan isolate'ında yeniden öğrenilir.
- **Yeniden çizim:** Ekranlar yalnızca okudukları veri dilimine abonedir (`AppScope.of(context, {Slice.tasks})`).
  Bir görev değişince not ekranı yeniden çizilmez. Listeler tembeldir (sliver). Sekmeler ilk
  açıldıklarında oluşturulur.
- iPhone'da 120 Hz ProMotion açık (`CADisableMinimumFrameDurationOnPhone`). Impeller varsayılan.

Performansı her zaman `flutter run --release` ya da `--profile` ile değerlendirin; debug modu
bilerek yavaştır.

## Çalıştırma

```bash
flutter pub get
flutter run                 # bağlı cihaz / simülatör
flutter run -d macos        # Mac
flutter run -d windows      # Windows
flutter run -d chrome       # hızlı önizleme (web)
flutter test                # 47 test
```

Flutter 3.47 / Dart 3.13 ile geliştirildi.

### Platform notları

- **iOS widget'ı:** Swift kodu `ios/PamukWidget/` içinde hazır. Widget extension hedefi Xcode'da bir
  kez eklenmeli; adımlar [`ios/PamukWidget/README.md`](ios/PamukWidget/README.md) dosyasında. App Group:
  `group.app.pamuk.shared`.
- **iOS dağıtım hedefi** 16.0 (kilit ekranı widget'ları ve ML Kit için).
- **ML Kit el yazısı modelleri** ilk kullanımda indirilir (dil başına yaklaşık 20 MB). Ayarlar'dan önceden
  indirilebilir. ML Kit Apple Silicon üzerindeki iOS simülatöründe çalışmayabilir; gerçek cihazda deneyin.
- **Android:** Android 13+ bildirim izni anımsatıcı eklerken istenir. Tam zamanlı alarm izni varsa
  `exactAllowWhileIdle`, yoksa `inexactAllowWhileIdle` kullanılır.
- **Windows/Linux:** Bildirimler çalışır. Tekrarlayan anımsatıcılarda sıradaki tekrar kurulur ve
  uygulama her açıldığında yeniden planlanır.
- **macOS/Windows widget'ı** ve **Windows'ta el yazısı tanıma** sonraki adımlar arasında.

## Yapı

```
lib/
  core/          tarih yardımcıları, Türkçe metin işlemleri, doğal dil tarih ayrıştırıcı
  models/        Note, InkStroke (+ ikili codec), TaskItem, Reminder, Habit, AppSettings
  data/          anahtar-değer deposu (cihazda dosya, web'de tarayıcı depolama)
  prediction/    sözlük ve kelime tahmin motoru
  services/      bildirimler, widget senkronu, el yazısı tanıma
  state/         AppController (tüm durum ve yan etkiler), AppScope, ilk açılış örnekleri
  theme/         pastel palet, açık/koyu tema
  ui/            bugün, notlar (+ mürekkep tuvali), takip, plan, anımsatıcılar, ayarlar
assets/
  lexicon/       tr.txt, en.txt (sıklık sıralı), *_phrases.txt (sonraki kelime tohumları)
  fonts/         Nunito (SIL Open Font License 1.1)
```
