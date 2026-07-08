import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:keepy/models/note.dart';
import 'package:keepy/models/space.dart';
import 'package:keepy/models/tweet_card.dart';
import 'package:keepy/services/storage_service.dart';
import 'package:keepy/state/app_state.dart';

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
    root = Directory.systemTemp.createTempSync('braim_state_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // Fresh data file per test.
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    final inbox = Directory('${root.path}/share_inbox');
    if (inbox.existsSync()) inbox.deleteSync(recursive: true);
  });

  Future<AppState> boot(AppData data) async {
    await StorageService.instance.save(data);
    final state = AppState();
    await state.init();
    return state;
  }

  test('feeds exclude archived, deleted and crypt items', () async {
    final state = await boot(AppData(
      notes: [
        Note(title: 'plain'),
        Note(title: 'archived', archived: true),
        Note(title: 'deleted', deletedAt: DateTime.now()),
        Note(title: 'crypt', spaceId: kCryptSpaceId),
      ],
      spaces: [
        Space(name: 'live'),
        Space(name: 'archived', archived: true),
        Space(name: 'deleted', deletedAt: DateTime.now()),
      ],
      cards: [
        TweetCard(url: 'https://a.com/1'),
        TweetCard(url: 'https://a.com/2', archived: true),
        TweetCard(url: 'https://a.com/3', deletedAt: DateTime.now()),
        TweetCard(url: 'https://a.com/4', spaceId: kCryptSpaceId),
      ],
    ));

    expect(state.notes.map((n) => n.title), ['plain']);
    expect(state.archivedNotes.map((n) => n.title), ['archived']);
    expect(state.deletedNotes.map((n) => n.title), ['deleted']);
    expect(state.spaces.map((s) => s.name), ['live']);
    expect(state.cards.length, 1);
    expect(state.archivedCards.length, 1);
    expect(state.deletedCards.length, 1);
  });

  test('pinned items sort first; pin limit enforced at $kMaxPins', () async {
    final notes = [
      for (var i = 0; i < kMaxPins; i++)
        Note(title: 'pinned$i', pinned: true),
      Note(title: 'unpinned'),
    ];
    final state = await boot(AppData(notes: notes, spaces: [], cards: []));

    expect(state.notes.first.pinned, isTrue);
    expect(state.notes.last.title, 'unpinned');

    final extra = state.notes.last;
    expect(await state.setNotePinned(extra.id, true), isFalse,
        reason: 'limit reached');

    await state.setNotePinned(state.notes.first.id, false);
    expect(await state.setNotePinned(extra.id, true), isTrue);
  });

  test('expired trash purges notes, cards and folders on init', () async {
    final old = DateTime.now().subtract(const Duration(days: 31));
    final fresh = DateTime.now().subtract(const Duration(days: 5));
    final expiredSpace = Space(name: 'gone', deletedAt: old);
    final state = await boot(AppData(
      notes: [
        Note(title: 'old', deletedAt: old),
        Note(title: 'fresh', deletedAt: fresh),
        Note(title: 'inGoneFolder', spaceId: expiredSpace.id),
      ],
      spaces: [expiredSpace],
      cards: [TweetCard(url: 'https://x.com/old', deletedAt: old)],
    ));

    expect(state.deletedNotes.map((n) => n.title), ['fresh']);
    expect(state.deletedCards, isEmpty);
    expect(state.deletedSpaces, isEmpty);
    // Contents of a purged folder fall back to no folder.
    expect(
        state.notes.singleWhere((n) => n.title == 'inGoneFolder').spaceId,
        isNull);
  });

  test('writes are coalesced and flushNow persists everything', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    await state.addCardFromUrl('https://a.com/1');
    await state.addCardFromUrl('https://a.com/2');
    await state.addCardFromUrl('https://a.com/3');

    // Debounced: the file should not have been rewritten yet.
    final before = await StorageService.instance.load();
    expect(before.cards, isEmpty, reason: 'write is coalesced, not immediate');

    await state.flushNow();
    final after = await StorageService.instance.load();
    expect(after.cards.length, 3);
  });

  test('addCardFromUrl merges duplicates on normalized URL', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    await state.addCardFromUrl('https://Example.com/Post/');
    final again =
        await state.addCardFromUrl('https://example.com/Post', spaceId: 'f1');

    expect(state.cards.length, 1);
    expect(again.spaceId, 'f1', reason: 'merge adopts the requested folder');
    await state.flushNow(); // drain the debounce so it can't pollute the next test
  });

  test('backup reminder: overdue only with content and stale/absent backup',
      () async {
    // Empty library: nothing worth nudging about.
    final empty = await boot(AppData(notes: [], spaces: [], cards: []));
    expect(empty.backupOverdue, isFalse);

    // Has content, never backed up.
    final withNote = await boot(AppData(
        notes: [Note(title: 'keep me')], spaces: [], cards: []));
    expect(withNote.backupOverdue, isTrue);

    // A recent backup clears it; the flag persists across a reload.
    await withNote.markBackedUp();
    await withNote.flushNow(); // land the write before reloading from disk
    expect(withNote.backupOverdue, isFalse);
    final reloaded = AppState();
    await reloaded.init();
    expect(reloaded.lastBackupAt, isNotNull);
    expect(reloaded.backupOverdue, isFalse);

    // A backup older than the threshold is overdue again.
    final stale = await boot(AppData(
        notes: [Note(title: 'old')],
        spaces: [],
        cards: [],
        lastBackupAt: DateTime.now().subtract(const Duration(days: 40))));
    expect(stale.backupOverdue, isTrue);
  });

  test('note colorValue round-trips through storage', () async {
    final n = Note(title: 'tinted', colorValue: 0xFFFFF1B8);
    final state = await boot(AppData(notes: [n], spaces: [], cards: []));
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.notes.single.colorValue, 0xFFFFF1B8);
  });
}
