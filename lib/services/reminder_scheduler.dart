import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../features/overdue/overdue_inbox.dart';
import '../features/overdue/overdue_notice.dart';
import '../l10n/strings.dart';
import '../models/reminder.dart';

/// One notification the app wants delivered.
class Alert {
  const Alert({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
    this.repeat = Repeat.none,
    this.alarm = false,
    this.category,
  });

  /// Stable string id (`r:<reminderId>` or `t:<taskId>`).
  final String key;
  final String title;
  final String body;
  final DateTime at;
  final Repeat repeat;

  /// Rings as an alarm (AlarmKit) instead of a notification.
  final bool alarm;

  /// Notification category: null for an ordinary alert, `'overdue'` for the
  /// final notice of a task past its due time (it carries Done and Snooze).
  final String? category;

  /// Notification ids must be 32-bit ints; FNV-1a keeps them stable.
  int get id {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  /// An alert without a [category] keeps the fingerprint it had before
  /// categories existed.
  String get fingerprint =>
      '$key|$title|$body|${at.toIso8601String()}|${repeat.name}|$alarm${category == null ? '' : '|$category'}';
}

abstract class ReminderScheduler {
  Future<void> init();
  Future<bool> requestPermission();

  /// Whether the OS currently lets the app post notifications. Never shows
  /// a prompt.
  Future<bool> isGranted();

  /// Whether the OS delivers notifications while the app is closed.
  bool get schedulesInBackground;

  /// Replaces everything scheduled with [alerts].
  Future<void> sync(List<Alert> alerts);
  Future<void> showNow(String title, String body);
}

class NoopScheduler implements ReminderScheduler {
  final List<List<Alert>> synced = [];

  /// What [isGranted] answers; [requestPermission] grants.
  bool granted = false;

  /// How many times [requestPermission] was called.
  int permissionRequests = 0;

  /// Called at the start of [requestPermission], before it answers.
  void Function()? onRequest;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    onRequest?.call();
    permissionRequests++;
    granted = true;
    return true;
  }

  @override
  Future<bool> isGranted() async => granted;

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
  /// [strings] gives the titles of the final notice's actions, read once
  /// in [init]; English when omitted.
  LocalNotificationScheduler({this.onTap, S Function()? strings}) : _strings = strings ?? (() => S.en);

  final void Function(String? payload)? onTap;
  final S Function() _strings;
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
      final darwin = _darwinSettings(_strings());
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_pamnot'),
          iOS: darwin,
          macOS: darwin,
          linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: const WindowsInitializationSettings(
            appName: 'Pamnot',
            appUserModelId: 'App.Pamnot.Notes',
            guid: '6f1d2c8e-9a4b-4f3e-b1a7-2c5d8e9f0a12',
          ),
        ),
        onDidReceiveNotificationResponse: respond,
        // Done tapped while the app is not running.
        onDidReceiveBackgroundNotificationResponse: overdueBackgroundAction,
      );
      _ready = true;
      if (!kIsWeb) {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final response = launch?.notificationResponse;
        if ((launch?.didNotificationLaunchApp ?? false) && response != null) await respond(response);
      }
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// No permission is asked here. Done finishes the task without opening
  /// the app; Snooze opens it on the snooze screen.
  static DarwinInitializationSettings _darwinSettings(S s) => DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(overdueCategory, actions: [
            DarwinNotificationAction.plain('done', s.overdueClose),
            DarwinNotificationAction.plain(
              'snooze',
              s.overdueSnooze,
              options: const {DarwinNotificationActionOption.foreground},
            ),
          ]),
        ],
      );

  /// A response while the app runs: Done takes the background path (the
  /// inbox and its ping), so a task is finished one way only; anything else
  /// is a tap on [NotificationResponse.payload].
  @visibleForTesting
  Future<void> respond(NotificationResponse r) async {
    if (r.actionId == 'done') return overdueBackgroundAction(r);
    onTap?.call(r.payload);
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
        // No badge: the app never sets one.
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: false, sound: true) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: false, sound: true) ??
              false;
        default:
          return true;
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isGranted() async {
    await init();
    if (!_ready) return false;
    try {
      if (kIsWeb) return true;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _plugin
                  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                  ?.areNotificationsEnabled() ??
              false;
        case TargetPlatform.iOS:
          final options = await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions();
          return options?.isEnabled ?? false;
        case TargetPlatform.macOS:
          final options = await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions();
          return options?.isEnabled ?? false;
        default:
          return true;
      }
    } catch (e) {
      debugPrint('Permission check failed: $e');
      return false;
    }
  }

  static const _android = AndroidNotificationDetails(
    'pamnot_reminders',
    'Reminders',
    channelDescription: 'Pamnot reminders and task alerts',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF9B8AD8),
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  /// A final notice carries the Done and Snooze actions on iOS and macOS.
  static const NotificationDetails _overdueDetails = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(categoryIdentifier: overdueCategory),
    macOS: DarwinNotificationDetails(categoryIdentifier: overdueCategory),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  static NotificationDetails _detailsFor(Alert a) => a.category == overdueCategory ? _overdueDetails : _details;

  @override
  Future<void> sync(List<Alert> alerts) async {
    await init();
    if (!_ready || kIsWeb) return;
    final chosen = choose(alerts, DateTime.now());
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
          notificationDetails: _detailsFor(a),
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

  /// The alerts that get a pending notification: the [_maxPending] whose
  /// next occurrence after [now] is nearest, nearest first, each with that
  /// occurrence. A one-time alert in the past has none and is left out.
  @visibleForTesting
  static List<(Alert, DateTime)> choose(List<Alert> alerts, DateTime now) {
    final upcoming = <(Alert, DateTime)>[];
    for (final a in alerts) {
      final next = Reminder(id: a.key, title: a.title, at: a.at, repeat: a.repeat, createdAt: now)
          .nextOccurrence(now);
      if (next != null) upcoming.add((a, next));
    }
    upcoming.sort((x, y) => x.$2.compareTo(y.$2));
    return upcoming.take(_maxPending).toList();
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
