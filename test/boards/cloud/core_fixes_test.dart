import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/data/store.dart';

/// Core changes made on the cloud branch: overlapping refreshConnections and
/// idempotent LocalConnection.close.
class _Counted extends LocalConnection {
  int closes = 0;

  @override
  Future<void> close() async {
    closes++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await super.close();
  }
}

void main() {
  const acc = BoardAccount(host: 'h', userId: 'u');

  test('LocalConnection.close is safe to call twice', () async {
    final c = LocalConnection();
    await c.close();
    await c.close();
  });

  test('overlapping refreshConnections close each connection once and still rerun', () async {
    final boards = BoardsController(store: MemoryStore(), saveDelay: Duration.zero);
    await boards.load();
    final made = <_Counted>[];
    BoardAccount? current;
    boards.currentAccount = () => current;
    boards.connectionFactory = (b, c) {
      made.add(_Counted());
      return made.last;
    };
    await boards.addJoined(boardId: 'b1', title: 'B', account: acc);
    final open = (await boards.open('b1'))!;
    expect(open.connection, isA<LocalConnection>());

    current = acc;
    await Future.wait([boards.refreshConnections(), boards.refreshConnections(), boards.refreshConnections()]);
    // One pass for the first call and one rerun for the overlapping ones.
    expect(made.length, 2);
    expect(made.first.closes, 1);
    expect(identical(open.connection, made.last), isTrue);

    await boards.release(open);
    expect(made.last.closes, 1);
    boards.dispose();
  });

  test('a board released during a refresh is skipped, not reconnected', () async {
    final boards = BoardsController(store: MemoryStore(), saveDelay: Duration.zero);
    await boards.load();
    var made = 0;
    boards.currentAccount = () => acc;
    boards.connectionFactory = (b, c) {
      made++;
      return _Counted();
    };
    await boards.addJoined(boardId: 'b1', title: 'B', account: acc);
    await boards.addJoined(boardId: 'b2', title: 'C', account: acc);
    final one = (await boards.open('b1'))!;
    final two = (await boards.open('b2'))!;
    expect(made, 2);
    final refresh = boards.refreshConnections();
    await boards.release(two);
    await refresh;
    expect(boards.openBoard('b2'), isNull);
    expect(made, 3, reason: 'only b1 got a new connection');
    await boards.release(one);
    boards.dispose();
  });
}
