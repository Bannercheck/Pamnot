# Panolarda ortak çalışma: kurulum rehberi

Bu rehber, Pamnot'ta panoları ekip arkadaşlarınla paylaşabilmek için gereken sunucuyu **bir kez**
kurman içindir. Teknik bilgi gerekmez; yaklaşık 5 dakika sürer. Uygulamadaki kurulum sihirbazı
(Ayarlar › Ortak çalışma › **Kur**) aynı adımları sırayla gösterir ve her adımda kopyalama düğmesi
sunar. Bu sayfayı sihirbazın yanında açık tutabilirsin.

Kurulumu ekipten **yalnızca bir kişi** yapar. Ekip arkadaşların hiçbir şey kurmaz; senden gelen
davet metnini yapıştırıp adlarını yazarlar, o kadar.

> Pamnot sunucu olarak [Supabase](https://supabase.com)'in ücretsiz planını kullanır. Panoların
> içeriği bu sunucuda, senin hesabında durur. Paylaşmadığın panolar ve notların, görevlerin,
> anımsatıcıların hiçbir zaman cihazından çıkmaz.

---

## 1. adım — Supabase hesabı ve proje

1. Sihirbazda **Adresi kopyala**'ya bas, tarayıcıda aç (ya da doğrudan
   `https://supabase.com/dashboard/projects` adresine git).
2. Ücretsiz bir hesap aç (GitHub ile ya da e-postayla).
3. **New project**'e bas.
   - **Name**: istediğin bir ad, ör. `pamnot-ekip`.
   - **Database password**: istediğin bir şifre (Pamnot'a girmen gerekmeyecek; yine de bir yere
     not et).
   - **Region**: sana en yakın bölge (Türkiye için ör. *Central EU (Frankfurt)*).
4. **Create new project**'e bas ve projenin hazırlanmasını bekle (1–2 dakika).

Sihirbazda **Devam**'a bas.

## 2. adım — Kurulum SQL'ini çalıştır

1. Sihirbazda **SQL'i kopyala**'ya bas. (Kurulum metni uygulamanın içinde gelir; aynı metin
   kaynak kodda `supabase/schema.sql` dosyasındadır.)
2. Supabase panelinde soldaki menüden **SQL Editor**'ü aç.
3. **New query** ile boş bir sayfa aç, kopyaladığın metnin **tamamını** yapıştır.
4. Sağ alttaki **Run** düğmesine bas.
5. Altta **Success. No rows returned** yazısını görürsen tamamdır.

Bu metni tekrar çalıştırmak zararsızdır; hiçbir veriyi silmez. Pamnot ileride “Kurulum SQL’i eski”
derse aynı adımı yeni metinle tekrarlaman yeterli.

Sihirbazda **Devam**'a bas.

## 3. adım — Anonim girişleri aç

Ekip arkadaşların e-posta adresi vermeden, yalnızca adlarıyla katılır. Bunun için:

1. Soldaki menüden **Authentication**'a, sonra **Sign In / Providers**'a git.
2. **Allow anonymous sign-ins** seçeneğini aç.
3. Aynı sayfada **Allow new users to sign up** seçeneğinin de açık olduğundan emin ol.
4. **Save changes**'e bas.

Sihirbazda **Devam**'a bas.

## 4. adım — Sunucu adresi ve anahtar

1. Soldaki menünün en altındaki **Project Settings**'e (dişli simgesi) gir, sonra **API Keys**'e
   geç.
2. **Project URL**'yi kopyala ve sihirbazdaki **Sunucu adresi (Project URL)** alanına yapıştır.
   Adres `https://xxxxxxxxxxxxxxxxxxxx.supabase.co` biçimindedir. Yanlışlıkla tarayıcının adres
   çubuğundaki panel adresini (`supabase.com/dashboard/project/…`) yapıştırırsan da olur; Pamnot
   doğru adresi kendisi çıkarır ve altında “Kullanılacak adres: …” diye gösterir.
3. **Publishable key**'i (`sb_publishable_…` ile başlar) kopyala ve **Publishable anahtar (anon)**
   alanına yapıştır. Eski projelerde bu anahtar **anon** / **public** adıyla, `eyJ…` ile başlayan
   uzun bir metin olarak görünür; o da olur.

> **Dikkat:** **secret** (`sb_secret_…`) ya da **service_role** anahtarını asla kullanma ve kimseyle
> paylaşma. Bu anahtarlar bütün korumaları aşar. Pamnot bunları tanır ve kabul etmez:
> “Bu gizli (secret) anahtar — asla paylaşma!” uyarısını görürsen doğru anahtarı kopyala.

Publishable anahtar gizli değildir: davet metinlerinin içinde zaten bulunur. Panolarını koruyan şey
kurulum SQL'indeki erişim kurallarıdır; bir panoyu yalnızca üyeleri görebilir.

Sihirbazda **Devam**'a bas.

## 5. adım — Adın ve rengin

1. **Adın**: ekip arkadaşların seni bu adla görür (ör. “Ayşe”).
2. **Rengin**: avatarının ve imlecinin rengi.
3. **Bağlan**'a bas.

Pamnot şu kontrolleri sırayla yapar ve her birini ekranda gösterir:

| Ekranda | Ne kontrol ediliyor |
|---|---|
| Sunucuya ulaşılıyor… | Adres doğru mu, anahtar geçerli mi |
| Kurulum kontrol ediliyor… | 2. adımdaki SQL çalıştırılmış mı |
| Giriş yapılıyor… | Anonim giriş açık mı (3. adım) |
| Adın kaydediliyor… | Profilin sunucuya yazılabiliyor mu |

**Hazır 🌸** yazısını gördüğünde kurulum bitti.

---

## Bir panoyu paylaşmak

1. Panoyu aç ve **Paylaş**'a bas.
2. “Pano sunucuya yüklenecek. Davet metnine sahip olan herkes panoyu görebilir ve
   düzenleyebilir.” uyarısını oku ve **Paylaş**'a bas. Yükleme ilerlemesini görürsün.
3. Yükleme bitince davet metni çıkar. **Davet metnini kopyala**'ya bas ve WhatsApp, Telegram,
   e-posta… nereden istersen gönder. Kopyalanan mesaj şöyle görünür:

   ```
   Pamnot’ta «Pano adı» panosuna katıl 🌸
   1. Pamnot’u aç → Takip → Panolar → Davete katıl
   2. Bu metnin tamamını yapıştır:
   PMN1.eyJ1Ijoi…
   ```

Davet metni panoya **düzenleme** erişimi verir; yalnızca birlikte çalışmak istediğin kişilere
gönder.

## Ekip arkadaşların nasıl katılır

1. Pamnot'u açar: **Takip → Panolar → Davete katıl**.
2. **Yapıştır**'a basar (gelen mesajın tamamı yapıştırılabilir; Pamnot daveti içinden bulur).
3. Pano adını ve sunucuyu görür: «Pano adı» · xxxx.supabase.co
4. İlk kez katılıyorsa **Adın** alanına adını yazar.
5. **Katıl**'a basar; pano listesine eklenir ve açılır.

Kurulum, e-posta, şifre yok. Aynı kişi telefonu ve iPad'i gibi iki cihazdan katılırsa, şimdilik iki
ayrı üye olarak görünür.

## Üyeleri yönetmek

Panonun **Paylaş** ekranında **Üyeler** listesi vardır: kimin şu an panoda olduğu (“Şimdi burada”),
kimin çevrimdışı olduğu, pano sahibi (“Sahip”) ve sen (“(sen)”).

Pano sahibi olarak:

- **Panodan çıkar**: bir üyeyi çıkarır. Erişimi hemen kapanır ve davet metni otomatik yenilenir;
  eski davet artık çalışmaz.
- **Daveti yenile**: yeni bir davet metni üretir. Eski metin artık çalışmaz; katılmış olanlar
  panoda kalır. Davetin yanlış yere gittiğini düşünürsen kullan.
- **Herkes için sil** (pano listesinde panoyu silerken): pano herkes için silinir. Bu geri alınamaz.
  Diğer üyeler panonun bir kopyasını kendi cihazlarında saklamayı seçebilir.

Üye olarak:

- **Panodan ayrıl**: panodan çıkarsın ve bu cihazdaki kopyası silinir. Yeniden katılmak için yeni
  davet gerekir.

## Bu cihazın bağlantısını kaldırmak

**Ayarlar › Ortak çalışma › Bu cihazın bağlantısını kaldır**: bu cihaz sunucudan çıkar, ortak
panoların bu cihazdaki kopyaları silinir. Gönderilmemiş değişiklik varsa onay penceresi kaç tane
olduğunu söyler. Yalnızca bu cihazdaki panoların yerinde kalır. Yeniden katılmak için yeni davet
gerekir. Başka bir sunucuya geçmek için de önce bunu yapman gerekir.

---

## Sorun giderme

| Pamnot'un dediği | Ne yapmalı |
|---|---|
| Sunucuya ulaşılamadı. İnternet bağlantını ve adresi kontrol et. | İnternetini kontrol et; 4. adımdaki Project URL'yi yeniden kopyala. Proje duraklatılmışsa (aşağıya bak) panelden geri aç. |
| Anahtar hatalı. / Anahtar tanınmadı. | 4. adımda **Publishable key**'i (ya da eski projelerde **anon** anahtarını) baştan sona eksiksiz kopyala. |
| Bu gizli (secret) anahtar — asla paylaşma! | Yanlış anahtarı kopyaladın. **Publishable** anahtarı kullan. |
| Kurulum SQL’i çalıştırılmamış görünüyor (2. adım). | 2. adımı yap; **Success** yazısını gördüğünden emin ol. Hemen ardından hâlâ görüyorsan 1 dakika bekleyip yeniden dene. |
| Kurulum SQL’i eski; 2. adımı yeniden çalıştır. | Uygulamanın güncel sürümündeki SQL'i kopyalayıp 2. adımı tekrarla. |
| Anonim girişler kapalı (3. adım). | 3. adımdaki **Allow anonymous sign-ins** seçeneğini aç ve kaydet. |
| Yeni kullanıcı kaydı kapalı… | 3. adımdaki **Allow new users to sign up** seçeneğini aç. |
| Çok fazla deneme; biraz sonra tekrar dene. | Birkaç dakika bekle. Yanlış davet kodları da sayılır: 15 dakikada 10 yanlış denemeden sonra katılmak bir süre durur. |
| Bu davet artık geçerli değil. Pano sahibinden yeni davet iste. | Davet yenilenmiş ya da pano silinmiş. Pano sahibinden yeni davet metni iste. |
| Bu davet başka bir sunucuya ait… | Cihazın başka bir sunucuya bağlı. Önce Ayarlar › Ortak çalışma'dan bağlantıyı kaldır. |

**Ücretsiz plan notları**

- Ücretsiz projeler bir hafta boyunca hiç kullanılmazsa Supabase tarafından **duraklatılır**.
  Panelde projeyi açıp **Restore project**'e basman yeterli; veriler kaybolmaz.
- Canlı imleçler ve “şu an burada” bilgisi Realtime mesaj kotasından harcar. Pamnot imleci yalnızca
  panoda başka biri varken ve imleç gerçekten hareket ederken gönderir; günlük kullanımda kota
  yeterlidir.

**İsteğe bağlı sıkılaştırma**

- **Realtime → Settings**'te **Allow public access** seçeneğini kapatabilirsin. Pamnot yalnızca
  üyelere açık (private) kanallar kullanır; bu ayar başka türlü kanalları da kapatır.

---

## Geliştiriciler için

- Sunucu şeması: `supabase/schema.sql` (uygulamaya `assets/supabase/schema.sql` olarak gömülür;
  iki dosya aynı kalmalıdır).
- Şema testleri: `supabase/tests/run.sh`. Yerel bir PostgreSQL 16'da Supabase benzeri bir taslak
  kurar, şemayı iki kez çalıştırır ve saldırı/davranış testlerini koşar:

  ```
  PGHOST=/tmp/pg PGPORT=5432 PGUSER=postgres supabase/tests/run.sh
  ```

- Sunucuyu derleme sırasında sabitlemek (sihirbazın 1–4. adımları atlanır):

  ```
  flutter run --dart-define=PAMNOT_SUPABASE_URL=https://xxxx.supabase.co \
              --dart-define=PAMNOT_SUPABASE_KEY=sb_publishable_…
  ```

- macOS: `com.apple.security.network.client` iki entitlements dosyasında da açıktır; yoksa
  sandbox bütün bağlantıları engeller.
