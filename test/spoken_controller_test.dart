import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/core/spoken/spoken_task.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/voice_log.dart';
import 'package:pamnot/services/reminder_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 11, 23, 9);

  late MemoryStore store;
  late NoopScheduler scheduler;
  late AppController c;

  String settingsDoc({bool keepVoiceLog = false, bool notificationsAsked = false}) => jsonEncode(AppSettings(
        language: AppLanguage.tr,
        seeded: true,
        keepVoiceLog: keepVoiceLog,
        notificationsAsked: notificationsAsked,
      ).toJson());

  /// Swallows the log lines a deliberately damaged input produces.
  void quiet() {
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = saved);
  }

  Future<AppController> boot(MemoryStore s) async {
    final a = AppController(store: s, scheduler: scheduler, clock: () => now, saveDelay: Duration.zero);
    await a.load();
    return a;
  }

  setUp(() async {
    store = MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr, seeded: true).toJson())});
    scheduler = NoopScheduler();
    c = await boot(store);
  });
  tearDown(() => c.dispose());

  // ------------------------------------------------------------ addSpokenTask

  test('saatli görev: remindAt = due ve t: uyarısı hemen eşitlenir', () async {
    final t = c.addSpokenTask(SpokenTask(title: 'Annemi ara', due: DateTime(2026, 11, 24, 19), hasTime: true))!;
    expect(t.remindAt, DateTime(2026, 11, 24, 19));
    expect(c.alerts().map((a) => a.key), contains('t:${t.id}'));
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.synced.last.map((a) => a.key), contains('t:${t.id}'));
  });

  test('geçmiş saat bildirim kurmaz', () {
    expect(c.addSpokenTask(SpokenTask(title: 'x', due: DateTime(2026, 11, 23, 8), hasTime: true))!.remindAt, isNull);
  });

  test('hatırlat + gün, saat yok: o gün 09:00', () {
    final t = c.addSpokenTask(SpokenTask(title: 'Faturayı öde', due: DateTime(2026, 11, 24), remind: true))!;
    expect((t.hasTime, t.remindAt), (false, DateTime(2026, 11, 24, 9)));
  });

  test('hatırlat + bugün: 09:00 geçmişse bildirim yok', () {
    expect(c.addSpokenTask(SpokenTask(title: 'x', due: DateTime(2026, 11, 23), remind: true))!.remindAt, isNull);
  });

  test('hatırlat tarihsiz: görev tarihsiz, bildirim yok', () {
    final t = c.addSpokenTask(const SpokenTask(title: 'Annemi ara', remind: true))!;
    expect((t.due, t.remindAt), (null, null));
  });

  test('gün var, saat ve hatırlat yok: görev o güne düşer, bildirim yok', () {
    final t = c.addSpokenTask(SpokenTask(title: 'Faturayı öde', due: DateTime(2026, 11, 24)))!;
    expect((t.title, t.due, t.hasTime, t.remindAt), ('Faturayı öde', DateTime(2026, 11, 24), false, null));
    expect(c.tasks.single.id, t.id);
    expect(c.alerts().map((a) => a.key), isNot(contains('t:${t.id}')));
  });

  test('boş başlık ve not görev olmaz', () {
    expect(c.addSpokenTask(const SpokenTask(title: '')), isNull);
    expect(c.addSpokenTask(const SpokenTask(title: 'x', isNote: true)), isNull);
    expect(c.tasks, isEmpty);
  });

  test('sesle eklenen görev silinerek geri alınır', () async {
    final t = c.addSpokenTask(SpokenTask(title: 'Annemi ara', due: DateTime(2026, 11, 24, 19), hasTime: true))!;
    c.deleteTask(t.id);
    expect(c.tasks, isEmpty);
    expect(c.alerts().map((a) => a.key), isNot(contains('t:${t.id}')));
  });

  // ------------------------------------------------------------ addSpokenNote

  test('addSpokenNote metni gövde yapar; deleteNote geri alır', () {
    final n = c.addSpokenNote('Süt bitmiş')!;
    expect((c.notes.first.id, n.body, n.title), (n.id, 'Süt bitmiş', ''));
    expect(c.addSpokenNote('  '), isNull);
    c.deleteNote(n.id);
    expect(c.notes, isEmpty);
  });

  // -------------------------------------------------------- notification access

  test('bildirim izni yalnız bir kez sorulur ve sorulduğu kaydedilir', () async {
    bool? grantedAtRequest;
    scheduler.onRequest = () => grantedAtRequest = scheduler.granted;
    expect(await c.notificationAccess(), NotificationAccess.notAsked);
    await c.ensureNotificationPermission();
    await c.ensureNotificationPermission();
    expect(scheduler.permissionRequests, 1);
    expect(grantedAtRequest, isFalse); // onRequest runs before the request answers
    expect(c.settings.notificationsAsked, isTrue);
    expect(await c.notificationAccess(), NotificationAccess.granted);
    scheduler.granted = false;
    expect(await c.notificationAccess(), NotificationAccess.denied);
  });

  test('reddedildiyse ensureNotificationPermission yeniden sormaz', () async {
    final s = MemoryStore({'settings': settingsDoc(notificationsAsked: true)});
    final a = await boot(s);
    addTearDown(a.dispose);
    expect(await a.notificationAccess(), NotificationAccess.denied);
    await a.ensureNotificationPermission();
    expect(scheduler.permissionRequests, 0);
  });

  test('izin önceden verilmişse durum açık ve yeniden sorulmaz', () async {
    scheduler.granted = true;
    expect(await c.notificationAccess(), NotificationAccess.granted);
    await c.ensureNotificationPermission();
    expect(scheduler.permissionRequests, 0);
  });

  test('requestNotifications izni ister, sonucu döner ve sorulduğunu kalıcı kaydeder', () async {
    expect(await c.requestNotifications(), isTrue);
    expect(await c.requestNotifications(), isTrue);
    expect(scheduler.permissionRequests, 2);
    await c.flush();
    expect((jsonDecode(store.data['settings']!) as Map)['notificationsAsked'], isTrue);
  });

  // ---------------------------------------------------------------- voice log

  test('günlük varsayılan kapalı; açıkken en çok 20 kayıt, en yeni başta; kapatınca silinir', () async {
    const p = SpokenTask(title: 'Toplantı');
    c.logRecognized('toplantı', p, localeId: 'tr-TR');
    expect(c.voiceLog, isEmpty);
    c.updateSettings(c.settings.copyWith(keepVoiceLog: true));
    for (var i = 0; i < 25; i++) {
      c.logRecognized('metin $i', p, localeId: 'tr-TR');
    }
    expect(c.voiceLog.length, 20);
    expect(c.voiceLog.first.transcript, 'metin 24');
    expect(c.voiceLog.last.transcript, 'metin 5');
    await c.flush();
    await Future<void>.delayed(Duration.zero);
    expect(store.data['voice_log'], contains('metin 24'));
    expect(jsonDecode(store.data['voice_log']!), isA<List<Object?>>());
    c.updateSettings(c.settings.copyWith(keepVoiceLog: false));
    await Future<void>.delayed(Duration.zero);
    expect(c.voiceLog, isEmpty);
    expect(store.data.containsKey('voice_log'), isFalse);
  });

  test('günlük kaydı ayrıştırma sonucunu tutar ve Ayarlar dilimini yeniler', () {
    c.updateSettings(c.settings.copyWith(keepVoiceLog: true));
    final rev = c.revisions[Slice.settings]!;
    c.logRecognized(
      'yarın akşam yedide annemi aramayı hatırlat',
      SpokenTask(title: 'Annemi ara', due: DateTime(2026, 11, 24, 19), hasTime: true, remind: true),
      localeId: 'tr-TR',
    );
    expect(c.revisions[Slice.settings], greaterThan(rev));
    final e = c.voiceLog.single;
    expect(
      (e.at, e.localeId, e.transcript, e.title, e.due, e.hasTime, e.remind, e.isNote),
      (now, 'tr-TR', 'yarın akşam yedide annemi aramayı hatırlat', 'Annemi ara', DateTime(2026, 11, 24, 19), true, true, false),
    );
  });

  test('günlük yeniden açılışta yüklenir; bozuk belge yok sayılır', () async {
    c.updateSettings(c.settings.copyWith(keepVoiceLog: true));
    c.logRecognized(
      'yarın 19:00 annemi ara',
      SpokenTask(title: 'Annemi ara', due: DateTime(2026, 11, 24, 19), hasTime: true, remind: true),
      localeId: 'tr-TR',
    );
    c.logRecognized('süt bitmiş diye not al', const SpokenTask(title: 'Süt bitmiş', isNote: true), localeId: 'en-US');
    await c.flush();

    final again = await boot(store);
    addTearDown(again.dispose);
    expect(again.voiceLog.map((e) => e.transcript), ['süt bitmiş diye not al', 'yarın 19:00 annemi ara']);
    final first = again.voiceLog.first;
    expect((first.localeId, first.title, first.due, first.isNote), ('en-US', 'Süt bitmiş', null, true));
    final last = again.voiceLog.last;
    expect(
      (last.at, last.localeId, last.title, last.due, last.hasTime, last.remind, last.isNote),
      (now, 'tr-TR', 'Annemi ara', DateTime(2026, 11, 24, 19), true, true, false),
    );

    quiet();
    final broken = await boot(MemoryStore({'settings': settingsDoc(keepVoiceLog: true), 'voice_log': '{bozuk'}));
    addTearDown(broken.dispose);
    expect(broken.voiceLog, isEmpty);

    final damagedItem = await boot(MemoryStore({
      'settings': settingsDoc(keepVoiceLog: true),
      'voice_log': jsonEncode([
        {'transcript': 'tarihsiz kayıt'},
        VoiceLogEntry(at: now, localeId: 'tr-TR', transcript: 'sağlam', title: 'Sağlam').toJson(),
      ]),
    }));
    addTearDown(damagedItem.dispose);
    expect(damagedItem.voiceLog.map((e) => e.transcript), ['sağlam']);
  });

  test('anahtar kapalıyken kalmış günlük yüklenmez ve silinir', () async {
    final s = MemoryStore({
      'settings': settingsDoc(),
      'voice_log': jsonEncode([VoiceLogEntry(at: now, localeId: 'tr-TR', transcript: 'eski', title: 'Eski').toJson()]),
    });
    final a = await boot(s);
    addTearDown(a.dispose);
    expect(a.voiceLog, isEmpty);
    await a.flush();
    expect(s.data.containsKey('voice_log'), isFalse);
  });

  test('clearVoiceLog günlüğü boşaltır, belgeyi siler, anahtarı açık bırakır', () async {
    c.updateSettings(c.settings.copyWith(keepVoiceLog: true));
    c.logRecognized('x', const SpokenTask(title: 'x'), localeId: 'en-US');
    await c.flush();
    expect(store.data.containsKey('voice_log'), isTrue);
    final rev = c.revisions[Slice.settings]!;
    c.clearVoiceLog();
    expect(c.voiceLog, isEmpty);
    expect(c.revisions[Slice.settings], greaterThan(rev));
    expect(c.settings.keepVoiceLog, isTrue);
    await c.flush();
    expect(store.data.containsKey('voice_log'), isFalse);
  });

  // ------------------------------------------------------------- typed capture

  test('yazarak hızlı ekleme hatırlatma kurmaz (değişmedi)', () {
    expect(c.addQuickTask('yarın 10:00 toplantı')!.remindAt, isNull);
  });

  // --------------------------------------------------- LocalNotificationScheduler

  group('LocalNotificationScheduler izin durumu', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <MethodCall>[];
    late Object? Function(MethodCall) answer;

    void use(TargetPlatform platform, FlutterLocalNotificationsPlatform impl) {
      debugDefaultTargetPlatformOverride = platform;
      FlutterLocalNotificationsPlatform.instance = impl;
    }

    setUp(() {
      calls.clear();
      answer = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'initialize') return true;
        return answer(call);
      });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    Map<String, bool> permissions({required bool enabled}) => {
          'isEnabled': enabled,
          'isAlertEnabled': enabled,
          'isBadgeEnabled': false,
          'isSoundEnabled': enabled,
          'isProvisionalEnabled': false,
          'isCriticalEnabled': false,
        };

    test('iOS: checkPermissions().isEnabled; yanıt yoksa ya da hata olursa kapalı', () async {
      use(TargetPlatform.iOS, IOSFlutterLocalNotificationsPlugin());
      answer = (call) => call.method == 'checkPermissions' ? permissions(enabled: true) : null;
      expect(await LocalNotificationScheduler().isGranted(), isTrue);
      answer = (call) => call.method == 'checkPermissions' ? permissions(enabled: false) : null;
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
      answer = (_) => null;
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
      answer = (call) => call.method == 'checkPermissions' ? throw PlatformException(code: 'boom') : null;
      quiet();
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
    });

    test('macOS: checkPermissions().isEnabled', () async {
      use(TargetPlatform.macOS, MacOSFlutterLocalNotificationsPlugin());
      answer = (call) => call.method == 'checkPermissions' ? permissions(enabled: true) : null;
      expect(await LocalNotificationScheduler().isGranted(), isTrue);
      answer = (_) => null;
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
    });

    test('Android: areNotificationsEnabled()', () async {
      use(TargetPlatform.android, AndroidFlutterLocalNotificationsPlugin());
      answer = (call) => call.method == 'areNotificationsEnabled' ? true : null;
      expect(await LocalNotificationScheduler().isGranted(), isTrue);
      answer = (call) => call.method == 'areNotificationsEnabled' ? false : null;
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
      answer = (_) => null;
      expect(await LocalNotificationScheduler().isGranted(), isFalse);
    });

    test('diğer platformlar: açık sayılır', () async {
      use(TargetPlatform.linux, IOSFlutterLocalNotificationsPlugin());
      expect(await LocalNotificationScheduler().isGranted(), isTrue);
    });

    test('iOS ve macOS izin isteği rozet istemez', () async {
      for (final (platform, impl) in [
        (TargetPlatform.iOS, IOSFlutterLocalNotificationsPlugin() as FlutterLocalNotificationsPlatform),
        (TargetPlatform.macOS, MacOSFlutterLocalNotificationsPlugin()),
      ]) {
        calls.clear();
        use(platform, impl);
        answer = (call) => call.method == 'requestPermissions' ? true : null;
        expect(await LocalNotificationScheduler().requestPermission(), isTrue, reason: '$platform');
        final args = (calls.singleWhere((c) => c.method == 'requestPermissions').arguments as Map).cast<String, Object?>();
        expect((args['alert'], args['sound'], args['badge']), (true, true, false), reason: '$platform');
      }
    });
  });
}
