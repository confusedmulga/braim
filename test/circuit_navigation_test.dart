import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/screens/circuit_map_screen.dart';
import 'package:braim/screens/note_open.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/widgets/glass_morph.dart';

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
    root = Directory.systemTemp.createTempSync('braim_circuit_nav_test');
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

  List<NoteBlock> body(String text) => [
        NoteBlock(
            type: NoteBlockType.text,
            text: jsonEncode([
              {'insert': '$text\n'}
            ])),
      ];

  /// A circuit "Trip" with branches "Note #1" and "Note #2" (each with a
  /// line of text, so they open to read), on a Home screen with an Open
  /// button that opens the first note as the feed does.
  Future<(AppState, Note)> pumpHome(WidgetTester tester) async {
    final state = AppState();
    await tester.runAsync(state.init);
    late Note first;
    await tester.runAsync(() async {
      first = state.newCircuitRootDraft()
        ..title = 'Trip'
        ..blocks = body('The plan');
      await state.ensureCircuitRootSaved(first);
      await state.upsertNote(first);
      for (final line in ['Flights, then [[Note #2]]', 'Hotels']) {
        final branch = await state.addCircuitChild(first.id);
        branch.blocks = body(line);
        await state.upsertNote(branch);
      }
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // The feed opens a note through GlassMorph's card-to-screen route.
        home: Scaffold(
          body: Center(
            child: GlassMorph(
              openBuilder: (_) => noteScreen(first),
              closedBuilder: (context, open) => TextButton(
                onPressed: open,
                child: const Text('Home: open Trip'),
              ),
            ),
          ),
        ),
      ),
    ));
    return (state, first);
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  /// Android's back (gesture or button).
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  // Home stays painted under a note opened from it (that route is see-through
  // while it animates), so "on top" means "receives taps". The feed card also
  // ignores taps while hidden, so onHome() checks that it is showing again.
  bool onHome() =>
      find.text('Home: open Trip').hitTestable().evaluate().isNotEmpty;
  bool onMap() => find.byType(CircuitMapScreen).evaluate().isNotEmpty;

  /// The note screen on top, by the text of its body.
  bool reading(String text) =>
      !onMap() && find.textContaining(text).hitTestable().evaluate().isNotEmpty;

  Future<void> openFirstNoteThenMap(WidgetTester tester) async {
    await tester.tap(find.text('Home: open Trip'));
    await tester.pumpAndSettle();
    expect(reading('The plan'), isTrue);
    await tester.tap(find.byTooltip('Circuit map'));
    await tester.pumpAndSettle();
    expect(onMap(), isTrue);
  }

  /// Taps [title]'s node on the map (not the map's own title, which can
  /// read the same).
  Future<void> openFromMap(WidgetTester tester, String title) async {
    await tester.tap(find.text(title).hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('map → note → back lands on the map, however many trips',
      (tester) async {
    final (state, _) = await pumpHome(tester);
    await openFirstNoteThenMap(tester);

    for (final (title, text) in [
      ('Note #1', 'Flights'),
      ('Note #2', 'Hotels'),
      ('Note #1', 'Flights'),
    ]) {
      await openFromMap(tester, title);
      expect(reading(text), isTrue, reason: 'opened $title from the map');
      await back(tester);
      expect(onMap(), isTrue, reason: 'back from $title');
    }

    await back(tester);
    expect(reading('The plan'), isTrue, reason: 'back from the map');
    await back(tester);
    expect(onHome(), isTrue, reason: 'back from the first note');
    await close(tester, state);
  });

  testWidgets('the first note opened from the map also comes back to it',
      (tester) async {
    final (state, _) = await pumpHome(tester);
    await openFirstNoteThenMap(tester);

    // Tapping the first note on the map used to return to its screen under
    // the map, closing the map; now it opens above the map like any note.
    await openFromMap(tester, 'Trip');
    expect(reading('The plan'), isTrue);
    await back(tester);
    expect(onMap(), isTrue, reason: 'back from the first note');

    // Other trips keep working, and back still runs map → first note → Home.
    await openFromMap(tester, 'Note #2');
    await back(tester);
    expect(onMap(), isTrue);
    await back(tester);
    expect(reading('The plan'), isTrue, reason: 'back from the map');
    await back(tester);
    expect(onHome(), isTrue, reason: 'back from the first note');
    await close(tester, state);
  });

  testWidgets('a link followed in a note from the map also comes back to it',
      (tester) async {
    final (state, _) = await pumpHome(tester);
    await openFirstNoteThenMap(tester);

    await openFromMap(tester, 'Note #1');
    expect(reading('Flights'), isTrue);
    // Note #1 links to Note #2; following it opens Note #2 in its place.
    await tester.tapOnText(find.textRange.ofSubstring('Note #2').first);
    await tester.pumpAndSettle();
    expect(reading('Hotels'), isTrue);
    await back(tester);
    expect(onMap(), isTrue, reason: 'back from the linked note');
    await back(tester);
    expect(reading('The plan'), isTrue);
    await close(tester, state);
  });

  testWidgets('a map opened from Home goes back via the first note',
      (tester) async {
    final (state, first) = await pumpHome(tester);
    // As after importing a circuit: the map opens straight over Home.
    final home = tester.element(find.text('Home: open Trip'));
    Navigator.of(home).push(MaterialPageRoute(
        builder: (_) => CircuitMapScreen(circuitId: first.id)));
    await tester.pumpAndSettle();
    expect(onMap(), isTrue);

    await openFromMap(tester, 'Note #1');
    await back(tester);
    expect(onMap(), isTrue);
    await back(tester);
    expect(reading('The plan'), isTrue, reason: 'back from the map');
    await back(tester);
    expect(onHome(), isTrue, reason: 'back from the first note');
    await close(tester, state);
  });
}
