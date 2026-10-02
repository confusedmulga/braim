import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/widgets/circuit_sheets.dart';

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
    root = Directory.systemTemp.createTempSync('braim_import_ui_test');
    Directory('${root.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  });

  /// Shows a blank screen with the app's state and strings; returns the state
  /// and a context inside the Scaffold (for dialogs and snackbars).
  Future<(AppState, BuildContext)> pumpApp(WidgetTester tester) async {
    final state = AppState();
    await tester.runAsync(state.init);
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        })),
      ),
    ));
    return (state, ctx);
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  testWidgets('the already-have-it dialog offers replace, keep both, cancel',
      (tester) async {
    final (state, ctx) = await pumpApp(tester);
    for (final (button, expected) in [
      ('Replace', CircuitImportChoice.replace),
      ('Keep both', CircuitImportChoice.keepBoth),
      ('Cancel', null),
    ]) {
      final answer = showCircuitImportConflictDialog(ctx, title: 'Trip');
      await tester.pumpAndSettle();
      expect(find.text('You already have "Trip"'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(await answer, expected);
    }
    await close(tester, state);
  });

  testWidgets('a file that is not a circuit is refused with a reason',
      (tester) async {
    final (state, ctx) = await pumpApp(tester);
    final file = File('${root.path}/tmp/holiday.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    await tester.runAsync(
        () => importCircuitFile(ctx, file.path, onOpen: (_) {}));
    await tester.pump();
    expect(find.textContaining("Braim can't import this file"), findsOneWidget);
    expect(state.notes, isEmpty);
    await close(tester, state);
  });

  testWidgets('a received circuit lands on Home and says so', (tester) async {
    final (state, ctx) = await pumpApp(tester);
    // Make a circuit file, then empty the library so it arrives as new.
    final first = state.newCircuitRootDraft()..title = 'Trip';
    late List<int> bytes;
    await tester.runAsync(() async {
      await state.ensureCircuitRootSaved(first);
      await state.addCircuitChild(first.id);
      bytes = await state.exportCircuitBytes(first.id);
      await state.deleteCircuit(first.id);
      await state.permanentlyDeleteTrashGroup(
          state.deletedNoteGroups.single.key);
    });
    expect(state.notes, isEmpty);
    final file = File('${root.path}/tmp/Trip.braim')..writeAsBytesSync(bytes);

    Note? opened;
    await tester.runAsync(() => importCircuitFile(ctx, file.path,
        onOpen: (rootNote) => opened = rootNote));
    await tester.pump();

    final imported = state.notes.single; // the feed shows the first note
    expect(imported.title, 'Trip');
    expect(imported.isCircuitRoot, isTrue);
    expect(find.text('Imported "Trip" · 2 notes'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500)); // slide-in done
    await tester.tap(find.text('Open'));
    expect(opened?.id, imported.id);
    await close(tester, state);
  });
}
