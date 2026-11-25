import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Dart side of the iOS accessibility bridge (channel 'app.pamnot/a11y').
/// It reports system settings Flutter does not expose itself; today that is
/// iOS "Reduce Transparency", which turns the glass surfaces into plain ones.
abstract final class SystemAccessibility {
  static const _channel = MethodChannel('app.pamnot/a11y');

  /// iOS "Reduce Transparency". Stays false where there is no bridge
  /// (tests, other platforms).
  static final ValueNotifier<bool> reduceTransparency = ValueNotifier(false);

  /// The bridge exists only in the iOS app.
  static bool get _available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Call once in main(). iOS only (not web): installs the handler for
  /// 'changed' (argument: bool) first, then asks for the current value with
  /// 'reduceTransparency', so a change between the two is not lost.
  /// Elsewhere it does nothing and the value stays false.
  static void start() {
    if (!_available) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && call.arguments is bool) {
        reduceTransparency.value = call.arguments as bool;
      }
    });
    unawaited(_pull());
  }

  static Future<void> _pull() async {
    try {
      final value = await _channel.invokeMethod<bool>('reduceTransparency');
      if (value != null) reduceTransparency.value = value;
    } on MissingPluginException {
      // The bridge is not registered (widget tests).
    } on PlatformException catch (e) {
      // The bridge failed: keep the current value (glass stays as it is).
      debugPrint('Accessibility bridge failed: $e');
    }
  }
}
