import 'package:flutter/widgets.dart';

import '../models/task_list.dart';

/// UI strings in Turkish and English. Kept as plain getters so a missing
/// translation is a compile error rather than a blank label.
class S {
  const S(this.isTr);

  final bool isTr;

  static S of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'tr';
    return code == 'tr' ? tr : en;
  }

  static const tr = S(true);
  static const en = S(false);

  String get locale => isTr ? 'tr' : 'en';

  String _(String t, String e) => isTr ? t : e;

  // Navigation
  String get today => _('Bugün', 'Today');
  String get notes => _('Notlar', 'Notes');
  String get tasks => _('Takip', 'Track');
  String get planner => _('Plan', 'Plan');
  String get reminders => _('Anımsatıcılar', 'Reminders');

  /// Fits a phone's bottom bar on one line.
  String get remindersShort => _('Hatırlatma', 'Reminders');
  String get settings => _('Ayarlar', 'Settings');

  // Greetings
  String greeting(int hour) {
    if (hour < 5) return _('İyi geceler', 'Good night');
    if (hour < 12) return _('Günaydın', 'Good morning');
    if (hour < 18) return _('Tünaydın', 'Good afternoon');
    return _('İyi akşamlar', 'Good evening');
  }

  String get quickCapture => _('Aklında ne var?', "What's on your mind?");
  String get quickCaptureHint => _('Görev ekle, ör. "Yarın 10:00 toplantı"', 'Add a task, e.g. "Call Anna tomorrow 10:00"');
  String get todaysPlan => _('Bugünün planı', "Today's plan");
  String get upcoming => _('Yaklaşanlar', 'Upcoming');
  String get pinnedNotes => _('Sabitlenen notlar', 'Pinned notes');
  String get recentNotes => _('Son notlar', 'Recent notes');
  String get habits => _('Alışkanlıklar', 'Habits');
  String get nothingToday => _('Bugün için plan yok. Keyfine bak 🌿', 'Nothing planned today. Enjoy 🌿');
  String progressLabel(int done, int total) =>
      _('$done/$total tamamlandı', '$done/$total done');
  String get allDone => _('Hepsi tamam, harikasın!', 'All done, lovely!');
  String get seeAll => _('Tümü', 'See all');

  // Notes
  String get searchNotes => _('Notlarda ara', 'Search notes');
  String get newNote => _('Yeni not', 'New note');
  String get newHandwriting => _('El yazısı not', 'Handwritten note');
  String get untitled => _('Başlıksız', 'Untitled');
  String get title => _('Başlık', 'Title');
  String get startWriting => _('Yazmaya başla…', 'Start writing…');
  String get noNotes => _('Henüz not yok. İlk notunu yaz ✍️', 'No notes yet. Write your first one ✍️');
  String get noResults => _('Sonuç bulunamadı', 'No results');
  String get pin => _('Sabitle', 'Pin');
  String get unpin => _('Sabitlemeyi kaldır', 'Unpin');
  String get color => _('Renk', 'Colour');
  String get delete => _('Sil', 'Delete');
  String get deleted => _('Silindi', 'Deleted');
  String get undo => _('Geri al', 'Undo');
  String get redo => _('Yinele', 'Redo');
  String get textMode => _('Yazı', 'Text');
  String get inkMode => _('Kalem', 'Pen');
  String get paper => _('Kâğıt', 'Paper');
  String get paperBlank => _('Düz', 'Blank');
  String get paperLined => _('Çizgili', 'Lined');
  String get paperGrid => _('Kareli', 'Grid');
  String get paperDotted => _('Noktalı', 'Dotted');
  String get pen => _('Kalem', 'Pen');
  String get highlighter => _('Fosforlu', 'Highlighter');
  String get eraser => _('Silgi', 'Eraser');
  String get hand => _('Kaydır', 'Scroll');
  String get clearPage => _('Sayfayı temizle', 'Clear page');
  String get convertToText => _('Yazıya çevir', 'Convert to text');
  String get removeInkAfter => _('Çevirdikten sonra mürekkebi kaldır', 'Remove the ink after converting');
  String get recognizing => _('Okunuyor…', 'Recognising…');
  String get pickRecognition => _('Hangisini yazdın?', 'Which did you write?');
  String get recognitionUnsupported => _(
      'El yazısını yazıya çevirme şimdilik iPad, iPhone ve Android’de çalışıyor. iPad’de metin alanına Apple Pencil ile doğrudan da yazabilirsin (Karalama).',
      'Handwriting to text currently works on iPad, iPhone and Android. On iPad you can also write straight into text fields with Apple Pencil (Scribble).');
  String get downloadingModel => _('El yazısı modeli indiriliyor…', 'Downloading handwriting model…');
  String get recognitionFailed => _('Okunamadı, tekrar dener misin?', "Couldn't read that, try again?");
  String get stylusOnlyOn => _('Apple Pencil algılandı: yalnızca kalem çizer, parmakla kaydırırsın.',
      'Stylus detected: only the pencil draws, fingers scroll.');
  String get words => _('kelime', 'words');

  // Tasks
  String get tasksTab => _('Görevler', 'Tasks');
  String get newTask => _('Yeni görev', 'New task');
  String get taskTitleHint => _('Ne yapılacak?', 'What needs doing?');
  String get notesHint => _('Not ekle', 'Add a note');
  String get dueDate => _('Tarih', 'Date');
  String get time => _('Saat', 'Time');
  String get noDate => _('Tarih yok', 'No date');
  String get remindMe => _('Bana hatırlat', 'Remind me');
  String get priority => _('Öncelik', 'Priority');
  String get low => _('Düşük', 'Low');
  String get normal => _('Normal', 'Normal');
  String get high => _('Yüksek', 'High');
  String get subtasks => _('Alt görevler', 'Subtasks');
  String get addSubtask => _('Alt görev ekle', 'Add subtask');
  String get save => _('Kaydet', 'Save');
  String get cancel => _('Vazgeç', 'Cancel');
  String get overdue => _('Gecikenler', 'Overdue');
  String get tomorrow => _('Yarın', 'Tomorrow');
  String get later => _('Daha sonra', 'Later');
  String get someday => _('Tarihsiz', 'Someday');
  String get completed => _('Tamamlananlar', 'Completed');
  String get noTasks => _('Görev yok. Güzel bir gün 🌸', 'No tasks. A lovely day 🌸');
  String get filterAll => _('Tümü', 'All');
  String get filterToday => _('Bugün', 'Today');
  String get filterUpcoming => _('Yaklaşan', 'Upcoming');
  String get filterDone => _('Biten', 'Done');

  // Habits
  String get newHabit => _('Yeni alışkanlık', 'New habit');
  String get habitNameHint => _('ör. Su iç, Kitap oku', 'e.g. Drink water, Read');
  String get perWeek => _('Haftada', 'Per week');
  String timesAWeek(int n) => n == 7 ? _('Her gün', 'Every day') : _('Haftada $n gün', '$n days a week');
  String streakDays(int n) => _('$n gün seri', '$n day streak');
  String get noHabits => _('Küçük adımlar, büyük değişimler. İlk alışkanlığını ekle.',
      'Small steps, big changes. Add your first habit.');
  String get thisWeek => _('Bu hafta', 'This week');

  // Planner
  String get week => _('Hafta', 'Week');
  String get month => _('Ay', 'Month');
  String get allDay => _('Gün boyu', 'All day');
  String get emptyDay => _('Bu gün boş. Bir şey planla?', 'This day is free. Plan something?');
  String get add => _('Ekle', 'Add');
  String get task => _('Görev', 'Task');
  String get reminder => _('Anımsatıcı', 'Reminder');
  String get goToToday => _('Bugüne git', 'Go to today');

  // Reminders
  String get newReminder => _('Yeni anımsatıcı', 'New reminder');
  String get reminderTitleHint => _('Neyi hatırlatayım?', 'What should I remind you of?');
  String get repeat => _('Tekrar', 'Repeat');
  String get repeatNone => _('Bir kez', 'Once');
  String get repeatDaily => _('Her gün', 'Daily');
  String get repeatWeekly => _('Her hafta', 'Weekly');
  String get repeatMonthly => _('Her ay', 'Monthly');
  String get repeatYearly => _('Her yıl', 'Yearly');
  String get recurring => _('Tekrarlayan', 'Recurring');
  String get past => _('Geçmiş', 'Past');
  String get noReminders => _('Anımsatıcı yok. Ben burada, hatırlatırım 🔔', "No reminders. I'm here to remind you 🔔");
  String get notificationsOff => _('Bildirimler kapalı. Anımsatıcıların çalışması için izin ver.',
      'Notifications are off. Allow them so reminders can reach you.');
  String get allow => _('İzin ver', 'Allow');
  String get notificationsUnsupported => _(
      'Bu platformda zamanlanmış bildirimler sınırlı; uygulama açıkken hatırlatırım.',
      'Scheduled notifications are limited on this platform; I remind you while the app is open.');

  // Settings
  String get language => _('Dil', 'Language');
  String get systemDefault => _('Sistem', 'System');
  String get theme => _('Tema', 'Theme');
  String get themeLight => _('Açık', 'Light');
  String get themeDark => _('Koyu', 'Dark');
  String get wordPrediction => _('Kelime tahmini', 'Word prediction');
  String get wordPredictionSub => _('Yazarken klavyenin üstünde öneriler gösterir ve notlarından öğrenir.',
      'Shows suggestions above the keyboard and learns from your notes.');
  String get predictionLanguage => _('Tahmin dili', 'Prediction language');
  String get auto => _('Otomatik', 'Automatic');
  String get pencil => _('Apple Pencil ve kalem', 'Apple Pencil & stylus');
  String get stylusOnly => _('Yalnızca kalemle çiz', 'Draw with stylus only');
  String get stylusOnlySub => _('Avuç içi reddi: parmaklar sayfayı kaydırır.', 'Palm rejection: fingers scroll the page.');
  String get autoStylus => _('Kalem algılanınca otomatik aç', 'Turn on when a stylus is detected');
  String get weekStartsMonday => _('Hafta pazartesi başlar', 'Week starts on Monday');
  String get notifications => _('Bildirimler', 'Notifications');
  String get testNotification => _('Deneme bildirimi gönder', 'Send a test notification');
  String get testNotificationBody => _('Pamnot bildirimleri çalışıyor 🌸', 'Pamnot notifications are working 🌸');
  String get handwritingModels => _('El yazısı tanıma modelleri', 'Handwriting recognition models');
  String get download => _('İndir', 'Download');
  String get ready => _('Hazır', 'Ready');
  String get about => _('Hakkında', 'About');
  String get aboutText => _('Pamnot — yumuşacık notlar, planlar ve anımsatıcılar. Notların ve görevlerin yalnızca cihazında saklanır.',
      'Pamnot — soft notes, plans and reminders. Your notes and tasks stay on your device.');
  String get turkish => 'Türkçe';
  String get english => 'English';

  // Voice
  String get voiceTitle => _('Sesle ekle', 'Add by voice');
  String get voiceMicTooltip => _('Sesle görev ekle', 'Add a task by voice');
  String get voicePreparing => _('Hazırlanıyor…', 'Getting ready…');
  String get voiceListening => _('Dinliyorum…', 'Listening…');
  String get voicePaused => _('Duraklatıldı', 'Paused');
  String get voiceTapToContinue => _('Devam etmek için dokun', 'Tap to continue');
  String get voiceSaved => _('Kaydedildi', 'Saved');
  String get voiceFix => _('Düzelt', 'Fix');
  String get voiceDraftHint => _('Görevi düzelt', 'Fix the task');
  String get voiceStartListening => _('Dinlemeyi başlat', 'Start listening');
  String get voiceStopListening => _('Dinlemeyi durdur', 'Stop listening');
  String get voiceAdded => _('Eklenenler', 'Added');
  String get voiceSavedOnLock => _('Kilitlenirken kaydedildi', 'Saved while locking');
  String voiceUndoItem(String title) => _('$title görevini geri al', 'Undo $title');
  String get voiceUndatedRemindHint => _(
      'Tarihsiz · hatırlatma için gün söyle',
      'No date · say a day to get a reminder');
  String get voiceReminderOn => _('hatırlatma açık', 'reminder on');
  String get voiceTimeGuess => _('saat tahmini', 'time is a guess');
  String get voiceNoteChip => _('Not', 'Note');
  String voiceCountdown(int n) => _('$n sn', '$n s');
  String voiceSummary(int n) => _('$n kayıt eklendi', n == 1 ? '1 item added' : '$n items added');
  String get voiceErrorGeneric => _(
      'Şu anda dinleyemiyorum. Bağlantını kontrol edip tekrar dene.',
      'I can’t listen right now. Check your connection and try again.');
  String get voiceRetry => _('Tekrar dene', 'Try again');
  String get voicePermissionDenied => _(
      'Mikrofon ya da Konuşma Tanıma izni kapalı. Sesle eklemek için Ayarlar’dan ikisini de aç. Yazarak eklemeye devam edebilirsin.',
      'Microphone or Speech Recognition access is off. Turn both on in Settings to add by voice. You can still add tasks by typing.');
  String get openSettings => _('Ayarlar’ı Aç', 'Open Settings');
  String get voiceDictationOff => _(
      'Dikte kapalı. Ayarlar > Genel > Klavye > Dikte’yi aç, sonra tekrar dene.',
      'Dictation is off. Turn on Settings > General > Keyboard > Enable Dictation, then try again.');
  String get voiceUnsupportedLocale => _(
      'Telefonunun dili için konuşma tanıma yok.',
      'Speech recognition isn’t available for your phone’s language.');
  String get voiceUnsupportedPlatform => _(
      'Sesle ekleme bu cihazda henüz yok.',
      'Adding by voice isn’t available on this device yet.');

  // Voice settings
  String get voiceSettings => _('Sesle ekleme', 'Add by voice');
  String get voiceSetupReady => _(
      '“Sesle Görev Ekle” eylemi Kestirmeler’de, Spotlight’ta ve Eylem düğmesi ayarlarında hazır.',
      '“Add Voice Task” is ready in Shortcuts, Spotlight and the Action button settings.');
  String get voiceSiriHint => _('Siri’ye “Pamnot ile görev ekle” de.', 'Say “Add a task in Pamnot” to Siri.');
  String get voiceBackTapTitle => _('Arkaya Dokunma', 'Back Tap');
  String get voiceBackTapSteps => _(
      '1. Kestirmeler’de + ile yeni bir kestirme oluştur ve Pamnot > Sesle Görev Ekle eylemini ekle.\n2. Ayarlar > Erişilebilirlik > Dokunma > Arkaya Dokunma’da bu kestirmeyi seç.',
      '1. In Shortcuts, tap + to create a shortcut and add the Pamnot > Add Voice Task action.\n2. In Settings > Accessibility > Touch > Back Tap, choose that shortcut.');
  String get voiceVoiceControlTitle => _('Sesle Denetim', 'Voice Control');
  String get voiceVoiceControlSteps => _(
      '1. Kestirmeler’de tek eylemli bir kestirme oluştur: Pamnot > Sesle Görev Ekle.\n2. Ayarlar > Erişilebilirlik > Sesle Denetim > Komutlar > Yeni Komut Yarat > Eylem > Kestirmeyi Çalıştır’da bu kestirmeyi seç.',
      '1. In Shortcuts, create a shortcut with one action: Pamnot > Add Voice Task.\n2. In Settings > Accessibility > Voice Control > Commands > Create New Command > Action > Run Shortcut, choose that shortcut.');
  String get voiceKeepLog => _('Tanınan metinleri sakla', 'Keep recognised text');
  String get voiceKeepLogSub => _(
      'Son 20 metin, yalnız bu cihazda. Tarih ve saat tanımayı iyileştirmeye yarar.',
      'The last 20, on this device only. Helps improve date and time recognition.');
  String get voiceRecent => _('Son tanınanlar', 'Recently recognised');
  String get voiceRecentEmpty => _('Henüz kayıt yok.', 'Nothing yet.');
  String get voiceClearLog => _('Temizle', 'Clear');
  String get voicePrivacyNote => _(
      'Konuşman Apple’ın konuşma tanımasıyla yazıya çevrilir. Çevrimiçiyken sesin, klavyedeki dikte gibi Apple’a gidebilir. Pamnot ses kaydı saklamaz.',
      'Your speech is turned into text by Apple’s speech recognition. When you’re online, your voice may be sent to Apple, like keyboard dictation. Pamnot doesn’t save audio.');
  String get notificationsAllow => _('Bildirimlere izin ver', 'Allow notifications');
  String get notificationsDenied => _('Bildirimler kapalı — Ayarlar’ı aç', 'Notifications are off — open Settings');
  String get notificationsOn => _('Bildirimler açık', 'Notifications are on');

  // Privacy and about
  String get privacyPolicy => _('Gizlilik Politikası', 'Privacy Policy');
  String get support => _('Destek', 'Support');
  String get licenses => _('Açık kaynak lisansları', 'Open-source licences');
  String get dataNote => _(
      'Sesle eklerken konuşman Apple’a, el yazısı tanımada kişisel olmayan kullanım ölçümleri Google’a gidebilir. Ayrıntılar Gizlilik Politikası’nda.',
      'When you add by voice, your speech may go to Apple; handwriting recognition may send non-personal usage metrics to Google. Details are in the Privacy Policy.');
  String get handwritingPrivacyNote => _(
      'El yazısı cihazında yazıya çevrilir; yazdıkların Google’a gönderilmez. Google ML Kit, tanıma modelini indirir ve Google’a kişisel olmayan kullanım ve performans ölçümleri gönderir.',
      'Handwriting is converted to text on your device; what you write is not sent to Google. Google ML Kit downloads the recognition model and sends non-personal usage and performance metrics to Google.');
  String get handwritingDownloadTitle => _('El yazısı modeli indirilsin mi?', 'Download the handwriting model?');
  String get handwritingDownloadBody => _('Yaklaşık 20 MB.', 'About 20 MB.');

  // Accessibility
  /// Spoken name of note colour [i] (0..7), in the palette's order.
  String colorName(int i) => isTr
      ? const ['krem', 'şeftali', 'nane', 'lavanta', 'gök mavisi', 'tereyağı', 'gül', 'adaçayı'][i]
      : const ['cream', 'peach', 'mint', 'lavender', 'sky', 'butter', 'rose', 'sage'][i];
  String get previous => _('Önceki', 'Previous');
  String get next => _('Sonraki', 'Next');
  String get removeSubtask => _('Alt görevi kaldır', 'Remove subtask');
  String get clearSearch => _('Aramayı temizle', 'Clear search');
  String get overdueLabel => _('Gecikti', 'Overdue');
  String inkColor(int n) => _('Renk $n', 'Colour $n');
  String strokeWidth(int n) => _('Kalınlık $n', 'Width $n');

  // Misc
  String get edit => _('Düzenle', 'Edit');
  String get done => _('Tamam', 'Done');
  String get close => _('Kapat', 'Close');
  String get dueToday => _('Bugün', 'Today');

  // Final fix wave
  /// Undo label of a note saved by voice ([text] is the note's beginning).
  String voiceUndoNote(String text) => _('Notu geri al: $text', 'Undo note: $text');

  // v2 · K1
  String get unpinned => _('Sabitleme kaldırıldı', 'Unpinned');
  /// Plan's section picker: the other section is the existing [reminders].
  String get planAgendaTab => _('Takvim', 'Calendar');
  /// The middle navigation button on platforms without a microphone.
  String get navAddTask => _('Yeni görev ekle', 'Add a task');

  // v2 · K2
  String get matrix => _('Matris', 'Matrix');
  /// Box titles describe the box; no imperative mood.
  String quadrantTitle(Quadrant q) => switch (q) {
        Quadrant.doNow => _('Önemli · Acil', 'Important · Urgent'),
        Quadrant.plan => _('Önemli · Planlı', 'Important · Planned'),
        Quadrant.delegate => _('Acil · Önemsiz', 'Urgent · Less important'),
        Quadrant.later => _('Sonra · Belki', 'Later · Maybe'),
      };
  String quadrantHint(Quadrant q) => switch (q) {
        Quadrant.doNow => _('Bugün ilgilen', 'Deal with it today'),
        Quadrant.plan => _('Zamanını belirle', 'Give it a time'),
        Quadrant.delegate => _('Kısa tut ya da paylaş', 'Keep it short or share it'),
        Quadrant.later => _('Gerekirse dön', 'Come back if needed'),
      };
  /// Name of a ready-made list; an unknown [id] is returned as is.
  String defaultListName(String id) => switch (id) {
        TaskList.personalId => _('Kişisel', 'Personal'),
        'work' => _('İş', 'Work'),
        'school' => _('Okul', 'School'),
        'shopping' => _('Alışveriş', 'Shopping'),
        'home' => _('Ev', 'Home'),
        _ => id,
      };
  String get list => _('Liste', 'List');
  String get box => _('Kutu', 'Box');
  String get newList => _('Yeni liste', 'New list');
  String get listNameHint => _('Liste adı', 'List name');
  String get renameList => _('Listeyi düzenle', 'Edit list');
  String get deleteList => _('Listeyi sil', 'Delete list');
  String deleteListBody(String name, int n, String target) => _(
      '“$name” silinecek. İçindeki $n görev “$target” listesine taşınır.',
      '“$name” will be deleted. Its $n tasks move to “$target”.');
  String get lastListNote => _('En az bir liste kalmalı.', 'At least one list must stay.');
  String get listDeleted => _('Liste silindi', 'List deleted');
  String get moveToList => _('Başka listeye taşı…', 'Move to another list…');
  String moveToBox(String box) => _('$box kutusuna taşı', 'Move to $box');
  String get markDone => _('Bitti', 'Done');
  String finishedCount(int n) => _('Biten ($n)', 'Finished ($n)');
  String get addToBox => _('Ekle', 'Add');
  String get boxEmpty => _('Boş', 'Empty');
  String movedTo(String where) => _('$where içine taşındı', 'Moved to $where');
  String get icon => _('Simge', 'Icon');
  String voiceSavedTo(String list) => _('$list listesine eklendi', 'Added to $list');
  String get voiceAutoSaveTitle =>
      _('8 saniye sonra kendiliğinden kaydet', 'Save by itself after 8 seconds');
  String get voiceAutoSaveSub => _(
      'Liste seçmezsen son kullandığın listeye kaydeder. Eller serbest kullanım için.',
      'If you don’t pick a list, it saves to the one you used last. For hands-free use.');

  // Task 9
  /// What VoiceOver reads for an icon of `lib/ui/matrix/list_icons.dart`.
  String listIconName(String key) => switch (key) {
        'person' => _('Kişi', 'Person'),
        'work' => _('Çanta', 'Briefcase'),
        'school' => _('Kep', 'Graduation cap'),
        'shopping' => _('Alışveriş arabası', 'Shopping cart'),
        'home' => _('Ev', 'House'),
        'star' => _('Yıldız', 'Star'),
        'favorite' => _('Kalp', 'Heart'),
        'fitness' => _('Dambıl', 'Dumbbell'),
        'travel' => _('Uçak', 'Plane'),
        'book' => _('Kitap', 'Book'),
        'pets' => _('Pati', 'Paw'),
        'money' => _('Kumbara', 'Piggy bank'),
        'health' => _('Sağlık', 'Health'),
        'music' => _('Nota', 'Music note'),
        'idea' => _('Ampul', 'Light bulb'),
        _ => _('Liste', 'List'),
      };
  /// The open-task count beside a box title, as VoiceOver reads it.
  String openTasks(int n) => _('$n açık görev', '$n open tasks');

  // Fix: voice close
  /// The voice screen's state right after a save.
  String get voiceSavedDone => _('Eklendi', 'Added');
  /// Listens again after a save; the only way the microphone re-opens.
  String get voiceAddAnother => _('Bir tane daha', 'Add another');
}
