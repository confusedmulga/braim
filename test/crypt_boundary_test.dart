import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/space.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/screens/recently_deleted_screen.dart';
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

/// What is kept in the Crypt stays there, and stays reachable from there.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_crypt_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  Future<AppState> boot(AppData data) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(data);
    final state = AppState();
    states.add(state);
    await state.init();
    return state;
  }

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  test('saving a link already kept in the Crypt leaves the Crypt copy alone',
      () async {
    final hidden = TweetCard(
      id: 'c',
      url: 'https://example.com/a',
      spaceId: kCryptSpaceId,
    );
    final state = await boot(AppData(
      notes: [],
      spaces: [Space(id: 'reading', name: 'Reading')],
      cards: [hidden],
    ));

    final saved =
        await state.addCardFromUrl('https://example.com/a', spaceId: 'reading');
    expect(saved.id, isNot('c'));
    expect(saved.spaceId, 'reading');
    expect(state.cardById('c')!.spaceId, kCryptSpaceId);
    expect(state.cards.any((c) => c.id == 'c'), isFalse);
  });

  test('an item archived inside the Crypt can still be found there', () async {
    final note = Note(id: 'n', title: 'Private', spaceId: kCryptSpaceId);
    final card = TweetCard(
      id: 'c',
      url: 'https://example.com/b',
      spaceId: kCryptSpaceId,
    );
    final state = await boot(AppData(notes: [note], spaces: [], cards: [card]));

    await state.setNoteArchived('n', true);
    await state.setCardArchived('c', true);
    expect(state.notesForSpace(kCryptSpaceId).map((n) => n.id), ['n']);
    expect(state.cardsForSpace(kCryptSpaceId).map((c) => c.id), ['c']);
    // Still nowhere outside it.
    expect(state.archivedNotes.any((n) => n.id == 'n'), isFalse);
  });

  test('emptying the trash while the Crypt is locked keeps its items',
      () async {
    final state = await boot(AppData(
      notes: [
        Note(id: 'open', title: 'Groceries'),
        Note(id: 'secret', title: 'Private', spaceId: kCryptSpaceId),
      ],
      spaces: [],
      cards: [],
    ));
    await state.deleteNote('open');
    await state.deleteNote('secret');
    await state.emptyTrash(keepCrypt: true);
    expect(state.noteById('open'), isNull);
    expect(state.noteById('secret')!.deletedAt, isNotNull);
  });

  testWidgets('Recently Deleted keeps Crypt items out of sight until unlocked',
      (tester) async {
    final state = (await tester.runAsync(() => boot(AppData(
          notes: [
            Note(id: 'open', title: 'Groceries'),
            Note(id: 'secret', title: 'Private plans', spaceId: kCryptSpaceId),
          ],
          spaces: [],
          cards: [],
        ))))!;
    await tester.runAsync(() async {
      await state.deleteNote('open');
      await state.deleteNote('secret');
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RecentlyDeletedScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Private plans'), findsNothing);
    expect(find.text('1 item from the Crypt'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
