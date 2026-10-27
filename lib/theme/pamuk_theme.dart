import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Soft pastels for notes, tasks and reminders. Every colour has a light
/// "paper" tone and a deeper accent used for dots, icons and progress.
class Pastel {
  const Pastel(this.name, this.light, this.dark, this.accent);

  final String name;
  final Color light;
  final Color dark;
  final Color accent;

  Color paper(Brightness b) => b == Brightness.dark ? dark : light;
}

const pastels = <Pastel>[
  Pastel('cream', Color(0xFFFFFBF3), Color(0xFF2B2830), Color(0xFFD8B98A)),
  Pastel('peach', Color(0xFFFDE8DF), Color(0xFF3A2C2A), Color(0xFFF2A88A)),
  Pastel('mint', Color(0xFFE2F4EC), Color(0xFF243330), Color(0xFF86C5B0)),
  Pastel('lavender', Color(0xFFEEE9FB), Color(0xFF2D2A3D), Color(0xFF9B8AD8)),
  Pastel('sky', Color(0xFFE3F0FB), Color(0xFF253039), Color(0xFF86B4DE)),
  Pastel('butter', Color(0xFFFDF5D8), Color(0xFF35322A), Color(0xFFE6C66E)),
  Pastel('rose', Color(0xFFFBE6EE), Color(0xFF382A31), Color(0xFFE79AB5)),
  Pastel('sage', Color(0xFFEAF0E1), Color(0xFF2C3128), Color(0xFFA3BC8A)),
];

Pastel pastelAt(int i) => pastels[i.clamp(0, pastels.length - 1)];

/// Ink colours offered in the pen toolbar.
const inkColors = <Color>[
  Color(0xFF3E3A4A),
  Color(0xFF7C6BC4),
  Color(0xFF5B9BD5),
  Color(0xFF5FAE93),
  Color(0xFFE58C6A),
  Color(0xFFD9719A),
  Color(0xFFE0B04A),
];

const highlighterColors = <Color>[
  Color(0xFFFFE27A),
  Color(0xFFB8E6CF),
  Color(0xFFC9BEF5),
  Color(0xFFFFC2A8),
  Color(0xFFA9D3F5),
];

class PamukTheme {
  static const _font = 'Nunito';

  static ThemeData light() => _build(const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF8A78CF),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFECE7FB),
        onPrimaryContainer: Color(0xFF3B3060),
        secondary: Color(0xFFE99A7B),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFDE8DF),
        onSecondaryContainer: Color(0xFF5A3426),
        tertiary: Color(0xFF6DB59C),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFFDDF2EA),
        onTertiaryContainer: Color(0xFF1F4A3C),
        error: Color(0xFFD9707A),
        onError: Colors.white,
        errorContainer: Color(0xFFFBE3E5),
        onErrorContainer: Color(0xFF5E2329),
        surface: Color(0xFFFAF7F2),
        onSurface: Color(0xFF3E3A4A),
        onSurfaceVariant: Color(0xFF7A7488),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFFFFDF9),
        surfaceContainer: Color(0xFFF6F2EC),
        surfaceContainerHigh: Color(0xFFF1EDE6),
        surfaceContainerHighest: Color(0xFFEBE6DF),
        outline: Color(0xFFD5CFDF),
        outlineVariant: Color(0xFFECE7F0),
        shadow: Color(0xFF6B5E8A),
        inverseSurface: Color(0xFF3E3A4A),
        onInverseSurface: Color(0xFFF7F3FB),
        inversePrimary: Color(0xFFC9BCF5),
      ));

  static ThemeData dark() => _build(const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFBFB1F2),
        onPrimary: Color(0xFF2E2550),
        primaryContainer: Color(0xFF3D3560),
        onPrimaryContainer: Color(0xFFE9E3FF),
        secondary: Color(0xFFF4B9A1),
        onSecondary: Color(0xFF4A2A1E),
        secondaryContainer: Color(0xFF4A3530),
        onSecondaryContainer: Color(0xFFFDE3D8),
        tertiary: Color(0xFF9FD6C2),
        onTertiary: Color(0xFF173A2F),
        tertiaryContainer: Color(0xFF2B433B),
        onTertiaryContainer: Color(0xFFD6F1E6),
        error: Color(0xFFF0A3AA),
        onError: Color(0xFF4F1D22),
        errorContainer: Color(0xFF5A2E33),
        onErrorContainer: Color(0xFFFCE1E3),
        surface: Color(0xFF1E1C24),
        onSurface: Color(0xFFECE8F4),
        onSurfaceVariant: Color(0xFFADA6BC),
        surfaceContainerLowest: Color(0xFF19171E),
        surfaceContainerLow: Color(0xFF24212B),
        surfaceContainer: Color(0xFF28252F),
        surfaceContainerHigh: Color(0xFF2E2B36),
        surfaceContainerHighest: Color(0xFF35313D),
        outline: Color(0xFF524C5E),
        outlineVariant: Color(0xFF3A3642),
        shadow: Color(0xFF000000),
        inverseSurface: Color(0xFFECE8F4),
        onInverseSurface: Color(0xFF2B2833),
        inversePrimary: Color(0xFF8A78CF),
      ));

  static ThemeData _build(ColorScheme c) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: c,
      fontFamily: _font,
      brightness: c.brightness,
    );
    final text = base.textTheme.apply(bodyColor: c.onSurface, displayColor: c.onSurface).copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        );
    final soft = RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
    return base.copyWith(
      scaffoldBackgroundColor: c.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: c.onSurface),
        iconTheme: IconThemeData(color: c.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: soft,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceContainer,
        hintStyle: TextStyle(color: c.onSurfaceVariant.withValues(alpha: 0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: c.primary.withValues(alpha: 0.45), width: 1.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        extendedTextStyle: text.labelLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: c.outline),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceContainer,
        selectedColor: c.primaryContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: text.labelLarge?.copyWith(color: c.onSurface),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          side: WidgetStatePropertyAll(BorderSide(color: c.outlineVariant)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.primaryContainer : c.surfaceContainerLowest),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? c.onPrimaryContainer : c.onSurfaceVariant),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: c.outline, width: 1.6),
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.tertiary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onTertiary),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.surfaceContainerLowest),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceContainerHighest),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelSmall?.copyWith(
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              color: s.contains(WidgetState.selected) ? c.onSurface : c.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? c.onPrimaryContainer : c.onSurfaceVariant,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceContainerLow,
        indicatorColor: c.primaryContainer,
        selectedIconTheme: IconThemeData(color: c.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: c.onSurfaceVariant),
        selectedLabelTextStyle: text.labelLarge?.copyWith(color: c.onSurface, fontWeight: FontWeight.w800),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(color: c.onSurfaceVariant),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        iconColor: c.onSurfaceVariant,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.primaryContainer,
        circularTrackColor: c.primaryContainer,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: c.inverseSurface, borderRadius: BorderRadius.circular(10)),
        textStyle: text.bodySmall?.copyWith(color: c.onInverseSurface),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

/// A gentle, wide shadow that lifts cards without a hard edge.
List<BoxShadow> softShadow(BuildContext context, {double strength = 1}) {
  final c = Theme.of(context).colorScheme;
  final dark = c.brightness == Brightness.dark;
  return [
    BoxShadow(
      color: c.shadow.withValues(alpha: (dark ? 0.28 : 0.07) * strength),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}
