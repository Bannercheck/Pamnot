import 'strings.dart';

/// Strings of the board list, board page, Kanban and card sheet.
///
/// Rules (docs/boards/DESIGN.md, ux_specs §12): never use "pano" for the
/// clipboard, and never attach a Turkish suffix to user content — names
/// and titles stand alone after a colon or inside «».
extension BoardStrings on S {
  // Board list
  String get boards => pick('Panolar', 'Boards');
  String get newBoard => pick('Yeni pano', 'New board');
  String get boardName => pick('Pano adı', 'Board name');
  String get boardNameHint => pick('ör. Web sitesi yenileme', 'e.g. Website refresh');
  String get taskBoardTemplate => pick('Görev panosu', 'Task board');
  String get taskBoardTemplateSub => pick('Yapılacak · Yapılıyor · Bitti', 'To do · Doing · Done');
  String get blankCanvasTemplate => pick('Boş tuval', 'Blank canvas');
  String get blankCanvasTemplateSub => pick('Sütunsuz, serbest çalışma', 'No columns, free-form');
  String get create => pick('Oluştur', 'Create');
  String get boardsEmpty => pick('İşlerini sütunlara ayır, fikirlerini notlara yaz. İlk panonu oluştur!',
      'Split your work into columns and jot ideas on notes. Create your first board!');
  String get joinInvite => pick('Davete katıl', 'Join with invite');
  String get haveInvite => pick('Davetim var', 'I have an invite');
  String get onDevice => pick('Cihazda', 'On this device');
  String get sharedBoard => pick('Paylaşılıyor', 'Shared');
  String get readOnlyBoard => pick('Salt okunur', 'Read-only');
  String doneOfTotal(int done, int total) => pick('$done/$total bitti', '$done/$total done');
  String get boardNotFound => pick('Bu pano bulunamadı.', 'This board could not be found.');

  // Relative times on the list
  String get justNow => pick('şimdi', 'just now');
  String minutesAgo(int n) => pick('$n dk önce', '$n min ago');
  String hoursAgo(int n) => pick('$n sa önce', '$n h ago');
  String get yesterdayAgo => pick('dün', 'yesterday');
  String daysAgo(int n) => pick('$n gün önce', '$n days ago');

  // Board actions
  String get rename => pick('Yeniden adlandır', 'Rename');
  String get share => pick('Paylaş', 'Share');
  String get members => pick('Üyeler', 'Members');
  String get leaveBoard => pick('Panodan ayrıl', 'Leave board');

  /// Shared boards: the owner deletes for everyone, a member leaves; the
  /// confirmation that follows says which.
  String get removeSharedBoard => pick('Panoyu kaldır…', 'Remove board…');

  // Columns
  String get addColumn => pick('Sütun ekle', 'Add column');
  String get columnName => pick('Sütun adı', 'Column name');
  String get newColumnTitle => pick('Yeni sütun', 'New column');
  String get doneColumn => pick('Tamamlanan sütunu', 'Done column');
  String get doneColumnSub => pick('Bu sütundaki kartlar bitmiş sayılır', 'Cards here count as done');
  String get moveLeft => pick('Sola taşı', 'Move left');
  String get moveRight => pick('Sağa taşı', 'Move right');
  String get deleteColumn => pick('Sütunu sil', 'Delete column');
  String cardsWillMove(int n, String column) => pick(
      'Bu sütundaki $n kart «$column» sütununa taşınacak.', n == 1 ? '1 card will move to “$column”.' : '$n cards will move to “$column”.');
  String cardsWillBeDeleted(int n) =>
      pick('Bu son sütun; içindeki $n kart da silinecek.', n == 1 ? 'This is the last column; its card will be deleted too.' : 'This is the last column; its $n cards will be deleted too.');
  String get deleteCardsToo => pick('Kartları da sil', 'Delete the cards too');
  String get noColumns => pick('Bu panoda henüz sütun yok.', 'This board has no columns yet.');

  // Views
  String get canvasView => pick('Tuval', 'Canvas');
  String get kanbanView => pick('Kanban', 'Kanban');
  String canvasItemsNote(int n) => pick('Tuvalde $n not ve çizim var', '$n notes and drawings on the canvas');
  String get showOnCanvas => pick('Tuvalde gör', 'Show on canvas');

  // Cards
  String get card => pick('Kart', 'Card');
  String get addCard => pick('Kart ekle', 'Add card');
  String get cardTitleHint => pick('Kart başlığı', 'Card title');
  String get description => pick('Açıklama', 'Description');
  String get column => pick('Sütun', 'Column');
  String get cardDue => pick('Son tarih', 'Due date');
  String get assignee => pick('Atanan', 'Assignee');
  String get unassigned => pick('Atanmamış', 'Unassigned');
  String get me => pick('Ben', 'Me');
  String get someone => pick('Biri', 'Someone');
  String overdueOn(String date) => pick('Gecikti · $date', 'Overdue · $date');
  String movedTo(String title, String column) => '«$title» → $column';
  String editingNow(String names) => pick('Şu an düzenleyen: $names', 'Also editing: $names');
  String get changedBySomeoneElse => pick('Bu öğe başkası tarafından değiştirildi', 'Someone else changed this item');
  String get savedOnClose =>
      pick('Kapatınca kaydedilir ve ekibinle eşitlenir.', 'Saved when you close, then synced with your team.');
  String get noDue => pick('Tarihi kaldır', 'Remove date');

  /// Screen reader summary of a card; empty parts are left out.
  String cardSemantics({
    required String title,
    required String column,
    String? due,
    String? assignee,
    int subtasksDone = 0,
    int subtasks = 0,
    bool done = false,
  }) {
    final parts = [
      pick('Kart: $title', 'Card: $title'),
      pick('Sütun: $column', 'Column: $column'),
      if (done) pick('Bitti', 'Done'),
      if (due != null) pick('Son tarih: $due', 'Due: $due'),
      if (assignee != null) pick('Atanan: $assignee', 'Assignee: $assignee'),
      if (subtasks > 0) pick('Alt görevler: $subtasksDone/$subtasks', 'Subtasks: $subtasksDone/$subtasks'),
    ];
    return '${parts.join('. ')}.';
  }

  // Accessibility actions
  String get moveToNextColumn => pick('Sonraki sütuna taşı', 'Move to next column');
  String get moveToPreviousColumn => pick('Önceki sütuna taşı', 'Move to previous column');
  String get moveUp => pick('Yukarı taşı', 'Move up');
  String get moveDown => pick('Aşağı taşı', 'Move down');

  // Sync
  String get syncUpToDate => pick('Eşitlendi', 'Up to date');
  String syncSending(int n) => pick('$n değişiklik gönderiliyor', 'Sending $n changes');
  String get syncOffline =>
      pick('Çevrimdışı — değişiklikler kaydedildi, bağlanınca gönderilecek', 'Offline — changes are saved and will be sent when you reconnect');
  String get syncError => pick('Eşitlenemedi. Tekrar denemek için dokun.', "Couldn't sync. Tap to retry.");

  // Read-only boards
  String get boardDeletedBanner =>
      pick('Bu pano sahibi tarafından silindi. Artık değiştirilemez.', 'The owner deleted this board. It can no longer be changed.');
  String get boardRevokedBanner =>
      pick('Bu panoya erişimin kaldırıldı. Artık değiştirilemez.', 'Your access to this board was removed. It can no longer be changed.');
  String get keepCopy => pick('Kopyayı sakla', 'Keep a copy');
  String get copySaved => pick('Kopya bu cihaza kaydedildi.', 'A copy was saved on this device.');
  String get removeFromList => pick('Listeden kaldır', 'Remove from list');
}
