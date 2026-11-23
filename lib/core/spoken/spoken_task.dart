/// What one spoken sentence asks for: a task (with an optional day and time)
/// or, when [isNote] is set, a note.
class SpokenTask {
  const SpokenTask({
    required this.title,
    this.due,
    this.hasTime = false,
    this.remind = false,
    this.ambiguousHour = false,
    this.isNote = false,
  });

  /// The task title; the note's body when [isNote] is set.
  final String title;

  /// Only the day counts when [hasTime] is false.
  final DateTime? due;

  /// [due] carries a time of day.
  final bool hasTime;

  /// The sentence asked to be reminded ("…mayı hatırlat", "remind me to").
  final bool remind;

  /// The hour was said without morning/evening and was guessed.
  final bool ambiguousHour;

  /// The sentence asked for a note rather than a task.
  final bool isNote;
}
