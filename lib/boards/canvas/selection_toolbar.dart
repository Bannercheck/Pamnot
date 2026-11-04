import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import '../model/board_item.dart';
import 'canvas_strings.dart';
import 'session.dart';

/// Colours offered for stickies and cards.
const selectionColors = [5, 1, 6, 2, 4];

/// What can be done with the current selection.
class SelectionCaps {
  SelectionCaps(BoardSession session) {
    for (final id in session.selection.value) {
      switch (session.scene.byId(id)?.kind) {
        case ItemKind.sticky:
          stickies++;
        case ItemKind.ink:
          inks++;
        case ItemKind.card:
          cards++;
        default:
          break;
      }
    }
    toCard = stickies == 1 && inks == 0 && cards == 0 && session.firstOpenColumn != null;
  }

  int stickies = 0, inks = 0, cards = 0;
  late final bool toCard;

  bool get colors => stickies + cards > 0;
  bool get free => stickies + inks > 0;
  bool get any => stickies + inks + cards > 0;
}

/// The menu for a right-click (or a ctrl-click on macOS) on an item.
Future<void> showSelectionMenu(BuildContext context, BoardSession session, Offset globalPosition) async {
  final s = S.of(context);
  final caps = SelectionCaps(session);
  if (!caps.any || session.readOnly) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(globalPosition & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (caps.toCard) PopupMenuItem(value: 'card', child: Text(s.canvasToCard)),
      if (caps.free) ...[
        PopupMenuItem(value: 'dup', child: Text(s.canvasDuplicate)),
        PopupMenuItem(value: 'front', child: Text(s.canvasBringToFront)),
        PopupMenuItem(value: 'back', child: Text(s.canvasSendToBack)),
      ],
      PopupMenuItem(value: 'delete', child: Text(s.delete)),
    ],
  );
  _run(session, v);
}

void _run(BoardSession session, String? v) {
  switch (v) {
    case 'card':
      final id = session.selection.value.first;
      session.stickyToCard(id);
    case 'dup':
      session.duplicateSelection();
    case 'front':
      session.bringToFront();
    case 'back':
      session.sendToBack();
    case 'delete':
      session.deleteSelection();
  }
}

/// The mini-toolbar 12 dp above the selection: colours, Karta dönüştür,
/// Kopyasını oluştur, ⋯ (Öne getir / Arkaya gönder), Sil. It follows pans
/// and zooms by relayout only, and hides while a gesture is in progress
/// (it rebuilds at the start and end of a gesture, never during one).
class SelectionToolbar extends StatefulWidget {
  const SelectionToolbar({super.key, required this.session});

  final BoardSession session;

  @override
  State<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<SelectionToolbar> {
  bool _visible = false;
  Set<String> _shown = const {};

  BoardSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    for (final l in _listenables) {
      l.addListener(_sync);
    }
    _sync();
  }

  List<Listenable> get _listenables => [_session.selection, _session.interacting, _session.editing];

  @override
  void dispose() {
    for (final l in _listenables) {
      l.removeListener(_sync);
    }
    super.dispose();
  }

  void _sync() {
    final busy = _session.interacting.value || _session.isEditing || _session.readOnly;
    final sel = _session.selection.value;
    final visible = !busy && sel.isNotEmpty;
    if (busy) {
      if (_visible) setState(() => _visible = false);
      return;
    }
    if (visible != _visible || !setEquals(sel, _shown)) {
      setState(() {
        _visible = visible;
        _shown = sel;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    final caps = SelectionCaps(_session);
    if (!caps.any) return const SizedBox.shrink();
    return CustomSingleChildLayout(
      delegate: _AboveSelection(_session),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: c.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            boxShadow: softShadow(context, strength: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caps.colors) ...[
                for (final i in selectionColors)
                  Semantics(
                    button: true,
                    label: '${s.color} ${pastels[i].name}',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _session.setColor(i),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Color.lerp(pastels[i].paper(t.brightness), pastels[i].accent, 0.4),
                            shape: BoxShape.circle,
                            border: Border.all(color: pastels[i].accent, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: c.outlineVariant,
                ),
              ],
              if (caps.toCard)
                IconButton(
                  tooltip: s.canvasToCard,
                  icon: const Icon(Icons.post_add_rounded),
                  onPressed: () => _session.stickyToCard(_session.selection.value.first),
                ),
              if (caps.free) ...[
                IconButton(
                  tooltip: s.canvasWithKey(s.canvasDuplicate, '⌘D'),
                  icon: const Icon(Icons.copy_all_rounded),
                  onPressed: _session.duplicateSelection,
                ),
                PopupMenuButton<String>(
                  tooltip: s.canvasMore,
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (v) => _run(_session, v),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'front', child: Text(s.canvasBringToFront)),
                    PopupMenuItem(value: 'back', child: Text(s.canvasSendToBack)),
                  ],
                ),
              ],
              IconButton(
                tooltip: s.delete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _session.deleteSelection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboveSelection extends SingleChildLayoutDelegate {
  _AboveSelection(this.session)
    : super(relayout: Listenable.merge([session.viewport, session.scene, session.selection]));

  final BoardSession session;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    Rect? r;
    for (final id in session.selection.value) {
      final si = session.scene.byId(id);
      if (si == null) continue;
      final b = session.viewport.rectToScreen(si.bounds);
      r = r == null ? b : r.expandToInclude(b);
    }
    if (r == null) return const Offset(-10000, -10000);
    final maxX = size.width - child.width - 8;
    final x = (r.center.dx - child.width / 2).clamp(8.0, maxX < 8 ? 8.0 : maxX);
    var y = r.top - 12 - child.height;
    if (y < 8) y = r.bottom + 12;
    final maxY = size.height - child.height - 8;
    return Offset(x, y.clamp(8.0, maxY < 8 ? 8.0 : maxY));
  }

  @override
  bool shouldRelayout(_AboveSelection old) => old.session != session;
}
