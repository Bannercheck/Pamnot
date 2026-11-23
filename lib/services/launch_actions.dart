import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A request to open the "Add by voice" screen (the shortcut, a pamnot://ses
/// link, the microphone button). HomeShell consumes it and sets it back to
/// false, the way it consumes `notificationTaps`.
final voiceRequests = ValueNotifier<bool>(false);

/// The Dart side of ios/Runner/PamnotLaunchBridge.swift. The native side
/// holds one pending action; Dart takes it with `takePendingAction`, and is
/// told with `actionAvailable` when one arrives while Dart is running. So a
/// request is delivered once, whichever side is ready first.
abstract final class LaunchActionsBridge {
  static const _channel = MethodChannel('app.pamnot/launch');

  /// The bridge exists only in the iOS app.
  static bool get _available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Call once in main(), before runApp. iOS only (not web): installs the
  /// handler first, then pulls, which covers a shortcut run before the
  /// engine started as well as one run after.
  static void start() {
    if (!_available) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'actionAvailable') await pull();
    });
    unawaited(pull());
  }

  /// Takes the pending action, if any; 'voice' becomes a [voiceRequests]
  /// request, other actions are ignored. Does nothing outside iOS.
  static Future<void> pull() async {
    if (!_available) return;
    try {
      final action = await _channel.invokeMethod<String>('takePendingAction');
      if (action == 'voice') voiceRequests.value = true;
    } on MissingPluginException {
      // The bridge is not registered (widget tests).
    }
  }
}
