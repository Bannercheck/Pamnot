import 'package:flutter/widgets.dart';

import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'calendar/calendar_view_controller.dart';

/// The v3 features (calendar, meetings, sync, sharing) next to the
/// [AppController]. Feature state lives here, never in the controller.
///
/// Later milestones add optional named bridge parameters to the constructor;
/// an omitted bridge falls back to its in-memory `No…` implementation. Only
/// `main.dart` passes the real platform bridges.
class Features {
  Features({required this.app});

  final AppController app;

  /// The calendar page's state, created on first use.
  late final CalendarViewController calendar = CalendarViewController(app);

  /// No platform bridges; everything runs in memory.
  static Features local(AppController app) => Features(app: app);

  static final _fallback = Expando<Features>('Features.local');

  /// The [Features.local] kept for [app], created once.
  static Features _localFor(AppController app) => _fallback[app] ??= local(app);

  /// Reads the feature documents. Called after `runApp`, without awaiting,
  /// so it never delays the first frame.
  Future<void> load() async {}

  /// The nearest [FeaturesScope]; without one, the [Features.local] kept for
  /// the [AppScope]'s controller, the same instance every time.
  static Features of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FeaturesScope>()?.features ?? _localFor(AppScope.of(context));
}

/// Gives the widget tree the [Features].
class FeaturesScope extends InheritedWidget {
  const FeaturesScope({super.key, required this.features, required super.child});

  final Features features;

  @override
  bool updateShouldNotify(FeaturesScope oldWidget) => !identical(features, oldWidget.features);
}

