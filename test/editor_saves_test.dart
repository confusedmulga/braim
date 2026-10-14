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

/// The note screens keep what was typed, and change nothing while reading.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_editor_saves_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<NoteBlock> body(String text) => [
    NoteBlock(
      type: NoteBlockType.text,
      text: jsonEncode([
        {'insert': '$text\n'},
      ]),
    ),
  ];

  List<NoteBlock> source(String text) => [
    NoteBlock(type: NoteBlockType.text, text: text),
  ];

  final navKey = GlobalKey<NavigatorState>();

  /// Opens [screen] as a route over a blank home, so it can pop.
  Future<AppState> open(
    WidgetTester tester,
    Widget Function(AppState) screen, {
    List<Note> notes = const [],
  }) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await tester.runAsync(
      () => StorageService.instance.save(
        AppData(notes: notes, spaces: const [], cards: const []),
      ),
    );
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          navigatorKey: navKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => screen(state)),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  }

  /// Home pressed: the app goes inactive, then hidden.
  void hideApp(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }

  void showApp(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('the Markdown editor saves its source when the app is hidden', (
    tester,
  ) async {
    final note = Note(
      id: 'm',
      title: 'Doc',
      markdown: true,
      blocks: source('# Doc'),
    );
    final state = await open(
      tester,
      (s) => MarkdownNoteScreen(note: s.noteById('m')!, startEditing: true),
      notes: [note],
    );
    final before = state.revision;
    await tester.enterText(find.byType(TextField), '# Doc\n\nNew paragraph');
    await tester.pump();

    hideApp(tester);
    await tester.pump();
    expect(state.noteById('m')!.markdownSource, '# Doc\n\nNew paragraph');
    expect(state.revision, greaterThan(before));

    showApp(tester);
    await close(tester, state);
  });

  testWidgets('the rich editor collects what was typed when the app is hidden', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Shopping', blocks: body('Milk'));
    final state = await open(
      tester,
      (s) => NoteEditorScreen(
        note: s.noteById('n')!,
        isNew: false,
        startEditing: true,
      ),
      notes: [note],
    );
    final before = state.revision;
    await tester.enterText(find.byType(TextField).first, 'Groceries');
    await tester.pump();

    hideApp(tester);
    await tester.pump();
    expect(state.noteById('n')!.title, 'Groceries');
    expect(state.revision, greaterThan(before));

    showApp(tester);
    await close(tester, state);
  });

  testWidgets('archiving a note being read is saved', (tester) async {
    final note = Note(id: 'n', title: 'Shopping', blocks: body('Milk'));
    final state = await open(
      tester,
      (s) => NoteEditorScreen(note: s.noteById('n')!, isNew: false),
      notes: [note],
    );
    final before = state.revision;
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(state.revision, greaterThan(before));
    expect(state.notes.any((n) => n.id == 'n'), isFalse);
    expect(state.archivedNotes.any((n) => n.id == 'n'), isTrue);
    await close(tester, state);
  });

  testWidgets('the map button of a Markdown note being read keeps newer text', (
    tester,
  ) async {
    final rootNote = Note(id: 'r', title: 'Plan', blocks: body('x'), circuitId: 'r');
    final branch = Note(
      id: 'm',
      title: 'Note #1',
      markdown: true,
      blocks: source('# Note #1\n\nold'),
      circuitId: 'r',
      circuitParentId: 'r',
    );
    final state = await open(
      tester,
      (s) => MarkdownNoteScreen(note: s.noteById('m')!, startEditing: true),
      notes: [rootNote, branch],
    );
    // Written on the phone, then back to reading.
    await tester.tap(find.byKey(const ValueKey('md-done')));
    await tester.pumpAndSettle();
    // Braim Web saves a new source on the live note while the phone reads.
    final live = state.noteById('m')!;
    live.blocks = source('# Note #1\n\nfrom the browser');
    await tester.runAsync(() => state.upsertNote(live));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.account_tree_rounded));
    await tester.pump();
    expect(state.noteById('m')!.markdownSource, '# Note #1\n\nfrom the browser');

    await tester.pumpAndSettle();
    await close(tester, state);
  });

  testWidgets('emptying a saved Markdown note and tapping done leaves it', (
    tester,
  ) async {
    final note = Note(
      id: 'm',
      title: 'Doc',
      markdown: true,
      blocks: source('# Doc'),
    );
    final state = await open(
      tester,
      (s) => MarkdownNoteScreen(note: s.noteById('m')!, startEditing: true),
      notes: [note],
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(const ValueKey('md-done')));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownNoteScreen), findsNothing);
    expect(state.noteById('m')!.deletedAt, isNotNull);
    await close(tester, state);
  });

  testWidgets('a note deleted elsewhere while read is not edited', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Shopping', blocks: body('Milk'));
    final state = await open(
      tester,
      (s) => NoteEditorScreen(note: s.noteById('n')!, isNew: false),
      notes: [note],
    );
    // Braim Web deletes the note while the phone shows it.
    await tester.runAsync(() => state.deleteNote('n'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(state.editLeaseHolder('n'), isNull);
    await close(tester, state);
  });

  testWidgets('a Markdown note deleted elsewhere while read is not edited', (
    tester,
  ) async {
    final note = Note(
      id: 'm',
      title: 'Doc',
      markdown: true,
      blocks: source('# Doc'),
    );
    final state = await open(
      tester,
      (s) => MarkdownNoteScreen(note: s.noteById('m')!),
      notes: [note],
    );
    await tester.runAsync(() => state.deleteNote('m'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('md-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownNoteScreen), findsNothing);
    expect(state.editLeaseHolder('m'), isNull);
    await close(tester, state);
  });

  testWidgets('a book note left empty is removed', (tester) async {
    final state = await open(tester, (s) => const SizedBox());
    // The workshop's + adds the note to the library before opening it.
    final draft = (await tester.runAsync(() => state.addBookNote('book-1')))!;
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(note: draft, isNew: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.noteById(draft.id), isNull);
    await close(tester, state);
  });
}
