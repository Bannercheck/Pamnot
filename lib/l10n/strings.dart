import 'package:flutter/widgets.dart';

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
  String get testNotificationBody => _('Pamuk bildirimleri çalışıyor 🌸', 'Pamuk notifications are working 🌸');
  String get handwritingModels => _('El yazısı tanıma modelleri', 'Handwriting recognition models');
  String get download => _('İndir', 'Download');
  String get ready => _('Hazır', 'Ready');
  String get about => _('Hakkında', 'About');
  String get aboutText => _('Pamuk — yumuşacık notlar, planlar ve anımsatıcılar. Verilerin yalnızca cihazında saklanır.',
      'Pamuk — soft notes, plans and reminders. Your data stays on your device.');
  String get turkish => 'Türkçe';
  String get english => 'English';

  // Misc
  String get edit => _('Düzenle', 'Edit');
  String get done => _('Tamam', 'Done');
  String get close => _('Kapat', 'Close');
  String get dueToday => _('Bugün', 'Today');
}
