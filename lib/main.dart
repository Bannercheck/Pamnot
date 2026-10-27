import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/store.dart';
import 'prediction/word_predictor.dart';
import 'services/handwriting.dart';
import 'services/reminder_scheduler.dart';
import 'services/widget_sync.dart';
import 'state/app_controller.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  final scheduler = LocalNotificationScheduler(onTap: (payload) => notificationTaps.value = payload);
  final widgets = WidgetSync.platformDefault()..listenForTaps(() => notificationTaps.value = 'w:today');
  final controller = AppController(
    store: KeyValueStore.platformDefault(),
    scheduler: scheduler,
    widgetSync: widgets,
    handwriting: HandwritingRecognizer.platformDefault(),
  );
  await controller.load();
  runApp(PamukApp(controller: controller));

  // Everything below is off the critical path to the first frame.
  unawaited(scheduler.init().then((_) => controller.syncAlerts()));
  unawaited(WordPredictor.load(rootBundle).then(controller.attachPredictor));
  controller.startInAppTicker();
}
