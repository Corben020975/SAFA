import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/enums.dart';

/// Palette chaude sur fond noir. Contrastes vérifiés (WCAG AA) sur le thème sombre.
class Palette {
  const Palette({
    required this.bg,
    required this.card,
    required this.field,
    required this.line,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.sage,
    required this.blue,
    required this.sand,
    required this.coral,
  });

  final Color bg, card, field, line, ink, muted, faint;
  final Color sage, blue, sand, coral;

  /// Fond quasi noir, accents ambre / terracotta / crème.
  static const dark = Palette(
    bg: Color(0xFF0A0908),
    card: Color(0xFF161311),
    field: Color(0xFF1F1A16),
    line: Color(0xFF2C261F),
    ink: Color(0xFFF4EEE6),
    muted: Color(0xFFB9A99A),
    faint: Color(0xFF8A7B6C),
    sage: Color(0xFFD4A574), // ambre chaud (primaire)
    blue: Color(0xFFC4956A), // bronze
    sand: Color(0xFFE8C07A), // or doux
    coral: Color(0xFFE07A5F), // terracotta
  );

  /// Clair secondaire : crème chaude, pas blanc froid.
  static const light = Palette(
    bg: Color(0xFFF6F0E8),
    card: Color(0xFFFFFBF6),
    field: Color(0xFFEDE4D8),
    line: Color(0xFFD9CFC2),
    ink: Color(0xFF1A1410),
    muted: Color(0xFF6B5C4E),
    faint: Color(0xFF8F7F6E),
    sage: Color(0xFF9A6B3C),
    blue: Color(0xFF8A5A38),
    sand: Color(0xFFA67C2D),
    coral: Color(0xFFB54E3A),
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Durée des bandeaux « Annuler » : sans elle, un SnackBar avec bouton
/// reste affiché indéfiniment (comportement Material récent).
const kUndoDuration = Duration(seconds: 5);

/// Titres en Fraunces (police éditoriale, douce), texte courant en Roboto.
const _display = 'Fraunces';
const _displayAxes = [
  FontVariation('wght', 560),
  FontVariation('SOFT', 60),
  FontVariation('opsz', 40),
];

TextStyle displayStyle(BuildContext context, double size, {Color? color}) =>
    TextStyle(
      fontFamily: _display,
      fontVariations: _displayAxes,
      fontSize: size,
      height: 1.15,
      letterSpacing: -0.3,
      color: color ?? Palette.of(context).ink,
    );

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.sage,
    onPrimary: dark ? const Color(0xFF1A1208) : Colors.white,
    primaryContainer: dark ? const Color(0xFF3A2A1A) : const Color(0xFFF0DFC8),
    onPrimaryContainer: dark
        ? const Color(0xFFF5E2C8)
        : const Color(0xFF3A2410),
    secondary: p.blue,
    onSecondary: dark ? const Color(0xFF1A1008) : Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF3A281C)
        : const Color(0xFFEED9C8),
    onSecondaryContainer: dark
        ? const Color(0xFFF0DCC8)
        : const Color(0xFF3A2010),
    tertiary: p.sand,
    onTertiary: dark ? const Color(0xFF241B07) : Colors.white,
    tertiaryContainer: dark ? const Color(0xFF3A3121) : const Color(0xFFF5E8CC),
    onTertiaryContainer: dark
        ? const Color(0xFFF5E8C8)
        : const Color(0xFF3D2E0E),
    error: p.coral,
    onError: dark ? const Color(0xFF2B0F0A) : Colors.white,
    errorContainer: dark ? const Color(0xFF42251F) : const Color(0xFFF6DDD7),
    onErrorContainer: dark ? const Color(0xFFF7D6CF) : const Color(0xFF4A1A12),
    surface: p.bg,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: dark ? const Color(0xFF050403) : Colors.white,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.field,
    surfaceContainerHighest: dark
        ? const Color(0xFF2A231C)
        : const Color(0xFFE6DDD2),
    outline: dark ? const Color(0xFF4A3F34) : const Color(0xFFB9AFA2),
    outlineVariant: p.line,
    inverseSurface: p.ink,
    onInverseSurface: p.bg,
    inversePrimary: dark ? const Color(0xFF9A6B3C) : const Color(0xFFD4A574),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
  );
  final text = base.textTheme;
  TextStyle? serif(TextStyle? s, double size) => s?.copyWith(
    fontFamily: _display,
    fontVariations: _displayAxes,
    fontSize: size,
    letterSpacing: -0.2,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: serif(text.headlineLarge, 32),
      headlineMedium: serif(text.headlineMedium, 28),
      headlineSmall: serif(text.headlineSmall, 24),
      titleLarge: serif(text.titleLarge, 22),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: p.muted,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: _overlay(dark, p.bg),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      hintStyle: TextStyle(color: p.faint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.sage.withValues(alpha: 0.6)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 44),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.sage,
        minimumSize: const Size(48, 44),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: p.line),
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        foregroundColor: p.muted,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.field,
      selectedColor: scheme.primaryContainer,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: p.ink,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      indicatorColor: scheme.primaryContainer,
      height: 68,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : p.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.ink, fontSize: 15),
      actionTextColor: p.sage,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.ink),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.sage : p.field,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : p.muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(p.line),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.sage,
      linearTrackColor: p.field,
    ),
  );
}

SystemUiOverlayStyle _overlay(bool dark, Color bg) =>
    (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: bg,
      systemNavigationBarDividerColor: Colors.transparent,
    );

IconData kindIcon(ItemKind kind) => switch (kind) {
  ItemKind.idea => Icons.lightbulb_outline,
  ItemKind.task => Icons.task_alt,
  ItemKind.note => Icons.notes,
};

Color kindColor(ItemKind kind, ColorScheme scheme) => switch (kind) {
  ItemKind.idea => scheme.tertiary,
  ItemKind.task => scheme.primary,
  ItemKind.note => scheme.secondary,
};

Color? priorityColor(ItemPriority p, ColorScheme scheme) => switch (p) {
  ItemPriority.urgent => scheme.error,
  ItemPriority.high => scheme.tertiary,
  _ => null,
};

/// Multiplie la taille de texte système par le réglage de l'app.
TextScaler combinedTextScaler(TextScaler system, double factor) {
  if (factor == 1.0) return system;
  final base = system.scale(16) / 16;
  return TextScaler.linear((base * factor).clamp(0.8, 3.0));
}
