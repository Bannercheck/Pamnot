import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/system_accessibility.dart';

/// Whether glass surfaces are drawn: true while both iOS "Reduce
/// Transparency" ([SystemAccessibility.reduceTransparency]) and "Increase
/// Contrast" ([MediaQueryData.highContrast]) are off.
///
/// Reads the current values; [GlassPanel] rebuilds itself when Reduce
/// Transparency changes, and the [MediaQuery] lookup registers a dependency.
bool glassEnabledOf(BuildContext context) =>
    !SystemAccessibility.reduceTransparency.value && !MediaQuery.highContrastOf(context);

/// Every [GlassPanel] below this widget shares one backdrop read
/// ([BackdropGroup]), so several panels on one screen cost a single read of
/// the content behind them.
class GlassScope extends StatelessWidget {
  const GlassScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(child: child);
}

/// A frosted glass surface: the content behind it is blurred (σ = [sigma]),
/// then a translucent [fill], a 1 px [border] and a top [highlight] that fades
/// out over the upper 40 % are painted under [child].
///
/// With Reduce Transparency or Increase Contrast on it paints a plain surface
/// instead (light: `surfaceContainerLowest`, dark: `surfaceContainerHigh`,
/// border `outlineVariant`). Cards are not glass; use this only for bars,
/// tabs, menus and the matrix boxes.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.blurred = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// false skips the blur and paints only the translucent fill (the single
  /// low-quality switch for older devices).
  final bool blurred;

  static const double sigma = 20;

  /// Fill over the blurred backdrop. The design asked for white 62 % /
  /// 0x28252F 58 %; raised to 84 % / 90 % so onSurface and onSurfaceVariant
  /// keep 4.5:1 over the worst backdrop (primary, secondary) without the
  /// blur's help, measured on the painted surface: fill plus the full-strength
  /// [highlight] at the top edge (worst: light 4.86, dark 4.58).
  static Color fill(Brightness b) =>
      b == Brightness.dark ? const Color(0xE628252F) : const Color(0xD6FFFFFF);

  /// 1 px edge: white 55 % (light), white 14 % (dark).
  static Color border(Brightness b) =>
      b == Brightness.dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF);

  /// Top light: white 28 % (light), white 4 % (dark); transparent at 40 %.
  /// The design asked for 8 % in dark; halved because white over the dark
  /// fill lowers the text contrast (8 % needs a 95 % fill to keep 4.5:1).
  static Color highlight(Brightness b) =>
      b == Brightness.dark ? const Color(0x0AFFFFFF) : const Color(0x47FFFFFF);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SystemAccessibility.reduceTransparency,
        builder: (context, _) => glassEnabledOf(context) ? _glass(context) : _plain(context),
      );

  /// The plain surface drawn while glass is off. Under Increase Contrast the
  /// edge is `outline` (≥ 3:1 on the surface; `outlineVariant` is about 1.2:1).
  static BoxDecoration plainDecoration(BuildContext context, double radius) {
    final c = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: c.brightness == Brightness.dark ? c.surfaceContainerHigh : c.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: MediaQuery.highContrastOf(context) ? c.outline : c.outlineVariant),
    );
  }

  /// The glass fill and edge, without the blur.
  static BoxDecoration glassDecoration(Brightness b, double radius) => BoxDecoration(
        color: fill(b),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border(b)),
      );

  /// The top light over [glassDecoration].
  static BoxDecoration highlightDecoration(Brightness b, double radius) => BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [highlight(b), highlight(b).withValues(alpha: 0)],
          stops: const [0, 0.4],
        ),
      );

  Widget _plain(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: plainDecoration(context, radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  Widget _glass(BuildContext context) {
    final b = Theme.of(context).colorScheme.brightness;
    final shape = BorderRadius.circular(radius);
    final Widget surface = DecoratedBox(
      decoration: glassDecoration(b, radius),
      child: DecoratedBox(
        decoration: highlightDecoration(b, radius),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (!blurred) return ClipRRect(borderRadius: shape, child: surface);

    final filter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropGroup.of(context) != null
          ? BackdropFilter.grouped(filter: filter, child: surface)
          : BackdropFilter(filter: filter, child: surface),
    );
  }
}

/// [GlassPanel] around a [sliver], for a panel that is a section of a
/// scrolling page and builds its rows lazily (the Matrix's single column).
///
/// The same fill, edge and top light, and the same plain surface while glass
/// is off; there is no blur, because a sliver cannot carry a
/// [BackdropFilter] (the fill alone keeps the text contrast, see
/// [GlassPanel.fill]). Nothing is clipped: the rows keep clear of the corners.
class SliverGlassPanel extends StatelessWidget {
  const SliverGlassPanel({super.key, required this.sliver, this.radius = 24});

  final Widget sliver;
  final double radius;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SystemAccessibility.reduceTransparency,
        builder: (context, _) {
          if (!glassEnabledOf(context)) {
            return DecoratedSliver(decoration: GlassPanel.plainDecoration(context, radius), sliver: sliver);
          }
          final b = Theme.of(context).colorScheme.brightness;
          return DecoratedSliver(
            decoration: GlassPanel.glassDecoration(b, radius),
            sliver: DecoratedSliver(decoration: GlassPanel.highlightDecoration(b, radius), sliver: sliver),
          );
        },
      );
}
