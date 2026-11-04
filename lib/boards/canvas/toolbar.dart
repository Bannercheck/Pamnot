import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/pamnot_theme.dart';
import 'canvas_strings.dart';
import 'session.dart';

/// The soft floating pill every canvas toolbar sits in.
class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.padding = const EdgeInsets.all(4)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(26),
        boxShadow: softShadow(context, strength: 1.4),
      ),
      child: child,
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? c.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 22,
              color: !enabled
                  ? c.onSurfaceVariant.withValues(alpha: 0.38)
                  : selected
                  ? c.onPrimaryContainer
                  : c.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outlineVariant;
    return vertical
        ? Container(width: 26, height: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: c)
        : Container(width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 6), color: c);
  }
}

IconData toolIcon(BoardTool t) => switch (t) {
  BoardTool.select => Icons.near_me_outlined,
  BoardTool.pen => Icons.edit_rounded,
  BoardTool.highlighter => Icons.brush_rounded,
  BoardTool.eraser => Icons.cleaning_services_rounded,
};

String toolLabel(S s, BoardTool t) => switch (t) {
  BoardTool.select => s.canvasWithKey(s.canvasSelect, 'V'),
  BoardTool.pen => s.canvasWithKey(s.pen, 'P'),
  BoardTool.highlighter => s.canvasWithKey(s.highlighter, 'F'),
  BoardTool.eraser => s.canvasWithKey(s.eraser, 'E'),
};

/// Undo / redo buttons that follow the editor's history.
class _History extends StatelessWidget {
  const _History({required this.session, this.redo = true});

  final BoardSession session;
  final bool redo;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: session.editor,
      builder: (context, _) {
        final e = session.editor;
        final undoBtn = _ToolButton(
          icon: Icons.undo_rounded,
          tooltip: s.undo,
          onTap: e.canUndo && !e.readOnly ? session.undo : null,
        );
        if (!redo) return undoBtn;
        return Flex(
          direction: Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          children: [
            undoBtn,
            _ToolButton(
              icon: Icons.redo_rounded,
              tooltip: s.redo,
              onTap: e.canRedo && !e.readOnly ? session.redo : null,
            ),
          ],
        );
      },
    );
  }
}

/// Wide screens: a vertical pill at the left edge, centred —
/// Seç, Not, Kart | Kalem, Fosforlu, Silgi | Geri al, Yinele — with ink
/// options flying out to its right while an ink tool is on.
class WideToolbar extends StatelessWidget {
  const WideToolbar({super.key, required this.session});

  final BoardSession session;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ro = session.readOnly;
    return ListenableBuilder(
      // Kart needs a column to add to.
      listenable: Listenable.merge([session.tool, session.columnCount]),
      builder: (context, _) {
        final tool = session.tool.value;
        Widget toolBtn(BoardTool t) => _ToolButton(
          icon: toolIcon(t),
          tooltip: toolLabel(s, t),
          selected: tool == t,
          onTap: ro && t != BoardTool.select ? null : () => session.setTool(t),
        );
        final hasColumns = session.columnCount.value > 0;
        final pill = _Pill(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolBtn(BoardTool.select),
              _ToolButton(
                icon: Icons.sticky_note_2_outlined,
                tooltip: s.canvasWithKey(s.canvasStickyNote, 'N'),
                onTap: ro ? null : () => session.addStickyAtCenter(),
              ),
              _ToolButton(
                icon: Icons.view_agenda_outlined,
                tooltip: s.canvasWithKey(s.canvasCard, 'K'),
                onTap: ro || !hasColumns ? null : session.addCard,
              ),
              const _Divider(vertical: true),
              toolBtn(BoardTool.pen),
              toolBtn(BoardTool.highlighter),
              toolBtn(BoardTool.eraser),
              const _Divider(vertical: true),
              _History(session: session),
            ],
          ),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill,
            if (tool.inks && !ro) ...[
              const SizedBox(width: 10),
              _Pill(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: InkOptions(session: session, axis: Axis.vertical),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Phones: a bottom pill [Seç][Not][Kart][Kalem][↶][⋯]; the ⋯ menu holds
/// Yinele, Ekrana sığdır, Fosforlu and Silgi. While an ink tool is on, a
/// second row above shows colours, widths, Fosforlu and Silgi.
class PhoneToolbar extends StatelessWidget {
  const PhoneToolbar({super.key, required this.session});

  final BoardSession session;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ro = session.readOnly;
    return ListenableBuilder(
      listenable: Listenable.merge([session.tool, session.columnCount]),
      builder: (context, _) {
        final tool = session.tool.value;
        final hasColumns = session.columnCount.value > 0;
        final inking = tool.inks || tool.erases;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (inking && !ro) ...[
              _Pill(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // Tools first: on a narrow phone the colours scroll, the
                  // tools never do.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToolButton(
                        icon: toolIcon(BoardTool.highlighter),
                        tooltip: s.highlighter,
                        selected: tool == BoardTool.highlighter,
                        onTap: () => session.setTool(BoardTool.highlighter),
                      ),
                      _ToolButton(
                        icon: toolIcon(BoardTool.eraser),
                        tooltip: s.eraser,
                        selected: tool == BoardTool.eraser,
                        onTap: () => session.setTool(BoardTool.eraser),
                      ),
                      if (tool.inks) ...[
                        const _Divider(vertical: false),
                        InkOptions(session: session, axis: Axis.horizontal),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolButton(
                    icon: toolIcon(BoardTool.select),
                    tooltip: s.canvasSelect,
                    selected: tool == BoardTool.select,
                    onTap: () => session.setTool(BoardTool.select),
                  ),
                  _ToolButton(
                    icon: Icons.sticky_note_2_outlined,
                    tooltip: s.canvasNote,
                    onTap: ro ? null : () => session.addStickyAtCenter(),
                  ),
                  _ToolButton(
                    icon: Icons.view_agenda_outlined,
                    tooltip: s.canvasCard,
                    onTap: ro || !hasColumns ? null : session.addCard,
                  ),
                  _ToolButton(
                    icon: toolIcon(BoardTool.pen),
                    tooltip: s.pen,
                    selected: inking,
                    onTap: ro ? null : () => session.setTool(inking ? BoardTool.select : BoardTool.pen),
                  ),
                  _History(session: session, redo: false),
                  _MoreMenu(session: session),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.session});

  final BoardSession session;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ro = session.readOnly;
    return PopupMenuButton<String>(
      tooltip: s.canvasMore,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) => switch (v) {
        'redo' => session.redo(),
        'fit' => session.fitToScreen(),
        'highlighter' => session.setTool(BoardTool.highlighter),
        'eraser' => session.setTool(BoardTool.eraser),
        _ => null,
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'redo',
          enabled: session.editor.canRedo && !ro,
          child: ListTile(leading: const Icon(Icons.redo_rounded), title: Text(s.redo)),
        ),
        PopupMenuItem(
          value: 'fit',
          child: ListTile(leading: const Icon(Icons.fit_screen_rounded), title: Text(s.canvasFit)),
        ),
        if (!ro) ...[
          PopupMenuItem(
            value: 'highlighter',
            child: ListTile(leading: Icon(toolIcon(BoardTool.highlighter)), title: Text(s.highlighter)),
          ),
          PopupMenuItem(
            value: 'eraser',
            child: ListTile(leading: Icon(toolIcon(BoardTool.eraser)), title: Text(s.eraser)),
          ),
        ],
      ],
    );
  }
}

/// Colours (and pen widths) of the current ink tool.
class InkOptions extends StatelessWidget {
  const InkOptions({super.key, required this.session, required this.axis});

  final BoardSession session;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InkSettings>(
      valueListenable: session.ink,
      builder: (context, ink, _) {
        final hi = session.tool.value == BoardTool.highlighter;
        final colors = hi ? highlighterColors : inkColors;
        final current = hi ? ink.highlighterColor : ink.penColor;
        return Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final col in colors)
              _ColorDot(
                color: col,
                selected: col.toARGB32() == current,
                onTap: () => session.ink.value = hi
                    ? ink.copyWith(highlighterColor: col.toARGB32())
                    : ink.copyWith(penColor: col.toARGB32()),
              ),
            if (!hi) ...[
              _Divider(vertical: axis == Axis.vertical),
              for (final w in InkSettings.widths)
                _WidthDot(
                  width: w,
                  color: Color(ink.penColor),
                  selected: ink.penWidth == w,
                  onTap: () => session.ink.value = ink.copyWith(penWidth: w),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 36,
      height: 36,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: selected ? 28 : 22,
          height: selected ? 28 : 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.surfaceContainerLowest : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)] : null,
          ),
        ),
      ),
    ),
  );
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({required this.width, required this.color, required this.selected, required this.onTap});

  final double width;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Container(
          width: width * 2.2 + 2,
          height: width * 2.2 + 2,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Bottom-right zoom control: [−] [%] [+]; tapping the percentage fits the
/// board. Only the label rebuilds, and only when the number changes.
class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key, required this.session});

  final BoardSession session;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButton(icon: Icons.remove_rounded, tooltip: s.canvasZoomOut, onTap: () => session.zoomBy(1 / 1.25)),
          Tooltip(
            message: s.canvasWithKey(s.canvasFit, '⇧1'),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: session.fitToScreen,
              child: SizedBox(
                width: 56,
                height: 44,
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: session.viewport.zoomPercent,
                    builder: (context, p, _) => Text(
                      s.isTr ? '%$p' : '$p%',
                      style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ToolButton(icon: Icons.add_rounded, tooltip: s.canvasZoomIn, onTap: () => session.zoomBy(1.25)),
        ],
      ),
    );
  }
}
