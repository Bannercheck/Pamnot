import 'package:flutter/material.dart';

/// The icons a list can carry, by the key stored in [TaskList.icon]. The
/// ready-made lists use `person`, `work`, `school`, `shopping` and `home`.
const listIcons = <String, IconData>{
  'list': Icons.list_rounded,
  'person': Icons.person_rounded,
  'work': Icons.work_rounded,
  'school': Icons.school_rounded,
  'shopping': Icons.shopping_cart_rounded,
  'home': Icons.home_rounded,
  'star': Icons.star_rounded,
  'favorite': Icons.favorite_rounded,
  'fitness': Icons.fitness_center_rounded,
  'travel': Icons.flight_rounded,
  'book': Icons.menu_book_rounded,
  'pets': Icons.pets_rounded,
  'money': Icons.savings_rounded,
  'health': Icons.local_hospital_rounded,
  'music': Icons.music_note_rounded,
  'idea': Icons.lightbulb_rounded,
};

/// The icon of [key]; an unknown key (a newer app's icon) shows as `list`.
IconData listIconOf(String key) => listIcons[key] ?? Icons.list_rounded;
