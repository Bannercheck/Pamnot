import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_sync.dart';

WidgetSync createWidgetSync() =>
    (Platform.isIOS || Platform.isAndroid) ? _HomeWidgetSync() : NoopWidgetSync();

class _HomeWidgetSync extends DedupingWidgetSync {
  bool _groupSet = false;

  /// The native widgets open `pamnot://today?homeWidget` (today) and
  /// `pamnot://list/<id>?homeWidget` (the list widget).
  @override
  void listenForTaps(void Function(String payload) onTap) {
    void handle(Uri? uri) {
      if (uri == null) return;
      if (uri.host == 'today') {
        onTap('w:today');
      } else if (uri.host == 'list') {
        final segments = uri.pathSegments;
        onTap('w:list:${segments.isEmpty ? '' : segments.first}');
      }
    }

    HomeWidget.initiallyLaunchedFromHomeWidget().then(handle, onError: (_) {});
    HomeWidget.widgetClicked.listen(handle, onError: (_) {});
  }

  Future<void> _ensureGroup() async {
    if (_groupSet || !Platform.isIOS) return;
    await HomeWidget.setAppGroupId(WidgetSync.appGroupId);
    _groupSet = true;
  }

  @override
  Future<void> write(String json) async {
    try {
      await _ensureGroup();
      await HomeWidget.saveWidgetData<String>(WidgetSync.dataKey, json);
      await HomeWidget.updateWidget(
        iOSName: WidgetSync.iOSName,
        qualifiedAndroidName: WidgetSync.androidName,
      );
    } catch (e) {
      // No widget installed yet, or the extension isn't built: harmless.
      debugPrint('Widget update skipped: $e');
    }
  }

  /// Only iOS has a list widget; Android keeps the data and reloads nothing.
  @override
  Future<void> writeLists(String json) async {
    try {
      await _ensureGroup();
      await HomeWidget.saveWidgetData<String>(WidgetSync.listsKey, json);
      if (Platform.isIOS) await HomeWidget.updateWidget(iOSName: WidgetSync.iOSListName);
    } catch (e) {
      debugPrint('List widget update skipped: $e');
    }
  }

  @override
  Future<List<String>> takePendingDone() async {
    try {
      await _ensureGroup();
      final text = await HomeWidget.getWidgetData<String>(WidgetSync.pendingDoneKey);
      final ids = DedupingWidgetSync.decodePending(text);
      // Cleared even when unreadable, so a damaged value is not read forever.
      if (text != null && text != '[]') await HomeWidget.saveWidgetData<String>(WidgetSync.pendingDoneKey, '[]');
      return ids;
    } catch (e) {
      debugPrint('Pending widget completions unreadable: $e');
      return const [];
    }
  }
}
