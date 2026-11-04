import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/app.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/ui/board_page.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';

/// Tuesday 27 Oct 2026, 09:00 — the same clock the app tests use.
final testNow = DateTime(2026, 10, 27, 9, 0);

const phone = Size(390, 844);
const tablet = Size(1194, 834);

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A controller on a memory store, loaded (boards too), Turkish UI.
Future<AppController> makeApp(
  WidgetTester tester, {
  MemoryStore? store,
  AppSettings settings = const AppSettings(language: AppLanguage.tr, seeded: true, boardsSeeded: true),
}) async {
  final st = store ?? MemoryStore({'settings': jsonEncode(settings.toJson())});
  final c = AppController(store: st, clock: () => testNow, saveDelay: Duration.zero);
  await tester.runAsync(() async {
    await c.load();
    while (!c.boards.loaded) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  return c;
}

/// The whole app (HomeShell) at [size].
Future<AppController> bootApp(
  WidgetTester tester, {
  Size size = phone,
  MemoryStore? store,
  AppSettings settings = const AppSettings(language: AppLanguage.tr, seeded: true, boardsSeeded: true),
}) async {
  setSize(tester, size);
  final c = await makeApp(tester, store: store, settings: settings);
  await tester.pumpWidget(PamnotApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

/// Just a board page, as the root route.
Future<void> pumpBoardPage(
  WidgetTester tester,
  AppController c,
  String boardId, {
  Size size = phone,
  Locale locale = const Locale('tr'),
}) async {
  setSize(tester, size);
  await tester.pumpWidget(AppScope(
    controller: c,
    child: MaterialApp(
      theme: PamnotTheme.light(),
      locale: locale,
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BoardPage(boardId: boardId),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Ends a test without pending timers.
Future<void> shutdown(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
  await tester.runAsync(c.flush);
  c.dispose();
}

/// A task board with three default columns and the given cards per column.
Future<String> makeBoard(
  WidgetTester tester,
  AppController c, {
  String title = 'Proje',
  List<List<String>> cards = const [],
}) async {
  late String id;
  await tester.runAsync(() async {
    id = await c.boards.createBoard(title: title, colorIndex: 3, template: BoardTemplate.tasks, strings: S.tr);
    if (cards.isEmpty) return;
    final b = (await c.boards.open(id))!;
    final cols = b.editor.columns;
    for (var i = 0; i < cards.length; i++) {
      for (final t in cards[i]) {
        b.editor.addCard(columnId: cols[i].id, title: t);
      }
    }
    await c.boards.release(b);
  });
  await settleReal(tester);
  return id;
}

/// Lets real timers started inside runAsync fire (the list's 300 ms
/// notify), so they do not hold back the fake ones that follow.
Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 350)));
  await tester.pump();
}

/// Card titles of every column, in order.
List<List<String>> titles(OpenBoard b) => [
      for (final col in b.editor.columns) [for (final card in b.editor.cardsIn(col.id)) card.title],
    ];

/// Records what the board page and sheet tell the connection.
class FakeConnection implements BoardConnection {
  FakeConnection({SyncState state = const SyncState(SyncStatus.synced), List<Peer> peers = const []})
      : stateN = ValueNotifier(state),
        peersN = ValueNotifier(peers);

  final ValueNotifier<SyncState> stateN;
  final ValueNotifier<List<Peer>> peersN;
  final cursorsN = ValueNotifier<Map<String, PeerCursor>>(const {});
  final activity = <(String, String?)>[];
  int retries = 0;
  int kicks = 0;
  bool closed = false;

  @override
  ValueListenable<SyncState> get state => stateN;

  @override
  ValueListenable<List<Peer>> get peers => peersN;

  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => cursorsN;

  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) {}

  @override
  void setActivity({required String view, String? editing}) => activity.add((view, editing));

  @override
  void kick() => kicks++;

  @override
  Future<void> retry() async => retries++;

  @override
  Future<void> close() async => closed = true;
}

const testAccount = BoardAccount(host: 'abc.supabase.co', userId: 'me-1');

/// Turns [id] into a shared board of [testAccount] whose connection is a
/// [FakeConnection] (the latest one is returned by [latest]).
Future<FakeConnection Function()> shareBoard(
  WidgetTester tester,
  AppController c,
  String id, {
  List<Peer> peers = const [],
  SyncState state = const SyncState(SyncStatus.synced),
}) async {
  FakeConnection? last;
  c.boards.currentAccount = () => testAccount;
  c.boards.connectionFactory = (board, controller) => last = FakeConnection(state: state, peers: peers);
  await tester.runAsync(() => c.boards.beginUpload(id, testAccount));
  await settleReal(tester);
  return () => last!;
}
