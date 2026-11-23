import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a request to open the "Add by voice" screen came from.
enum VoiceRequest {
  /// The user's own action: the App Intent (Shortcuts, the Action button,
  /// Back Tap, Siri) or the microphone button in the app. The screen opens
  /// and listens.
  listen,

  /// A pamnot://ses or pamnot://voice link, which any app or web page can
  /// open. The screen opens paused: listening needs a tap inside Pamnot, and
  /// a link while the screen is open changes nothing.
  link,
}

/// A request to open the "Add by voice" screen. HomeShell consumes it and
/// sets it back to null, the way it consumes `notificationTaps`.
final voiceRequests = ValueNotifier<VoiceRequest?>(null);

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

  /// Takes the pending action, if any: 'voice' (the App Intent) becomes a
  /// [VoiceRequest.listen] request, 'voice-link' (a pamnot://ses or
  /// pamnot://voice link) a [VoiceRequest.link] one; other actions are
  /// ignored. Does nothing outside iOS.
  static Future<void> pull() async {
    if (!_available) return;
    try {
      final action = await _channel.invokeMethod<String>('takePendingAction');
      final request = switch (action) {
        'voice' => VoiceRequest.listen,
        'voice-link' => VoiceRequest.link,
        _ => null,
      };
      if (request != null) voiceRequests.value = request;
    } on MissingPluginException {
      // The bridge is not registered (widget tests).
    }
  }
}
