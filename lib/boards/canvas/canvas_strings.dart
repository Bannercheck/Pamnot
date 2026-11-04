import '../../l10n/strings.dart';

/// Canvas (Tuval) strings. Prefixed so they never clash with the other board
/// string extensions when a file imports several.
extension CanvasStrings on S {
  String get canvasSelect => pick('Seç', 'Select');
  String get canvasNote => pick('Not', 'Note');
  String get canvasStickyNote => pick('Yapışkan not', 'Sticky note');
  String get canvasCard => pick('Kart', 'Card');
  String get canvasFit => pick('Ekrana sığdır', 'Fit to screen');
  String get canvasZoomIn => pick('Yakınlaştır', 'Zoom in');
  String get canvasZoomOut => pick('Uzaklaştır', 'Zoom out');
  String get canvasDuplicate => pick('Kopyasını oluştur', 'Duplicate');
  String get canvasBringToFront => pick('Öne getir', 'Bring to front');
  String get canvasSendToBack => pick('Arkaya gönder', 'Send to back');
  String get canvasToCard => pick('Karta dönüştür', 'Turn into card');
  String get canvasMore => pick('Diğer', 'More');
  String get canvasRename => pick('Yeniden adlandır', 'Rename');
  String get canvasColumnName => pick('Sütun adı', 'Column name');
  String get canvasStickyHint => pick('Aklındakini yaz…', 'Write your idea…');

  String get canvasCardsLiveInColumns => pick(
    'Kartlar sütunlarda durur. Serbest fikirler için yapışkan not kullan.',
    'Cards live in columns. Use a sticky note for free-form ideas.',
  );
  String get canvasEmpty =>
      pick('Boş tuval. Not’a dokun ya da çift dokunarak not ekle.', 'Empty canvas. Tap Note or double-tap to add one.');
  String get canvasChangedElsewhere => pick('Bu öğe başkası tarafından değiştirildi', 'Someone else changed this item');

  /// The one screen-reader label of the painted canvas.
  String canvasSummary(int n) =>
      pick('Tuval, $n öğe. Liste için Kanban görünümüne geç.', 'Canvas, $n items. Switch to Kanban for a list.');

  /// Undo snack after a card changed column. No suffixes on user content.
  String canvasCardMoved(String title, String column) => '«$title» → $column';

  String canvasOverdue(String date) => pick('Gecikti · $date', 'Overdue · $date');

  /// Name tag on an item a teammate is editing.
  String canvasEditing(String name) => pick('$name düzenliyor', '$name is editing');

  /// Tooltip with the keyboard shortcut, e.g. 'Not (N)'.
  String canvasWithKey(String label, String key) => '$label ($key)';
}
