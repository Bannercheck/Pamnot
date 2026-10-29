import '../core/dates.dart';
import '../l10n/strings.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/reminder.dart';
import '../models/task.dart';

/// A small, friendly first-run workspace so the app never opens empty.
class SampleData {
  const SampleData(this.notes, this.tasks, this.reminders, this.habits);

  final List<Note> notes;
  final List<TaskItem> tasks;
  final List<Reminder> reminders;
  final List<Habit> habits;

  static SampleData build(S s, DateTime now, String Function() id) {
    final tr = s.isTr;
    final today = dateOnly(now);
    DateTime at(int dayOffset, int h, [int m = 0]) =>
        DateTime(today.year, today.month, today.day + dayOffset, h, m);

    final notes = [
      Note(
        id: id(),
        title: tr ? 'Pamnot’a hoş geldin 🌸' : 'Welcome to Pamnot 🌸',
        body: tr
            ? '• Notlarına yazı ekleyebilir ya da Apple Pencil ile el yazısıyla yazabilirsin.\n'
                '• Yazarken klavyenin üstünde Türkçe ve İngilizce kelime önerileri çıkar. Öneriye dokun ya da Tab tuşuna bas.\n'
                '• Takip sekmesinde görevlerini ve alışkanlıklarını izle.\n'
                '• Plan sekmesinde haftanı düzenle; anımsatıcılar sana zamanında haber versin.\n'
                '• Ana ekranına Pamnot widget’ını ekleyerek bugünün planını hep gör.'
            : '• Type your notes or write them by hand with Apple Pencil.\n'
                '• Word suggestions in English and Turkish appear above the keyboard as you type. Tap one or press Tab.\n'
                '• Track your tasks and habits in the Track tab.\n'
                '• Shape your week in Plan; reminders reach you right on time.\n'
                '• Add the Pamnot widget to your home screen to keep today in sight.',
        colorIndex: 3,
        pinned: true,
        createdAt: now,
        updatedAt: now,
      ),
      Note(
        id: id(),
        title: tr ? 'Alışveriş listesi' : 'Shopping list',
        body: tr ? 'Ekmek\nSüt\nYumurta\nDomates\nZeytinyağı\nÇiçek 🌷' : 'Bread\nMilk\nEggs\nTomatoes\nOlive oil\nFlowers 🌷',
        colorIndex: 2,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
      Note(
        id: id(),
        title: tr ? 'Hafta sonu fikirleri' : 'Weekend ideas',
        body: tr
            ? 'Sahilde uzun bir yürüyüş, yeni açılan kahvaltı yeri, akşam film gecesi.'
            : 'A long walk by the sea, the new brunch place, a movie night.',
        colorIndex: 1,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    ];

    final tasks = [
      TaskItem(
        id: id(),
        title: tr ? 'Sunumu bitir' : 'Finish the presentation',
        priority: Priority.high,
        due: at(0, 10),
        hasTime: true,
        colorIndex: 3,
        subtasks: [
          SubTask(id: id(), title: tr ? 'Grafikleri güncelle' : 'Update the charts', done: true),
          SubTask(id: id(), title: tr ? 'Son kontrol' : 'Final check'),
        ],
        createdAt: now,
      ),
      TaskItem(id: id(), title: tr ? 'Annemi ara' : 'Call mom', due: today, colorIndex: 1, createdAt: now),
      TaskItem(
        id: id(),
        title: tr ? 'Faturayı öde' : 'Pay the bill',
        due: at(1, 0),
        colorIndex: 5,
        createdAt: now,
      ),
      TaskItem(id: id(), title: tr ? '20 sayfa kitap oku' : 'Read 20 pages', colorIndex: 2, createdAt: now),
    ];

    final reminders = [
      Reminder(
        id: id(),
        title: tr ? 'Toplantıya hazırlan' : 'Get ready for the meeting',
        at: at(1, 9, 30),
        colorIndex: 4,
        createdAt: now,
      ),
      Reminder(
        id: id(),
        title: tr ? 'Su iç 💧' : 'Drink water 💧',
        at: at(0, 15),
        repeat: Repeat.daily,
        colorIndex: 2,
        enabled: false,
        createdAt: now,
      ),
    ];

    final habits = [
      Habit(
        id: id(),
        name: tr ? 'Su iç' : 'Drink water',
        emoji: '💧',
        colorIndex: 4,
        checkins: {for (var i = 1; i <= 4; i++) dayKey(addDays(today, -i))},
        createdAt: now,
      ),
      Habit(
        id: id(),
        name: tr ? 'Yürüyüş' : 'Walk',
        emoji: '🚶',
        colorIndex: 2,
        targetPerWeek: 4,
        checkins: {dayKey(addDays(today, -1)), dayKey(addDays(today, -3))},
        createdAt: now,
      ),
      Habit(
        id: id(),
        name: tr ? 'Kitap oku' : 'Read',
        emoji: '📖',
        colorIndex: 3,
        targetPerWeek: 5,
        checkins: {dayKey(addDays(today, -2))},
        createdAt: now,
      ),
    ];

    return SampleData(notes, tasks, reminders, habits);
  }
}
