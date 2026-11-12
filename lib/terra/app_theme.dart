// From Soloza's `app/theme/app_theme.dart`, unchanged apart from the one skin.
import 'package:flutter/material.dart';

import 'press.dart';
import 'fonts.dart';
import 'palette.dart';

/// Variable fonts need the `wght` axis set explicitly to render weights.
TextStyle _style(String family, double size, int weight, Color color,
        {double height = 1.35, double spacing = 0}) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      height: height,
      letterSpacing: spacing,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

extension WeightX on TextStyle {
  /// Sets a variable-font weight (100–900) correctly.
  TextStyle weight(int w) => copyWith(
        fontWeight: FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wght', w.toDouble())],
      );
}

ThemeData buildTheme(Palette p, [AppFonts fonts = const AppFonts()]) {
  final sans = fonts.ui, serif = fonts.display;
  final isDark = p.brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.danger,
    onError: p.onAccent,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.background,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceRaised,
    surfaceContainerHighest: p.surfaceRaised,
    onSurfaceVariant: p.textMuted,
    outline: p.border,
    outlineVariant: p.border,
  );

  final text = TextTheme(
    // unslop: hierarchy from size and colour; weights 400–500 (560 for titles).
    displaySmall: _style(serif, 32, 400, p.text, height: 1.12, spacing: -0.4),
    headlineMedium: _style(serif, 27, 400, p.text, height: 1.12, spacing: -0.4),
    headlineSmall: _style(serif, 21, 400, p.text, height: 1.2),
    titleLarge: _style(sans, 17, 560, p.text, height: 1.3),
    titleMedium: _style(sans, 14.5, 560, p.text),
    titleSmall: _style(sans, 13, 560, p.text),
    bodyLarge: _style(sans, 14.5, 400, p.text, height: 1.5),
    bodyMedium: _style(sans, 13, 400, p.text, height: 1.45),
    bodySmall: _style(sans, 12, 400, p.textMuted),
    labelLarge: _style(sans, 12.5, 500, p.text, spacing: 0.1),
    labelMedium: _style(sans, 12, 500, p.textMuted, spacing: 0.2),
    // Section labels: sentence case, quiet, normal tracking.
    labelSmall: _style(sans, 11.5, 500, p.textMuted, spacing: 0.1),
  );

  final radius = BorderRadius.circular(p.radius);
  final controlShape = RoundedRectangleBorder(borderRadius: radius);

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.windows: InstantPageTransitions()}),
    fontFamily: sans,
    textTheme: text,
    extensions: [p, fonts],
    splashFactory: const PressTint(),
    hoverColor: p.text.withValues(alpha: 0.04),
    focusColor: p.accent.withValues(alpha: 0.24),
    highlightColor: p.text.withValues(alpha: 0.08),
    splashColor: p.text.withValues(alpha: 0.08),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent, selectionColor: p.accent.withValues(alpha: 0.28), selectionHandleColor: p.accent),
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.textMuted, size: 20),
    // TT1-TT8: the same look as TerraTooltip, for the few Material tooltips left.
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 300),
      exitDuration: const Duration(milliseconds: 100),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
      textStyle: text.bodySmall?.copyWith(color: p.onAccent),
    ),
    // TT6: icon buttons light up in the same frame the pointer arrives.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? p.accent.withValues(alpha: 0.28) : s.contains(WidgetState.hovered) ? p.accent.withValues(alpha: 0.18) : s.contains(WidgetState.focused) ? p.accent.withValues(alpha: 0.24) : null),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.surfaceRaised,
      hintStyle: text.bodyMedium?.copyWith(color: p.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: p.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        textStyle: text.labelLarge,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        iconSize: 14,
        shape: controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.s3,
        side: BorderSide(color: p.border),
        textStyle: text.labelLarge,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        iconSize: 14,
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: text.labelLarge, minimumSize: const Size(30, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap, padding: const EdgeInsets.symmetric(horizontal: 9), iconSize: 14, visualDensity: VisualDensity.standard, shape: controlShape),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surfaceRaised),
        shape: WidgetStatePropertyAll(p.shape(p.radius)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceRaised,
      textStyle: text.bodyMedium,
      shape: p.shape(p.radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: p.shape(12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceRaised,
      contentTextStyle: text.bodyMedium,
      actionTextColor: p.accent,
      // Every message can be closed; ones with Undo still fade (persist: false at each).
      showCloseIcon: true,
      closeIconColor: p.textMuted,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.lineStrong,
      thumbColor: p.accent,
      overlayColor: p.accent.withValues(alpha: 0.12),
    ),
    // Selection is a quiet accent tint, not a solid fill: a screen of 27
    // ticked chips (My gym) must stay calm. Solid accent is for primary actions.
    chipTheme: ChipThemeData(
      backgroundColor: p.s2,
      selectedColor: p.accentSoft,
      checkmarkColor: p.accent,
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? p.accent.withValues(alpha: 0.45) : p.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      labelStyle: text.labelLarge?.copyWith(color: p.text),
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceRaised),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.lineStrong),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: p.lineStrong)),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
        minimumSize: const WidgetStatePropertyAll(Size(36, 30)),
        visualDensity: VisualDensity.standard,
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.textMuted,
        ),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.textFaint.withValues(alpha: isDark ? 0.35 : 0.45)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
  );
}

/// Every popup menu opens in this: quick enough to feel instant, with just
/// enough fade to see where it came from (Material's default is 300 ms).
/// Reduce motion shortens it further through `timeDilation`.
const kMenuMotion = AnimationStyle(duration: Duration(milliseconds: 90), reverseDuration: Duration(milliseconds: 60));

/// Pages swap at once (QA-18). The default fade-and-slide shows the old page
/// through the new one's translucent first frames, and a page that takes a
/// moment to build looked like artifacts of the previous page.
class InstantPageTransitions extends PageTransitionsBuilder {
  const InstantPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
