import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/services/pip_player.dart';

const _channel = MethodChannel('app.pamnot/pip');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  void mock(Object? Function(MethodCall c) answer) {
    messenger.setMockMethodCallHandler(_channel, (c) async {
      calls.add(c);
      return answer(c);
    });
  }

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS: isSupported, prepare {asset}, start, stop kanala gider', () async {
    mock((c) => switch (c.method) { 'isSupported' => true, 'start' => true, _ => null });
    final p = MethodChannelPipPlayer();
    expect(await p.isSupported(), isTrue);
    await p.prepare('assets/guide/action_button.mp4');
    expect(await p.start(), isTrue);
    await p.stop();
    expect(calls.map((c) => c.method), ['isSupported', 'prepare', 'start', 'stop']);
    expect(calls[1].arguments, {'asset': 'assets/guide/action_button.mp4'});
  });

  test('start false yanıtı false; null yanıt false', () async {
    mock((c) => c.method == 'start' ? false : null);
    expect(await MethodChannelPipPlayer().start(), isFalse);
    mock((_) => null);
    expect(await MethodChannelPipPlayer().start(), isFalse);
    expect(await MethodChannelPipPlayer().isSupported(), isFalse);
  });

  test('köprü yokken (MissingPluginException) false; prepare ve stop hata vermez', () async {
    mock((_) => throw MissingPluginException());
    final p = MethodChannelPipPlayer();
    expect(await p.isSupported(), isFalse);
    await p.prepare('assets/guide/back_tap.mp4');
    expect(await p.start(), isFalse);
    await p.stop();
  });

  test('PlatformException false; prepare ve stop hata vermez', () async {
    mock((_) => throw PlatformException(code: 'x'));
    final p = MethodChannelPipPlayer();
    expect(await p.isSupported(), isFalse);
    await p.prepare('assets/guide/back_tap.mp4');
    expect(await p.start(), isFalse);
    await p.stop();
  });

  test('iOS dışında kanal hiç çağrılmaz', () async {
    mock((_) => true);
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      final p = MethodChannelPipPlayer();
      expect(await p.isSupported(), isFalse, reason: '$platform');
      await p.prepare('assets/guide/outlook.mp4');
      expect(await p.start(), isFalse, reason: '$platform');
      await p.stop();
    }
    expect(calls, isEmpty);
  });

  test('createPipPlayer: iOS kanal, diğerleri NoPipPlayer', () {
    expect(createPipPlayer(), isA<MethodChannelPipPlayer>());
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(createPipPlayer(), isA<NoPipPlayer>());
  });

  test('NoPipPlayer: desteklenmez, başlamaz, çağrıları kaydeder', () async {
    final p = NoPipPlayer();
    expect(await p.isSupported(), isFalse);
    await p.prepare('assets/guide/shortcut.mp4');
    expect(await p.start(), isFalse);
    await p.stop();
    expect(p.calls, ['isSupported', 'prepare assets/guide/shortcut.mp4', 'start', 'stop']);
  });
}
