import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/task_list.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/settings/voice_settings.dart';
import 'package:pamnot/ui/voice/voice_capture_controller.dart';
import 'package:pamnot/ui/voice/voice_capture_page.dart';

import 'support/fake_speech_engine.dart';
import 'support/voice_harness.dart';

const tr = S.tr;

/// The voice screen as the app's home with a Turkish phone, after the first
/// listen has started.
Future<FakeSpeechEngine> pumpVoice(
  WidgetTester tester,
  VoiceHarness h, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool accessibleNavigation = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = const [Locale('tr', 'TR')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final e = FakeSpeechEngine();
  await tester.pumpWidget(
    AppScope(
      controller: h.app,
      child: MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: PamnotTheme.light(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale), accessibleNavigation: accessibleNavigation),
          child: child!,
        ),
        home: VoiceCapturePage(engine: e),
      ),
    ),
  );
  await tester.pump(VoiceTimings.startDelay);
  await tester.pump();
  return e;
}

Future<void> shutdown(WidgetTester tester, VoiceHarness h) async {
  await tester.pumpWidget(const SizedBox());
  await h.dispose(tester);
}

/// Says [text] and waits until the preview is up.
Future<void> sayToPreview(WidgetTester tester, FakeSpeechEngine e, String text) async {
  e.say(text);
  await tester.pump(VoiceTimings.utteranceGap);
}

Finder listChip(String id) => find.byKey(Key('voice-list-$id'));
Finder boxChip(Quadrant q) => find.byKey(Key('voice-box-${q.name}'));

/// The chip's node has a selected state, and it is [value].
void expectSelected(WidgetTester tester, Finder f, bool value) =>
    expect(tester.getSemantics(f), isSemantics(hasSelectedState: true, isSelected: value));

void main() {
  testWidgets('konuşma bitince liste ve kutu satırları görünür; son kullanılan liste seçili', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    h.app.selectList('work');
    final e = await pumpVoice(tester, h);
    e.say('yarın annemi ara');
    await tester.pump();
    // Not while listening.
    expect(listChip('work'), findsNothing);
    await tester.pump(VoiceTimings.utteranceGap);
    expect(find.text(tr.list), findsOneWidget);
    expect(find.text(tr.box), findsOneWidget);
    for (final l in h.app.lists) {
      expect(listChip(l.id), findsOneWidget, reason: l.id);
    }
    for (final q in Quadrant.values) {
      expect(boxChip(q), findsOneWidget, reason: q.name);
      expect(find.text(tr.quadrantTitle(q)), findsOneWidget);
    }
    // The last used list is first and selected; the default box is "plan".
    expectSelected(tester, listChip('work'), true);
    expectSelected(tester, listChip('personal'), false);
    expect(tester.getTopLeft(listChip('work')).dx, lessThan(tester.getTopLeft(listChip('personal')).dx));
    expectSelected(tester, boxChip(Quadrant.plan), true);
    expectSelected(tester, boxChip(Quadrant.doNow), false);
    // The boxes are two by two.
    final a = tester.getTopLeft(boxChip(Quadrant.doNow));
    final b = tester.getTopLeft(boxChip(Quadrant.plan));
    final c = tester.getTopLeft(boxChip(Quadrant.delegate));
    expect(a.dy, b.dy);
    expect(c.dy, greaterThan(a.dy));
    expect(c.dx, a.dx);
    expect(find.byKey(const Key('voice-countdown')), findsOneWidget);
    expect(find.text('8 sn'), findsOneWidget);
    expect(find.byKey(const Key('voice-fix')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, tr.add), findsOneWidget);
    expect(find.byKey(const Key('voice-save')), findsOneWidget);
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('seçim yoksa 8 sn sonra son kullanılan listeye ve plan kutusuna kaydeder', (tester) async {
    final h = await VoiceHarness.create(tester);
    h.app.selectList('school');
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ödev yap');
    await tester.pump(const Duration(milliseconds: 7900));
    expect(h.app.tasks, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.listId, t.quadrant), ('school', Quadrant.plan));
    await shutdown(tester, h);
  });

  testWidgets('liste çipine dokunmak hemen o listeye kaydeder', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ekmek al');
    // The row scrolls sideways.
    await tester.ensureVisible(listChip('shopping'));
    await tester.pump();
    await tester.tap(listChip('shopping'));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.title, t.listId, t.quadrant), ('Ekmek al', 'shopping', Quadrant.plan));
    // The list becomes the last used one.
    expect(h.app.currentListId, 'shopping');
    await shutdown(tester, h);
  });

  testWidgets('kutu çipi seçer, sayacı baştan başlatır; sonra "Ekle" seçilenle kaydeder', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ekmek al');
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('3 sn'), findsOneWidget);
    await tester.tap(boxChip(Quadrant.later));
    await tester.pump();
    expect(h.app.tasks, isEmpty);
    expectSelected(tester, boxChip(Quadrant.later), true);
    expectSelected(tester, boxChip(Quadrant.plan), false);
    expect(find.text('8 sn'), findsOneWidget);
    // Past the first eight seconds: the countdown started again.
    await tester.pump(const Duration(seconds: 5));
    expect(h.app.tasks, isEmpty);
    expect(find.text('3 sn'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.listId, t.quadrant), ('personal', Quadrant.later));
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('"alışveriş listesine ekmek ekle": Alışveriş seçili gelir, başlık "ekmek"', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'alışveriş listesine ekmek ekle');
    expectSelected(tester, listChip('shopping'), true);
    expectSelected(tester, listChip('personal'), false);
    // The parser writes titles in sentence case.
    expect(find.text('Ekmek'), findsOneWidget);
    expect(find.text('Alışveriş listesine ekmek ekle'), findsNothing);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.title, t.listId), ('Ekmek', 'shopping'));
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('"bugün 18\'de annemi ara" (saat 09:00): kutu Önemli · Acil seçili gelir', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, "bugün 18'de annemi ara");
    expectSelected(tester, boxChip(Quadrant.doNow), true);
    expectSelected(tester, boxChip(Quadrant.plan), false);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    expect(h.app.tasks.single.quadrant, Quadrant.doNow);
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('voiceAutoSave kapalı: sayaç yok, 30 sn beklemek kaydetmez, "Ekle" kaydeder', (tester) async {
    final h = await VoiceHarness.create(tester);
    h.app.updateSettings(h.app.settings.copyWith(voiceAutoSave: false));
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ekmek al');
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    expect(find.byKey(const Key('voice-fix')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, tr.add), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(h.app.tasks, isEmpty);
    await tester.tap(boxChip(Quadrant.delegate));
    await tester.pump();
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.listId, t.quadrant), ('personal', Quadrant.delegate));
    await shutdown(tester, h);
  });

  testWidgets('VoiceOver açık: sayaç yok (mevcut kural), çipler etiketli', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h, accessibleNavigation: true);
    await sayToPreview(tester, e, 'yarın ekmek al');
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    expect(
      tester.getSemantics(listChip('shopping')),
      isSemantics(label: 'Alışveriş', isButton: true, hasTapAction: true, isSelected: false, hasSelectedState: true),
    );
    expect(
      tester.getSemantics(boxChip(Quadrant.plan)),
      isSemantics(
        label: 'Önemli · Planlı',
        isButton: true,
        hasTapAction: true,
        isSelected: true,
        hasSelectedState: true,
      ),
    );
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.pump(const Duration(seconds: 10));
    expect(h.app.tasks, isEmpty);
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('not ("not al süt bitti") için liste/kutu satırı yok, 8 sn sonra not kaydedilir', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'not al süt bitti');
    expect(find.text(tr.voiceNoteChip), findsOneWidget);
    expect(find.text(tr.list), findsNothing);
    expect(find.text(tr.box), findsNothing);
    expect(listChip('personal'), findsNothing);
    expect(boxChip(Quadrant.plan), findsNothing);
    await tester.pump(const Duration(milliseconds: 7900));
    expect(h.app.notes, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(h.app.notes.single.body, isNotEmpty);
    expect(h.app.tasks, isEmpty);
    await shutdown(tester, h);
  });

  testWidgets('önizlemedeyken arka plana gitmek seçili listeye kaydeder ("Kilitlenirken kaydedildi")', (tester) async {
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'alışveriş listesine ekmek ekle');
    await tester.tap(boxChip(Quadrant.later));
    await tester.pump();
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.title, t.listId, t.quadrant), ('Ekmek', 'shopping', Quadrant.later));
    expect(find.text(tr.voiceSavedOnLock), findsOneWidget);
    expect(find.text(tr.voiceSavedTo('Alışveriş')), findsOneWidget);
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await shutdown(tester, h);
  });

  testWidgets('RF2: önizlemedeyken seçili liste silinirse kayıt geçerli listeye gider, hata yok', (tester) async {
    final h = await VoiceHarness.create(tester);
    h.app.selectList('work');
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'alışveriş listesine ekmek ekle');
    expect(listChip('shopping'), findsOneWidget);
    h.app.deleteList('shopping');
    await tester.pump();
    expect(listChip('shopping'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(VoiceTimings.previewHold);
    await tester.pump();
    final t = h.app.tasks.single;
    expect(t.listId, 'work');
    expect(tester.takeException(), isNull);
    await shutdown(tester, h);
  });

  testWidgets('RF: 20 liste, 40 karakterlik ad, ölçek 2,0, 375 pt: çipler kaydırılır, taşma yok', (tester) async {
    final h = await VoiceHarness.create(tester);
    final long = 'Çok uzun bir liste adı ' * 2;
    final name40 = long.substring(0, 40);
    final added = h.app.addList(name40);
    for (var i = 0; i < 14; i++) {
      h.app.addList('Liste $i');
    }
    expect(h.app.lists, hasLength(20));
    final e = await pumpVoice(tester, h, size: const Size(375, 667), textScale: 2);
    await sayToPreview(tester, e, 'yarın ekmek al');
    expect(tester.takeException(), isNull);
    final row = find.byKey(const Key('voice-list-row'));
    expect(row, findsOneWidget);
    expect(tester.widget<SingleChildScrollView>(row).scrollDirection, Axis.horizontal);
    // The last list is off screen until the row is scrolled.
    final last = listChip(h.app.lists.last.id);
    await tester.ensureVisible(row);
    await tester.pump();
    expect(tester.getTopLeft(last).dx, greaterThan(375));
    await tester.drag(row, const Offset(-20000, 0));
    await tester.pump();
    expect(tester.getTopRight(last).dx, lessThanOrEqualTo(375));
    expect(listChip(added.id), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Every box chip fits the width.
    for (final q in Quadrant.values) {
      expect(tester.getTopRight(boxChip(q)).dx, lessThanOrEqualTo(375), reason: q.name);
    }
    await shutdown(tester, h);
  });

  testWidgets('Ayarlar > Sesle ekleme: "8 saniye sonra kendiliğinden kaydet" anahtarı ayarı yazar', (tester) async {
    final h = await VoiceHarness.create(tester);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: PamnotTheme.light(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: h.app,
            builder: (_, _) => ListView(children: [VoiceSettingsGroup(app: h.app)]),
          ),
        ),
      ),
    );
    final tile = find.widgetWithText(SwitchListTile, tr.voiceAutoSaveTitle);
    expect(tile, findsOneWidget);
    expect(find.text(tr.voiceAutoSaveSub), findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pump();
    expect(h.app.settings.voiceAutoSave, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pump();
    expect(h.app.settings.voiceAutoSave, isTrue);
    await shutdown(tester, h);
  });

  testWidgets('kayıt satırı liste adını gösterir; geri al görevi siler', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ekmek al');
    // The row scrolls sideways.
    await tester.ensureVisible(listChip('home'));
    await tester.pump();
    await tester.tap(listChip('home'));
    await tester.pump();
    final t = h.app.tasks.single;
    final row = find.byKey(Key('voice-saved-${t.id}'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(tr.voiceSavedTo('Ev'))), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Ev listesine eklendi')), findsOneWidget);
    await tester.tap(find.byKey(Key('voice-undo-${t.id}')));
    await tester.pump();
    expect(h.app.tasks, isEmpty);
    expect(row, findsNothing);
    handle.dispose();
    await shutdown(tester, h);
  });

  testWidgets('F2: Düzelt\'te liste ve kutu satırları kalır; seçim kaydetmez, metindeki liste yeniden eşleşir', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await VoiceHarness.create(tester);
    final e = await pumpVoice(tester, h);
    await sayToPreview(tester, e, 'yarın ekmek al');
    await tester.tap(find.byKey(const Key('voice-fix')));
    await tester.pump();
    expect(find.byKey(const Key('voice-draft')), findsOneWidget);
    expect(find.text(tr.list), findsOneWidget);
    expect(find.text(tr.box), findsOneWidget);
    expect(find.byKey(const Key('voice-countdown')), findsNothing);
    expectSelected(tester, listChip('personal'), true);
    // The list follows the text as it is typed.
    await tester.enterText(find.byKey(const Key('voice-draft')), 'iş listesine rapor ekle');
    await tester.pump();
    expectSelected(tester, listChip('work'), true);
    expectSelected(tester, listChip('personal'), false);
    // A pick only selects while correcting; no timer runs.
    await tester.ensureVisible(listChip('home'));
    await tester.tap(listChip('home'));
    await tester.pump();
    await tester.ensureVisible(boxChip(Quadrant.later));
    await tester.tap(boxChip(Quadrant.later));
    await tester.pump();
    expectSelected(tester, listChip('home'), true);
    expectSelected(tester, boxChip(Quadrant.later), true);
    await tester.pump(VoiceTimings.previewHold * 2);
    expect(h.app.tasks, isEmpty);
    expect(find.byKey(const Key('voice-draft')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('voice-save')));
    await tester.tap(find.byKey(const Key('voice-save')));
    await tester.pump();
    final t = h.app.tasks.single;
    expect((t.title, t.listId, t.quadrant), ('Rapor', 'home', Quadrant.later));
    handle.dispose();
    await shutdown(tester, h);
  });
}
