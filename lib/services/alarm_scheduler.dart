import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder.dart';
import 'reminder_scheduler.dart';

/// Whether the system lets Pamnot set alarms (AlarmKit, iOS 26+).
enum AlarmAccess { unsupported, notDetermined, denied, authorized }

/// Alarms that ring like the Clock app's (design §7.1).
abstract class AlarmScheduler {
  /// The current permission; never shows a prompt.
  Future<AlarmAccess> access();

  /// Shows the system prompt (only the first time) and answers the result.
  Future<AlarmAccess> requestAccess();

  /// Replaces the installed Pamnot alarms with [alarms]. One-offs in the
  /// past are skipped.
  Future<void> sync(List<Alert> alarms);
}

/// No alarms (tests, and every platform but iOS).
class NoopAlarmScheduler implements AlarmScheduler {
  /// What [access] answers; [requestAccess] sets it to [onRequest].
  AlarmAccess state = AlarmAccess.unsupported;

  /// What [requestAccess] answers.
  AlarmAccess onRequest = AlarmAccess.authorized;

  /// Every list passed to [sync], in order.
  final List<List<Alert>> synced = [];

  /// How many times [requestAccess] was called.
  int requests = 0;

  @override
  Future<AlarmAccess> access() async => state;

  @override
  Future<AlarmAccess> requestAccess() async {
    requests++;
    return state = onRequest;
  }

  @override
  Future<void> sync(List<Alert> alarms) async => synced.add(List.of(alarms));
}

/// The Dart side of the iOS alarm bridge (channel 'app.pamnot/alarm').
///
/// Methods: 'access' and 'requestAccess' answer one of the [AlarmAccess]
/// names as a String; 'sync' takes a List of Maps
/// `{id: UUID string, title, at: epoch ms, repeat: 'none|daily|weekly|monthly|yearly'}`.
/// The id is `Uuid().v5(Namespace.url.value, 'pamnot-alarm:' + alert.key)`,
/// so the same alert always keeps the same alarm. Outside iOS, and on iOS
/// without the bridge (below iOS 26 the bridge answers 'unsupported'), the
/// access is [AlarmAccess.unsupported]; outside iOS the channel is never
/// called.
class MethodChannelAlarmScheduler implements AlarmScheduler {
  MethodChannelAlarmScheduler({MethodChannel? channel, DateTime Function()? clock})
      : _channel = channel ?? const MethodChannel('app.pamnot/alarm'),
        _now = clock ?? DateTime.now;

  final MethodChannel _channel;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  static bool get _available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// The alarm id the bridge stores for [alert].
  static String alarmId(Alert alert) => _uuid.v5(Namespace.url.value, 'pamnot-alarm:${alert.key}');

  @override
  Future<AlarmAccess> access() => _ask('access');

  @override
  Future<AlarmAccess> requestAccess() => _ask('requestAccess');

  Future<AlarmAccess> _ask(String method) async {
    if (!_available) return AlarmAccess.unsupported;
    try {
      final reply = await _channel.invokeMethod<String>(method);
      return AlarmAccess.values.firstWhere((a) => a.name == reply, orElse: () => AlarmAccess.denied);
    } on MissingPluginException {
      return AlarmAccess.unsupported;
    } on PlatformException catch (e) {
      debugPrint('Alarm bridge $method failed: $e');
      return AlarmAccess.unsupported;
    }
  }

  @override
  Future<void> sync(List<Alert> alarms) async {
    if (!_available) return;
    final now = _now();
    final payload = [
      for (final a in alarms)
        if (a.repeat != Repeat.none || a.at.isAfter(now))
          {
            'id': alarmId(a),
            'title': a.title,
            'at': a.at.millisecondsSinceEpoch,
            'repeat': a.repeat.name,
          },
    ];
    try {
      await _channel.invokeMethod<void>('sync', payload);
    } on MissingPluginException {
      // No bridge (widget tests, iOS builds without AlarmKit).
    } on PlatformException catch (e) {
      debugPrint('Alarm bridge sync failed: $e');
    }
  }
}

/// The bridge on iOS; [NoopAlarmScheduler] everywhere else. Creating it asks
/// for nothing.
AlarmScheduler createAlarmScheduler() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? MethodChannelAlarmScheduler() : NoopAlarmScheduler();
