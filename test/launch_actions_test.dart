import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/launch_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.pamnot/launch');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Methods Dart called on the native side, in order.
  late List<String> calls;

  /// What the native side answers to the next `takePendingAction`.
  String? pending;

  /// Stands in for ios/Runner/PamnotLaunchBridge.swift: hands out the
  /// pending action once.
  void mockNative() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method != 'takePendingAction') return null;
      final action = pending;
      pending = null;
      return action;
    });
  }

  /// The native side tells Dart that a new action is waiting.
  Future<void> nativeSendsActionAvailable() async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('actionAvailable')),
      (_) {},
    );
  }

  setUp(() {
    calls = [];
    pending = null;
    voiceRequests.value = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    // start() installs a handler for calls from the native side.
    channel.setMethodCallHandler(null);
    debugDefaultTargetPlatformOverride = null;
    voiceRequests.value = false;
  });

  test('iOS: start bekleyen "voice" eylemini çeker', () async {
    mockNative();
    pending = 'voice';
    LaunchActionsBridge.start();
    await pumpEventQueue();
    expect(voiceRequests.value, isTrue);
    expect(calls, ['takePendingAction']);
    // The native side gives an action out once.
    expect(pending, isNull);
  });

  test('bekleyen eylem yoksa istek oluşmaz', () async {
    mockNative();
    LaunchActionsBridge.start();
    await pumpEventQueue();
    expect(calls, ['takePendingAction']);
    expect(voiceRequests.value, isFalse);
  });

  test('bilinmeyen eylem yok sayılır', () async {
    mockNative();
    pending = 'reminders';
    LaunchActionsBridge.start();
    await pumpEventQueue();
    expect(calls, ['takePendingAction']);
    expect(voiceRequests.value, isFalse);
  });

  test('actionAvailable gelince yeniden çeker', () async {
    mockNative();
    LaunchActionsBridge.start();
    await pumpEventQueue();
    expect(voiceRequests.value, isFalse);

    // A shortcut runs while the app is open.
    pending = 'voice';
    await nativeSendsActionAvailable();
    await pumpEventQueue();
    expect(voiceRequests.value, isTrue);
    expect(calls, ['takePendingAction', 'takePendingAction']);
  });

  test('pull bekleyen eylemi çeker (uygulama öne gelince)', () async {
    mockNative();
    pending = 'voice';
    await LaunchActionsBridge.pull();
    expect(voiceRequests.value, isTrue);
    expect(calls, ['takePendingAction']);

    // Nothing waiting on the next resume: an earlier request stays as it is.
    voiceRequests.value = false;
    await LaunchActionsBridge.pull();
    expect(voiceRequests.value, isFalse);
    expect(calls, ['takePendingAction', 'takePendingAction']);
  });

  test('eklenti kayıtlı değilse sessizce geçer', () async {
    // No native handler: the call ends in MissingPluginException.
    LaunchActionsBridge.start();
    await pumpEventQueue();
    await expectLater(LaunchActionsBridge.pull(), completes);
    expect(voiceRequests.value, isFalse);
  });

  test('iOS dışında kanal hiç çağrılmaz', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      mockNative();
      pending = 'voice';
      LaunchActionsBridge.start();
      await LaunchActionsBridge.pull();
      await pumpEventQueue();
      expect(calls, isEmpty, reason: '$platform');
      expect(voiceRequests.value, isFalse, reason: '$platform');
    }
    // start() listened to nothing either: a message from the native side
    // finds no handler and gets no reply.
    ByteData? reply = ByteData(1);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('actionAvailable')),
      (r) => reply = r,
    );
    expect(reply, isNull);
    expect(calls, isEmpty);
  });
}
