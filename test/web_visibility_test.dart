import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/book.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/space.dart';
import 'package:braim/models/tweet_card.dart';
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

NoteBlock _image(String name) =>
    NoteBlock(type: NoteBlockType.image, imagePath: '/data/app/images/$name');

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_visibility_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  setUp(() {
    for (final name in [
      'keepy_data.json',
      'keepy_data.bak',
      'keepy_json_ahead',
    ]) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  });

  Future<AppState> boot(AppData data) async {
    await StorageService.instance.save(data);
    final state = AppState();
    states.add(state);
    await state.init();
    return state;
  }

  /// One of everything the web must show or refuse.
  Future<AppState> library() => boot(
    AppData(
      notes: [
        Note(
          id: 'plain',
          title: 'Plain',
          tags: ['x'],
          blocks: [_image('plain.jpg')],
        ),
        Note(id: 'other', title: 'Other', tags: ['y']),
        Note(
          id: 'crypt',
          title: 'Secret',
          spaceId: kCryptSpaceId,
          blocks: [_image('crypt.jpg')],
        ),
        Note(
          id: 'deleted',
          title: 'Gone',
          deletedAt: DateTime.now(),
          blocks: [_image('deleted.jpg')],
        ),
        Note(
          id: 'archived',
          title: 'Old',
          archived: true,
          blocks: [_image('archived.jpg')],
        ),
        Note(
          id: 'journal',
          title: 'Dear diary',
          journalDate: '2026-09-30',
          blocks: [_image('journal.jpg')],
        ),
        Note(id: 'hidden', title: 'In a hidden fold', spaceId: 'fold'),
        // A circuit: first note, a branch, and a placeholder with a child.
        Note(id: 'root', title: 'Trip')..circuitId = 'root',
        Note(id: 'branch', title: 'Note #1', blocks: [_image('branch.jpg')])
          ..circuitId = 'root'
          ..circuitParentId = 'root',
        Note(id: 'slot', title: 'Placeholder #1')
          ..circuitId = 'root'
          ..circuitParentId = 'root'
          ..circuitOrder = 1
          ..circuitPlaceholder = true,
        Note(id: 'under-slot', title: 'Note #2')
          ..circuitId = 'root'
          ..circuitParentId = 'slot',
        // A circuit whose first note is in the Crypt hides its branches.
        Note(id: 'croot', title: 'Hidden trip', spaceId: kCryptSpaceId)
          ..circuitId = 'croot',
        Note(id: 'cbranch', title: 'Note #1', blocks: [_image('cbranch.jpg')])
          ..circuitId = 'croot'
          ..circuitParentId = 'croot',
        // Pages of a live book, and of an archived one.
        Note(
          id: 'contents',
          title: 'Contents',
          bookId: 'book',
          bookPageKind: BookPageKind.contents,
          bookOrder: 0,
        ),
        Note(
          id: 'chapter',
          title: 'Chapter I',
          bookId: 'book',
          bookPageKind: BookPageKind.chapter,
          bookOrder: 1,
          blocks: [_image('chapter.jpg')],
        ),
        Note(
          id: 'workshop',
          title: 'Characters',
          bookId: 'book',
          bookPageKind: BookPageKind.note,
        ),
        Note(
          id: 'deleted-page',
          title: 'Chapter II',
          bookId: 'book',
          bookPageKind: BookPageKind.chapter,
          bookOrder: 2,
          deletedAt: DateTime.now(),
        ),
        Note(
          id: 'shelved-page',
          title: 'Chapter I',
          bookId: 'shelved',
          bookPageKind: BookPageKind.chapter,
          blocks: [_image('shelved-page.jpg')],
        ),
      ],
      spaces: [Space(id: 'fold', name: 'Private-ish', hiddenFromFeed: true)],
      cards: [
        TweetCard(
          id: 'card',
          url: 'https://example.com/a',
          blocks: [_image('card.jpg')],
        ),
        TweetCard(
          id: 'crypt-card',
          url: 'https://example.com/b',
          spaceId: kCryptSpaceId,
          blocks: [_image('crypt-card.jpg')],
        ),
        TweetCard(
          id: 'archived-card',
          url: 'https://example.com/c',
          archived: true,
          blocks: [_image('archived-card.jpg')],
        ),
      ],
      books: [
        Book(
          id: 'book',
          title: 'Novel',
          coverPath: '/data/app/images/cover.jpg',
        ),
        Book(
          id: 'shelved',
          title: 'Shelved',
          archived: true,
          coverPath: '/data/app/images/shelved-cover.jpg',
        ),
      ],
    ),
  );

  test('isWebVisibleNote refuses Crypt, deleted, archived, journal and '
      'placeholder notes and accepts live book pages', () async {
    final s = await library();
    bool visible(String id) => s.isWebVisibleNote(s.noteById(id)!);

    expect(visible('plain'), isTrue);
    expect(visible('crypt'), isFalse);
    expect(visible('deleted'), isFalse);
    expect(visible('archived'), isFalse);
    expect(visible('journal'), isFalse);
    expect(visible('slot'), isFalse);

    // Circuit branches are visible (as in search), unless the circuit's first
    // note is hidden.
    expect(visible('root'), isTrue);
    expect(visible('branch'), isTrue);
    expect(visible('under-slot'), isTrue);
    expect(visible('croot'), isFalse);
    expect(visible('cbranch'), isFalse);

    // Hidden folds keep notes out of the feed, not out of reach.
    expect(visible('hidden'), isTrue);

    // Books: manuscript pages of a live book only.
    expect(visible('contents'), isTrue);
    expect(visible('chapter'), isTrue);
    expect(visible('workshop'), isFalse);
    expect(visible('deleted-page'), isFalse);
    expect(visible('shelved-page'), isFalse);
  });

  test('a note moved to the Crypt stops being visible', () async {
    final s = await library();
    await s.moveNoteToSpace('plain', kCryptSpaceId);
    expect(s.isWebVisibleNote(s.noteById('plain')!), isFalse);
    expect(s.webFeedNotes.map((n) => n.id), isNot(contains('plain')));
  });

  test('webFeedNotes ignores the phone\'s tag filter', () async {
    final s = await library();
    s.setActiveTag('x');
    expect(s.notes.map((n) => n.id), ['plain']);
    expect(s.webFeedNotes.map((n) => n.id).toSet(), {'plain', 'other', 'root'});

    s.setActiveTag('y');
    expect(s.notes.map((n) => n.id), ['other']);
    expect(s.webFeedNotes.map((n) => n.id).toSet(), {'plain', 'other', 'root'});
  });

  test('webFeedNotes follows the phone\'s sort order, pinned first', () async {
    final s = await library();
    await s.setNotePinned('other', true);
    await s.setSortMode(NoteSort.azTitle);
    expect(s.webFeedNotes.map((n) => n.id), ['other', 'plain', 'root']);
    await s.setSortMode(NoteSort.zaTitle);
    expect(s.webFeedNotes.map((n) => n.id), ['other', 'root', 'plain']);
    for (final n in s.webFeedNotes) {
      expect(s.isWebVisibleNote(n), isTrue);
    }
  });

  test('webImageNames lists only images the web may show', () async {
    final s = await library();
    expect(s.webImageNames, {
      'plain.jpg',
      'branch.jpg',
      'chapter.jpg',
      'card.jpg',
      'cover.jpg',
    });

    // Recomputed when the library changes.
    await s.moveNoteToSpace('plain', kCryptSpaceId);
    expect(s.webImageNames, isNot(contains('plain.jpg')));
    await s.setCardArchived('card', true);
    expect(s.webImageNames, isNot(contains('card.jpg')));
  });
}
