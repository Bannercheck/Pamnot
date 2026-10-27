import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../l10n/strings.dart';
import '../../models/reminder.dart';

/// "Today 14:20", "Tomorrow", "Fri 9:30", "12 Oct".
String formatWhen(S s, DateTime d, {required DateTime now, bool withTime = true}) {
  final today = dateOnly(now);
  final day = dateOnly(d);
  final diff = day.difference(today).inDays;
  final time = withTime ? ' ${hhmm(d)}' : '';
  if (diff == 0) return '${s.dueToday}$time';
  if (diff == 1) return '${s.tomorrow}$time';
  if (diff > 1 && diff < 7) return '${DateFormat('EEEE', s.locale).format(d)}$time';
  final pattern = d.year == now.year ? 'd MMM' : 'd MMM y';
  return '${DateFormat(pattern, s.locale).format(d)}$time';
}

String repeatLabel(S s, Repeat r) => switch (r) {
      Repeat.none => s.repeatNone,
      Repeat.daily => s.repeatDaily,
      Repeat.weekly => s.repeatWeekly,
      Repeat.monthly => s.repeatMonthly,
      Repeat.yearly => s.repeatYearly,
    };

String longDate(S s, DateTime d) => DateFormat('d MMMM EEEE', s.locale).format(d);
