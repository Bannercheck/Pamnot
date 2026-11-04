import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'boards/cloud/cloud_scope.dart';
import 'boards/cloud/cloud_service.dart';
import 'boards/sync/board_sync.dart';
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
  final store = KeyValueStore.platformDefault();
  final controller = AppController(
    store: store,
    scheduler: scheduler,
    widgetSync: widgets,
    handwriting: HandwritingRecognizer.platformDefault(),
  );
  await controller.load();

  // Shared boards: the cloud link decides which boards get a live sync
  // connection. Without a configured server every board stays device-only.
  final cloud = CloudService(store: store);
  cloud.attach(
    controller.boards,
    connections: (board, boards) => BoardSync(board: board, controller: boards, backend: cloud.backend!, session: cloud),
  );
  runApp(CloudScope(service: cloud, child: PamnotApp(controller: controller)));

  // Everything below is off the critical path to the first frame.
  unawaited(scheduler.init().then((_) => controller.syncAlerts()));
  unawaited(WordPredictor.load(rootBundle).then(controller.attachPredictor));
  controller.startInAppTicker();
  // A saved session makes it ready without waiting for the network.
  unawaited(cloud.start());
}
