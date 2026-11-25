import 'package:flutter/material.dart';

import 'glass.dart';

/// Height of the empty space at the end of a shell page's scroll view.
///
/// The shell's body runs under the floating [GlassNavBar], whose height
/// (with the home indicator) arrives as `MediaQuery.padding.bottom`; scroll
/// views do not consume it. The spacer therefore grows with the bar, so the
/// last row clears the page's floating action button (which floats above
/// the bar) as it did before the bar floated.
double scrollEndSpace(BuildContext context) => 120 + MediaQuery.paddingOf(context).bottom;

/// One tab of [GlassNavBar]: outlined [icon], filled [selectedIcon], [label].
class GlassNavItem {
  const GlassNavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The phone's bottom menu: four tabs on a floating glass bar with a round
/// action button in the middle that rises above it.
///
/// The bar is 64 pt high, floats 12 pt from the sides and 8 pt above the
/// bottom safe area; the centre button is a 60 pt [ColorScheme.primary] disc
/// 14 pt above the bar. The selected tab shows its filled icon and a
/// `primary` label on an opaque [indicatorColor] (so its contrast does not
/// depend on what scrolls behind the glass); the others are
/// outlined in `onSurfaceVariant`. Labels grow at most to 1.3 with the
/// system text size, like the iOS tab bar.
///
/// Keys: `nav-0` … `nav-3` for the tabs, `nav-center` for the button.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.centerIcon,
    required this.centerLabel,
    required this.onCenter,
  }) : assert(items.length == 4);

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final IconData centerIcon;
  final String centerLabel;
  final VoidCallback onCenter;

  static const double barHeight = 64;
  static const double centerSize = 60;
  static const double centerRise = 14;

  /// Behind the selected tab: `surfaceContainerLowest` tinted with 10 %
  /// `primary`, opaque. `primaryContainer` would leave the `primary` label at
  /// 4.39:1 in the light theme; this keeps it at 4.66 (dark 7.6).
  static Color indicatorColor(ColorScheme c) =>
      Color.alphaBlend(c.primary.withValues(alpha: 0.10), c.surfaceContainerLowest);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    Widget tab(int i) => Expanded(
          child: _Tab(
            key: Key('nav-$i'),
            item: items[i],
            selected: i == selectedIndex,
            onTap: () => onSelected(i),
          ),
        );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 8),
        child: SizedBox(
          height: barHeight + centerRise,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: barHeight,
                child: GlassPanel(
                  radius: 28,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          tab(0),
                          tab(1),
                          const SizedBox(width: centerSize + 12),
                          tab(2),
                          tab(3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: _CenterButton(icon: centerIcon, label: centerLabel, onTap: onCenter),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({super.key, required this.item, required this.selected, required this.onTap});

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final fg = selected ? c.primary : c.onSurfaceVariant;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? item.selectedIcon : item.icon, color: fg, size: 24),
          const SizedBox(height: 1),
          Text(
            item.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: selected
              ? DecoratedBox(
                  decoration: BoxDecoration(color: GlassNavBar.indicatorColor(c), borderRadius: BorderRadius.circular(20)),
                  child: SizedBox.expand(child: content),
                )
              : SizedBox.expand(child: content),
        ),
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        key: const Key('nav-center'),
        container: true,
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: GlassNavBar.centerSize,
          child: Material(
            color: c.primary,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: c.shadow.withValues(alpha: 0.5),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, color: c.onPrimary, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
