import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/board_editor.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/boards_repository.dart';
import 'package:pamnot/boards/canvas/board_canvas_view.dart';
import 'package:pamnot/boards/canvas/session.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/hlc.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';
import 'package:pamnot/theme/pamnot_theme.dart';

int _ids = 0;
String nextId() => 'id${(_ids++).toString().padLeft(6, '0')}';

/// A board with three columns (the last one done) at lane origin (0, 0).
OpenBoard makeBoard({List<(String, int, bool)> columns = const [('A', 1, false), ('B', 2, false), ('C', 3, true)]}) {
  final clock = HlcClock(node: '0000000000000001', wallMs: () => 1000);
  final e = BoardEditor(
    doc: BoardDoc(id: nextId()),
    clock: clock,
    newId: nextId,
  );
  e.initialize(title: 'Pano', colorIndex: 3, columns: columns);
  return OpenBoard(e, LocalConnection());
}

class CanvasHarness {
  CanvasHarness(this.tester, this.board);

  final WidgetTester tester;
  final OpenBoard board;
  final opened = <String>[];
  final views = <BoardViewState>[];
  var stylusSeen = 0;

  BoardEditor get editor => board.editor;

  BoardSession get session => debugCanvasSession(tester.state(find.byType(BoardCanvasView)));
}

/// Pumps the canvas full screen. The default view puts canvas (x, y) at
/// screen (x, y) at 100 % on a 1200 × 800 window (a wide layout).
Future<CanvasHarness> pumpCanvas(
  WidgetTester tester,
  OpenBoard board, {
  Size size = const Size(1200, 800),
  BoardViewState? view,
  bool useDefaultView = true,
  bool stylusOnly = false,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = CanvasHarness(tester, board);
  final app = AppController(store: MemoryStore(), saveDelay: Duration.zero);
  addTearDown(app.dispose);
  final vs =
      view ??
      (useDefaultView
          ? BoardViewState(view: 'canvas', offset: Offset(size.width / 2, size.height / 2), scale: 1, fitted: true)
          : null);
  await tester.pumpWidget(
    AppScope(
      controller: app,
      child: MaterialApp(
        theme: PamnotTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: BoardCanvasView(
                board: board,
                viewState: vs,
                onViewChanged: h.views.add,
                onOpenCard: h.opened.add,
                stylusOnly: stylusOnly,
                onStylusDetected: () => h.stylusSeen++,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}

/// Unmounts the canvas so timers and tickers are cleaned up.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
