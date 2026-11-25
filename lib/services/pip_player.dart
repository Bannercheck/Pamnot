import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Plays a short, silent guide video in Picture in Picture (design §10), so
/// it keeps playing over the Settings app.
abstract class PipPlayer {
  /// Whether this device can play in Picture in Picture.
  Future<bool> isSupported();

  /// Loads [assetPath], e.g. 'assets/guide/action_button.mp4'.
  Future<void> prepare(String assetPath);

  /// Starts Picture in Picture. Only ever called from a user's tap; answers
  /// whether it started.
  Future<bool> start();

  Future<void> stop();
}

/// No Picture in Picture (tests, and every platform but iOS).
class NoPipPlayer implements PipPlayer {
  /// Every call in order: 'isSupported', `'prepare <asset>'`, 'start', 'stop'.
  final List<String> calls = [];

  @override
  Future<bool> isSupported() async {
    calls.add('isSupported');
    return false;
  }

  @override
  Future<void> prepare(String assetPath) async => calls.add('prepare $assetPath');

  @override
  Future<bool> start() async {
    calls.add('start');
    return false;
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

/// The Dart side of the iOS Picture in Picture bridge.
///
/// Channel 'app.pamnot/pip': 'isSupported' → bool, 'prepare' {asset},
/// 'start' → bool, 'stop'. Outside iOS the channel is never called and
/// nothing is supported; a missing or failing bridge answers false.
class MethodChannelPipPlayer implements PipPlayer {
  MethodChannelPipPlayer({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('app.pamnot/pip');

  final MethodChannel _channel;

  static bool get _available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> isSupported() => _ask('isSupported');

  @override
  Future<void> prepare(String assetPath) => _call('prepare', {'asset': assetPath});

  @override
  Future<bool> start() => _ask('start');

  @override
  Future<void> stop() => _call('stop');

  Future<bool> _ask(String method) async {
    if (!_available) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('PiP bridge $method failed: $e');
      return false;
    }
  }

  Future<void> _call(String method, [Object? arguments]) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No bridge (widget tests, builds without the plugin).
    } on PlatformException catch (e) {
      debugPrint('PiP bridge $method failed: $e');
    }
  }
}

/// The bridge on iOS; [NoPipPlayer] everywhere else. Creating it plays nothing.
PipPlayer createPipPlayer() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? MethodChannelPipPlayer() : NoPipPlayer();
