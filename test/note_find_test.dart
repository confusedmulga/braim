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
import 'package:braim/screens/markdown_note_screen.dart';
import 'package:braim/screens/note_editor_screen.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/widgets/find_bar.dart';
import 'package:braim/widgets/markdown_view.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// The marker on the current match (the stronger of the two find colours).
final _current = find.byWidgetPredicate((w) =>
    w is Text && w.style?.backgroundColor == const Color(0xFFFFA726));

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_note_find_test');
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

  Future<AppState> pumpScreen(
      WidgetTester tester, Note note, Widget Function(Note) screen) async {
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.runAsync(() => state.upsertNote(note));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen(note),
      ),
    ));
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> tidy(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(state.flushNow);
    state.dispose();
  }

  Note richNote(String text) => Note(
        title: 'Orchard',
        blocks: [
          NoteBlock(
              type: NoteBlockType.text,
              text: jsonEncode([
                {'insert': '$text\n'}
              ])),
        ],
      );

  Future<void> openFind(WidgetTester tester, String query) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in note'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(FindBar), matching: find.byType(TextField)),
        query);
    await tester.pumpAndSettle();
  }

  testWidgets('a note being read: count, step through, close',
      (tester) async {
    final state = await pumpScreen(
        tester,
        richNote('Apple pie, apple tart\nAn APPLE a day'),
        (n) => NoteEditorScreen(note: n, isNew: false));

    await openFind(tester, 'apple');
    expect(find.text('1 of 3'), findsOneWidget);
    expect(tester.widget<Text>(_current).data, 'Apple');

    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(tester.widget<Text>(_current).data, 'apple');

    // Previous from the first wraps round to the last.
    await tester.tap(find.byTooltip('Previous match'));
    await tester.tap(find.byTooltip('Previous match'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(tester.widget<Text>(_current).data, 'APPLE');

    await tester.enterText(
        find.descendant(
            of: find.byType(FindBar), matching: find.byType(TextField)),
        'pear');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    // Back closes Find, not the note.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsNothing);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await tidy(tester, state);
  });

  testWidgets('a note being written: the match is selected in the editor',
      (tester) async {
    final state = await pumpScreen(
        tester,
        richNote('Apple pie, apple tart'),
        (n) => NoteEditorScreen(note: n, isNew: false, startEditing: true));

    await openFind(tester, 'apple');
    expect(find.text('1 of 2'), findsOneWidget);
    QuillController controller() =>
        tester.widget<QuillEditor>(find.byType(QuillEditor).first).controller;
    expect(controller().selection,
        const TextSelection(baseOffset: 0, extentOffset: 5));

    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(controller().selection,
        const TextSelection(baseOffset: 11, extentOffset: 16));
    // The keyboard stays with the Find field.
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byType(FindBar), matching: find.byType(TextField)))
            .focusNode!
            .hasFocus,
        isTrue);

    // Closing leaves the caret at the match, nothing selected.
    await tester.tap(find.byTooltip('Close find'));
    await tester.pumpAndSettle();
    expect(controller().selection, const TextSelection.collapsed(offset: 16));
    await tidy(tester, state);
  });

  testWidgets('a Markdown note: Find in note from its menu', (tester) async {
    final note = Note(
      title: 'Readme',
      markdown: true,
      blocks: [
        NoteBlock(
            type: NoteBlockType.text,
            text: '# Setup\n\nRun **setup** first.\n\n```\nsetup.sh\n```\n'),
      ],
    );
    final state =
        await pumpScreen(tester, note, (n) => MarkdownNoteScreen(note: n));

    await openFind(tester, 'setup');
    // The heading and the prose; the code is shown verbatim, not searched.
    expect(find.text('1 of 2'), findsOneWidget);
    expect(_current, findsOneWidget);
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    await tidy(tester, state);
  });

  testWidgets('a book page has the dictionary beside the 3 dots',
      (tester) async {
    final page = richNote('Once upon a time')..bookId = 'book-1';
    final state =
        await pumpScreen(tester, page, (n) => NoteEditorScreen(note: n, isNew: false));
    expect(find.byTooltip('Dictionary'), findsOneWidget);
    await tidy(tester, state);

    final plain = await pumpScreen(
        tester, richNote('Just a note'), (n) => NoteEditorScreen(note: n, isNew: false));
    expect(find.byTooltip('Dictionary'), findsNothing);
    await tidy(tester, plain);
  });

  group('MarkdownView', () {
    testWidgets('jumps to a match far down a long document', (tester) async {
      int? total;
      final key = GlobalKey();
      final source = [
        for (var i = 0; i < 400; i++) 'Paragraph $i of filler.',
        'The needle is here.',
      ].join('\n\n');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownView(source,
              find: FindHighlight('needle', 0, key),
              onFindTotal: (n) => total = n),
        ),
      ));
      await tester.pumpAndSettle();
      expect(total, 1);
      expect(key.currentContext, isNotNull);
      expect(find.textContaining('Paragraph 0 of'), findsNothing);
    });
  });
}
