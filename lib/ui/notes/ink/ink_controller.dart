import 'package:flutter/material.dart';

import '../../../models/ink.dart';
import '../../../theme/pamnot_theme.dart';

enum CanvasTool { pen, highlighter, eraser, hand }

/// Strokes of one page plus the current tool, with undo/redo.
///
/// Every edit produces a new stroke list, so painters can tell an append
/// (draw one more stroke onto the cached picture) from anything else.
class InkController extends ChangeNotifier {
  InkController(List<InkStroke> initial) : _strokes = List.unmodifiable(initial);

  List<InkStroke> _strokes;
  final List<List<InkStroke>> _undo = [];
  final List<List<InkStroke>> _redo = [];
  static const _historyLimit = 80;

  CanvasTool _tool = CanvasTool.pen;
  Color _penColor = inkColors.first;
  Color _highlighterColor = highlighterColors.first;
  double _penWidth = 4;

  /// Bumped on every stroke change; the note editor saves when it moves.
  int revision = 0;

  List<InkStroke> get strokes => _strokes;
  CanvasTool get tool => _tool;
  Color get penColor => _penColor;
  Color get highlighterColor => _highlighterColor;
  double get penWidth => _penWidth;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Color get activeColor => _tool == CanvasTool.highlighter ? _highlighterColor : _penColor;

  set tool(CanvasTool t) {
    if (t == _tool) return;
    _tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    if (_tool == CanvasTool.highlighter) {
      _highlighterColor = c;
    } else {
      _penColor = c;
      if (_tool != CanvasTool.pen) _tool = CanvasTool.pen;
    }
    notifyListeners();
  }

  set penWidth(double w) {
    _penWidth = w;
    if (_tool != CanvasTool.pen) _tool = CanvasTool.pen;
    notifyListeners();
  }

  void _commit(List<InkStroke> next, {bool record = true}) {
    if (record) {
      _undo.add(_strokes);
      if (_undo.length > _historyLimit) _undo.removeAt(0);
      _redo.clear();
    }
    _strokes = List.unmodifiable(next);
    revision++;
    notifyListeners();
  }

  void add(InkStroke s) => _commit([..._strokes, s]);

  // An erase gesture is one undo step however many strokes it removes.
  List<InkStroke>? _eraseStart;

  void beginErase() => _eraseStart = _strokes;

  void eraseAt(Offset p, double radius) {
    final keep = <InkStroke>[];
    var removed = false;
    for (final s in _strokes) {
      if (s.hitTest(p, radius)) {
        removed = true;
      } else {
        keep.add(s);
      }
    }
    if (removed) _commit(keep, record: false);
  }

  void endErase() {
    final start = _eraseStart;
    _eraseStart = null;
    if (start != null && !identical(start, _strokes)) {
      _undo.add(start);
      if (_undo.length > _historyLimit) _undo.removeAt(0);
      _redo.clear();
      notifyListeners();
    }
  }

  void clear() {
    if (_strokes.isNotEmpty) _commit(const []);
  }

  /// Removes [remove] in one undoable step (after converting them to text).
  void removeStrokes(Set<InkStroke> remove) =>
      _commit([for (final s in _strokes) if (!remove.contains(s)) s]);

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_strokes);
    _commit(_undo.removeLast(), record: false);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_strokes);
    _commit(_redo.removeLast(), record: false);
  }
}
