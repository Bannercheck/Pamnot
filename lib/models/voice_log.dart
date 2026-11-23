/// One recognised sentence and what the parser made of it. Kept on this
/// device only, and only while the user has turned on "keep recognised text"
/// in Settings (off by default). The audio itself is never stored.
class VoiceLogEntry {
  const VoiceLogEntry({
    required this.at,
    required this.localeId,
    required this.transcript,
    required this.title,
    this.due,
    this.hasTime = false,
    this.remind = false,
    this.isNote = false,
  });

  /// When the sentence was recognised.
  final DateTime at;

  /// The recognition language, e.g. `tr-TR`.
  final String localeId;

  /// The text exactly as the speech recogniser returned it.
  final String transcript;

  /// The parsed title (the note's body when [isNote] is set).
  final String title;
  final DateTime? due;
  final bool hasTime;
  final bool remind;
  final bool isNote;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'localeId': localeId,
        'transcript': transcript,
        'title': title,
        if (due != null) 'due': due!.toIso8601String(),
        'hasTime': hasTime,
        'remind': remind,
        'isNote': isNote,
      };

  factory VoiceLogEntry.fromJson(Map<String, Object?> j) => VoiceLogEntry(
        at: DateTime.parse(j['at']! as String),
        localeId: (j['localeId'] as String?) ?? '',
        transcript: (j['transcript'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        due: j['due'] is String ? DateTime.tryParse(j['due']! as String) : null,
        hasTime: j['hasTime'] == true,
        remind: j['remind'] == true,
        isNote: j['isNote'] == true,
      );
}
