import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';

/// A loaded [AppController] on an in-memory store with a clock the test
/// moves by hand, for widget tests of the voice screen and its controller.
class VoiceHarness {
  VoiceHarness._();

  /// The app's clock; tests move it to simulate time spent in the background.
  DateTime now = DateTime(2026, 11, 23, 9);

  late final MemoryStore store;
  late final NoopScheduler scheduler;
  late final AppController app;

  /// [settings] defaults to Turkish with the sample data already seeded (so
  /// the app starts empty). Saves are written without the usual pause.
  /// [speech] becomes the app's engine (what a screen opened without its own
  /// engine uses).
  static Future<VoiceHarness> create(WidgetTester tester, {AppSettings? settings, SpeechEngine? speech}) async {
    // The app's widget sync formats dates.
    await initializeDateFormatting();
    final h = VoiceHarness._();
    final s = settings ?? const AppSettings(language: AppLanguage.tr, seeded: true);
    h.store = MemoryStore({'settings': jsonEncode(s.toJson())});
    h.scheduler = NoopScheduler();
    h.app = AppController(
      store: h.store,
      scheduler: h.scheduler,
      speech: speech,
      clock: () => h.now,
      saveDelay: Duration.zero,
    );
    await tester.runAsync(h.app.load);
    return h;
  }

  /// Lets the app's pending saves and alert syncs run, then disposes it.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    app.dispose();
  }
}
