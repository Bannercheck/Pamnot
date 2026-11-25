import 'dart:convert';

import 'widget_sync_io.dart' if (dart.library.js_interop) 'widget_sync_web.dart' as platform;

/// Pushes the summaries the home-screen widgets render (iOS WidgetKit and
/// Android App Widgets). The native widgets read the JSON under [dataKey]
/// (today) and [listsKey] (the iOS list widget).
abstract class WidgetSync {
  static const appGroupId = 'group.app.pamnot.shared';
  static const dataKey = 'pamnot_today';
  static const iOSName = 'PamnotTodayWidget';
  static const androidName = 'app.pamnot.pamnot.widget.PamnotTodayWidgetProvider';

  /// Every list with its open tasks per box; see `AppController.listsSummary`.
  static const listsKey = 'pamnot_lists';

  /// Ids of tasks marked done on the widget, as JSON array text: `["id", …]`.
  static const pendingDoneKey = 'pamnot_pending_done';
  static const iOSListName = 'PamnotListWidget';

  Future<void> push(Map<String, Object?> summary);

  /// Writes the list summary under [listsKey] and reloads [iOSListName].
  Future<void> pushLists(Map<String, Object?> summary);

  /// The ids under [pendingDoneKey]; the key is set back to `[]`. Returns an
  /// empty list when there is nothing or it can't be read.
  Future<List<String>> takePendingDone();

  /// Calls [onTap] when the app is opened (or brought back) from a widget,
  /// with `w:today` or `w:list:<id>`.
  void listenForTaps(void Function(String payload) onTap) {}

  static WidgetSync platformDefault() => platform.createWidgetSync();
}

class NoopWidgetSync implements WidgetSync {
  Map<String, Object?>? last;
  Map<String, Object?>? lastLists;

  /// What [takePendingDone] returns next; tests fill it.
  List<String> pending = [];

  @override
  void listenForTaps(void Function(String payload) onTap) {}

  @override
  Future<void> push(Map<String, Object?> summary) async => last = summary;

  @override
  Future<void> pushLists(Map<String, Object?> summary) async => lastLists = summary;

  @override
  Future<List<String>> takePendingDone() async {
    final out = pending;
    pending = [];
    return out;
  }
}

/// Skips the platform call when nothing changed since the last push.
abstract class DedupingWidgetSync implements WidgetSync {
  String _last = '';
  String _lastLists = '';

  Future<void> write(String json);
  Future<void> writeLists(String json);

  @override
  void listenForTaps(void Function(String payload) onTap) {}

  @override
  Future<void> push(Map<String, Object?> summary) async {
    final key = _keyOf(summary);
    if (key == _last) return;
    _last = key;
    await write(jsonEncode(summary));
  }

  @override
  Future<void> pushLists(Map<String, Object?> summary) async {
    final key = _keyOf(summary);
    if (key == _lastLists) return;
    _lastLists = key;
    await writeLists(jsonEncode(summary));
  }

  static String _keyOf(Map<String, Object?> summary) => jsonEncode({...summary}..remove('updatedAt'));

  /// Reads [WidgetSync.pendingDoneKey]'s text: the ids in it, skipping
  /// anything that isn't a non-empty string. Unreadable text gives none.
  static List<String> decodePending(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final j = jsonDecode(text);
      if (j is! List) return const [];
      return [for (final e in j) if (e is String && e.isNotEmpty) e];
    } catch (_) {
      return const [];
    }
  }
}
