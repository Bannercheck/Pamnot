import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../prediction/word_predictor.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';

/// A text field the [PredictionBar] can suggest words for.
class PredictiveField {
  PredictiveField(this.controller, this.focusNode);

  final TextEditingController controller;
  final FocusNode focusNode;
}

/// Word suggestions for whichever of [fields] has focus, in a soft strip
/// that sits right above the keyboard. Tap a word, or press Tab on a
/// hardware keyboard to take the first one.
class PredictionBar extends StatefulWidget {
  const PredictionBar({super.key, required this.fields});

  final List<PredictiveField> fields;

  @override
  State<PredictionBar> createState() => _PredictionBarState();
}

class _PredictionBarState extends State<PredictionBar> {
  List<String> _words = const [];
  PredictiveField? _active;

  /// Only the tail of the text matters for the next word; this keeps every
  /// keystroke cheap even in very long notes.
  static const _window = 240;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      f.focusNode.addListener(_refresh);
      f.controller.addListener(_refresh);
    }
  }

  @override
  void didUpdateWidget(PredictionBar old) {
    super.didUpdateWidget(old);
    for (final f in old.fields) {
      f.focusNode.removeListener(_refresh);
      f.controller.removeListener(_refresh);
    }
    for (final f in widget.fields) {
      f.focusNode.addListener(_refresh);
      f.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final f in widget.fields) {
      f.focusNode.removeListener(_refresh);
      f.controller.removeListener(_refresh);
    }
    super.dispose();
  }

  (String, int)? _before(PredictiveField f) {
    final v = f.controller.value;
    final sel = v.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final end = sel.baseOffset.clamp(0, v.text.length);
    final start = math.max(0, end - _window);
    return (v.text.substring(start, end), start);
  }

  void _refresh() {
    PredictiveField? active;
    for (final f in widget.fields) {
      if (f.focusNode.hasFocus) active = f;
    }
    final app = AppScope.of(context);
    var words = const <String>[];
    if (active != null) {
      final b = _before(active);
      if (b != null) words = app.suggest(b.$1);
    }
    if (active != _active || !_same(words, _words)) {
      setState(() {
        _active = active;
        _words = words;
      });
    }
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _accept(String word) {
    final f = _active;
    if (f == null) return;
    final b = _before(f);
    if (b == null) return;
    final (text, offset) = b;
    final ctx = WordContext.of(text);
    final v = f.controller.value;
    final cursor = offset + text.length;
    final start = offset + ctx.prefixStart;
    final needsSpace = ctx.prefix.isEmpty && start > 0 && !RegExp(r'\s').hasMatch(v.text[start - 1]);
    final after = cursor < v.text.length ? v.text[cursor] : '';
    final insert = '${needsSpace ? ' ' : ''}$word${after == ' ' ? '' : ' '}';
    final next = v.text.replaceRange(start, cursor, insert);
    final caret = start + insert.length + (after == ' ' ? 1 : 0);
    AppScope.of(context).acceptedSuggestion(text, word);
    f.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// Wrap a predictive field with this so Tab takes the first suggestion.
  KeyEventResult handleKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab && _words.isNotEmpty && _active != null) {
      _accept(_words.first);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context, {Slice.settings});
    final t = Theme.of(context);
    final c = t.colorScheme;
    final visible = _active != null && _words.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: c.surfaceContainerLow,
                border: Border(top: BorderSide(color: c.outlineVariant)),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _words.length; i++) ...[
                    if (i > 0) Container(width: 1, height: 22, color: c.outlineVariant),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _accept(_words[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                          child: Text(
                            _words[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleSmall?.copyWith(
                              color: i == 0 ? c.primary : c.onSurface,
                              fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Routes Tab presses inside [child] to the nearest [PredictionBar] via [barKey].
class PredictionKeys extends StatelessWidget {
  const PredictionKeys({super.key, required this.barKey, required this.child});

  final GlobalKey<State<PredictionBar>> barKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) {
          final s = barKey.currentState;
          return s is _PredictionBarState ? s.handleKey(node, e) : KeyEventResult.ignored;
        },
        child: child,
      );
}
