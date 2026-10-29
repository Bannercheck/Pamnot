import 'package:flutter/material.dart';

import '../../../l10n/strings.dart';
import '../../../theme/pamnot_theme.dart';
import 'ink_controller.dart';

/// Floating pill with the pen tools, colours, sizes and undo/redo.
class InkToolbar extends StatelessWidget {
  const InkToolbar({super.key, required this.controller, this.onConvert, this.converting = false});

  final InkController controller;

  /// Null hides the "convert to text" action (unsupported platform).
  final VoidCallback? onConvert;
  final bool converting;

  static const _widths = [2.5, 4.0, 7.0];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = Theme.of(context);
    final c = t.colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tool = controller.tool;
        final colors = tool == CanvasTool.highlighter ? highlighterColors : inkColors;
        final current = controller.activeColor;
        Widget toolBtn(CanvasTool v, IconData icon, String tip) => _ToolButton(
              icon: icon,
              tooltip: tip,
              selected: tool == v,
              onTap: () => controller.tool = v,
            );
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(26),
            boxShadow: softShadow(context, strength: 1.6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                toolBtn(CanvasTool.pen, Icons.edit_rounded, s.pen),
                toolBtn(CanvasTool.highlighter, Icons.brush_rounded, s.highlighter),
                toolBtn(CanvasTool.eraser, Icons.cleaning_services_rounded, s.eraser),
                toolBtn(CanvasTool.hand, Icons.pan_tool_alt_rounded, s.hand),
                _divider(c),
                for (final col in colors)
                  _ColorDot(
                    color: col,
                    selected: col.toARGB32() == current.toARGB32() &&
                        (tool == CanvasTool.pen || tool == CanvasTool.highlighter),
                    onTap: () => controller.setColor(col),
                  ),
                if (tool == CanvasTool.pen) ...[
                  _divider(c),
                  for (final w in _widths)
                    _WidthDot(
                      width: w,
                      color: controller.penColor,
                      selected: controller.penWidth == w,
                      onTap: () => controller.penWidth = w,
                    ),
                ],
                _divider(c),
                IconButton(
                  tooltip: s.undo,
                  onPressed: controller.canUndo ? controller.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: s.redo,
                  onPressed: controller.canRedo ? controller.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                if (onConvert != null) ...[
                  _divider(c),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: FilledButton.tonalIcon(
                      onPressed: converting || controller.strokes.isEmpty ? null : onConvert,
                      icon: converting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.text_fields_rounded, size: 18),
                      label: Text(s.convertToText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _divider(ColorScheme c) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: c.outlineVariant,
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.selected, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
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
          child: Icon(icon, size: 22, color: selected ? c.onPrimaryContainer : c.onSurfaceVariant),
        ),
      ),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: selected ? 30 : 24,
          height: selected ? 30 : 24,
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
