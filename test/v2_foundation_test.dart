import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
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

  test('pubspec derleme numarası 4', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.0.0+4'));
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
}
