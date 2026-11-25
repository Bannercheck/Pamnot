import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/launch_actions.dart';
import 'package:pamnot/services/speech/speech_engine.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/ui/common/glass.dart';
import 'package:pamnot/ui/common/glass_nav_bar.dart';
import 'package:pamnot/ui/home_shell.dart';
import 'package:pamnot/ui/notes/notes_page.dart';
import 'package:pamnot/ui/planner/planner_page.dart';
import 'package:pamnot/ui/reminders/reminders_page.dart';
import 'package:pamnot/ui/tasks/task_editor.dart';
import 'package:pamnot/ui/tasks/track_page.dart';
import 'package:pamnot/ui/today/today_page.dart';
import 'package:pamnot/ui/voice/voice_capture_page.dart';

import 'support/fake_speech_engine.dart';

/// The v2 shell: the floating glass bar with the voice button in the middle,
/// and Reminders inside Plan (design §4).
void main() {
  setUpAll(() => initializeDateFormatting());
  final now = DateTime(2026, 10, 27, 9, 0);
  late AppController c;
  late FakeSpeechEngine engine;

  setUp(() {
    voiceRequests.value = null;
    notificationTaps.value = null;
  });

  tearDown(() {
    voiceRequests.value = null;
    notificationTaps.value = null;
    planSection.value = PlanSection.agenda;
  });

  Future<void> boot(WidgetTester tester, {SpeechEngine? speech, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    engine = FakeSpeechEngine();
    c = AppController(
      store: MemoryStore({'settings': jsonEncode(const AppSettings(language: AppLanguage.tr).toJson())}),
      clock: () => now,
      speech: speech ?? engine,
    );
    await tester.runAsync(c.load);
    c.upsertReminder(Reminder(id: 'r1', title: 'İlaç al', at: DateTime(2026, 10, 27, 20), createdAt: now));
    await tester.pumpWidget(PamnotApp(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> shutdown(WidgetTester tester) async {
    if (find.byType(VoiceCapturePage).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('voice-close')));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  int selected(WidgetTester tester) => tester.widget<GlassNavBar>(find.byType(GlassNavBar)).selectedIndex;

  testWidgets('telefon: GlassNavBar var, NavigationBar yok; sekmeler Bugün, Notlar, Takip, Plan', (tester) async {
    await boot(tester);
    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(GlassScope), findsOneWidget);
    expect(tester.widget<Scaffold>(find.ancestor(of: find.byType(GlassNavBar), matching: find.byType(Scaffold))).extendBody, isTrue);

    final labels = [
      for (var i = 0; i < 4; i++)
        tester.widget<Text>(find.descendant(of: find.byKey(Key('nav-$i')), matching: find.byType(Text))).data,
    ];
    expect(labels, ['Bugün', 'Notlar', 'Takip', 'Plan']);
    // Reminders is no longer a tab.
    expect(find.descendant(of: find.byType(GlassNavBar), matching: find.text('Hatırlatma')), findsNothing);

    final pages = [TodayPage, NotesPage, TrackPage, PlannerPage];
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(Key('nav-$i')));
      await tester.pumpAndSettle();
      expect(selected(tester), i);
      expect(find.byType(pages[i]), findsOneWidget);
    }
    await shutdown(tester);
  });

  testWidgets('orta düğme ses destekliyse voiceRequests = listen yazar; desteklemiyorsa görev düzenleyiciyi açar', (tester) async {
    await boot(tester);
    final center = find.byKey(const Key('nav-center'));
    expect(find.descendant(of: center, matching: find.byIcon(Icons.mic_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip('Sesle görev ekle')), findsOneWidget);
    await tester.tap(center);
    await tester.pumpAndSettle();
    // HomeShell consumed a listen request (a link would open it paused): the
    // voice screen is open and the engine listens.
    expect(voiceRequests.value, isNull);
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(engine.listening, isTrue);
    await shutdown(tester);

    await boot(tester, speech: UnsupportedSpeechEngine());
    expect(find.descendant(of: center, matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byType(GlassNavBar), matching: find.byTooltip('Yeni görev ekle')), findsOneWidget);
    final before = c.tasks.length;
    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    expect(voiceRequests.value, isNull);
    expect(c.tasks.length, before);
    await shutdown(tester);
  });

  testWidgets('r: bildirimi Plan sekmesini Hatırlatmalar bölümüyle açar; t: Takip, w: Bugün', (tester) async {
    await boot(tester);
    notificationTaps.value = 'r:r1';
    await tester.pumpAndSettle();
    expect(selected(tester), 3);
    expect(planSection.value, PlanSection.reminders);
    expect(find.byType(RemindersList), findsOneWidget);
    expect(find.text('İlaç al'), findsOneWidget);
    expect(notificationTaps.value, isNull);

    notificationTaps.value = 't:x';
    await tester.pumpAndSettle();
    expect(selected(tester), 2);
    expect(find.byType(TrackPage), findsOneWidget);

    notificationTaps.value = 'w:today';
    await tester.pumpAndSettle();
    expect(selected(tester), 0);
    await shutdown(tester);
  });

  testWidgets('Plan > Hatırlatmalar: hatırlatıcı listelenir, FAB yeni hatırlatıcı açar', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<PlanSection>), findsOneWidget);
    expect(find.text('Takvim'), findsOneWidget);
    expect(find.byType(RemindersList), findsNothing);
    // The agenda shows the week strip.
    expect(find.text('Hafta'), findsOneWidget);

    await tester.tap(find.text('Anımsatıcılar'));
    await tester.pumpAndSettle();
    expect(planSection.value, PlanSection.reminders);
    expect(find.byType(RemindersList), findsOneWidget);
    expect(find.text('Hafta'), findsNothing);
    expect(find.text('İlaç al'), findsOneWidget);
    expect(find.byType(RemindersPage), findsNothing);

    // The page's button floats above the bar and its rising centre button.
    final fab = tester.getRect(find.widgetWithText(FloatingActionButton, 'Yeni anımsatıcı'));
    expect(fab.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('nav-center'))).top));
    await tester.tap(find.text('Yeni anımsatıcı'));
    await tester.pumpAndSettle();
    // The editor sheet opens with an empty new reminder.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Yeni anımsatıcı'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Neyi hatırlatayım?'), findsOneWidget);
    await shutdown(tester);
  });

  testWidgets('geniş ekran: NavigationRail dört hedef ve orta düğme', (tester) async {
    await boot(tester, size: const Size(1366, 1024));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(4));
    expect(find.byType(GlassNavBar), findsNothing);
    final center = find.byKey(const Key('nav-center'));
    expect(center, findsOneWidget);
    expect(tester.widget(center), isA<FloatingActionButton>());
    expect(find.descendant(of: find.byType(NavigationRail), matching: center), findsOneWidget);
    expect(find.byTooltip('Sesle görev ekle'), findsWidgets);

    notificationTaps.value = 'r:r1';
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 3);
    expect(find.byType(RemindersList), findsOneWidget);

    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceCapturePage), findsOneWidget);
    expect(engine.listening, isTrue);
    await shutdown(tester);
  });

  // The body runs under the floating bar, so every page's end spacer must
  // grow with the bar: at the end of a long list the last row and its
  // control stay clear of the page's button, the centre button and the bar,
  // with and without the home indicator.
  for (final inset in [0.0, 34.0]) {
    testWidgets('uzun listenin sonunda son satır FAB ve menünün altında kalmaz (alt boşluk $inset)', (tester) async {
      await boot(tester);
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      for (var i = 0; i < 14; i++) {
        final n = i.toString().padLeft(2, '0');
        c.upsertReminder(Reminder(id: 'rx$i', title: 'Hatırlat $n', at: DateTime(2026, 10, 28 + i, 10), createdAt: now));
        c.upsertTask(TaskItem(id: 'tx$i', title: 'Görev $n', due: now, createdAt: now));
        c.upsertNote(Note(id: 'nx$i', title: 'Not $n', body: 'Satır $n', createdAt: now, updatedAt: now.add(Duration(minutes: i))));
      }
      await tester.pumpAndSettle();

      Future<void> checkEnd(String what, List<Finder> rows) async {
        final scroll = find.byType(Scrollable).hitTestable().first;
        await tester.drag(scroll, const Offset(0, -20000));
        await tester.pumpAndSettle();
        final height = tester.view.physicalSize.height;
        final visible = [
          for (final f in rows)
            for (final e in f.evaluate())
              if (tester.getRect(find.byWidget(e.widget).first).top < height) tester.getRect(find.byWidget(e.widget).first),
        ];
        expect(visible, isNotEmpty, reason: what);
        final last = visible.reduce((a, b) => a.bottom >= b.bottom ? a : b);
        final obstacles = [
          for (final e in find.byType(FloatingActionButton).evaluate()) tester.getRect(find.byWidget(e.widget)),
          tester.getRect(find.byType(GlassNavBar)),
        ];
        for (final o in obstacles) {
          expect(last.overlaps(o), isFalse, reason: '$what: last row $last overlaps $o');
          // Not only side by side: the end of the list rises above them.
          expect(last.bottom, lessThanOrEqualTo(o.top), reason: '$what: last row $last reaches under $o');
        }
      }

      await checkEnd('Bugün', [find.textContaining('Görev ')]);
      await tester.tap(find.byKey(const Key('nav-1')));
      await tester.pumpAndSettle();
      await checkEnd('Notlar', [find.textContaining('Not ')]);
      await tester.tap(find.byKey(const Key('nav-2')));
      await tester.pumpAndSettle();
      await checkEnd('Takip', [find.textContaining('Görev '), find.byType(Checkbox)]);
      await tester.tap(find.byKey(const Key('nav-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anımsatıcılar'));
      await tester.pumpAndSettle();
      await checkEnd('Plan > Anımsatıcılar', [find.textContaining('Hatırlat '), find.byType(Switch)]);
      await shutdown(tester);
    });
  }
}
