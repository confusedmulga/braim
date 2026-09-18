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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort; reminders simply don't fire if this fails.
  NotificationService.onSelect = _onNotificationTap;
  await NotificationService.instance.init();
  // If a focus session was killed with DND still on, turn it back off.
  await DndService.instance.restoreIfLeftOn();
  // Draw behind the status bar and the gesture-nav pill, and turn off the
  // system's auto contrast scrim so no white/black band paints behind the pill.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
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
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
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
      home: KeyedSubtree(
        key: ValueKey(dark),
        child: const _Root(),
      ),
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
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<AppState, bool>((s) => s.loaded);
    if (!loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const RootShell();
  }
}
