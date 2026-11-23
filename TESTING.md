# Pamnot'u test etmek

Her push'ta GitHub Actions uygulamayı analiz eder, testleri çalıştırır ve test sürümlerini
derler (bkz. `.github/workflows/build.yml`). Derlenen dosyalar çalıştırmanın sayfasında,
**Artifacts** bölümündedir: GitHub'da **Actions → Build → son çalıştırma**.

| Artifact | İçinde |
|---|---|
| `pamnot-android` | Android APK'ları. Telefonların çoğu için `app-arm64-v8a-release.apk`. |
| `pamnot-macos` | `Pamnot-macos.zip` (imzasız Mac uygulaması) |
| `pamnot-windows` | Windows uygulaması: klasördeki `pamnot.exe` |
| `pamnot-web` | Web sürümü (herhangi bir statik sunucuyla açılır) |

macOS, iOS ve Windows işleri daha pahalı Actions dakikası kullandığı için yalnızca `main`
dalında, etiketlerde, elle başlatıldığında (**Run workflow**) ya da commit mesajında
`[full-build]` geçtiğinde çalışır. Android ve web her push'ta derlenir.

## Kurulum

### Android
1. APK'yı telefona indirin ve açın.
2. Sorulursa tarayıcıya ya da dosya yöneticisine **bilinmeyen uygulamaları yükleme** izni verin.
3. Her derleme farklı bir anahtarla imzalandığından, yeni bir test sürümü kurmadan önce eskisini
   kaldırmanız gerekebilir.

### iPhone ve iPad (Mac ve Xcode gerekir)
iOS uygulamaları cihaza yalnızca Xcode ile imzalanarak kurulabilir.

```bash
git clone https://github.com/Bannercheck/Pamnot.git && cd Pamnot
flutter pub get
open ios/Runner.xcworkspace
```

1. Xcode'da **Runner → Signing & Capabilities** altında **Team** olarak Apple kimliğinizi seçin.
   Ücretsiz hesap da olur. Bundle ID başka bir hesapta kayıtlıysa sonuna bir ek getirin
   (ör. `app.pamnot.pamnot.test`).
2. iPad/iPhone'u kabloyla bağlayın. Cihazda **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu**
   açık olmalı.
3. Terminalde `flutter run --release` komutunu çalıştırın (birden çok cihaz varsa `-d <cihaz>`).
4. Ücretsiz hesapla ilk açılışta **Ayarlar → Genel → VPN ve Aygıt Yönetimi** altında
   geliştiriciye güvenin. Ücretsiz hesapla kurulan uygulama 7 gün sonra yeniden kurulmalıdır.

Ana ekran widget'ı için Xcode'da extension hedefi eklemek ve App Group kullanmak gerekir. Bu,
ücretli Apple Developer üyeliği ister: [`ios/PamnotWidget/README.md`](ios/PamnotWidget/README.md).

### Mac
- **Hazır sürüm:** `pamnot-macos` içindeki zip'i açın. Uygulama imzasız olduğu için ilk açılışta
  macOS engeller: **Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç** deyin. Alternatif olarak
  Terminal'de `xattr -dr com.apple.quarantine Pamnot.app` çalıştırın.
- **Kaynaktan:** `flutter run -d macos --release`.

### Windows
`pamnot-windows` klasörünü açın ve `pamnot.exe`'yi çalıştırın. SmartScreen uyarısında
**Ek bilgi → Yine de çalıştır** deyin. `data` klasörü ve DLL'ler `.exe` ile aynı yerde kalmalı.

## Neyi denemeli

**Kelime tahmini**
- [ ] Bir notta "Yarın sabah topl" yazın: toplantı / toplantıya / toplantısı önerilmeli.
- [ ] "gorusme" yazın: "görüşme" önerilmeli.
- [ ] "alışveriş " yazın (boşlukla): "listesi" önerilmeli.
- [ ] İngilizce bir cümle yazın: öneriler İngilizceye geçmeli.
- [ ] Klavyeli cihazda Tab tuşu ilk öneriyi almalı.
- [ ] Notlarda sık yazdığınız bir kelime birkaç saniye sonra önerilerde öne çıkmalı.

**Apple Pencil ve el yazısı**
- [ ] Kalem modunda yazın: çizgi kalınlığı bastırma kuvvetine göre değişmeli.
- [ ] Kalem ilk kez algılandığında "yalnızca kalem çizer" bildirimi çıkmalı. Sonra avucunuz
      ekrana değse de çizmemeli, parmakla sayfa kayabilmeli.
- [ ] Fosforlu kalem, silgi, geri al/yinele, renk ve kalınlık seçimleri çalışmalı.
- [ ] Sayfayı doldurup hızlı yazmaya devam edin: gecikme ya da takılma olmamalı.
- [ ] **Yazıya çevir** (iPad/iPhone/Android): ilk kullanımda dil modeli indirilir, internet
      gerekir.
- [ ] Notu kapatıp açın: mürekkep ve yazı korunmalı.

**Takip, plan ve anımsatıcılar**
- [ ] Bugün ekranındaki hızlı eklemeye "yarın 10:00 diş hekimi" ve "cuma saat 14 sunum" yazın:
      görevler doğru gün ve saatte görünmeli.
- [ ] Görev tamamlayın, kaydırarak silin ve **Geri al** deyin.
- [ ] Alışkanlıkta günleri işaretleyin; seri sayacı değişmeli.
- [ ] Plan'da hafta ve ay görünümü arasında geçin, bir güne görev veya anımsatıcı ekleyin.
- [ ] 2 dakika sonrası için anımsatıcı kurun ve uygulamayı kapatın: bildirim gelmeli.
      İlk seferde bildirim izni istenir. Ayarlar'daki **Deneme bildirimi gönder** de işe yarar.
- [ ] Her gün tekrarlayan bir anımsatıcı kurun.

**Sesle görev ekleme (iPhone)**

Not: `main`'e birleştirmeden önce bu liste cihazda geçilir.

- [ ] Kestirmeler uygulamasında Pamnot altında **Sesle Görev Ekle** eylemi görünmeli (Spotlight'ta
      da).
- [ ] Eylem düğmesine **Sesle Görev Ekle**'yi atayın (Eylem düğmesi olan iPhone'larda): düğmeye
      basınca Sesle ekle ekranı açılıp dinlemeye başlamalı.
- [ ] Arkaya Dokunma: önce Kestirmeler'de tek eylemli bir kestirme oluşturun (Pamnot > Sesle Görev
      Ekle), sonra **Ayarlar > Erişilebilirlik > Dokunma > Arkaya Dokunma**'da onu seçin. Telefonun
      arkasına dokununca ekran açılıp dinlemeli.
- [ ] Sesle Denetim: Pamnot'un Ayarlar > Sesle ekleme bölümündeki adımlarla bir komut kurun.
      Komutu söyleyince ekran açılıp dinlemeli (Sesle Denetim mikrofonu kendisi de kullanır).
- [ ] Siri'ye "Pamnot ile görev ekle" deyin: ekran açılmalı.
- [ ] Bugün ekranındaki hızlı eklemede mikrofon düğmesine dokunun: ekran açılmalı.
- [ ] Safari'nin adres çubuğuna `pamnot://ses` yazın: Pamnot Sesle ekle ekranıyla duraklatılmış açılmalı
      ("Devam etmek için dokun"); mikrofona dokunmadan dinlememeli. Ekran kapanınca altta tek bir ana
      ekran kalmalı; ikinci bir ana ekran açılmamalı.
- [ ] "yarın akşam yedide annemi ara" deyin: önizlemede **Yarın 19:00** ve zil simgesi (hatırlatma
      açık) görünmeli.
- [ ] "saat üçte dişçi" deyin: önizlemede **15:00 ?** görünmeli (saat tahmini).
- [ ] Önizlemede **Düzelt**'e dokunun: metni düzeltip kaydedebilmelisiniz.
- [ ] Önizlemedeyken ekranı ✕ ile kapatın: görev kaydedilmemeli.
- [ ] Bir görev söyleyip hemen telefonu kilitleyin: görev kaydedilmeli. Geri dönünce
      **Kilitlenirken kaydedildi** görünmeli; mikrofon kendiliğinden açılmamalı.
- [ ] Bildirim izni hiç sorulmamışken saatli bir görev söyleyip ("yarın 10'da toplantı") hemen
      kilitleyin: geri dönünce bildirim izni sorulmalı, mikrofon kapalıyken.
- [ ] Ekran açık ve **Duraklatıldı** yazarken Eylem düğmesine (ya da kestirmeye) yeniden basın:
      dinleme başlamalı. Dinlerken basınca bir şey değişmemeli.
- [ ] Bir cümlenin yarısında uçak modunu açın: söylenen kaybolmamalı; önizlemede geri sayım olmadan
      **Kaydet** ile kaydedilebilmeli.
- [ ] Mikrofon ya da Konuşma Tanıma iznini reddedin: ekranda **Ayarlar'ı Aç** çıkmalı ve iOS
      Ayarlar'da Pamnot'u açmalı. Sistem izni bir daha sorulmamalı.
- [ ] **Ayarlar > Genel > Klavye**'de Dikte kapalıyken ekranı açın: Dikte'yi açmaya yönlendirmeli.
- [ ] VoiceOver açıkken bir görev söyleyin: önizlemede geri sayım olmamalı; görev **Kaydet** ile
      kaydedilmeli. Dinleme başlarken VoiceOver "Dinliyorum" dememeli ve tanınan metne VoiceOver'ın
      sesi karışmamalı.
- [ ] Pamnot'ta **Ayarlar > Sesle ekleme > Tanınan metinleri sakla**'yı açın ve birkaç gerçek görev
      söyleyin. **Son tanınanlar** listesinde saatlerin nasıl yazıldığına bakın ("10'da" mı, "onda"
      mı) ve örnekleri paylaşın; ayrıştırıcı gerekirse bunlara göre düzeltilir. **Temizle** listeyi
      boşaltmalı.

Ücretsiz Apple kimliğiyle kurulan uygulama 7 günde bir yeniden kurulur. Uygulama silinip
kurulursa Eylem düğmesine ve Arkaya Dokunma'ya atanan kestirme yeniden seçilmelidir.

**Genel**
- [ ] Ayarlar'dan dili (Türkçe/English) ve temayı (açık/koyu) değiştirin.
- [ ] Uygulamayı tamamen kapatıp açın: tüm veriler yerinde olmalı.
- [ ] Android'de ana ekrana **Pamnot · Bugün** widget'ını ekleyin. Görev ekleyip tamamlayınca
      widget güncellenmeli; widget'a dokununca uygulama Bugün ekranında açılmalı.

Bir sorun görürseniz ekran görüntüsü ve kısa bir açıklama yeterli: hangi cihaz, ne yaptınız,
ne bekliyordunuz.

## Yayın (App Store)

Mağaza sürümü ücretsiz Apple kimliğiyle gönderilemez ve Mac'te Xcode 26 ya da sonrası gerekir.
App Store Connect yanıtları ve inceleme notu taslağı:
[uyum belgesi](docs/superpowers/specs/2026-11-23-app-store-compliance.md) §5.

1. Apple Developer Program üyeliği; App Store Connect'te uygulama kaydı (bundle ID
   `app.pamnot.pamnot`).
2. `pubspec.yaml` içindeki `version:` her yüklemede artan bir derleme numarası alır (`1.0.0+2`, …).
3. Xcode 26+: `flutter build ipa --release`, sonra Transporter ya da Organizer ile yükleyin.
4. Önce TestFlight (dahili test): gerçek cihazda bu dosyadaki kontrol listeleri ve uyum belgesinin
   §3 ve §4 maddeleri. **Xcode > Product > Archive > Generate Privacy Report** ile (Organizer'da
   arşivin üzerinde) ML Kit bildirimlerini doğrulayın.
5. App Store Connect alanları doldurulur (App Privacy, yaş derecelendirmesi, kategori, ekran
   görüntüleri, destek ve gizlilik adresi, inceleme notu), sonra **Submit for Review**. Gizlilik
   adresi [`PRIVACY.md`](PRIVACY.md)'nin GitHub sayfasıdır (`lib/services/links.dart`); depo
   herkese açık değilse oradaki iki sabit değiştirilir.
6. `CLAUDE.md` kuralı: yayından önce `security-audit` tam denetimi çalıştırılır.
