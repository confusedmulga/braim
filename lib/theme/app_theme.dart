import 'package:flutter/material.dart';

/// Central palette + theme for the glassy look.
///
/// Mode-dependent colors are getters over [dark]: light mode is white glass
/// with dark ink, dark mode flips to smoky glass with white ink. The flag is
/// driven by AppState; the app remounts on toggle so every widget re-reads it.
class AppPalette {
  /// Global dark-mode flag (set by AppState before it notifies).
  static bool dark = false;

  static const seed = Color(0xFF6C8CFF);

  // Background gradient stops (a soft aurora behind the frosted glass).
  static const bgTop = Color(0xFF12131A);
  static const bgBottom = Color(0xFF1B1430);

  static const blobA = Color(0xFF6C8CFF); // blue
  static const blobB = Color(0xFFB06CFF); // violet
  static const blobC = Color(0xFFFF6CA8); // pink
  static const blobD = Color(0xFF38E0C8); // teal

  // Glass surfaces (read fine over both backgrounds).
  static Color glassFill = Colors.white.withValues(alpha: 0.10);
  static Color glassFillStrong = Colors.white.withValues(alpha: 0.16);
  static Color glassBorder = Colors.white.withValues(alpha: 0.22);

  static const textPrimary = Color(0xFFF4F5FA);
  static Color textSecondary = const Color(0xFFF4F5FA).withValues(alpha: 0.66);

  // "Ink" colours for the main glass surfaces (cards, editors, islands):
  // near-black on white glass, near-white on dark glass.
  static Color get inkPrimary =>
      dark ? const Color(0xFFF0F1F6) : const Color(0xFF1B1C22);
  static Color get inkSecondary =>
      dark ? const Color(0xFFB4B6C0) : const Color(0xFF5E5F69);

  /// Translucent fill shared by the glass islands/search bar.
  static Color get whiteFill =>
      dark ? const Color(0xA6222530) : const Color(0xA6FFFFFF);

  /// Near-opaque fill for feed cards — no backdrop blur needed, so the
  /// scrolling feed stays smooth.
  static Color get cardFill =>
      dark ? const Color(0xF21D1F27) : const Color(0xF2FFFFFF);

  /// Fully opaque Keep-style tile surface: zero blending with the wallpaper
  /// while scrolling, and it matches the morph sheet so open/close reads as
  /// one continuous surface.
  static Color get cardSolid =>
      dark ? const Color(0xFF1E2028) : Colors.white;

  /// Hairline outline for the flat tiles (Keep uses an outline, no shadow).
  static Color get cardOutline =>
      dark ? const Color(0x24FFFFFF) : const Color(0x1F000000);

  /// Opaque sheet behind opened notes/cards (and the morph surface).
  static Color get sheet => dark ? const Color(0xFF15161C) : Colors.white;

  /// Fill for the liquid-glass bubbles (menu, FABs, island, search).
  static Color get bubbleGlass =>
      dark ? const Color(0xB31C1E28) : const Color(0xA6FFFFFF);

  /// Fill for the editor's floating format island.
  static Color get islandGlass =>
      dark ? const Color(0xCC191B23) : const Color(0xCCFFFFFF);

  /// Side pane glass fill/border.
  static Color get paneFill =>
      dark ? const Color(0xCC15161D) : const Color(0xCCFFFFFF);
  static Color get paneBorder =>
      dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF);

  /// Frosted scrim behind the settings overlay.
  static Color get scrimFill =>
      dark ? const Color(0x8C0E0F14) : const Color(0x99FFFFFF);

  /// Panels on the settings screen.
  static Color get surfaceGlass =>
      dark ? const Color(0x8C232630) : const Color(0xB3FFFFFF);

  /// Small chips / icon boxes on card surfaces.
  static Color get chipFill =>
      dark ? const Color(0x14FFFFFF) : const Color(0x0F000000);

  /// Selected pill fills (nav island, toggles, dividers on glass).
  static Color get selFill =>
      dark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

  /// Whitening/darkening tint over a themed note's background image.
  static Color get noteTint =>
      dark ? const Color(0x99000000) : const Color(0xADFFFFFF);
}

/// Keep-style note colour tags. Stored as the ARGB of the light swatch; dark
/// mode shows a restrained tint of that hue over the dark tile instead of the
/// bright pastel.
class NoteColors {
  const NoteColors._();

  /// Sentinel returned by the picker for "no colour".
  static const int none = -1;

  static const List<int> swatches = [
    0xFFFFF1B8, // sun
    0xFFFFD8B0, // peach
    0xFFFFC7CE, // blush
    0xFFE6D3FF, // lilac
    0xFFC9E4FF, // sky
    0xFFBFEAD6, // mint
    0xFFE3E7C9, // sage
    0xFFDDDFE4, // stone
  ];

  /// The fill to paint for a note tagged [value] in the current theme, or null
  /// for the default surface.
  static Color? resolve(int? value) {
    if (value == null) return null;
    final base = Color(value);
    if (!AppPalette.dark) return base;
    return Color.alphaBlend(
        base.withValues(alpha: 0.16), const Color(0xFF1E2028));
  }
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
    fontFamily: 'SpaceGrotesk',
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
