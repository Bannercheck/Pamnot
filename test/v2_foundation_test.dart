import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/alarm_scheduler.dart';
import 'package:pamnot/services/calendar/calendar_source.dart';
import 'package:pamnot/services/links.dart';
import 'package:pamnot/services/pip_player.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/services/system_accessibility.dart';

import 'support/fake_calendar_source.dart';

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

  test('pubspec derleme numarası 8, takvim paketi, cümle ve kılavuz varlıkları kayıtlı', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.0+8'));
    expect(pubspec, contains('    - assets/guide/'));
    expect(File('assets/guide/README.md').existsSync(), isTrue);
    expect(pubspec, contains('  device_calendar_plus: ^0.12.0'));
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
  test('K5 metinleri TR ve EN', () {
    expect((S.tr.widgetAll, S.en.widgetAll), ('Tümü', 'All'));
    expect((S.tr.widgetEmpty, S.en.widgetEmpty), ('Görev yok', 'No tasks'));
  });

  test('K4 metinleri TR ve EN', () {
    expect((S.tr.showCalendar, S.en.showCalendar), ('Takvimi göster', 'Show calendar'));
    expect((S.tr.calendarSection, S.en.calendarSection), ('Takvim', 'Calendar'));
    expect((S.tr.calendarEvents, S.en.calendarEvents), ('Takvim etkinlikleri', 'Calendar events'));
    expect((S.tr.calendarEventsSub, S.en.calendarEventsSub), (
      'iPhone takvimindeki etkinlikler Plan’da salt okunur görünür.',
      'Events from your iPhone calendar appear read-only in Plan.',
    ));
    expect((S.tr.calendarsToShow, S.en.calendarsToShow), ('Görünecek takvimler', 'Calendars to show'));
    expect((S.tr.calendarDenied, S.en.calendarDenied),
        ('Takvim erişimi kapalı — Ayarlar’ı aç', 'Calendar access is off — open Settings'));
    expect((S.tr.calendarEventLabel, S.en.calendarEventLabel), ('Takvim etkinliği', 'Calendar event'));
    expect((S.tr.calendarOutlookHint, S.en.calendarOutlookHint), (
      'Outlook etkinlikleri için hesabını iPhone Ayarlar > Takvim > Hesaplar’a ekle.',
      'For Outlook events, add your account in iPhone Settings > Calendar > Accounts.',
    ));
    expect((S.tr.untitledEvent, S.en.untitledEvent), ('Adsız etkinlik', 'Untitled event'));
  });

  test('ayarlar: takvim kapalı, gizli takvim yok; gidiş-dönüş ve eski JSON', () {
    const d = AppSettings();
    expect(d.showCalendar, isFalse);
    expect(d.hiddenCalendarIds, isEmpty);
    final old = AppSettings.fromJson(const {});
    expect(old.showCalendar, isFalse);
    expect(old.hiddenCalendarIds, isEmpty);
    final s = d.copyWith(showCalendar: true, hiddenCalendarIds: ['a', 'b']);
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
    expect(back.showCalendar, isTrue);
    expect(back.hiddenCalendarIds, ['a', 'b']);
    expect(back.copyWith(language: AppLanguage.en).hiddenCalendarIds, ['a', 'b']);
    final bad = AppSettings.fromJson(const {'showCalendar': 'yes', 'hiddenCalendarIds': 'x'});
    expect(bad.showCalendar, isFalse);
    expect(bad.hiddenCalendarIds, isEmpty);
    final mixed = AppSettings.fromJson(const {'hiddenCalendarIds': ['a', 3, null, 'b']});
    expect(mixed.hiddenCalendarIds, ['a', 'b']);
  });

  test('AppController.calendar: verilmezse NoCalendarSource; verilen kullanılır', () {
    expect(AppController(store: MemoryStore()).calendar, isA<NoCalendarSource>());
    final f = FakeCalendarSource();
    expect(AppController(store: MemoryStore(), calendar: f).calendar, same(f));
  });

  test('Slice.calendar diske yazılmaz (ilk açılış örnek verisi dahil)', () async {
    final store = MemoryStore();
    final app = AppController(store: store, saveDelay: Duration.zero);
    await app.load();
    expect(app.revisions[Slice.calendar], greaterThan(0));
    await app.flush();
    expect(await store.read('calendar'), isNull);
    expect(await store.read('settings'), isNotNull);
    app.dispose();
  });

  test('K6 metinleri TR ve EN', () {
    expect((S.tr.guideTitle, S.en.guideTitle), ('Kestirmeler ve Siri', 'Shortcuts & Siri'));
    expect((S.tr.guideCardTitle, S.en.guideCardTitle),
        ('Sesle eklemeyi tek dokunuşa indir', 'Make voice capture one tap away'));
    expect(S.tr.guideCardBody, isNotEmpty);
    expect(S.en.guideCardBody, isNotEmpty);
    expect((S.tr.guideOpen, S.en.guideOpen), ('Kılavuzu aç', 'Open the guide'));
    expect((S.tr.guideTodo, S.en.guideTodo), ('Yapılacak', 'To do'));
    expect((S.tr.guideDoneBadge, S.en.guideDoneBadge), ('Tamam', 'Done'));
    expect((S.tr.guideMarkDone, S.tr.guideMarkUndone), ('Tamam olarak işaretle', 'Geri al'));
    expect((S.en.guideMarkDone, S.en.guideMarkUndone), ('Mark as done', 'Undo'));
    expect((S.tr.guideAddShortcut, S.tr.guideRunShortcut), ('Kısayolu ekle', 'Kısayolu çalıştır'));
    expect((S.en.guideAddShortcut, S.en.guideRunShortcut), ('Add shortcut', 'Run shortcut'));
    expect((S.tr.guideOpenSettings, S.en.guideOpenSettings), ('Ayarlar’ı aç', 'Open Settings'));
    expect((S.tr.guidePipHint, S.en.guidePipHint), (
      'Kısa video küçük pencerede oynamaya devam eder',
      'A short video keeps playing in a small window',
    ));
    expect(AppSettings.guideSteps.map(S.tr.guideStepTitle),
        ['Sesli görev kestirmesi', 'Eylem düğmesi', 'Arkaya Dokunma', 'Outlook takvimi']);
    expect(AppSettings.guideSteps.map(S.en.guideStepTitle),
        ['Voice task shortcut', 'Action button', 'Back Tap', 'Outlook calendar']);
    for (final s in [S.tr, S.en]) {
      for (final step in AppSettings.guideSteps) {
        expect(s.guideStepLines(step).length, greaterThanOrEqualTo(3), reason: '${s.locale} $step');
        expect(s.guideStepLines(step).every((l) => l.trim().isNotEmpty), isTrue, reason: '${s.locale} $step');
      }
      expect(() => s.guideStepTitle('bogus'), throwsArgumentError);
      expect(() => s.guideStepLines('bogus'), throwsArgumentError);
    }
    expect(S.tr.guideStepLines('actionButton'), [
      'Ayarlar > Eylem Düğmesi’ni aç.',
      'Kestirme’ye kaydır ve ‘Kestirme Seç’e dokun.',
      'Sesle Görev Ekle’yi seç.',
    ]);
    expect(S.tr.guideStepLines('backTap'), [
      'Ayarlar > Erişilebilirlik > Dokunma > Arkaya Dokunma’yı aç.',
      'İki ya da Üç Dokunuş’u seç.',
      'Listeden Sesle Görev Ekle kestirmesini seç.',
    ]);
    expect(S.tr.guideStepLines('outlook'), [
      'Ayarlar > Uygulamalar > Takvim > Takvim Hesapları’nı aç.',
      'Hesap Ekle > Outlook.com ya da Microsoft Exchange’i seç ve giriş yap.',
      'Takvimler anahtarını aç; etkinlikler Pamnot’ta Plan’da görünür.',
    ]);
    expect(S.tr.guideStepLines('shortcut', hasShareLink: true), [
      'Kısayolu ekle’ye dokun ve Kestirmeler’de ‘Kestirme Ekle’yi seç.',
      'Kısayolu çalıştır’a dokun; Pamnot dinlemeye başlar.',
      'İstersen Siri’ye ‘Pamnot ile görev ekle’ de.',
    ]);
    expect(S.tr.guideStepLines('shortcut', hasShareLink: false).first,
        'Kestirmeler’de + ile yeni kestirme oluştur ve Pamnot > Sesle Görev Ekle eylemini ekle.');
    // Run shortcut opens the shortcut by its fixed name, so the manual setup
    // tells the user to give it exactly that name, in both languages.
    expect(S.tr.guideStepLines('shortcut', hasShareLink: false)[1], 'Kestirmeye ‘Sesle Görev Ekle’ adını ver.');
    expect(S.en.guideStepLines('shortcut', hasShareLink: false)[1], 'Name the shortcut ‘Sesle Görev Ekle’.');
    expect(S.tr.guideStepLines('shortcut', hasShareLink: false).skip(2),
        S.tr.guideStepLines('shortcut', hasShareLink: true).skip(1));
    expect(S.en.guideStepLines('shortcut', hasShareLink: false).skip(2),
        S.en.guideStepLines('shortcut', hasShareLink: true).skip(1));
    // The English steps that pick the shortcut name it as it is saved.
    expect(S.en.guideStepLines('actionButton').last, 'Pick Sesle Görev Ekle.');
    expect(S.en.guideStepLines('backTap').last, 'Pick the Sesle Görev Ekle shortcut from the list.');
    for (final s in [S.tr, S.en]) {
      for (final step in ['actionButton', 'backTap']) {
        expect(s.guideStepLines(step).last, contains(voiceShortcutName), reason: '${s.locale} $step');
      }
    }
    // The link is still empty, so the default tells the manual setup.
    expect(S.tr.guideStepLines('shortcut'), S.tr.guideStepLines('shortcut', hasShareLink: false));
    expect(S.en.guideStepLines('shortcut', hasShareLink: true).length, 3);
    expect(S.en.guideStepLines('shortcut', hasShareLink: false).first,
        isNot(S.en.guideStepLines('shortcut', hasShareLink: true).first));
  });

  test('bağlantılar: kestirme adı, boş paylaşım bağlantısı, çalıştırma adresi', () {
    expect(voiceShortcutName, 'Sesle Görev Ekle');
    expect(voiceShortcutShareUrl, isEmpty);
    expect(runShortcutUri().toString(), 'shortcuts://run-shortcut?name=Sesle%20G%C3%B6rev%20Ekle');
  });

  test('ayarlar: kılavuz alanları varsayılan boş/false; gidiş-dönüş ve eski JSON', () {
    const d = AppSettings();
    expect(d.guideDone, isEmpty);
    expect((d.guideCardDismissed, d.voiceUsed), (false, false));
    final old = AppSettings.fromJson(const {});
    expect(old.guideDone, isEmpty);
    expect((old.guideCardDismissed, old.voiceUsed), (false, false));
    final s = d.copyWith(guideDone: ['shortcut', 'outlook'], guideCardDismissed: true, voiceUsed: true);
    final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
    expect(back.guideDone, ['shortcut', 'outlook']);
    expect((back.guideCardDismissed, back.voiceUsed), (true, true));
    expect(back.copyWith(language: AppLanguage.en).guideDone, ['shortcut', 'outlook']);
    final bad = AppSettings.fromJson(const {
      'guideDone': ['shortcut', 3, null, 'bogus', 'backTap', 'shortcut'],
      'guideCardDismissed': 'yes',
      'voiceUsed': 1,
    });
    expect(bad.guideDone, ['shortcut', 'backTap']);
    expect((bad.guideCardDismissed, bad.voiceUsed), (false, false));
    expect(AppSettings.fromJson(const {'guideDone': 'x'}).guideDone, isEmpty);
  });

  test('AppController.markGuideStep: ekler, çıkarır, yinelemez, bilinmeyen adımı reddeder, kaydeder', () async {
    final store = MemoryStore();
    final app = AppController(store: store, saveDelay: Duration.zero);
    await app.load();
    expect(app.guideStepDone('shortcut'), isFalse);
    var notified = 0;
    app.addListener(() => notified++);
    app.markGuideStep('shortcut');
    app.markGuideStep('backTap');
    app.markGuideStep('shortcut');
    expect(app.settings.guideDone, ['shortcut', 'backTap']);
    expect((app.guideStepDone('shortcut'), app.guideStepDone('backTap')), (true, true));
    expect(notified, 2);
    app.markGuideStep('shortcut', done: false);
    app.markGuideStep('outlook', done: false);
    expect(app.settings.guideDone, ['backTap']);
    expect(app.guideStepDone('shortcut'), isFalse);
    expect(notified, 3);
    expect(() => app.markGuideStep('bogus'), throwsArgumentError);
    expect(() => app.guideStepDone('bogus'), throwsArgumentError);
    await app.flush();
    final again = AppController(store: store);
    await again.load();
    expect(again.settings.guideDone, ['backTap']);
    app.dispose();
    again.dispose();
  });

  test('AppController.pip: verilmezse NoPipPlayer; verilen kullanılır', () {
    expect(AppController(store: MemoryStore()).pip, isA<NoPipPlayer>());
    final p = NoPipPlayer();
    expect(AppController(store: MemoryStore(), pip: p).pip, same(p));
  });
}
