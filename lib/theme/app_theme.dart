import 'package:flutter/material.dart';

/// Central palette + theme for the glassy look.
class AppPalette {
  static const seed = Color(0xFF6C8CFF);

  // Background gradient stops (a soft aurora behind the frosted glass).
  static const bgTop = Color(0xFF12131A);
  static const bgBottom = Color(0xFF1B1430);

  static const blobA = Color(0xFF6C8CFF); // blue
  static const blobB = Color(0xFFB06CFF); // violet
  static const blobC = Color(0xFFFF6CA8); // pink
  static const blobD = Color(0xFF38E0C8); // teal

  // Glass surfaces.
  static Color glassFill = Colors.white.withValues(alpha: 0.10);
  static Color glassFillStrong = Colors.white.withValues(alpha: 0.16);
  static Color glassBorder = Colors.white.withValues(alpha: 0.22);

  static const textPrimary = Color(0xFFF4F5FA);
  static Color textSecondary = const Color(0xFFF4F5FA).withValues(alpha: 0.66);

  // Dark "ink" colours for white/light glass surfaces (note cards, the editor
  // island, the opened note background).
  static const inkPrimary = Color(0xFF1B1C22);
  static const inkSecondary = Color(0xFF5E5F69);

  /// Translucent white fill shared by the glass islands/search bar.
  static const whiteFill = Color(0xA6FFFFFF);

  /// Near-opaque white for feed cards — no backdrop blur needed, so the
  /// scrolling feed stays smooth.
  static const cardFill = Color(0xF2FFFFFF);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.seed,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    canvasColor: Colors.transparent,
    dialogTheme: const DialogThemeData(backgroundColor: Colors.transparent),
    textTheme: base.textTheme.apply(
      bodyColor: AppPalette.textPrimary,
      displayColor: AppPalette.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppPalette.textPrimary,
      centerTitle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppPalette.bgBottom.withValues(alpha: 0.95),
      contentTextStyle: const TextStyle(color: AppPalette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
