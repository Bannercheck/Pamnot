import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_sync.dart';

WidgetSync createWidgetSync() =>
    (Platform.isIOS || Platform.isAndroid) ? _HomeWidgetSync() : NoopWidgetSync();

class _HomeWidgetSync extends DedupingWidgetSync {
  bool _groupSet = false;

  /// The native widgets open `pamnot://today?homeWidget`.
  @override
  void listenForTaps(void Function() onTap) {
    void handle(Uri? uri) {
      if (uri?.host == 'today') onTap();
    }

    HomeWidget.initiallyLaunchedFromHomeWidget().then(handle, onError: (_) {});
    HomeWidget.widgetClicked.listen(handle, onError: (_) {});
  }

  @override
  Future<void> write(String json) async {
    try {
      if (!_groupSet && Platform.isIOS) {
        await HomeWidget.setAppGroupId(WidgetSync.appGroupId);
        _groupSet = true;
      }
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
}
