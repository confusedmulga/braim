import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/screens/settings_screen.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/theme/app_theme.dart';
import 'package:braim/web/web_controller.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getExternalStoragePath() async => '$root/ext';
}

/// The app's own scroll feel (main.dart): iOS-style bounce everywhere.
class _Bouncy extends MaterialScrollBehavior {
  const _Bouncy();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_settings_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Shows Settings on a typical phone, with the app's theme and scroll feel.
  /// [behind] paints the void behind the navigator (the app uses the surface
  /// colour there); a test can make it loud to catch see-through screens.
  Future<AppState> pumpSettings(WidgetTester tester,
      {bool dark = false, Color? behind}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.runAsync(state.init);
    await tester.runAsync(() => state.setDarkFollowSystem(false));
    await tester.runAsync(() => state.setDarkMode(dark));
    await tester.pumpWidget(RepaintBoundary(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(create: (_) => BraimWebController(state)),
        ],
        child: MaterialApp(
          theme: buildTheme(dark),
          scrollBehavior: const _Bouncy(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ColoredBox(
            color: behind ?? AppPalette.scheme.surface,
            child: child,
          ),
          home: const SettingsScreen(),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100))); // backup path lookup
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  testWidgets(
      'reaching the bottom of Settings never changes the list height '
      '(so it can\'t spring back up by itself)', (tester) async {
    final state = await pumpSettings(tester);

    // The page's one vertical list.
    final list = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.axis == Axis.vertical);
    final position = list.position;
    final heightAtOpen = position.maxScrollExtent;
    expect(heightAtOpen, greaterThan(0));

    // Fling hard toward the end, several times, like a user would.
    for (var i = 0; i < 4; i++) {
      await tester.fling(
          find.byWidget(list.widget), const Offset(0, -1500), 4000);
      await tester.pumpAndSettle();
    }

    expect(position.maxScrollExtent, heightAtOpen,
        reason: 'the list height was an estimate that changed at the bottom');
    expect(position.pixels, position.maxScrollExtent);
    await close(tester, state);
  });

  testWidgets(
      'the licenses page paints its own top bar: dark in dark mode, '
      'whatever is behind it', (tester) async {
    // Pure white behind the navigator: a see-through top bar would show it.
    final state =
        await pumpSettings(tester, dark: true, behind: const Color(0xFFFFFFFF));

    final link = find.text('Open-source licenses');
    await tester.scrollUntilVisible(link, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);

    // Sample the top bar's left edge (clear of the title text).
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first);
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      Color at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1),
            bytes.getUint8(i + 2));
      }

      return [for (final y in [4, 24, 44, 64]) at(3, y)];
    });

    final sheet = AppPalette.sheet;
    for (final c in pixels!) {
      expect(c.toARGB32(), sheet.toARGB32(),
          reason: 'the top bar let the white behind it show through');
    }
    await close(tester, state);
  });
}
