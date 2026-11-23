import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/sample_data.dart';

void main() {
  test('ilk açılış yalnız karşılama notunu getirir', () {
    final d = SampleData.build(S.tr, DateTime(2026, 11, 23, 9), () => 'id');
    expect(d.notes.length, 1);
    expect(d.notes.single.title, startsWith('Pamnot’a hoş geldin'));
    // A record of matchers is compared with ==, so each list is checked on its own.
    expect(d.tasks, isEmpty);
    expect(d.reminders, isEmpty);
    expect(d.habits, isEmpty);
  });

  test('widget maddesi iOS\'ta yok, Android\'de var', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(SampleData.build(S.tr, DateTime(2026), () => 'id').notes.single.body, isNot(contains('widget')));
    expect(SampleData.build(S.en, DateTime(2026), () => 'id').notes.single.body, isNot(contains('widget')));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SampleData.build(S.tr, DateTime(2026), () => 'id').notes.single.body, contains('widget'));
  });

  test('ilk açılışta zamanlanacak uyarı yok', () async {
    final store = MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())});
    final c = AppController(store: store, clock: () => DateTime(2026, 11, 23, 9), saveDelay: Duration.zero);
    addTearDown(c.dispose);
    await c.load();
    // The first-run seed ran, and nothing in it asks for a notification.
    expect(c.settings.seeded, isTrue);
    expect(c.alerts(), isEmpty);
    expect(c.notes.single.title, startsWith('Pamnot’a hoş geldin'));
  });
}
