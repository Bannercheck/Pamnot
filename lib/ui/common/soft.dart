import 'package:flutter/material.dart';

import '../../theme/pamnot_theme.dart';

/// A rounded card with a gentle shadow; the basic building block of Pamnot.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.onLongPress,
    this.radius = 24,
    this.shadow = true,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow ? softShadow(context) : null,
      ),
      child: Material(
        color: color ?? c.surfaceContainerLowest,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.icon});

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: t.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(title, style: t.textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.text, this.action});

  final String emoji;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Text(emoji, style: const TextStyle(fontSize: 38)),
            ),
            const SizedBox(height: 18),
            Text(
              text,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class PastelDot extends StatelessWidget {
  const PastelDot(this.colorIndex, {super.key, this.size = 10});

  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: pastelAt(colorIndex).accent, shape: BoxShape.circle),
      );
}

/// A row of pastel swatches.
class PastelPicker extends StatelessWidget {
  const PastelPicker({super.key, required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < pastels.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: pastels[i].name,
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: pastels[i].paper(b),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == selected ? pastels[i].accent : pastels[i].accent.withValues(alpha: 0.35),
                    width: i == selected ? 3 : 1.5,
                  ),
                ),
                child: i == selected ? Icon(Icons.check_rounded, size: 18, color: pastels[i].accent) : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// A soft rounded chip with an icon, used for dates, repeats and priorities.
class SoftChip extends StatelessWidget {
  const SoftChip({super.key, required this.label, this.icon, this.color, this.onTap, this.selected = false});

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final bg = selected ? c.primaryContainer : (color ?? c.surfaceContainer);
    final fg = selected ? c.onPrimaryContainer : c.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: t.textTheme.labelLarge?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Max content width so tablet and desktop layouts stay airy.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 820});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// Takes the messenger rather than a context so it also works right after
/// the sheet or page that triggered it has been popped.
void showUndoSnack(ScaffoldMessengerState m, String text, VoidCallback onUndo, String undoLabel) {
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    duration: const Duration(seconds: 4),
  ));
}
