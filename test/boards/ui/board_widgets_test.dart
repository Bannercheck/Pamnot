import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/ui/board_widgets.dart';
import 'package:pamnot/boards/ui/kanban_view.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/board_strings.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';

import 'harness.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('initials are Turkish-aware and at most two letters', () {
    expect(initialsOf('ilker'), 'İ');
    expect(initialsOf('ışıl yıldız'), 'IY');
    expect(initialsOf('  Ayşe  Nur  Kaya '), 'AK');
    expect(initialsOf(''), '?');
    expect(initialsOf('🌸 Bahar'), '🌸B');
  });

  test('relative times', () {
    final now = DateTime(2026, 10, 27, 9, 0);
    expect(relativeAgo(S.tr, now.subtract(const Duration(seconds: 20)), now), 'şimdi');
    expect(relativeAgo(S.tr, now.subtract(const Duration(minutes: 5)), now), '5 dk önce');
    expect(relativeAgo(S.tr, now.subtract(const Duration(hours: 2)), now), '2 sa önce');
    expect(relativeAgo(S.tr, DateTime(2026, 10, 26, 8), now), 'dün');
    expect(relativeAgo(S.tr, DateTime(2026, 10, 23, 12), now), '4 gün önce');
    expect(relativeAgo(S.tr, DateTime(2026, 9, 2), now), '2 Eyl');
    expect(relativeAgo(S.en, DateTime(2025, 9, 2), now), '2 Sep 2025');
    expect(relativeAgo(S.en, now.subtract(const Duration(hours: 3)), now), '3 h ago');
  });

  test('no suffix is ever attached to user content', () {
    expect(S.tr.editingNow('Ayşe'), 'Şu an düzenleyen: Ayşe');
    expect(S.tr.movedTo('Logo', 'Bitti'), '«Logo» → Bitti');
    expect(S.tr.cardSemantics(title: 'Logo', column: 'Yapılacak', assignee: 'Mert'),
        'Kart: Logo. Sütun: Yapılacak. Atanan: Mert.');
  });

  testWidgets('English UI', (tester) async {
    final c = await makeApp(tester,
        store: MemoryStore({
          'settings': jsonEncode(const AppSettings(language: AppLanguage.en, seeded: true, boardsSeeded: true).toJson()),
        }));
    late String id;
    await tester.runAsync(() async {
      id = await c.boards.createBoard(title: 'Launch', colorIndex: 2, template: BoardTemplate.tasks, strings: S.en);
      c.boards.saveView(id, const BoardViewState(view: 'kanban'));
      await c.boards.flush();
    });
    await settleReal(tester);
    await pumpBoardPage(tester, c, id, locale: const Locale('en'));
    expect(find.byType(KanbanView), findsOneWidget);
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('Add card'), findsWidgets);
    expect(find.byTooltip('Canvas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shutdown(tester, c);
  });
}
