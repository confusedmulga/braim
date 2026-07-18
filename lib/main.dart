import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'screens/root_shell.dart';
import 'screens/share_popup.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
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
    final theme = _themes.putIfAbsent(dark, buildTheme);
    return MaterialApp(
      title: 'Braim',
      debugShowCheckedModeBanner: false,
      theme: theme,
      scrollBehavior: const _NoStretchScrollBehavior(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...FlutterQuillLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
