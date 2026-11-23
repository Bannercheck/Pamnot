import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/core/dates.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/models/habit.dart';
import 'package:pamnot/models/ink.dart';
import 'package:pamnot/models/note.dart';
import 'package:pamnot/models/reminder.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/services/handwriting.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/theme/pamnot_theme.dart';
import 'package:pamnot/ui/notes/ink/ink_canvas.dart';
import 'package:pamnot/ui/notes/notes_page.dart';
import 'package:pamnot/ui/planner/planner_page.dart';
import 'package:pamnot/ui/tasks/task_tile.dart';
import 'package:pamnot/ui/today/today_page.dart';

/// Accessibility sweep over the whole app (compliance §3.2, §3.3, §3.6,
/// §3.7, §3.8): tap targets, VoiceOver labels, contrast, Reduce Motion,
/// large and bold text, haptics and the handwriting download prompt.
void main() {
  setUpAll(() => initializeDateFormatting());
  // Tuesday.
  final now = DateTime(2026, 10, 27, 9, 0);
  const tabs = ['Bugün', 'Notlar', 'Takip', 'Plan', 'Hatırlatma'];

  /// The first-run welcome note stays; on top of it three tasks (one
  /// overdue), a habit, a reminder and two notes (one pinned).
  void addContent(AppController c) {
    c.upsertTask(TaskItem(id: 't1', title: 'Raporu bitir', due: DateTime(2026, 10, 26), createdAt: now));
    c.upsertTask(TaskItem(
      id: 't2',
      title: 'Annemi ara',
      due: DateTime(2026, 10, 27, 18),
      hasTime: true,
      priority: Priority.high,
      subtasks: const [SubTask(id: 's1', title: 'Numarasını bul')],
      createdAt: now,
    ));
    c.upsertTask(TaskItem(id: 't3', title: 'Kitap oku', due: DateTime(2026, 10, 29), createdAt: now));
    c.upsertHabit(Habit(
      id: 'h1',
      name: 'Su iç',
      emoji: '💧',
      checkins: {dayKey(DateTime(2026, 10, 26))},
      createdAt: now,
    ));
    c.upsertReminder(Reminder(id: 'r1', title: 'İlaç al', at: DateTime(2026, 10, 27, 20), createdAt: now));
    c.upsertNote(Note(
      id: 'n1',
      title: 'Alışveriş listesi',
      body: 'Süt, ekmek, yumurta, peynir, zeytin\nBir de mevsim meyvesi ve çay',
      pinned: true,
      colorIndex: 4,
      createdAt: now,
      updatedAt: now,
    ));
    c.upsertNote(Note(
      id: 'n2',
      title: 'Fikirler',
      body: 'Hafta sonu için küçük bir gezi planı',
      colorIndex: 1,
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<AppController> boot(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double? textScale,
    ThemeMode theme = ThemeMode.light,
    HandwritingRecognizer? handwriting,
    bool content = true,
    bool boldText = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != null) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final c = AppController(
      store: MemoryStore({
        'settings': jsonEncode(AppSettings(language: AppLanguage.tr, themeMode: theme).toJson()),
      }),
      clock: () => now,
      handwriting: handwriting,
    );
    await tester.runAsync(c.load);
    if (content) addContent(c);
    final app = PamnotApp(controller: c);
    await tester.pumpWidget(boldText
        ? Builder(
            builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(boldText: true), child: app),
          )
        : app);
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab).last);
    await tester.pumpAndSettle();
  }

  /// Activates [f] the way VoiceOver does (double tap), through its
  /// semantics node rather than a pointer.
  Future<void> semanticTap(WidgetTester tester, Finder f) async {
    final node = tester.getSemantics(f);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
  }

  /// Colour of the check mark drawn inside [of].
  Color? checkColor(WidgetTester tester, Finder of) =>
      tester.widget<Icon>(find.descendant(of: of, matching: find.byIcon(Icons.check_rounded))).color;

  Future<void> meetsAllGuidelines(WidgetTester tester, String reason) async {
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: reason);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: reason);
    await expectLater(tester, meetsGuideline(textContrastGuideline), reason: reason);
  }

  // ------------------------------------------------------------ yönergeler

  for (final (name, mode) in [('açık', ThemeMode.light), ('koyu', ThemeMode.dark)]) {
    testWidgets('beş sekme yönergeleri karşılar: $name tema', (tester) async {
      final handle = tester.ensureSemantics();
      final c = await boot(tester, theme: mode);
      for (final tab in tabs) {
        await openTab(tester, tab);
        await meetsAllGuidelines(tester, tab);
      }
      handle.dispose();
      await shutdown(tester, c);
    });
  }

  testWidgets('Takip > Alışkanlıklar ve alışkanlık düzenleyici yönergeleri karşılar', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await boot(tester);
    await openTab(tester, 'Takip');
    await tester.tap(find.text('Alışkanlıklar'));
    await tester.pumpAndSettle();
    await meetsAllGuidelines(tester, 'alışkanlıklar');

    // Each day ring says which day it is and whether it is done; a future
    // day is read as disabled.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pazartesi 26 Ekim')),
      isSemantics(isButton: true, hasCheckedState: true, isChecked: true, isEnabled: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Salı 27 Ekim')),
      isSemantics(isButton: true, hasCheckedState: true, isChecked: false, isEnabled: true, hasTapAction: true),
    );
    // The check on the pastel fill is dark ink, not white (contrast).
    final doneRing = find.bySemanticsLabel('Pazartesi 26 Ekim');
    expect(checkColor(tester, doneRing), inkOnPastel);
    expect(tester.getSize(doneRing), const Size(44, 44));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Çarşamba 28 Ekim')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false, hasTapAction: false),
    );
    await semanticTap(tester, find.bySemanticsLabel('Salı 27 Ekim'));
    expect(c.habits.single.doneOn(DateTime(2026, 10, 27)), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Salı 27 Ekim')), isSemantics(isChecked: true));

    await tester.tap(find.text('Su iç'));
    await tester.pumpAndSettle();
    await meetsAllGuidelines(tester, 'alışkanlık düzenleyici');
    expect(
      tester.getSemantics(find.bySemanticsLabel('💧')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('📖')),
      isSemantics(isButton: true, isSelected: false, hasTapAction: true),
    );
    await semanticTap(tester, find.bySemanticsLabel('📖'));
    expect(tester.getSemantics(find.bySemanticsLabel('📖')), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('💧')), isSemantics(isSelected: false));
    handle.dispose();
    await shutdown(tester, c);
  });

  testWidgets('görev düzenleyici ve renk seçici yönergeleri karşılar', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await boot(tester, size: const Size(390, 1100));
    await tester.tap(find.text('Annemi ara'));
    await tester.pumpAndSettle();
    expect(find.text('Numarasını bul'), findsOneWidget);
    await meetsAllGuidelines(tester, 'görev düzenleyici');
    // Colours are read in the app's language, with the selected one marked.
    expect(find.bySemanticsLabel('lavanta'), findsOneWidget);
    expect(find.bySemanticsLabel('lavender'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('lavanta')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('nane')),
      isSemantics(isButton: true, isSelected: false, hasTapAction: true),
    );
    expect(tester.getSize(find.bySemanticsLabel('nane')), const Size(44, 44));
    expect(checkColor(tester, find.bySemanticsLabel('lavanta')), PamnotTheme.light().colorScheme.onSurface);
    await semanticTap(tester, find.bySemanticsLabel('nane'));
    expect(tester.getSemantics(find.bySemanticsLabel('nane')), isSemantics(isSelected: true));
    expect(find.byTooltip('Alt görevi kaldır'), findsOneWidget);
    handle.dispose();
    await shutdown(tester, c);
  });

  testWidgets('el yazısı araç çubuğu: renk ve kalınlık etiketli ve 44 pt', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await boot(tester, size: const Size(1366, 1024));
    await openTab(tester, 'Notlar');
    await tester.tap(find.byTooltip('El yazısı not'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kalem'), findsWidgets);

    for (var n = 1; n <= inkColors.length; n++) {
      final dot = find.bySemanticsLabel('Renk $n');
      expect(dot, findsOneWidget, reason: 'Renk $n');
      expect(tester.getSemantics(dot), isSemantics(isButton: true, isSelected: n == 1, hasTapAction: true));
      expect(tester.getSize(dot).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(dot).height, greaterThanOrEqualTo(44));
    }
    for (var n = 1; n <= 3; n++) {
      final dot = find.bySemanticsLabel('Kalınlık $n');
      expect(dot, findsOneWidget, reason: 'Kalınlık $n');
      // The pen starts at the middle width.
      expect(tester.getSemantics(dot), isSemantics(isButton: true, isSelected: n == 2, hasTapAction: true));
      expect(tester.getSize(dot).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(dot).height, greaterThanOrEqualTo(44));
    }
    await semanticTap(tester, find.bySemanticsLabel('Kalınlık 3'));
    expect(tester.getSemantics(find.bySemanticsLabel('Kalınlık 3')), isSemantics(isSelected: true));

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await shutdown(tester, c);
  });

  // ------------------------------------------------------------- VoiceOver

  testWidgets('onay halkası görev başlığıyla okunur', (tester) async {
    final c = await boot(tester);
    // The overdue task comes first on Today.
    final check = find.byType(SoftCheck).first;
    expect(tester.getSemantics(check).label, 'Raporu bitir');
    expect(
      tester.getSemantics(check),
      isSemantics(isButton: true, hasCheckedState: true, isChecked: false, hasTapAction: true),
    );
    expect(tester.getSize(check).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(check).height, greaterThanOrEqualTo(44));
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(c.tasks.firstWhere((t) => t.id == 't1').done, isTrue);

    // Today's task stays on screen once done: checked, with a dark check
    // on the pastel fill.
    final today = find.ancestor(of: find.bySemanticsLabel('Annemi ara'), matching: find.byType(SoftCheck));
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(c.tasks.firstWhere((t) => t.id == 't2').done, isTrue);
    expect(tester.getSemantics(today), isSemantics(label: 'Annemi ara', isChecked: true));
    expect(checkColor(tester, today), inkOnPastel);
    await shutdown(tester, c);
  });

  testWidgets('gecikmiş görev renk dışında ikon ve yazıyla da belli', (tester) async {
    final c = await boot(tester);
    expect(find.textContaining('Gecikti'), findsOneWidget);
    expect(find.text('Gecikti · 26 Eki'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    // The icon sits on the overdue task's row, not on today's task.
    final row = find.ancestor(of: find.text('Raporu bitir'), matching: find.byType(TaskTile));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.error_outline_rounded)), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('kaydırarak silmenin VoiceOver eylemi var', (tester) async {
    final c = await boot(tester);
    final node = tester.getSemantics(find.text('Raporu bitir'));
    final labels = [
      for (final id in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label,
    ];
    expect(labels, contains('Sil'));

    // Running the action deletes the task and offers undo, like the swipe.
    final delete = node
        .getSemanticsData()
        .customSemanticsActionIds!
        .firstWhere((id) => CustomSemanticsAction.getAction(id)!.label == 'Sil');
    node.owner!.performAction(node.id, SemanticsAction.customAction, delete);
    await tester.pumpAndSettle();
    expect(c.tasks.any((t) => t.id == 't1'), isFalse);
    expect(find.text('Silindi'), findsOneWidget);
    await tester.tap(find.text('Geri al'));
    await tester.pumpAndSettle();
    expect(c.tasks.any((t) => t.id == 't1'), isTrue);
    await shutdown(tester, c);
  });

  testWidgets('plan gün hücresi tam tarihi ve seçili durumunu okur', (tester) async {
    final c = await boot(tester);
    await openTab(tester, 'Plan');
    final today = find.bySemanticsLabel(RegExp('Salı 27 Ekim'));
    expect(today, findsOneWidget);
    expect(tester.getSemantics(today), isSemantics(isButton: true, isSelected: true, hasTapAction: true));
    final tomorrow = find.bySemanticsLabel(RegExp('Çarşamba 28 Ekim'));
    expect(tester.getSemantics(tomorrow), isSemantics(isButton: true, isSelected: false, hasTapAction: true));
    await semanticTap(tester, tomorrow);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Çarşamba 28 Ekim'))), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Salı 27 Ekim'))), isSemantics(isSelected: false));
    expect(find.byTooltip('Önceki'), findsOneWidget);
    expect(find.byTooltip('Sonraki'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('anımsatıcı anahtarı ve arama temizleme düğmesi adlarıyla okunur', (tester) async {
    final handle = tester.ensureSemantics();
    final c = await boot(tester);
    await openTab(tester, 'Hatırlatma');
    expect(
      tester.getSemantics(find.byType(Switch)),
      isSemantics(label: 'İlaç al', hasToggledState: true, isToggled: true, hasTapAction: true),
    );

    await openTab(tester, 'Notlar');
    expect(find.byTooltip('Aramayı temizle'), findsNothing);
    await tester.enterText(find.byType(TextField), 'liste');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aramayı temizle'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    handle.dispose();
    await shutdown(tester, c);
  });

  testWidgets('süs emojileri okunmaz', (tester) async {
    // Nothing planned today: the progress ring shows its cloud too.
    final c = await boot(tester, size: const Size(1366, 1024), content: false);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('☁️'), findsNWidgets(2));
    expect(find.bySemanticsLabel('☁️'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('☁️')), findsNothing);
    // An empty day in Plan.
    await openTab(tester, 'Plan');
    expect(find.text('☁️'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('☁️')), findsNothing);
    await shutdown(tester, c);
  });

  // ------------------------------------------------------------ hareket

  testWidgets('Hareketi Azalt: onay halkası sıçramaz', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final c = await boot(tester);
    final check = find.byType(SoftCheck).first;
    await tester.tap(check);
    await tester.pump();
    final box = tester.widget<AnimatedContainer>(find.descendant(of: check, matching: find.byType(AnimatedContainer)));
    expect(box.duration, Duration.zero);
    expect(box.curve, Curves.easeOut);
    await tester.pumpAndSettle();
    await shutdown(tester, c);
  });

  testWidgets('hareket ayarı kapalıyken onay halkası yine canlanır', (tester) async {
    final c = await boot(tester);
    final check = find.byType(SoftCheck).first;
    final box = tester.widget<AnimatedContainer>(find.descendant(of: check, matching: find.byType(AnimatedContainer)));
    expect(box.duration, const Duration(milliseconds: 220));
    expect(box.curve, Curves.easeOutBack);
    await shutdown(tester, c);
  });

  // ----------------------------------------------------- büyük ve kalın metin

  testWidgets('metin ölçeği 2,0 ve 375×667: beş sekmede taşma yok', (tester) async {
    final c = await boot(tester, size: const Size(375, 667), textScale: 2.0);
    expect(tester.takeException(), isNull);

    // Today's progress ring grows with the text so the count fits inside,
    // and the summary moves below the ring instead of being squeezed.
    bool inside(Rect a, Rect b) => a.left >= b.left && a.top >= b.top && a.right <= b.right && a.bottom <= b.bottom;
    final (done, total) = c.progressOn(now);
    // First: the task row's subtask count can read the same.
    final count = find.text('$done/$total').first;
    final ring = tester.getRect(find.ancestor(of: count, matching: find.byType(Stack)).first);
    expect(ring.size, const Size(148, 148));
    expect(inside(tester.getRect(count), ring), isTrue);
    expect(tester.getRect(find.text('Bugünün planı').first).top, greaterThanOrEqualTo(ring.bottom));

    // The welcome note and the pinned note are where cards used to overflow:
    // the Today strip (pinned notes) and the Notes grid.
    Finder welcomeIn(Type page) =>
        find.descendant(of: find.byType(page), matching: find.textContaining('hoş geldin'));
    for (final tab in tabs) {
      await openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
      if (tab == 'Notlar') expect(welcomeIn(NotesPage), findsOneWidget);
      // Lay out the whole tab, not only its first screen.
      for (var i = 0; i < 6; i++) {
        await tester.dragFrom(const Offset(187, 300), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab, kaydırma $i');
      }
      if (tab == 'Bugün') {
        expect(welcomeIn(TodayPage), findsOneWidget);
        final pinned = find.descendant(of: find.byType(TodayPage), matching: find.text('Alışveriş listesi'));
        expect(pinned, findsOneWidget);
      }
      if (tab == 'Plan') {
        // The agenda's time column widens with the text instead of breaking "18:00".
        final time = find.descendant(of: find.byType(PlannerPage), matching: find.text('18:00'));
        expect(time, findsOneWidget);
        expect(tester.getSize(find.ancestor(of: time, matching: find.byType(SizedBox)).first).width, 116);
      }
    }
    await shutdown(tester, c);
  });

  testWidgets('alt çubuk etiketi 1,3 ölçekle sınırlı', (tester) async {
    final c = await boot(tester, textScale: 2.0);
    final label = find.descendant(of: find.byType(NavigationBar), matching: find.text('Notlar'));
    expect(label, findsOneWidget);
    expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), lessThanOrEqualTo(13));
    expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), greaterThan(10));
    // Page text still follows the full system size.
    expect(MediaQuery.textScalerOf(tester.element(find.text('Raporu bitir'))).scale(10), 20);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);
  });

  testWidgets('Kalın Metin açıkken gövde ağırlığı artar', (tester) async {
    var c = await boot(tester);
    var ctx = tester.element(find.text('Raporu bitir'));
    expect(Theme.of(ctx).textTheme.bodyMedium!.fontWeight, FontWeight.w400);
    await shutdown(tester, c);

    c = await boot(tester, boldText: true);
    ctx = tester.element(find.text('Raporu bitir'));
    expect(MediaQuery.boldTextOf(ctx), isTrue);
    final text = Theme.of(ctx).textTheme;
    expect(text.bodyMedium!.fontWeight, FontWeight.w600);
    expect(text.bodyLarge!.fontWeight, FontWeight.w600);
    expect(text.titleMedium!.fontWeight, FontWeight.w800);
    expect(text.headlineMedium!.fontWeight, FontWeight.w800);
    // Sheets sit under the same theme.
    await tester.tap(find.text('Annemi ara'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Numarasını bul'))).textTheme.bodyMedium!.fontWeight, FontWeight.w600);
    await shutdown(tester, c);
  });

  test('PamnotTheme.bolder: 400→600, 600→700, 700→800, 800 aynı', () {
    const styles = TextTheme(
      bodyMedium: TextStyle(fontWeight: FontWeight.w400),
      bodySmall: TextStyle(),
      labelSmall: TextStyle(fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(fontWeight: FontWeight.w800),
    );
    final t = PamnotTheme.bolder(ThemeData(textTheme: styles, primaryTextTheme: styles));
    for (final text in [t.textTheme, t.primaryTextTheme]) {
      expect(text.bodyMedium!.fontWeight, FontWeight.w600);
      expect(text.bodySmall!.fontWeight, FontWeight.w600, reason: 'no weight means regular');
      expect(text.labelSmall!.fontWeight, FontWeight.w700);
      expect(text.titleMedium!.fontWeight, FontWeight.w800);
      expect(text.headlineLarge!.fontWeight, FontWeight.w800);
    }
    // The rest of the theme is untouched.
    final light = PamnotTheme.light();
    expect(PamnotTheme.bolder(light).colorScheme, light.colorScheme);
  });

  // ------------------------------------------------------------ dokunsal

  testWidgets('görev tamamlama ve silme dokunsal geri bildirim verir', (tester) async {
    final haptics = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final c = await boot(tester);

    await tester.tap(find.byType(SoftCheck).first);
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    await tester.drag(find.text('Annemi ara'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(c.tasks.any((t) => t.id == 't2'), isFalse);
    expect(haptics, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.mediumImpact']);
    await shutdown(tester, c);
  });

  // --------------------------------------------------- el yazısı modeli

  testWidgets('el yazısı modeli boyut söylenip sorulmadan inmez', (tester) async {
    final rec = _FakeRecognizer();
    final c = await boot(tester, size: const Size(1366, 1024), handwriting: rec);
    await openTab(tester, 'Notlar');
    await tester.tap(find.byTooltip('El yazısı not'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(InkCanvas));
    final g = await tester.startGesture(center);
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(8, 3));
    }
    await g.up();
    await tester.pump();

    await tester.tap(find.text('Yazıya çevir'));
    await tester.pumpAndSettle();
    expect(find.text('El yazısı modeli indirilsin mi?'), findsOneWidget);
    expect(find.text('Yaklaşık 20 MB.'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('El yazısı modeli indirilsin mi?'), findsNothing);
    expect(rec.prepares, 0);
    expect(rec.recognitions, 0);
    expect(find.text('El yazısı modeli indiriliyor…'), findsNothing);

    await tester.tap(find.text('Yazıya çevir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('İndir'));
    // The convert button keeps spinning while the choice sheet is open.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(rec.prepares, 1);
    expect(rec.recognitions, 1);
    expect(find.text('merhaba'), findsOneWidget);
    await tester.tap(find.text('merhaba'));
    await tester.pumpAndSettle();
    expect(find.text('El yazısı modeli indirilsin mi?'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(c.notes.any((n) => n.body == 'merhaba'), isTrue);
    await shutdown(tester, c);
  });
}

/// Supported, with the model not downloaded yet.
class _FakeRecognizer implements HandwritingRecognizer {
  int prepares = 0;
  int recognitions = 0;

  @override
  bool get isSupported => true;

  @override
  Future<bool> isModelReady(String model) async => false;

  @override
  Future<bool> prepare(String model) async {
    prepares++;
    return true;
  }

  @override
  Future<List<String>> recognize(List<InkStroke> strokes, {required String model, String preContext = ''}) async {
    recognitions++;
    return const ['merhaba'];
  }
}
