import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/board_editor.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/hlc.dart';

/// BoardEditor.undoToken (a core addition for undo snacks).
void main() {
  var n = 0;
  String id() => 'id${n++}';

  BoardEditor editor() {
    final e = BoardEditor(doc: BoardDoc(id: id()), clock: HlcClock(node: '0000000000000001', wallMs: () => 1000), newId: id);
    e.initialize(title: 'P', colorIndex: 0, columns: const [('A', 1, false), ('B', 2, false)]);
    return e;
  }

  test('identifies the newest undo step and follows undo and redo', () {
    final e = editor();
    expect(e.undoToken, isNull, reason: 'creation is not undoable');
    final card = e.addCard(columnId: e.columns.first.id, title: 'k');
    final afterAdd = e.undoToken;
    expect(afterAdd, isNotNull);

    e.moveCard(card, columnId: e.columns[1].id, index: 0);
    final afterMove = e.undoToken;
    expect(identical(afterMove, afterAdd), isFalse);

    e.undo();
    expect(identical(e.undoToken, afterAdd), isTrue);
    e.redo();
    expect(e.undoToken, isNotNull);
    expect(identical(e.undoToken, afterAdd), isFalse);
  });

  test('an edit that writes nothing leaves the token alone', () {
    final e = editor();
    final card = e.addCard(columnId: e.columns.first.id, title: 'k');
    final t = e.undoToken;
    e.updateCard(card, {'title': 'k'});
    e.moveCard(card, columnId: e.columns.first.id, index: 0);
    expect(identical(e.undoToken, t), isTrue);
  });
}
