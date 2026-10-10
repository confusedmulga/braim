import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'screens/pomodoro_screen.dart';
import 'screens/root_shell.dart';
import 'screens/share_popup.dart';
import 'services/dnd_service.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'state/pomodoro_controller.dart';
import 'theme/app_theme.dart';
import 'web/web_controller.dart';
import 'widgets/glass.dart';

/// Root navigator, so a tapped notification can open a screen without a
/// BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handles taps on the focus notification: its play/pause button toggles the
/// timer; tapping the body opens the timer screen.
void _onNotificationTap(String? payload, String? actionId) {
  if (payload != NotificationService.focusPayload) return;
  if (actionId == 'pomo_toggle') {
    PomodoroController.instance.toggleFromNotification();
    return;
  }
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const PomodoroScreen()),
  );
}

/// The bundled OFL fonts aren't Dart packages, so Flutter's license page
/// doesn't list them on its own; each font's license file is registered here.
void registerFontLicenses() {
  const fonts = {
    'Lora': 'OFL-Lora.txt',
    'Caveat': 'OFL-Caveat.txt',
    'Space Grotesk': 'OFL-SpaceGrotesk.txt',
    'EB Garamond': 'OFL-EBGaramond.txt',
    'Merriweather': 'OFL-Merriweather.txt',
    'JetBrains Mono': 'OFL-JetBrainsMono.txt',
    'Inter': 'OFL-Inter.txt',
    'Nunito': 'OFL-Nunito.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      final text = await rootBundle.loadString('assets/fonts/${e.value}');
      yield LicenseEntryWithLineBreaks(['${e.key} (font)'], text);
    }
  });
}

/// Braim Web's note editor (Quill) ships inside the app; its licence is listed
/// with the others.
void registerWebLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/web/vendor/LICENSE-quill.txt',
    );
    // Quill's file also carries the notices of the packages its build bundles.
    yield LicenseEntryWithLineBreaks([
      'Quill (Braim Web editor)',
      'parchment',
      'quill-delta',
      'eventemitter3',
      'lodash-es',
    ], text);
  });
}

/// The offline dictionary's data (Open English WordNet, over Princeton
/// WordNet) asks for credit to both; its licence is listed with the others.
void registerDictionaryLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/dictionary/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(
        ['Open English WordNet (dictionary)', 'Princeton WordNet'], text);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The launch screen stays up until the library and the feed's backdrop are
  // ready (see _Root), so the app opens as itself: no blank page, no backdrop
  // popping in, no flash of the other theme.
  _LaunchGate.hold();
  registerFontLicenses();
  registerWebLicenses();
  registerDictionaryLicense();
  // Reminders are set up on first use (AppState re-arms them just after the
  // launch), not here: setting up reads the time-zone database, which took
  // most of a second of every launch.
  NotificationService.onSelect = _onNotificationTap;
  // If a focus session was killed with DND still on, turn it back off.
  await DndService.instance.restoreIfLeftOn();
  // Draw behind the status bar and the gesture-nav pill, and turn off the
  // system's auto contrast scrim so no white/black band paints behind the pill.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const BraimApp());
}

/// Entrypoint for the translucent ShareActivity: renders only the small
/// save-to-folder popup over whatever app the user shared from.
@pragma('vm:entry-point')
void shareMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SharePopupApp());
}

class BraimApp extends StatelessWidget {
  const BraimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final state = AppState()..init();
          NotificationService.onExactAlarmsGranted = state.rescheduleReminders;
          return state;
        }),
        // Braim Web: created when Settings first reads it, and always off at
        // launch. It shares the one AppState, so web edits go where phone
        // edits go.
        ChangeNotifierProvider(
          create: (context) => BraimWebController(context.read<AppState>()),
        ),
      ],
      child: const _ThemedApp(),
    );
  }
}

class _ThemedApp extends StatelessWidget {
  const _ThemedApp();

  /// One ThemeData per mode, built lazily and reused. Rebuilding the theme
  /// on every AppState notification handed the whole app a new Theme — an
  /// app-wide rebuild for every note save, pin or archive.
  static final Map<bool, ThemeData> _themes = {};

  @override
  Widget build(BuildContext context) {
    // Only the effective brightness matters here; AppPalette.scheme is
    // already flipped by AppState before it notifies.
    final dark = context.select<AppState, bool>((s) => s.effectiveDark);
    final theme = _themes.putIfAbsent(dark, () => buildTheme(dark));
    return MaterialApp(
      title: 'Braim',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme,
      scrollBehavior: const _NoStretchScrollBehavior(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...FlutterQuillLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // The theme keeps the scaffold/canvas transparent so each screen can
      // paint its own backdrop. That leaves the void *behind* the Navigator
      // uncoloured, which flashed white for a frame during route push/pop in
      // dark mode. Fill it with the same base surface every screen sits on so
      // transitions never reveal white.
      builder: (context, child) => ColoredBox(
        color: AppPalette.scheme.surface,
        child: child ?? const SizedBox.shrink(),
      ),
      // Remount the tree when the theme flips so every widget re-reads
      // the mode-aware palette.
      home: KeyedSubtree(key: ValueKey(dark), child: const _Root()),
    );
  }
}

/// Removes the Android stretch overscroll (it broke the glass header elements)
/// and replaces it with springy rubber-band physics: scrolls bounce softly at
/// the edges instead of glowing or stretching.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// Holds back the app's first frame, which keeps the system launch screen
/// (the logo) showing until [release]. Never for long: after a few seconds the
/// app shows whatever it has, a slow first load its spinner.
abstract final class _LaunchGate {
  static bool _held = false;

  static void hold() {
    if (_held) return;
    _held = true;
    WidgetsBinding.instance.deferFirstFrame();
    Timer(const Duration(seconds: 4), release);
  }

  static void release() {
    if (!_held) return;
    _held = false;
    WidgetsBinding.instance.allowFirstFrame();
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _warming = false;

  /// Decodes the feed's backdrop (the frames before it are built, just not
  /// shown), then lets the first frame through with it in place. Decoding a
  /// full-screen image takes a moment; before, the feed showed its plain
  /// surface until it arrived.
  Future<void> _showWhenReady() async {
    try {
      await precacheImage(
              feedWallpaper(context.read<AppState>().feedBackgroundForTheme),
              context)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // A missing or slow image just shows the plain surface, as before.
    }
    _LaunchGate.release();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<AppState, bool>((s) => s.loaded);
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_warming) {
      _warming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWhenReady();
      });
    }
    return const RootShell();
  }
}
