import '../../models/habit.dart';
import '../../models/note.dart';
import '../../models/reminder.dart';
import '../../models/task.dart';
import '../../models/task_list.dart';

/// Changes that arrived from another device, applied together by
/// `AppController.applyRemote`: removals first, then the upserts.
class RemoteBatch {
  const RemoteBatch({
    this.lists = const [],
    this.tasks = const [],
    this.notes = const [],
    this.reminders = const [],
    this.habits = const [],
    this.removedLists = const {},
    this.removedTasks = const {},
    this.removedNotes = const {},
    this.removedReminders = const {},
    this.removedHabits = const {},
    this.inkChanged = const {},
  });

  /// Items to insert or replace, matched by id.
  final List<TaskList> lists;
  final List<TaskItem> tasks;
  final List<Note> notes;
  final List<Reminder> reminders;
  final List<Habit> habits;

  /// Ids of items to remove.
  final Set<String> removedLists;
  final Set<String> removedTasks;
  final Set<String> removedNotes;
  final Set<String> removedReminders;
  final Set<String> removedHabits;

  /// Ids of notes in [notes] whose ink came with them; for any other note
  /// the ink already on this device is kept.
  final Set<String> inkChanged;

  bool get isEmpty =>
      lists.isEmpty &&
      tasks.isEmpty &&
      notes.isEmpty &&
      reminders.isEmpty &&
      habits.isEmpty &&
      removedLists.isEmpty &&
      removedTasks.isEmpty &&
      removedNotes.isEmpty &&
      removedReminders.isEmpty &&
      removedHabits.isEmpty;
}
