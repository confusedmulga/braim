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
import 'package:braim/models/tweet_card.dart';
import 'package:braim/screens/card_detail_screen.dart';
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

/// The phone's editors and Braim Web's edit leases (plan section 11).
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_phone_lease_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  const browser = 'web:session-1';
  const editingOnComputer = 'Being edited on your computer';

  List<NoteBlock> body(String text) => [
    NoteBlock(
      type: NoteBlockType.text,
      text: jsonEncode([
        {'insert': '$text\n'},
      ]),
    ),
  ];

  Future<AppState> pumpWith(
    WidgetTester tester,
    Widget Function(AppState) screen, {
    List<Note> notes = const [],
    List<TweetCard> cards = const [],
  }) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await tester.runAsync(
      () => StorageService.instance.save(
        AppData(notes: notes, spaces: const [], cards: cards),
      ),
    );
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Builder(builder: (_) => screen(state))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// The refusal's snackbar sits over the edit button; let it time out.
  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    state.dispose();
  }

  testWidgets('the note editor stays in reading while a browser edits', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Shopping', blocks: body('Milk'));
    final state = await pumpWith(
      tester,
      (s) => NoteEditorScreen(note: s.noteById('n')!, isNew: false),
      notes: [note],
    );
    expect(state.acquireEditLease('n', browser), isTrue);

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(find.text(editingOnComputer), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing); // still reading
    expect(state.editLeaseHolder('n'), browser);

    // Once the browser lets go, the phone takes the lease to write...
    state.releaseEditLease('n', browser);
    await dismissSnackBar(tester);
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(state.editLeaseHolder('n'), kPhoneLease);
    expect(state.acquireEditLease('n', browser), isFalse);

    // ...and hands it back when done.
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(state.editLeaseHolder('n'), isNull);
    await close(tester, state);
  });

  testWidgets('a note that would open straight into editing opens to read', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Note #1', blocks: body('x'));
    final state = await pumpWith(tester, (s) {
      s.acquireEditLease('n', browser);
      return NoteEditorScreen(
        note: s.noteById('n')!,
        isNew: false,
        startEditing: true,
      );
    }, notes: [note]);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text(editingOnComputer), findsOneWidget);
    expect(state.editLeaseHolder('n'), browser);
    await close(tester, state);
  });

  testWidgets('closing the editor releases the lease once the note is saved', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Shopping', blocks: body('Milk'));
    final state = await pumpWith(
      tester,
      (s) => NoteEditorScreen(
        note: s.noteById('n')!,
        isNew: false,
        startEditing: true,
      ),
      notes: [note],
    );
    expect(state.editLeaseHolder('n'), kPhoneLease);
    await close(tester, state);
    expect(state.editLeaseHolder('n'), isNull);
  });

  testWidgets('a rename from the browser survives the phone editing after it', (
    tester,
  ) async {
    final note = Note(id: 'n', title: 'Old title', blocks: body('Milk'));
    final state = await pumpWith(
      tester,
      (s) => NoteEditorScreen(note: s.noteById('n')!, isNew: false),
      notes: [note],
    );
    // Braim Web saves a new title on the live note while the phone reads.
    final live = state.noteById('n')!;
    live.title = 'New title';
    await tester.runAsync(() => state.upsertNote(live));
    await tester.pumpAndSettle();
    expect(find.text('New title'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(state.noteById('n')!.title, 'New title');
    await close(tester, state);
  });

  testWidgets('the Markdown screen stays in reading while a browser edits', (
    tester,
  ) async {
    final note = Note(
      id: 'm',
      title: 'Doc',
      markdown: true,
      blocks: [NoteBlock(type: NoteBlockType.text, text: '# Doc\n\nbody')],
    );
    final state = await pumpWith(tester, (s) {
      s.acquireEditLease('m', browser);
      return MarkdownNoteScreen(note: s.noteById('m')!, startEditing: true);
    }, notes: [note]);
    expect(find.text(editingOnComputer), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // no source editor
    expect(state.editLeaseHolder('m'), browser);
    await close(tester, state);
  });

  testWidgets('the spark screen stays in reading while a browser edits', (
    tester,
  ) async {
    final card = TweetCard(
      id: 'c',
      url: 'https://example.com',
      noteTitle: 'Saved',
      blocks: body('note'),
    );
    final state = await pumpWith(
      tester,
      (s) => CardDetailScreen(card: s.cardById('c')!),
      cards: [card],
    );
    expect(state.acquireEditLease('c', browser), isTrue);
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(find.text(editingOnComputer), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    state.releaseEditLease('c', browser);
    await dismissSnackBar(tester);
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    expect(state.editLeaseHolder('c'), kPhoneLease);
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(state.editLeaseHolder('c'), isNull);
    await close(tester, state);
  });
}
