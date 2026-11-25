import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/reminder.dart';
import '../models/task.dart';

/// The first-run workspace: a single welcome note. Tasks, reminders and habits
/// start empty, so nothing the user did not add shows up or gets scheduled.
class SampleData {
  const SampleData(this.notes, this.tasks, this.reminders, this.habits);

  final List<Note> notes;
  final List<TaskItem> tasks;
  final List<Reminder> reminders;
  final List<Habit> habits;

  static SampleData build(S s, DateTime now, String Function() id) {
    final tr = s.isTr;
    // Only Android ships a home-screen widget in this release.
    final hasWidget = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final tips = tr
        ? [
            '• Notlarına yazı ekleyebilir ya da Apple Pencil ile el yazısıyla yazabilirsin.',
            '• Yazarken klavyenin üstünde Türkçe ve İngilizce kelime önerileri çıkar. Öneriye dokun ya da Tab tuşuna bas.',
            '• Matris sekmesinde görevlerini listelere ve kutulara ayır; alışkanlıkların da orada.',
            '• Plan sekmesinde haftanı düzenle; anımsatıcılar sana zamanında haber versin.',
            if (hasWidget) '• Ana ekranına Pamnot widget’ını ekleyerek bugünün planını hep gör.',
          ]
        : [
            '• Type your notes or write them by hand with Apple Pencil.',
            '• Word suggestions in English and Turkish appear above the keyboard as you type. Tap one or press Tab.',
            '• Sort your tasks into lists and boxes in the Matrix tab; your habits are there too.',
            '• Shape your week in Plan; reminders reach you right on time.',
            if (hasWidget) '• Add the Pamnot widget to your home screen to keep today in sight.',
          ];

    final welcome = Note(
      id: id(),
      title: tr ? 'Pamnot’a hoş geldin 🌸' : 'Welcome to Pamnot 🌸',
      body: tips.join('\n'),
      colorIndex: 3,
      pinned: true,
      createdAt: now,
      updatedAt: now,
    );

    // Growable: the controller adds to these lists in place.
    return SampleData([welcome], [], [], []);
  }
}
