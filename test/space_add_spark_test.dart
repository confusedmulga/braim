import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/space.dart';
import 'package:braim/screens/space_detail_screen.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_fold_spark_test');
    Directory('${root.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a fold can take a new spark right there', (tester) async {
    // The add-link box first looks on the clipboard for a link: empty here.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
    final fold = Space(name: 'Reading');
    await tester.runAsync(() => StorageService.instance
        .save(AppData(notes: [], spaces: [fold], cards: [])));
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SpaceDetailScreen(spaceId: fold.id),
      ),
    ));
    await tester.pumpAndSettle();

    // Beside "Add existing" and "New node".
    expect(find.byTooltip('Add existing'), findsOneWidget);
    expect(find.byTooltip('New node'), findsOneWidget);
    await tester.tap(find.byTooltip('New spark'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'https://example.com/article');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final card = state.cards.single;
    expect(card.url, 'https://example.com/article');
    expect(card.spaceId, fold.id);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(state.flushNow);
    state.dispose();
  });
}
