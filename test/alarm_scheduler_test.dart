import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/services/alarm_scheduler.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:uuid/uuid.dart';

const _channelName = 'app.pamnot/alarm';
const _channel = MethodChannel(_channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime(2026, 11, 25, 12);
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

  MethodChannelAlarmScheduler scheduler() => MethodChannelAlarmScheduler(clock: () => now);

  test('access: yerel yanıt AlarmAccess değerine çevrilir; bilinmeyen metin denied', () async {
    for (final (reply, want) in [
      ('authorized', AlarmAccess.authorized),
      ('denied', AlarmAccess.denied),
      ('notDetermined', AlarmAccess.notDetermined),
      ('unsupported', AlarmAccess.unsupported),
      ('whatever', AlarmAccess.denied),
    ]) {
      mock((_) => reply);
      expect(await scheduler().access(), want, reason: reply);
    }
    expect(calls.map((c) => c.method).toSet(), {'access'});
  });

  test('requestAccess kendi yöntemini çağırır', () async {
    mock((c) => c.method == 'requestAccess' ? 'authorized' : 'notDetermined');
    expect(await scheduler().requestAccess(), AlarmAccess.authorized);
    expect(calls.single.method, 'requestAccess');
  });

  test('köprü yokken (MissingPluginException) unsupported; sync hata vermez', () async {
    mock((_) => throw MissingPluginException());
    final s = scheduler();
    expect(await s.access(), AlarmAccess.unsupported);
    expect(await s.requestAccess(), AlarmAccess.unsupported);
    await s.sync([Alert(key: 'r:1', title: 'a', body: 'b', at: now.add(const Duration(hours: 1)), alarm: true)]);
  });

  test('sync: id aynı anahtar için hep aynı geçerli UUID; alanlar ve tekrar adı; geçmiş tek seferlik atlanır',
      () async {
    mock((_) => null);
    final at = DateTime(2026, 11, 26, 9, 30);
    final alerts = [
      Alert(key: 'r:abc', title: 'Su iç', body: 'x', at: at, repeat: Repeat.daily, alarm: true),
      Alert(key: 't:old', title: 'Eski', body: 'x', at: now.subtract(const Duration(minutes: 1)), alarm: true),
      Alert(key: 'r:past-weekly', title: 'Haftalık', body: 'x', at: DateTime(2026, 1, 5, 8), repeat: Repeat.weekly, alarm: true),
    ];
    await scheduler().sync(alerts);
    await scheduler().sync(alerts);
    expect(calls.map((c) => c.method), ['sync', 'sync']);
    final first = (calls[0].arguments as List).cast<Map>();
    final second = (calls[1].arguments as List).cast<Map>();
    expect(first, hasLength(2));
    expect(first.map((m) => m['title']), ['Su iç', 'Haftalık']);
    expect(first[0]['at'], at.millisecondsSinceEpoch);
    expect((first[0]['repeat'], first[1]['repeat']), ('daily', 'weekly'));
    final id = first[0]['id'] as String;
    expect(Uuid.isValidUUID(fromString: id), isTrue);
    expect(id, const Uuid().v5(Namespace.url.value, 'pamnot-alarm:r:abc'));
    expect(second[0]['id'], id);
    expect(first[1]['id'], isNot(id));
  });

  test('sync boş liste de gönderilir (hepsini kaldırır)', () async {
    mock((_) => null);
    await scheduler().sync(const []);
    expect(calls.single.method, 'sync');
    expect(calls.single.arguments, isEmpty);
  });

  test('Android\'de kanal hiç çağrılmaz', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    mock((_) => 'authorized');
    final s = scheduler();
    expect(await s.access(), AlarmAccess.unsupported);
    expect(await s.requestAccess(), AlarmAccess.unsupported);
    await s.sync([Alert(key: 'r:1', title: 'a', body: 'b', at: now.add(const Duration(hours: 1)), alarm: true)]);
    expect(calls, isEmpty);
  });

  test('createAlarmScheduler: iOS dışında NoopAlarmScheduler', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(createAlarmScheduler(), isA<NoopAlarmScheduler>());
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(createAlarmScheduler(), isA<MethodChannelAlarmScheduler>());
  });

  test('NoopAlarmScheduler: state, onRequest, requests, synced', () async {
    final n = NoopAlarmScheduler();
    expect(await n.access(), AlarmAccess.unsupported);
    n.onRequest = AlarmAccess.denied;
    expect(await n.requestAccess(), AlarmAccess.denied);
    expect((n.requests, n.state), (1, AlarmAccess.denied));
    final a = Alert(key: 'r:1', title: 'a', body: 'b', at: now, alarm: true);
    await n.sync([a]);
    expect(n.synced.single.single.key, 'r:1');
  });

  test('Alert.alarm varsayılan false ve parmak izine girer', () {
    final a = Alert(key: 'r:1', title: 'a', body: 'b', at: now);
    final b = Alert(key: 'r:1', title: 'a', body: 'b', at: now, alarm: true);
    expect((a.alarm, b.alarm), (false, true));
    expect(a.fingerprint, isNot(b.fingerprint));
  });
}
