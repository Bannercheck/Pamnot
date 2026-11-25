import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/motivation.dart';
import 'data/store.dart';
import 'prediction/word_predictor.dart';
import 'services/alarm_scheduler.dart';
import 'services/handwriting.dart';
import 'services/launch_actions.dart';
import 'services/reminder_scheduler.dart';
import 'services/speech/stt_speech_engine.dart';
import 'services/system_accessibility.dart';
import 'services/widget_sync.dart';
import 'state/app_controller.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before runApp: a shortcut that launched the app is waiting on the iOS side.
  LaunchActionsBridge.start();
  SystemAccessibility.start();
  await initializeDateFormatting();

  final scheduler = LocalNotificationScheduler(onTap: (payload) => notificationTaps.value = payload);
  final widgets = WidgetSync.platformDefault()..listenForTaps(() => notificationTaps.value = 'w:today');
  final controller = AppController(
    store: KeyValueStore.platformDefault(),
    scheduler: scheduler,
    widgetSync: widgets,
    handwriting: HandwritingRecognizer.platformDefault(),
    // Building the engine asks for no permission and does not call the plugin.
    speech: createSpeechEngine(),
    // Building it asks for nothing; alarm permission waits for the first
    // time Alarm is picked.
    alarms: createAlarmScheduler(),
  );
  await controller.load();
  runApp(PamnotApp(controller: controller));

  // Everything below is off the critical path to the first frame.
  // The motivation lines join the first sync, once the first frame is out.
  unawaited(Future.wait([scheduler.init(), _loadQuotes(controller)]).then((_) => controller.syncAlerts()));
  unawaited(WordPredictor.load(rootBundle).then(controller.attachPredictor));
  controller.startInAppTicker();
}

Future<void> _loadQuotes(AppController controller) async {
  await WidgetsBinding.instance.endOfFrame;
  try {
    final files = await Future.wait([
      rootBundle.loadString('assets/quotes/tr.txt'),
      rootBundle.loadString('assets/quotes/en.txt'),
    ]);
    controller.attachQuotes(tr: parseQuotes(files[0]), en: parseQuotes(files[1]));
  } catch (e) {
    // Without the lines there is simply no motivation notification.
    debugPrint('Quotes unreadable: $e');
  }
}
