import 'package:flutter/foundation.dart';

import '../../state/app_controller.dart';
import 'calendar_models.dart';

/// The calendar page's state: view mode, anchor day, loaded events and
/// moving items.
///
/// Skeleton from Task 8: harmless defaults only; Task 10 fills it in.
class CalendarViewController extends ChangeNotifier {
  CalendarViewController(this.app);

  final AppController app;

  CalendarViewMode get mode => CalendarViewMode.day;
  set mode(CalendarViewMode m) {}

  bool get showPamnot => true;
  set showPamnot(bool v) {}

  DateTime get anchor {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void goTo(DateTime day) {}
  void shift(int direction) {}
  void goToday() {}

  /// Loads the events of the visible range.
  Future<void> ensureRange() async {}

  List<DayItem> timedOn(DateTime day) => const [];
  List<DayItem> allDayOn(DateTime day) => const [];

  /// At most [maxMonthDots] dots and how many more there are.
  ({List<DayItem> dots, int more}) dotsOn(DateTime day) => (dots: const <DayItem>[], more: 0);

  /// Moves [item] to [newStart]; returns the undo, or null when it cannot move.
  VoidCallback? move(DayItem item, DateTime newStart) => null;
}
