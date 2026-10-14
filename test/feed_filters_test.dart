import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
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

/// The tag filter follows the tags that exist, and filters where it's set.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_feed_filters_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppState> boot(AppData data) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(data);
    final state = AppState();
    await state.init();
    return state;
  }

  test('a tag filter whose last note is gone clears itself', () async {
    final state = await boot(AppData(
      notes: [
        Note(id: 'a', title: 'Report', tags: ['work']),
        Note(id: 'b', title: 'Groceries'),
      ],
      spaces: [],
      cards: [],
    ));
    state.setActiveTag('work');
    expect(state.notes.map((n) => n.id), ['a']);

    await state.deleteNote('a');
    expect(state.notes.map((n) => n.id), ['b']);
    expect(state.activeTag, isNull);
    await state.flushNow();
    state.dispose();
  });

  testWidgets('a folder emptied by the tag filter still shows its chip',
      (tester) async {
    final state = (await tester.runAsync(() => boot(AppData(
          notes: [
            Note(id: 'a', title: 'In the folder', spaceId: 'f'),
            Note(id: 'b', title: 'Report', tags: ['work']),
          ],
          spaces: [Space(id: 'f', name: 'Folder')],
          cards: [],
        ))))!;
    state.setActiveTag('work');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'f'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('#work'), findsOneWidget);

    await tester.tap(find.text('#work'));
    await tester.pumpAndSettle();
    expect(find.text('In the folder'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  });

  testWidgets('a folder shows only its notes with the chosen tag',
      (tester) async {
    final state = (await tester.runAsync(() => boot(AppData(
          notes: [
            Note(id: 'a', title: 'Tagged note', tags: ['x'], spaceId: 'f'),
            Note(id: 'b', title: 'Other note', spaceId: 'f'),
          ],
          spaces: [Space(id: 'f', name: 'Folder')],
          cards: [],
        ))))!;
    state.setActiveTag('x');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SpaceDetailScreen(spaceId: 'f'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tagged note'), findsOneWidget);
    expect(find.text('Other note'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  });
}
