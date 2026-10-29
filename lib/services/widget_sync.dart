import 'dart:convert';

import 'widget_sync_io.dart' if (dart.library.js_interop) 'widget_sync_web.dart' as platform;

/// Pushes the "today" summary to the home-screen widgets (iOS WidgetKit and
/// Android App Widgets). The native widgets read the JSON under [dataKey].
abstract class WidgetSync {
  static const appGroupId = 'group.app.pamnot.shared';
  static const dataKey = 'pamnot_today';
  static const iOSName = 'PamnotTodayWidget';
  static const androidName = 'app.pamnot.pamnot.widget.PamnotTodayWidgetProvider';

  Future<void> push(Map<String, Object?> summary);

  /// Calls [onTap] when the app is opened (or brought back) from a widget.
  void listenForTaps(void Function() onTap) {}

  static WidgetSync platformDefault() => platform.createWidgetSync();
}

class NoopWidgetSync implements WidgetSync {
  Map<String, Object?>? last;

  @override
  void listenForTaps(void Function() onTap) {}

  @override
  Future<void> push(Map<String, Object?> summary) async => last = summary;
}

/// Skips the platform call when nothing changed since the last push.
abstract class DedupingWidgetSync implements WidgetSync {
  String _last = '';

  Future<void> write(String json);

  @override
  void listenForTaps(void Function() onTap) {}

  @override
  Future<void> push(Map<String, Object?> summary) async {
    final copy = {...summary}..remove('updatedAt');
    final key = jsonEncode(copy);
    if (key == _last) return;
    _last = key;
    await write(jsonEncode(summary));
  }
}
