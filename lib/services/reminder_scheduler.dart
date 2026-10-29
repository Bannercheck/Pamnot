import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// One notification the app wants delivered.
class Alert {
  const Alert({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
    this.repeat = Repeat.none,
  });

  /// Stable string id (`r:<reminderId>` or `t:<taskId>`).
  final String key;
  final String title;
  final String body;
  final DateTime at;
  final Repeat repeat;

  /// Notification ids must be 32-bit ints; FNV-1a keeps them stable.
  int get id {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  String get fingerprint => '$key|$title|$body|${at.toIso8601String()}|${repeat.name}';
}

abstract class ReminderScheduler {
  Future<void> init();
  Future<bool> requestPermission();

  /// Whether the OS delivers notifications while the app is closed.
  bool get schedulesInBackground;

  /// Replaces everything scheduled with [alerts].
  Future<void> sync(List<Alert> alerts);
  Future<void> showNow(String title, String body);
}

class NoopScheduler implements ReminderScheduler {
  final List<List<Alert>> synced = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  bool get schedulesInBackground => false;

  @override
  Future<void> sync(List<Alert> alerts) async => synced.add(alerts);

  @override
  Future<void> showNow(String title, String body) async {}
}

/// Local notifications on iOS, iPadOS, macOS, Android, Windows and Linux.
/// Web has no background scheduling, so there it only shows notifications
/// while the app is open (see [AppController]'s in-app ticker).
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler({this.onTap});

  final void Function(String? payload)? onTap;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _lastFingerprint = '';

  /// iOS keeps at most 64 pending notifications per app.
  static const _maxPending = 60;

  static bool get _nativeRepeat =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  bool get schedulesInBackground => !kIsWeb;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      if (!kIsWeb) await _initTimeZone();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_pamnot'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'Pamnot',
            appUserModelId: 'App.Pamnot.Notes',
            guid: '6f1d2c8e-9a4b-4f3e-b1a7-2c5d8e9f0a12',
          ),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      _ready = true;
      if (!kIsWeb) {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) onTap?.call(launch!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  static Future<void> _initTimeZone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return;
    } catch (_) {}
    // Unknown identifier: pick any zone with today's offset.
    final offset = DateTime.now().timeZoneOffset;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.timeZone(now).offset == offset) {
        tz.setLocalLocation(loc);
        return;
      }
    }
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      if (kIsWeb) {
        return await _plugin
                .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                  ?.requestNotificationsPermission() ??
              false;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
        default:
          return true;
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          'pamnot_reminders',
          'Reminders',
          channelDescription: 'Pamnot reminders and task alerts',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF9B8AD8),
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      );

  @override
  Future<void> sync(List<Alert> alerts) async {
    await init();
    if (!_ready || kIsWeb) return;
    final now = DateTime.now();
    final upcoming = <(Alert, DateTime)>[];
    for (final a in alerts) {
      final next = Reminder(id: a.key, title: a.title, at: a.at, repeat: a.repeat, createdAt: now)
          .nextOccurrence(now);
      if (next != null) upcoming.add((a, next));
    }
    upcoming.sort((x, y) => x.$2.compareTo(y.$2));
    final chosen = upcoming.take(_maxPending).toList();
    final fp = chosen.map((e) => '${e.$1.fingerprint}@${e.$2}').join('\n');
    if (fp == _lastFingerprint) return;

    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      await _plugin.cancelAll();
    }
    final mode = await _androidMode();
    for (final (a, next) in chosen) {
      try {
        await _plugin.zonedSchedule(
          id: a.id,
          title: a.title,
          body: a.body,
          // The OS repeats from the first fire date, so that is the next
          // occurrence. Where repeats aren't native (Windows, Linux) only the
          // next one is scheduled and sync() runs again on every launch.
          scheduledDate: tz.TZDateTime.from(next, tz.local),
          notificationDetails: _details,
          androidScheduleMode: mode,
          payload: a.key,
          matchDateTimeComponents: _nativeRepeat ? _components(a.repeat) : null,
        );
      } catch (e) {
        debugPrint('Could not schedule ${a.key}: $e');
      }
    }
    _lastFingerprint = fp;
  }

  static DateTimeComponents? _components(Repeat r) => switch (r) {
        Repeat.none => null,
        Repeat.daily => DateTimeComponents.time,
        Repeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        Repeat.monthly => DateTimeComponents.dayOfMonthAndTime,
        Repeat.yearly => DateTimeComponents.dateAndTime,
      };

  Future<AndroidScheduleMode> _androidMode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    final exact = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
    return exact == true ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  @override
  Future<void> showNow(String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff, title: title, body: body, notificationDetails: _details);
    } catch (e) {
      debugPrint('Could not show notification: $e');
    }
  }
}
