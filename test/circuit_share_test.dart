import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/circuit_file.dart';
import 'package:braim/services/note_markdown.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/widgets/circuit_sheets.dart';
import 'package:braim/widgets/share_as.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

List<NoteBlock> _body(String text) => [
      NoteBlock(
          type: NoteBlockType.text,
          text: jsonEncode([
            {'insert': '$text\n'}
          ])),
    ];

void main() {
  group('circuitOutline', () {
    // Trip
    // ├─ Flights (with a bold line)
    // │  └─ (placeholder)
    // │     └─ Seats
    // └─ Packing (a Markdown note opening with its own # heading)
    final root = Note(title: 'Trip', blocks: _body('The plan'))
      ..circuitId = 'root';
    final flights = Note(title: 'Flights', blocks: _body('Book early'));
    final slot = Note(title: '')..circuitPlaceholder = true;
    final seats = Note(title: 'Seats', blocks: _body('Aisle'));
    final packing = Note(title: 'Packing', markdown: true, blocks: [
      NoteBlock(type: NoteBlockType.text, text: '# Packing\n\n- Passport'),
    ]);
    final tree = {
      root.id: [flights, packing],
      flights.id: [slot],
      slot.id: [seats],
    };
    List<Note> children(String id) => tree[id] ?? const [];

    String outline(Note from) => circuitOutline(from, children,
        untitledCircuit: 'Untitled circuit', untitledNote: 'Untitled');

    test('from the first note: every note, by depth, with its text', () {
      final rootWithId = root..circuitId = root.id;
      expect(outline(rootWithId), '''# Trip

The plan

## Flights

Book early

### Seats

Aisle

## Packing

- Passport''');
    });

    test('from a branch: that branch and what is under it', () {
      expect(outline(flights), '# Flights\n\nBook early\n\n## Seats\n\nAisle');
    });

    test("a Markdown note's own leading heading isn't repeated", () {
      expect(noteBodyToMarkdown(packing), '- Passport');
    });
  });

  group('sharing a circuit', () {
    late Directory dir;
    final calls = <Map<Object?, Object?>>[];

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('braim_circuit_share_test');
      Directory('${dir.path}/tmp').createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProvider(dir.path);
    });

    tearDownAll(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<(AppState, Note, BuildContext)> pumpCircuit(
        WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.fluttercommunity.plus/share'),
              (call) async {
        calls.add(call.arguments as Map<Object?, Object?>);
        return 'done';
      });
      calls.clear();
      final state = AppState();
      await tester.runAsync(state.init);
      late Note root;
      await tester.runAsync(() async {
        root = state.newCircuitRootDraft()
          ..title = 'Trip'
          ..blocks = _body('The plan');
        await state.ensureCircuitRootSaved(root);
        await state.upsertNote(root);
        for (final line in ['Flights', 'Hotels']) {
          final branch = await state.addCircuitChild(root.id);
          branch
            ..title = line
            ..blocks = _body('About $line');
          await state.upsertNote(branch);
        }
      });
      late BuildContext page;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Builder(builder: (context) {
            page = context;
            return const SizedBox();
          })),
        ),
      ));
      return (state, root, page);
    }

    Future<void> tidy(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(state.flushNow);
      state.dispose();
    }

    testWidgets('as Markdown from the first note: the whole circuit',
        (tester) async {
      final (state, root, page) = await pumpCircuit(tester);
      await tester.runAsync(
          () => shareCircuitAs(page, root, ShareFormat.markdown));
      final path = (calls.single['paths'] as List).single as String;
      expect(path, endsWith('Trip.md'));
      final text = File(path).readAsStringSync();
      expect(text, contains('# Trip'));
      expect(text, contains('## Flights\n\nAbout Flights'));
      expect(text, contains('## Hotels\n\nAbout Hotels'));
      await tidy(tester, state);
    });

    testWidgets(
        'as a circuit: a .braim file with its own type, not octet-stream',
        (tester) async {
      final (state, root, page) = await pumpCircuit(tester);
      final branch = state.circuitChildren(root.id).first;
      // From a branch, too: the file is always the whole circuit.
      await tester.runAsync(
          () => shareCircuitAs(page, branch, ShareFormat.circuit));
      final call = calls.single;
      expect((call['paths'] as List).single as String, endsWith('Trip.braim'));
      expect(call['mimeTypes'], [CircuitFile.mimeType]);
      expect(CircuitFile.mimeType, isNot('application/octet-stream'));
      await tidy(tester, state);
    });
  });

  group('looksLikeCircuitFile', () {
    late Directory dir;
    setUpAll(() => dir = Directory.systemTemp.createTempSync('braim_looks'));
    tearDownAll(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('by its type, its name, or by being a zip', () async {
      final renamed = File('${dir.path}/Trip.bin')
        ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, 0, 0]);
      final markdown = File('${dir.path}/Notes.md')
        ..writeAsStringSync('# Notes');
      expect(
          await looksLikeCircuitFile('${dir.path}/x',
              mimeType: CircuitFile.mimeType),
          isTrue);
      expect(await looksLikeCircuitFile('${dir.path}/Trip.BRAIM'), isTrue);
      // Renamed on the way ("Trip.bin"), still a zip inside.
      expect(await looksLikeCircuitFile(renamed.path), isTrue);
      expect(await looksLikeCircuitFile(markdown.path), isFalse);
      expect(await looksLikeCircuitFile('${dir.path}/missing'), isFalse);
    });
  });

  testWidgets('a circuit menu offers the whole circuit after the others',
      (tester) async {
    final shared = <ShareFormat>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ShareAsTile(formats: ShareFormat.forCircuit, onShare: shared.add),
      ),
    ));
    await tester.tap(find.text('.md'));
    await tester.pumpAndSettle();
    expect(find.text('Whole circuit (.braim)'), findsOneWidget);
    await tester.tap(find.text('Whole circuit (.braim)'));
    await tester.pumpAndSettle();
    expect(shared, [ShareFormat.circuit]);
  });
}
