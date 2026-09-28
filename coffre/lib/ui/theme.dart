import 'package:flutter/material.dart';

import '../data/enums.dart';

const _seed = Color(0xFF2E7D6B);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.35),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.35),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48)),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(fontSize: 15),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
  );
}

IconData kindIcon(ItemKind kind) => switch (kind) {
  ItemKind.idea => Icons.lightbulb_outline,
  ItemKind.task => Icons.task_alt,
  ItemKind.note => Icons.sticky_note_2_outlined,
};

Color kindColor(ItemKind kind, ColorScheme scheme) => switch (kind) {
  ItemKind.idea => scheme.tertiary,
  ItemKind.task => scheme.primary,
  ItemKind.note => scheme.secondary,
};

/// Multiplie la taille de texte système par le réglage de l'app.
TextScaler combinedTextScaler(TextScaler system, double factor) {
  if (factor == 1.0) return system;
  final base = system.scale(16) / 16;
  return TextScaler.linear((base * factor).clamp(0.8, 3.0));
}
