import '../boards/cloud/cloud_api.dart';
import '../boards/cloud/server_config.dart';
import 'strings.dart';

/// Collaboration strings: setup, sharing, joining, members, settings.
/// Never "pano" for the clipboard, never a suffix on someone's name or title.
extension CollabStrings on S {
  // Share
  String get share => pick('Paylaş', 'Share');
  String get shareWithTeam => pick('Ekibinle paylaş', 'Share with your team');
  String get shareNotSetUp => pick(
      'Bu pano şimdilik yalnızca bu cihazda. Ekip arkadaşlarınla birlikte çalışmak için ücretsiz bir Supabase sunucusunu bir kez kurman gerekiyor (yaklaşık 5 dakika). Arkadaşların kurulum yapmaz; yalnızca davet metnini yapıştırır.',
      'This board is on this device only. To work on it with teammates, set up a free Supabase server once (about 5 minutes). Teammates set up nothing; they just paste the invite text.');
  String get startSetup => pick('Kurulumu başlat', 'Start setup');
  String get haveInvite => pick('Davetim var', 'I have an invite');
  String get notNow => pick('Şimdilik kalsın', 'Not now');
  String get shareBoard => pick('Panoyu paylaş', 'Share board');
  String get uploadNotice => pick(
      'Pano sunucuya yüklenecek. Davet metnine sahip olan herkes panoyu görebilir ve düzenleyebilir.',
      'The board will be uploaded to the server. Anyone with the invite text can see and edit it.');
  String uploading(int n, int t) => pick('Yükleniyor… $n/$t', 'Uploading… $n/$t');
  String get uploadOffline => pick(
      'Şu an çevrimdışı. Bağlantı gelince yükleme kendiliğinden sürer.',
      'Offline right now. The upload carries on by itself once you are back online.');
  String get uploadFailed => pick('Yüklenemedi. Tekrar dene.', 'Upload failed. Try again.');
  String get tryAgain => pick('Tekrar dene', 'Try again');
  String get copyInvite => pick('Davet metnini kopyala', 'Copy invite');
  String get copied => pick('Kopyalandı', 'Copied');
  String inviteMessage(String title, String token) => pick(
      'Pamnot’ta «$title» panosuna katıl 🌸\n1. Pamnot’u aç → Takip → Panolar → Davete katıl\n2. Bu metnin tamamını yapıştır:\n$token',
      'Join the board «$title» in Pamnot 🌸\n1. Open Pamnot → Track → Boards → Join with invite\n2. Paste this whole text:\n$token');
  String get inviteOwnerOnly => pick(
      'Davet metnini pano sahibi paylaşır.',
      'The board owner shares the invite text.');
  String get resetInvite => pick('Daveti yenile', 'Reset invite');
  String get resetInviteBody => pick(
      'Eski davet metni artık çalışmaz. Katılmış olanlar panoda kalır.',
      'The old invite text stops working. People who joined stay on the board.');
  String get notSharedAnymore => pick('Bu pano artık paylaşılmıyor.', 'This board is no longer shared.');
  String get boardDeletedByOwner =>
      pick('Pano sahibi bu panoyu herkes için sildi.', 'The owner deleted this board for everyone.');
  String get accessRemoved => pick('Bu panoya erişimin kaldırıldı.', 'Your access to this board was removed.');
  String get keepLocalCopy => pick('Kopyasını cihazda sakla', 'Keep a copy on this device');
  String get localCopySaved => pick('Kopyası bu cihaza kaydedildi', 'A copy was saved on this device');

  // Members
  String get members => pick('Üyeler', 'Members');
  String get hereNow => pick('Şimdi burada', 'Here now');
  String get offline => pick('Çevrimdışı', 'Offline');
  String get you => pick('(sen)', '(you)');
  String get owner => pick('Sahip', 'Owner');
  String get removeFromBoard => pick('Panodan çıkar', 'Remove from board');
  String removeMemberBody(String name) => pick(
      'Çıkarılan kişi: $name. Panoya erişimi hemen kapanır ve davet yenilenir.',
      'Removing: $name. Their access ends now and the invite is reset.');
  String get noName => pick('İsimsiz', 'No name');

  // Join
  String get joinWithInvite => pick('Davete katıl', 'Join with invite');
  String get pasteInvite => pick('Davet metnini yapıştır', 'Paste the invite');
  String get paste => pick('Yapıştır', 'Paste');
  String get inviteNotFound =>
      pick('Bu metinde bir Pamnot daveti bulamadım.', 'No Pamnot invite found in this text.');
  String inviteWillConnect(String host) =>
      pick('Bu davet Pamnot’u $host sunucusuna bağlayacak.', 'This invite connects Pamnot to the server $host.');
  String get inviteOtherServer => pick(
      'Bu davet başka bir sunucuya ait. Önce Ayarlar › Ortak çalışma’dan bağlantıyı kaldır.',
      'This invite belongs to another server. First disconnect in Settings › Collaboration.');
  String get join => pick('Katıl', 'Join');
  String get joining => pick('Katılınıyor…', 'Joining…');
  String get downloadingBoard => pick('Pano indiriliyor…', 'Downloading board…');
  String get inviteInvalid => pick(
      'Bu davet artık geçerli değil. Pano sahibinden yeni davet iste.',
      'This invite is no longer valid. Ask the board owner for a new one.');
  String get needsInternet => pick('İnternet bağlantısı gerekiyor.', 'An internet connection is needed.');
  String get tooManyTries => pick('Çok fazla deneme; biraz sonra tekrar dene.', 'Too many tries; try again a little later.');
  String get joinedBoard => pick('Pano Panolar’a eklendi', 'The board was added to Boards');

  // Remove
  String get deleteBoardTitle => pick('Panoyu sil', 'Delete board');
  String deleteLocalBody(String title) =>
      pick('«$title» bu cihazdan silinecek. Bu geri alınamaz.', '«$title» will be deleted from this device. This cannot be undone.');
  String get leaveBoard => pick('Panodan ayrıl', 'Leave board');
  String leaveBody(String title) => pick(
      '«$title» panosundan ayrılırsın ve bu cihazdaki kopyası silinir. Yeniden katılmak için yeni davet gerekir.',
      'You leave «$title» and its copy on this device is deleted. Joining again needs a new invite.');
  String get deleteForEveryone => pick('Herkes için sil', 'Delete for everyone');
  String deleteForEveryoneBody(String title) =>
      pick('«$title» herkes için silinecek. Bu geri alınamaz.', '«$title» will be deleted for everyone. This cannot be undone.');
  String get removeFromDevice => pick('Bu cihazdan sil', 'Delete from this device');

  // Setup wizard
  String get setupTitle => pick('Ortak çalışmayı kur', 'Set up collaboration');
  String get setupIntro => pick(
      'Bunu bir kez, bir kişi yapar. Sunucu ücretsiz Supabase planında çalışır; ekip arkadaşların yalnızca davet metnini yapıştırır.',
      'One person does this, once. The server runs on Supabase’s free plan; teammates only paste the invite text.');
  String get step1 => pick('supabase.com’da ücretsiz hesap aç ve yeni proje oluştur.',
      'Create a free account at supabase.com and make a new project.');
  String get step1Hint => pick('Proje adı ve veritabanı şifresi istediğin gibi olabilir; bölge olarak sana yakın olanı seç.',
      'Any project name and database password will do; pick the region closest to you.');
  String get copyAddress => pick('Adresi kopyala', 'Copy address');
  String get step2 => pick('SQL Editor’ü aç, Pamnot kurulum SQL’ini yapıştır ve Run’a bas.',
      'Open the SQL Editor, paste the Pamnot setup SQL and press Run.');
  String get step2Hint => pick('“Success. No rows returned” görürsen tamamdır. Tekrar çalıştırmak zararsızdır.',
      '“Success. No rows returned” means it worked. Running it again is harmless.');
  String get copySql => pick('SQL’i kopyala', 'Copy SQL');
  String get step3 => pick(
      'Authentication → Sign In / Providers → ‘Allow anonymous sign-ins’ seçeneğini aç ve kaydet.',
      'Authentication → Sign In / Providers → turn on ‘Allow anonymous sign-ins’ and save.');
  String get step3Hint => pick('Ekip arkadaşların e-posta olmadan, yalnızca adlarıyla katılır.',
      'Teammates join without e-mail, with just their name.');
  String get step4 => pick('Project Settings → API Keys: Project URL ve publishable (anon) anahtarı buraya yapıştır.',
      'Project Settings → API Keys: paste the Project URL and the publishable (anon) key here.');
  String get serverUrl => pick('Sunucu adresi (Project URL)', 'Server address (Project URL)');
  String get publishableKey => pick('Publishable anahtar (anon)', 'Publishable key (anon)');
  String willUse(String url) => pick('Kullanılacak adres: $url', 'Will use: $url');
  String get step5 => pick('Ekip arkadaşların seni nasıl görsün?', 'How should teammates see you?');
  String get yourName => pick('Adın', 'Your name');
  String get yourNameHint => pick('Ekip arkadaşların seni bu adla görür', 'Teammates see you by this name');
  String get yourColor => pick('Rengin', 'Your colour');
  String get nameRequired => pick('Bir ad yaz.', 'Type a name.');
  String get next => pick('Devam', 'Next');
  String get back => pick('Geri', 'Back');
  String get connect => pick('Bağlan', 'Connect');
  String get connecting => pick('Bağlanıyor…', 'Connecting…');
  String get stepReach => pick('Sunucuya ulaşılıyor…', 'Reaching the server…');
  String get stepCheck => pick('Kurulum kontrol ediliyor…', 'Checking the setup…');
  String get stepSignIn => pick('Giriş yapılıyor…', 'Signing in…');
  String get stepProfile => pick('Adın kaydediliyor…', 'Saving your name…');
  String get readyBlossom => pick('Hazır 🌸', 'Ready 🌸');
  String goToStep(int n) => pick('$n. adıma git', 'Go to step $n');

  String urlProblem(UrlProblem p) => switch (p) {
        UrlProblem.empty => pick('Sunucu adresini yapıştır.', 'Paste the server address.'),
        UrlProblem.invalid => pick('Bu bir sunucu adresine benzemiyor. ör. https://abcd….supabase.co',
            'That does not look like a server address, e.g. https://abcd….supabase.co'),
        UrlProblem.dashboard => pick('Bu Supabase sitesinin adresi. Project Settings → API Keys’teki Project URL’yi kopyala.',
            'That is the Supabase website. Copy the Project URL from Project Settings → API Keys.'),
        UrlProblem.insecure => pick('Adres https:// ile başlamalı.', 'The address must start with https://.'),
      };

  String keyProblem(KeyProblem p) => switch (p) {
        KeyProblem.empty => pick('Publishable anahtarı yapıştır.', 'Paste the publishable key.'),
        KeyProblem.secret => pick(
            'Bu gizli (secret) anahtar — asla paylaşma! API Keys sayfasından ‘publishable’ ya da ‘anon’ anahtarı kopyala.',
            'That is the secret key — never share it! Copy the ‘publishable’ or ‘anon’ key from the API Keys page.'),
        KeyProblem.wrongRole => pick('Anahtar hatalı. ‘publishable’ ya da ‘anon’ anahtarı kopyala.',
            'Wrong key. Copy the ‘publishable’ or ‘anon’ key.'),
        KeyProblem.unrecognized => pick('Anahtar tanınmadı.', 'Key not recognised.'),
      };

  String cloudProblem(CloudProblem p) => switch (p) {
        CloudProblem.unreachable => pick('Sunucuya ulaşılamadı. İnternet bağlantını ve adresi kontrol et.',
            'Could not reach the server. Check your internet connection and the address.'),
        CloudProblem.badKey => pick('Anahtar hatalı.', 'The key is wrong.'),
        CloudProblem.sqlMissing => pick('Kurulum SQL’i çalıştırılmamış görünüyor (2. adım).',
            'The setup SQL does not seem to have been run (step 2).'),
        CloudProblem.sqlOutdated => pick('Kurulum SQL’i eski; 2. adımı yeniden çalıştır.',
            'The setup SQL is outdated; run step 2 again.'),
        CloudProblem.anonymousDisabled => pick('Anonim girişler kapalı (3. adım).', 'Anonymous sign-ins are off (step 3).'),
        CloudProblem.signupsDisabled => pick(
            'Yeni kullanıcı kaydı kapalı. Authentication → Sign In / Providers → ‘Allow new users to sign up’ seçeneğini aç.',
            'New sign-ups are off. Turn on Authentication → Sign In / Providers → ‘Allow new users to sign up’.'),
        CloudProblem.rateLimited => tooManyTries,
        CloudProblem.otherServer => inviteOtherServer,
        CloudProblem.unknown => pick('Bir şeyler ters gitti. Tekrar dener misin?', 'Something went wrong. Try again?'),
      };

  /// The wizard step that fixes [p], if any.
  int? stepFor(CloudProblem p) => switch (p) {
        CloudProblem.sqlMissing || CloudProblem.sqlOutdated => 2,
        CloudProblem.anonymousDisabled || CloudProblem.signupsDisabled => 3,
        CloudProblem.badKey => 4,
        _ => null,
      };

  // Settings › Ortak çalışma
  String get collaboration => pick('Ortak çalışma', 'Collaboration');
  String get collabOff => pick('Kapalı — panoların yalnızca bu cihazda.', 'Off — your boards stay on this device.');
  String get setUp => pick('Kur', 'Set up');
  String serverOk(String host) => pick('Sunucu: $host ✓', 'Server: $host ✓');
  String serverNotSignedIn(String host) =>
      pick('Sunucu: $host — bu cihaz bağlı değil', 'Server: $host — this device is not connected');
  String get disconnectDevice => pick('Bu cihazın bağlantısını kaldır', 'Disconnect this device');
  String disconnectBody(int unsent) => [
        if (unsent > 0) pick('$unsent gönderilmemiş değişiklik kaybolacak.', '$unsent unsent changes will be lost.'),
        pick('Ortak panoların bu cihazdaki kopyaları silinir. Yeniden katılmak için yeni davet gerekir; cihazdaki panoların kalır.',
            'This device’s copies of shared boards are deleted. Joining again needs a new invite; device-only boards stay.'),
      ].join('\n\n');
  String get disconnect => pick('Bağlantıyı kaldır', 'Disconnect');
  String get aboutTextShared => pick(
      'Pamnot — yumuşacık notlar, planlar ve anımsatıcılar. Paylaştığın panolar dışında verilerin yalnızca cihazında saklanır.',
      'Pamnot — soft notes, plans and reminders. Apart from boards you share, your data stays on your device.');
}
