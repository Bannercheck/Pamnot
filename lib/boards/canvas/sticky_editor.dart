import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../../ui/common/prediction_bar.dart';
import 'board_text.dart';
import 'canvas_strings.dart';
import 'item_painter.dart';
import 'session.dart';

/// Wide screens: the sticky's text edited in place. A screen-space field
/// (never inside a scale transform, so handles and the selection toolbar
/// keep their size) laid over the sticky at the canvas' own text style, so
/// nothing reflows when editing starts or ends. The scale is frozen while
/// editing (a pinch commits); panning moves the field by relayout only.
class InlineStickyEditor extends StatefulWidget {
  const InlineStickyEditor({super.key, required this.session, required this.id, required this.palette});

  final BoardSession session;
  final String id;
  final BoardPalette palette;

  @override
  State<InlineStickyEditor> createState() => _InlineStickyEditorState();
}

class _InlineStickyEditorState extends State<InlineStickyEditor> {
  late final TextEditingController _c;
  final _focus = FocusNode(debugLabel: 'Sticky editor');
  final _barKey = GlobalKey<State<PredictionBar>>();
  double _fit = StickyMetrics.maxFont.toDouble();
  bool _ended = false;
  double _insets = 0;

  BoardSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    final text = _session.scene.byId(widget.id)?.item.text ?? '';
    _c = TextEditingController(text: text)..selection = TextSelection.collapsed(offset: text.length);
    _fit = _fitFor(text);
    _c.addListener(_onText);
    _focus.addListener(_onFocus);
    _session.commitEdit = _commit;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_ended) _focus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    if (insets != _insets) {
      _insets = insets;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }
  }

  double _fitFor(String text) {
    final (f, tp) = fitStickyText(text, widget.palette.text);
    tp.dispose();
    return f;
  }

  String _lastText = '';

  void _onText() {
    if (_c.text == _lastText) return;
    _lastText = _c.text;
    final f = _fitFor(_c.text);
    if (f != _fit) setState(() => _fit = f);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  /// Keeps the sticky above the keyboard and the suggestion strip (pan
  /// only, never zoom).
  void _ensureVisible() {
    if (!mounted || _ended) return;
    final si = _session.scene.byId(widget.id);
    if (si == null) return;
    final vp = _session.viewport;
    final r = vp.rectToScreen(si.bounds);
    final bottom = vp.size.height - _insets - 56 - 24;
    if (r.bottom > bottom) vp.panBy(Offset(0, bottom - r.bottom));
  }

  void _commit() {
    if (_ended) return;
    _ended = true;
    if (identical(_session.commitEdit, _commit)) _session.commitEdit = null;
    _session.endEdit(widget.id, _c.text);
  }

  @override
  void dispose() {
    if (identical(_session.commitEdit, _commit)) _session.commitEdit = null;
    // The view is closing with the editor open: keep what was typed.
    if (!_ended) {
      _ended = true;
      _session.endEdit(widget.id, _c.text, refocus: false);
    }
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scale = _session.viewport.scale;
    final p = widget.palette;
    final size = _fit * scale;
    return Stack(
      children: [
        CustomSingleChildLayout(
          delegate: _OverSticky(_session, widget.id),
          child: MediaQuery.withNoTextScaling(
            child: Material(
              type: MaterialType.transparency,
              child: Focus(
                onKeyEvent: _onKey,
                canRequestFocus: false,
                skipTraversal: true,
                child: PredictionKeys(
                  barKey: _barKey,
                  child: TextField(
                    controller: _c,
                    focusNode: _focus,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: boardText(size, p.text),
                    strutStyle: boardStrut(size),
                    cursorColor: p.primary,
                    decoration: InputDecoration.collapsed(
                      hintText: s.canvasStickyHint,
                      hintStyle: boardText(size, p.muted),
                    ).copyWith(filled: false),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          child: PredictionBar(key: _barKey, fields: [PredictiveField(_c, _focus)]),
        ),
      ],
    );
  }
}

class _OverSticky extends SingleChildLayoutDelegate {
  _OverSticky(this.session, this.id) : super(relayout: session.viewport);

  final BoardSession session;
  final String id;

  Rect get _rect {
    final si = session.scene.byId(id);
    if (si == null) return Rect.zero;
    final inner = si.bounds.deflate(StickyMetrics.pad);
    return session.viewport.rectToScreen(inner);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final r = _rect;
    return BoxConstraints(minWidth: r.width, maxWidth: r.width, maxHeight: r.height.clamp(0, constraints.maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => _rect.topLeft;

  @override
  bool shouldRelayout(_OverSticky old) => old.session != session || old.id != id;
}

/// Phones: edits a sticky in a bottom sheet with word suggestions. The text
/// is returned however the sheet closes (button, swipe, tap outside, back).
Future<String?> showStickySheet(BuildContext context, {required String text, required int colorIndex}) async {
  var latest = text;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _StickySheet(initial: text, colorIndex: colorIndex, onChanged: (t) => latest = t),
  );
  return latest;
}

class _StickySheet extends StatefulWidget {
  const _StickySheet({required this.initial, required this.colorIndex, required this.onChanged});

  final String initial;
  final int colorIndex;
  final ValueChanged<String> onChanged;

  @override
  State<_StickySheet> createState() => _StickySheetState();
}

class _StickySheetState extends State<_StickySheet> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);
  final _f = FocusNode();
  final _barKey = GlobalKey<State<PredictionBar>>();

  @override
  void initState() {
    super.initState();
    _c.addListener(() => widget.onChanged(_c.text));
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final b = t.brightness;
    final paper = pastelAt(widget.colorIndex);
    final fill = b == Brightness.dark
        ? Color.lerp(paper.dark, paper.accent, 0.30)!
        : Color.lerp(paper.light, paper.accent, 0.40)!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: PredictionKeys(
              barKey: _barKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.canvasStickyNote, style: t.textTheme.titleLarge)),
                      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(s.done)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18)),
                    child: TextField(
                      controller: _c,
                      focusNode: _f,
                      autofocus: true,
                      minLines: 4,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                      decoration: InputDecoration.collapsed(hintText: s.canvasStickyHint).copyWith(filled: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          PredictionBar(key: _barKey, fields: [PredictiveField(_c, _f)]),
        ],
      ),
    );
  }
}
