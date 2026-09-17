import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central palette + theme.
///
/// The app follows Material 3: a [ColorScheme] seeded from [AppPalette.seed]
/// supplies every color role, and the getters below map the app's named
/// surfaces onto those roles so all screens restyle together. The exceptions
/// that deliberately stay custom: the frosted nav island, the glass (blur)
/// surfaces, and the editor's floating format island.
class AppPalette {
  static bool _dark = false;

  /// The active Material 3 scheme (recomputed when [dark] flips).
  static ColorScheme scheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

  /// Global dark-mode flag (set by AppState before it notifies).
  static bool get dark => _dark;
  static set dark(bool value) {
    _dark = value;
    scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: value ? Brightness.dark : Brightness.light,
    );
  }

  static const seed = Color(0xFF6C8CFF);

  // Background gradient stops (fallback when the wallpaper asset is missing).
  static const bgTop = Color(0xFF12131A);
  static const bgBottom = Color(0xFF1B1430);

  static const blobA = Color(0xFF6C8CFF); // blue
  static const blobB = Color(0xFFB06CFF); // violet
  static const blobC = Color(0xFFFF6CA8); // pink
  static const blobD = Color(0xFF38E0C8); // teal

  /// Legacy aliases (sheets and empty states used to sit on dark glass);
  /// they now resolve to the scheme's ink roles.
  static Color get textPrimary => scheme.onSurface;
  static Color get textSecondary => scheme.onSurfaceVariant;

  // ---- Material 3 roles ----------------------------------------------------

  /// Body ink on app surfaces.
  static Color get inkPrimary => scheme.onSurface;
  static Color get inkSecondary => scheme.onSurfaceVariant;

  /// Translucent fill under the frosted chrome's blur — the nav island, top bar
  /// (search + sort + menu), back button and the note/spark 3-dots pill. Kept
  /// see-through so the frost reads over the feed; tinted by the scheme so both
  /// modes harmonise.
  static Color get whiteFill => dark
      ? scheme.surfaceContainerHigh.withValues(alpha: 0.52)
      : scheme.surface.withValues(alpha: 0.52);

  /// Near-opaque fill for cards that sit over the wallpaper without blur.
  static Color get cardFill => scheme.surface.withValues(alpha: 0.95);

  /// Opaque feed-tile surface; matches the morph sheet so open/close reads
  /// as one continuous surface.
  static Color get cardSolid => scheme.surface;

  /// Hairline outline for tiles and flat chrome (M3 outline-variant).
  static Color get cardOutline => scheme.outlineVariant;

  /// Opaque sheet behind opened notes/cards (and the morph surface).
  static Color get sheet => scheme.surface;

  /// Fill for the flat floating chrome (menu, search, sort) — the M3
  /// search-bar / tonal icon-button surface.
  static Color get bubbleGlass => scheme.surfaceContainerHigh;

  /// Fill for the editor's floating format island — a touch more see-through
  /// than before so the frost shows more of the note behind it.
  static Color get islandGlass =>
      dark ? const Color(0xA6191B23) : const Color(0xA6FFFFFF);

  /// Side pane surface (M3 navigation-drawer container).
  static Color get paneFill => scheme.surfaceContainerLow;
  static Color get paneBorder => scheme.outlineVariant;

  /// Near-opaque backdrop of the settings overlay.
  static Color get scrimFill => scheme.surface.withValues(alpha: 0.97);

  /// Panels on the settings screen (M3 surface container).
  static Color get surfaceGlass => scheme.surfaceContainerLow;

  /// Small chips / icon boxes on card surfaces (M3 neutral container).
  static Color get chipFill => scheme.surfaceContainerHighest;

  /// Selected pill fills (nav island, toggles, dividers on glass).
  static Color get selFill =>
      dark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

  /// Whitening/darkening tint over a themed note's background image.
  static Color get noteTint =>
      dark ? const Color(0x99000000) : const Color(0xADFFFFFF);

  /// Warm amber accent for the Journal (selected day, entry dates).
  static const journalAccent = Color(0xFFEBA23C);

  /// Lavender accent for `[[@Name]]` impulse/thread mentions in note bodies —
  /// distinct from the blue used for node/spark links. Lighter in dark mode so
  /// it stays legible on the dark surface.
  static Color get mentionAccent =>
      dark ? const Color(0xFFC4A7FF) : const Color(0xFF8B5CF6);

  /// Diagonal gradient for the journal's month calendar card: lightest
  /// lavender into sky blue (dark mode uses tints of the same hues).
  static List<Color> get journalCalendarGradient => dark
      ? [
          Color.alphaBlend(
              const Color(0xFFB9A8FF).withValues(alpha: 0.16),
              const Color(0xFF1E2028)),
          Color.alphaBlend(
              const Color(0xFF7CC6FF).withValues(alpha: 0.16),
              const Color(0xFF1E2028)),
        ]
      : [const Color(0xFFF2EDFF), const Color(0xFFDDF1FF)];
}

/// The two writing faces: note and card body copy is set in Caveat (a
/// handwriting face), while their titles and headings use Lora like the rest
/// of the app.
const String kNoteBodyFont = 'Caveat';
const String kNoteHeadingFont = 'Lora';

/// Sky blue for inline hyperlinks (a pasted URL, or text linked with the "H"
/// button). Chosen bright enough to read on the dark app cards yet dark enough
/// on the white note sheet, so one value works in both places.
const Color kLinkColor = Color(0xFF2F9BF5);

/// The active body face for nodes & sparks — user-selectable in Settings, set by
/// AppState on load/change. Titles/chrome stay on [kNoteHeadingFont].
String activeBodyFont = kNoteBodyFont;

/// The fonts offered in the Settings body-font picker (family, label).
const List<({String family, String label})> kBodyFontOptions = [
  (family: 'Caveat', label: 'Caveat (handwriting)'),
  (family: 'Lora', label: 'Lora (serif)'),
  (family: 'EB Garamond', label: 'EB Garamond (serif)'),
  (family: 'Merriweather', label: 'Merriweather (serif)'),
  (family: 'SpaceGrotesk', label: 'Space Grotesk (sans)'),
  (family: 'Inter', label: 'Inter (sans)'),
  (family: 'Nunito', label: 'Nunito (rounded)'),
];

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
  /// for the default surface. Muted to a subtle tint in dark mode, which suits
  /// a large note-card fill.
  static Color? resolve(int? value) {
    if (value == null) return null;
    final base = Color(value);
    if (!AppPalette.dark) return base;
    return Color.alphaBlend(
        base.withValues(alpha: 0.16), const Color(0xFF1E2028));
  }

  /// A fill that keeps its swatch vivid in both themes — only a touch darker in
  /// dark mode. Used for folder tiles and folder chips, where the colour needs
  /// to read at a glance rather than sit as a faint tint.
  static Color? resolveStrong(int? value) {
    if (value == null) return null;
    final base = Color(value);
    if (!AppPalette.dark) return base;
    return Color.alphaBlend(Colors.black.withValues(alpha: 0.16), base);
  }

  /// Legible ink for text/icons placed on a [resolveStrong] swatch. The
  /// swatches are light-toned in both themes, so this stays dark.
  static const Color onSwatch = Color(0xFF232530);
}

/// Builds the theme for [dark]. The scheme is computed from the mode here
/// (not read from the mutable [AppPalette.scheme]), so the cached theme can
/// never be poisoned by a build that ran before the global flag was flipped —
/// which showed as dark-on-dark, unreadable ListTile text in dark mode.
ThemeData buildTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Lora',
  );

  return base.copyWith(
    canvasColor: Colors.transparent,
    // Android 14+ predictive back: routes using the default page transition
    // (folds/spaces, markdown notes) show the OS peek of the screen underneath
    // as you swipe from the edge. Falls back to the zoom transition on devices
    // without predictive back, and iOS keeps its native swipe.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // No shadow/tint band when content scrolls under a bar — text should
      // only ever fade at the status-bar scrim.
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      // The transparent background makes Flutter estimate the bar as "dark"
      // and paint white status icons; follow the surface brightness instead.
      systemOverlayStyle: (dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
    ),
    // M3 dialogs: extra-large shape on a high surface container.
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Lora',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Lora',
        fontSize: 14.5,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        fontFamily: 'Lora',
        color: scheme.onInverseSurface,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(TextStyle(
          fontFamily: 'Lora',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        )),
      ),
    ),
  );
}
