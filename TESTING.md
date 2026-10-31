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

**Genel**
- [ ] Ayarlar'dan dili (Türkçe/English) ve temayı (açık/koyu) değiştirin.
- [ ] Uygulamayı tamamen kapatıp açın: tüm veriler yerinde olmalı.
- [ ] Android'de ana ekrana **Pamnot · Bugün** widget'ını ekleyin. Görev ekleyip tamamlayınca
      widget güncellenmeli; widget'a dokununca uygulama Bugün ekranında açılmalı.

Bir sorun görürseniz ekran görüntüsü ve kısa bir açıklama yeterli: hangi cihaz, ne yaptınız,
ne bekliyordunuz.
