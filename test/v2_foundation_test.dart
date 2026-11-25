import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/alarm_scheduler.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/services/system_accessibility.dart';

void main() {
  test('K1 metinleri TR ve EN', () {
    expect(S.tr.unpinned, 'Sabitleme kaldırıldı');
    expect(S.en.unpinned, 'Unpinned');
    expect(S.tr.planAgendaTab, 'Takvim');
    expect(S.en.navAddTask, 'Add a task');
  });

  test('SystemAccessibility: köprü yokken false, start() hata vermez', () {
    SystemAccessibility.start();
    expect(SystemAccessibility.reduceTransparency.value, isFalse);
  });

  testWidgets('SystemAccessibility: iOS köprüsünün yanıtı ve "changed" çağrısı değeri günceller', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('app.pamnot/a11y');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async => c.method == 'reduceTransparency');
    SystemAccessibility.start();
    await tester.pump();
    expect(SystemAccessibility.reduceTransparency.value, isTrue);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.pamnot/a11y', const StandardMethodCodec().encodeMethodCall(const MethodCall('changed', false)), (_) {});
    expect(SystemAccessibility.reduceTransparency.value, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  test('pubspec derleme numarası 5 ve cümle varlıkları kayıtlı', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0+5'));
    expect(pubspec, contains('    - assets/quotes/'));
    for (final lang in ['tr', 'en']) {
      final lines = File('assets/quotes/$lang.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty);
      expect(lines, isNotEmpty, reason: lang);
    }
  });

  test('K2 metinleri TR ve EN', () {
    expect(S.tr.matrix, 'Matris');
    expect(S.en.matrix, 'Matrix');
    expect(['personal', 'work', 'school', 'shopping', 'home'].map(S.tr.defaultListName),
        ['Kişisel', 'İş', 'Okul', 'Alışveriş', 'Ev']);
    expect(['personal', 'work', 'school', 'shopping', 'home'].map(S.en.defaultListName),
        ['Personal', 'Work', 'School', 'Shopping', 'Home']);
    expect((S.tr.list, S.en.list, S.tr.box, S.en.box), ('Liste', 'List', 'Kutu', 'Box'));
    expect((S.tr.newList, S.en.listNameHint), ('Yeni liste', 'List name'));
    expect((S.tr.renameList, S.en.deleteList), ('Listeyi düzenle', 'Delete list'));
    expect(S.tr.deleteListBody('İş', 3, 'Kişisel'), '“İş” silinecek. İçindeki 3 görev “Kişisel” listesine taşınır.');
    expect(S.en.deleteListBody('Work', 3, 'Personal'), '“Work” will be deleted. Its 3 tasks move to “Personal”.');
    expect((S.tr.lastListNote, S.en.listDeleted), ('En az bir liste kalmalı.', 'List deleted'));
    expect((S.tr.moveToList, S.en.moveToBox('Later · Maybe')), ('Başka listeye taşı…', 'Move to Later · Maybe'));
    expect(S.tr.moveToBox('Sonra · Belki'), 'Sonra · Belki kutusuna taşı');
    expect((S.tr.markDone, S.en.finishedCount(2), S.tr.finishedCount(2)), ('Bitti', 'Finished (2)', 'Biten (2)'));
    expect((S.tr.addToBox, S.en.boxEmpty, S.tr.movedTo('İş')), ('Ekle', 'Empty', 'İş içine taşındı'));
    expect((S.tr.icon, S.en.voiceSavedTo('Work'), S.tr.voiceSavedTo('İş')), ('Simge', 'Added to Work', 'İş listesine eklendi'));
    expect(S.tr.voiceAutoSaveTitle, '8 saniye sonra kendiliğinden kaydet');
    expect(S.en.voiceAutoSaveSub,
        'If you don’t pick a list, it saves to the one you used last. For hands-free use.');
  });

  test('K3 metinleri TR ve EN', () {
    expect((S.tr.dailyMotivation, S.en.dailyMotivation), ('Günlük motivasyon', 'Daily motivation'));
    expect((S.tr.dailyMotivationSub, S.en.dailyMotivationSub),
        ('Her gün kısa, yumuşak bir cümle.', 'A short, gentle line every day.'));
    expect((S.tr.motivationTime, S.en.motivationTime), ('Saat', 'Time'));
    expect((S.tr.alertKind, S.en.alertKind), ('Uyarı türü', 'Alert type'));
    expect((S.tr.alertNotification, S.en.alertNotification), ('Bildirim', 'Notification'));
    expect((S.tr.alertAlarm, S.en.alertAlarm), ('Alarm', 'Alarm'));
    expect((S.tr.alarmHint, S.en.alarmHint), (
      'Sessiz modda da çalar; Ertele ve Kapat düğmeleriyle.',
      'Rings even in silent mode, with Snooze and Stop.',
    ));
    expect((S.tr.alarmDenied, S.en.alarmDenied), (
      'Alarm izni kapalı; bildirim olarak hatırlatılacak.',
      'Alarms are off; you’ll get a notification instead.',
    ));
  });

  test('Reminder.alertKind: varsayılan bildirim; "alert" yalnız alarmda yazılır; eski JSON bildirim', () {
    final r = Reminder(id: 'r1', title: 'Su', at: DateTime(2026, 11, 26, 9), createdAt: DateTime(2026, 11, 25));
    expect(r.alertKind, AlertKind.notification);
    expect(r.toJson().containsKey('alert'), isFalse);
    final a = r.copyWith(alertKind: AlertKind.alarm);
    expect(a.toJson()['alert'], 'alarm');
    expect(Reminder.fromJson(a.toJson()).alertKind, AlertKind.alarm);
    expect(Reminder.fromJson(r.toJson()).alertKind, AlertKind.notification);
    expect(Reminder.fromJson({...r.toJson(), 'alert': 'bogus'}).alertKind, AlertKind.notification);
    expect(a.copyWith(title: 'X').alertKind, AlertKind.alarm);
  });

  test('TaskItem.alertKind: varsayılan bildirim; "alert" yalnız alarmda yazılır; eski JSON bildirim', () {
    final t = TaskItem(id: 't1', title: 'Ara', createdAt: DateTime(2026, 11, 25));
    expect(t.alertKind, AlertKind.notification);
    expect(t.toJson().containsKey('alert'), isFalse);
    final a = t.copyWith(alertKind: AlertKind.alarm);
    expect(a.toJson()['alert'], 'alarm');
    expect(TaskItem.fromJson(a.toJson()).alertKind, AlertKind.alarm);
    expect(TaskItem.fromJson(t.toJson()).alertKind, AlertKind.notification);
    expect(a.copyWith(title: 'X').alertKind, AlertKind.alarm);
  });

  test('ayarlar: günlük motivasyon açık, 09:00; dakika 0..1439 aralığına sıkıştırılır', () {
    const d = AppSettings();
    expect((d.dailyMotivation, d.motivationMinutes), (true, 540));
    final old = AppSettings.fromJson(const {});
    expect((old.dailyMotivation, old.motivationMinutes), (true, 540));
    expect(AppSettings.fromJson(const {'motivationMinutes': 2000}).motivationMinutes, 1439);
    expect(AppSettings.fromJson(const {'motivationMinutes': -5}).motivationMinutes, 0);
    final s = d.copyWith(dailyMotivation: false, motivationMinutes: 1260);
    final back = AppSettings.fromJson(s.toJson());
    expect((back.dailyMotivation, back.motivationMinutes), (false, 1260));
    expect(AppSettings.fromJson(const {'dailyMotivation': null}).dailyMotivation, isTrue);
  });

  test('AppController.alarms: verilmezse NoopAlarmScheduler; verilen kullanılır', () {
    expect(AppController(store: MemoryStore()).alarms, isA<NoopAlarmScheduler>());
    final n = NoopAlarmScheduler();
    expect(AppController(store: MemoryStore(), alarms: n).alarms, same(n));
  });
}
