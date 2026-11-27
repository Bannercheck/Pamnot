import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/motivation.dart';
import 'data/store.dart';
import 'features/overdue/overdue_inbox.dart';
import 'features/overdue/overdue_notice.dart';
import 'prediction/word_predictor.dart';
import 'services/alarm_scheduler.dart';
import 'services/calendar/device_calendar_source.dart';
import 'services/handwriting.dart';
import 'services/launch_actions.dart';
import 'services/pip_player.dart';
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

  late final AppController controller;
  final scheduler = LocalNotificationScheduler(
    onTap: (payload) => notificationTaps.value = payload,
    // Read in init(), after load(): the actions follow the app's language.
    strings: () => controller.strings,
  );
  final widgets = WidgetSync.platformDefault()..listenForTaps((p) => notificationTaps.value = p);
  controller = AppController(
    store: KeyValueStore.platformDefault(),
    scheduler: scheduler,
    widgetSync: widgets,
    handwriting: HandwritingRecognizer.platformDefault(),
    // Building the engine asks for no permission and does not call the plugin.
    speech: createSpeechEngine(),
    // Building it asks for nothing; alarm permission waits for the first
    // time Alarm is picked.
    alarms: createAlarmScheduler(),
    // Building it asks for nothing; calendar permission waits for the first
    // tap on "Show calendar" in Plan.
    calendar: createCalendarSource(),
    // Building it plays nothing; a guide video starts only from a tap.
    pip: createPipPlayer(),
    alertProviders: const [overdueAlerts],
  );
  await controller.load();
  // The same documents the background Done action writes to.
  final overdueInbox = OverdueInbox(KeyValueStore.platformDefault());
  _listenForOverdueDone(controller, overdueInbox);
  runApp(PamnotApp(controller: controller, overdueInbox: overdueInbox));
  unawaited(applyOverdueInbox(controller, overdueInbox));

  // Everything below is off the critical path to the first frame.
  // The motivation lines join the first sync, once the first frame is out.
  unawaited(Future.wait([scheduler.init(), _loadQuotes(controller)]).then((_) => controller.syncAlerts()));
  unawaited(WordPredictor.load(rootBundle).then(controller.attachPredictor));
  controller.startInAppTicker();
}

/// A Done tapped on a final notice while the app runs pings this port; the
/// task is completed at once instead of on the next resume.
void _listenForOverdueDone(AppController controller, OverdueInbox inbox) {
  if (kIsWeb) return;
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(OverdueInbox.portName);
  IsolateNameServer.registerPortWithName(port.sendPort, OverdueInbox.portName);
  port.listen((_) => unawaited(applyOverdueInbox(controller, inbox)));
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
