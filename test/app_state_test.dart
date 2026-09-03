import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/annotation.dart';
import 'package:braim/models/book.dart';
import 'package:braim/models/impulse.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/space.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/services/wiki_links.dart';
import 'package:braim/state/app_state.dart';

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

  test('tags and reminders persist; tags feed search', () async {
    final due = DateTime(2030, 1, 2, 9, 30);
    final state = await boot(AppData(
      notes: [Note(title: 'idea', tags: ['work', 'todo'], reminderAt: due)],
      spaces: [],
      cards: [],
    ));

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final n = reloaded.notes.single;
    expect(n.tags, ['work', 'todo']);
    expect(n.reminderAt, due);
  });

  test('shared text becomes a note; bulk actions apply and persist', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final a = await state.addSharedNote(text: 'from a share');
    final b = await state.addSharedNote(text: 'second');
    expect(state.notes.length, 2);
    expect(a.textPreview, 'from a share');

    final space = Space(name: 'Filed');
    await state.bulkMoveNotes({a.id, b.id}, space.id);
    await state.bulkPinNotes({a.id}, true);
    await state.bulkArchiveNotes({b.id}, true);

    expect(state.notes.firstWhere((x) => x.id == a.id).spaceId, space.id);
    expect(state.notes.firstWhere((x) => x.id == a.id).pinned, isTrue);
    expect(state.notes.any((x) => x.id == b.id), isFalse); // archived

    await state.bulkDeleteNotes({a.id});
    expect(state.notes.any((x) => x.id == a.id), isFalse);
    await state.flushNow();
  });

  test('reader position and bookmarks persist per book', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    await state.setReaderPosition('bk', 0.42);
    await state.addReaderBookmark('bk', 0.1);
    await state.addReaderBookmark('bk', 0.6);
    await state.addReaderBookmark('bk', 0.605); // near-duplicate, ignored

    expect(state.readerPosition('bk'), closeTo(0.42, 0.0001));
    expect(state.readerBookmarks('bk').length, 2);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.readerPositions['bk'], closeTo(0.42, 0.0001));
    expect(reloaded.readerBookmarks['bk']!.length, 2);
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

  test('journal entries stay out of the feed and query by day', () async {
    final day = DateTime(2026, 7, 11);
    final state = await boot(AppData(
      notes: [
        Note(title: 'plain'),
        Note(title: 'entry', journalDate: AppState.journalKey(day)),
        Note(
            title: 'binned entry',
            journalDate: AppState.journalKey(day),
            deletedAt: DateTime.now()),
      ],
      spaces: [],
      cards: [],
    ));

    expect(state.notes.map((n) => n.title), ['plain']);
    expect(state.journalEntriesOn(day).map((n) => n.title), ['entry']);
    expect(state.journalEntriesOn(DateTime(2026, 7, 12)), isEmpty);
    expect(state.journalDaysIn(2026, 7), {11});
    expect(state.journalDaysIn(2026, 8), isEmpty);

    // The date string survives storage.
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(
        reloaded.notes.firstWhere((n) => n.title == 'entry').journalDate,
        '2026-07-11');
  });

  test('journal months, years, crypt hiding and covers', () async {
    final state = await boot(AppData(
      notes: [
        Note(title: 'july A', journalDate: '2026-07-11'),
        Note(title: 'july B', journalDate: '2026-07-03'),
        Note(title: 'old year', journalDate: '2024-02-01'),
        Note(
            title: 'hidden',
            journalDate: '2026-07-11',
            spaceId: kCryptSpaceId),
      ],
      spaces: [],
      cards: [],
    ));

    // Whole-month query, newest day first; Crypt entries stay hidden.
    expect(state.journalEntriesInMonth(2026, 7).map((n) => n.title),
        ['july A', 'july B']);
    expect(state.journalEntriesOn(DateTime(2026, 7, 11)).map((n) => n.title),
        ['july A']);
    expect(state.journalDaysIn(2026, 7), {11, 3});

    // Years: only years that have entries, newest first.
    expect(state.journalYears(), [2026, 2024]);

    // Month covers persist.
    await state.setJournalMonthCover('2026-07', '/tmp/cover.jpg');
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.journalMonthCovers['2026-07'], '/tmp/cover.jpg');
  });

  test('a year with no entries never appears in the year list', () async {
    final state = await boot(AppData(
      notes: [Note(title: 'only 2023', journalDate: '2023-05-05')],
      spaces: [],
      cards: [],
    ));
    // Exactly the entry year — the current (entry-less) year is absent.
    expect(state.journalYears(), [2023]);
  });

  test('backup nudge dismissal snoozes it for a week, persisted', () async {
    final state = await boot(AppData(
      notes: [Note(title: 'something worth backing up')],
      spaces: [],
      cards: [],
    ));
    // Never backed up: the nudge shows.
    expect(state.showBackupReminder, isTrue);

    await state.dismissBackupReminder();
    expect(state.showBackupReminder, isFalse);
    await state.flushNow();

    // The dismissal survives a restart (still inside the snooze week).
    final reloaded = await StorageService.instance.load();
    expect(reloaded.backupReminderDismissedAt, isNotNull);

    // Backing up clears the snooze and the overdue state entirely.
    await state.markBackedUp();
    expect(state.showBackupReminder, isFalse);
    expect(state.backupOverdue, isFalse);
  });

  test('an article keeps its byline and saved state across a reload',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    await state.upsertNote(Note(
      title: 'On writing',
      isArticle: true,
      articleDraft: false,
      articleSavedAt: DateTime(2026, 7, 20),
      authorName: 'Kalpesh',
      authorPhoto: 'https://example.com/p.jpg',
    ));
    await state.flushNow();

    final back = (await StorageService.instance.load()).notes.single;
    expect(back.isArticle, isTrue);
    expect(back.articleDraft, isFalse);
    expect(back.authorName, 'Kalpesh');
    expect(back.authorPhoto, 'https://example.com/p.jpg');
    expect(back.articleSavedAt, DateTime(2026, 7, 20));

    // A plain note stays a plain note.
    expect(Note(title: 'note').isArticle, isFalse);
  });

  test('a new book gets Contents, Introduction and Chapter I, hidden from feed',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('My Book');

    final pages = state.bookPages(book.id);
    expect(pages.map((p) => p.title),
        ['Contents', 'Introduction', 'Chapter I']);
    // Book pages never appear in the Home feed.
    expect(state.notes, isEmpty);

    // Next chapter auto-numbers.
    final ch = await state.addBookChapter(book.id);
    expect(ch.title, 'Chapter II');
    expect(state.bookChapters(book.id).length, 2);

    // Round-trips through storage.
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.books.single.title, 'My Book');
    expect(reloaded.notes.where((n) => n.bookId == book.id).length, 4);
  });

  test('book workshop notes stay out of the manuscript and totals', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('Saga');

    // Chapter I carries some words toward the book's totals.
    final chapter = state
        .bookPages(book.id)
        .firstWhere((p) => p.bookPageKind == BookPageKind.chapter);
    chapter.blocks
        .add(NoteBlock(type: NoteBlockType.text, text: 'one two three'));
    await state.upsertNote(chapter);

    final pagesBefore = state.totalBookPages;
    final wordsBefore = state.totalBookWords;

    // A workshop note (character sketch) with plenty of words.
    final note = await state.addBookNote(book.id);
    note.title = 'Protagonist';
    note.blocks.add(NoteBlock(
        type: NoteBlockType.text, text: 'a brave and weary traveller here'));
    await state.upsertNote(note);

    // It shows up as a note, never as a manuscript page.
    expect(state.bookNotes(book.id).single.title, 'Protagonist');
    expect(state.bookPages(book.id).any((p) => p.id == note.id), isFalse);
    // And it doesn't inflate the book's page or word totals.
    expect(state.totalBookPages, pagesBefore);
    expect(state.totalBookWords, wordsBefore);
    // It stays out of the Home feed like every book page.
    expect(state.notes, isEmpty);

    // The book's font applies book-wide and survives a reload.
    await state.setBookFont(book.id, 'Merriweather');
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.books.single.fontFamily, 'Merriweather');
    final savedNote = reloaded.notes.firstWhere((n) => n.id == note.id);
    expect(savedNote.bookPageKind, BookPageKind.note);
  });

  test('book find & replace rewrites the manuscript and counts matches',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('Echoes');
    final chapter = state
        .bookPages(book.id)
        .firstWhere((p) => p.bookPageKind == BookPageKind.chapter);
    chapter.blocks.add(NoteBlock(
        type: NoteBlockType.text, text: 'the fox and the fox ran'));
    await state.upsertNote(chapter);

    expect(state.bookFindMatches(book.id, 'fox'), 2);
    // Case-sensitive misses a differently-cased query.
    expect(state.bookFindMatches(book.id, 'FOX', caseSensitive: true), 0);

    final replaced = await state.bookReplaceAll(book.id, 'fox', 'hound');
    expect(replaced, 2);
    final saved = state.bookPages(book.id).firstWhere((p) => p.id == chapter.id);
    expect(saved.textPreview, 'the hound and the hound ran');
  });

  test('book stats, front/back matter, targets and note links', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('Craft');
    final chapter = state
        .bookPages(book.id)
        .firstWhere((p) => p.bookPageKind == BookPageKind.chapter);
    chapter.blocks
        .add(NoteBlock(type: NoteBlockType.text, text: 'one two three four'));
    await state.upsertNote(chapter);

    // Character and reading-time totals roll up from the pages.
    expect(state.bookCharCount(book.id), greaterThan(0));
    expect(state.bookReadingMinutes(book.id), 1);

    // Front/back matter is a manuscript page (counts toward pages).
    final before = state.totalBookPages;
    final dedication = await state.addBookMatter(
        book.id, BookPageKind.dedication, 'Dedication');
    expect(state.totalBookPages, before + 1);
    expect(state.bookPages(book.id).any((p) => p.id == dedication.id), isTrue);

    // A per-chapter word target persists.
    await state.setBookPageTarget(chapter.id, 2000);
    // A workshop note can be linked to a chapter and found by it.
    final note = await state.addBookNote(book.id);
    await state.setBookNoteLink(note.id, chapter.id);
    expect(state.bookNotesForPage(chapter.id).single.id, note.id);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final savedChapter =
        reloaded.notes.firstWhere((n) => n.id == chapter.id);
    expect(savedChapter.targetWords, 2000);
    final savedNote = reloaded.notes.firstWhere((n) => n.id == note.id);
    expect(savedNote.linkedPageId, chapter.id);
  });

  test('book pages reorder, count words and carry a status', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('Counting');
    final pages = state.bookPages(book.id);

    // Word counts roll up from the pages.
    pages[2].blocks.add(NoteBlock(
        type: NoteBlockType.text, text: 'one two three four five'));
    await state.upsertNote(pages[2]);
    expect(state.bookWordCount(book.id), 5);

    // Move Chapter I to the front; the order sticks and renumbers.
    await state.reorderBookPages(book.id, 2, 0);
    expect(state.bookPages(book.id).map((p) => p.title).first, 'Chapter I');
    expect(state.bookPages(book.id).map((p) => p.bookOrder), [0, 1, 2]);

    // Status tags persist.
    await state.setBookPageStatus(pages[2].id, BookPageStatus.draft);
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final saved =
        reloaded.notes.firstWhere((n) => n.id == pages[2].id);
    expect(saved.bookStatus, BookPageStatus.draft);
    expect(reloaded.books.single.description, '');
  });

  test('book author, highlights and reader prefs persist', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final book = await state.addBook('Ink');
    book.author = 'A. Nonymous';
    book.description = 'A slim volume.';
    await state.updateBook(book);

    // Highlight a passage on the intro page.
    final intro = state
        .bookPages(book.id)
        .firstWhere((p) => p.bookPageKind == BookPageKind.intro);
    await state.addAnnotation(
      intro.id,
      Annotation(text: 'a marked line', note: 'why it matters'),
    );

    await state.setReaderFontScale(1.3);
    await state.setReaderTheme('paper');
    await state.setReaderFont('Caveat');
    await state.flushNow();

    final reloaded = await StorageService.instance.load();
    final b = reloaded.books.single;
    expect(b.author, 'A. Nonymous');
    expect(b.description, 'A slim volume.');
    final page =
        reloaded.notes.firstWhere((n) => n.id == intro.id);
    expect(page.annotations.single.text, 'a marked line');
    expect(page.annotations.single.note, 'why it matters');

    // Reader prefs live on the settings doc; a fresh state reads them back.
    final state2 = AppState();
    await state2.init();
    expect(state2.readerFontScale, 1.3);
    expect(state2.readerTheme, 'paper');
    expect(state2.readerFont, 'Caveat');
  });

  test('feed wallpaper choice persists', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    expect(state.feedWallpaper, 0);

    await state.setFeedWallpaper(2);
    await state.flushNow();

    final reloaded = await StorageService.instance.load();
    expect(reloaded.feedWallpaper, 2);
  });

  test('sample data loads a full demo library and persists it', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    await state.loadSampleData();
    await state.flushNow();

    final data = await StorageService.instance.load();
    expect(data.spaces.length, 3);
    expect(data.cards.length, 5);
    expect(data.books.length, 1);
    expect(data.notes.length, greaterThan(10));

    // The book carries a description plus an intro and exactly two chapters.
    final book = data.books.single;
    expect(book.description, isNotEmpty);
    final pages = data.notes.where((n) => n.bookId == book.id).toList();
    expect(pages.where((p) => p.bookPageKind == 'intro').length, 1);
    expect(pages.where((p) => p.bookPageKind == 'chapter').length, 2);

    // Every note kind is represented so each feature has something to show.
    expect(data.notes.any((n) => n.reminderAt != null), isTrue);
    expect(data.notes.any((n) => n.tags.isNotEmpty), isTrue);
    expect(data.notes.any((n) => n.journalDate != null), isTrue);
    expect(data.notes.any((n) => n.isArticle), isTrue);
    expect(data.notes.any((n) => n.archived), isTrue);
    expect(data.notes.any((n) => n.deletedAt != null), isTrue);

    // Additive: loading again adds an independent copy, never wiping the first.
    await state.loadSampleData();
    await state.flushNow();
    final again = await StorageService.instance.load();
    expect(again.books.length, 2);
  });

  NoteBlock tb(String s) => NoteBlock(type: NoteBlockType.text, text: s);

  test('wiki-links resolve and backlinks list who mentions a note', () async {
    final target = Note(title: 'Deep Work', blocks: [tb('about focus')]);
    final a =
        Note(title: 'Reading', blocks: [tb('loved [[Deep Work]] this week')]);
    final b = Note(
        title: 'Mornings', blocks: [tb('apply [[deep work]] before 9am')]);
    final state =
        await boot(AppData(notes: [target, a, b], spaces: [], cards: []));

    // Resolution is case-insensitive; a note lists its outgoing links.
    expect(state.noteByTitle('deep WORK')?.id, target.id);
    expect(state.wikiLinkTitlesOf(a), ['Deep Work']);

    // Both notes show up as backlinks, newest edit first; target isn't its own.
    final backs = state.backlinksTo(target);
    expect(backs.map((n) => n.id).toSet(), {a.id, b.id});
    expect(state.backlinksTo(a), isEmpty);

    // An unresolved [[title]] can be created on demand and then resolves.
    expect(state.noteByTitle('Fresh Idea'), isNull);
    final created = await state.createLinkedNote('Fresh Idea');
    expect(state.noteByTitle('fresh idea')?.id, created.id);

    // Crypt notes stay out of the graph so a link never leaks them.
    await state.upsertNote(Note(title: 'Secret', spaceId: kCryptSpaceId));
    expect(state.noteByTitle('Secret'), isNull);
  });

  test('backlinks span notes and cards both ways', () async {
    final note = Note(title: 'Deep Work', blocks: [tb('about focus')]);
    final card = TweetCard(
      url: 'https://example.com/habits',
      noteTitle: 'Habits',
      blocks: [tb('inspired by [[Deep Work]]')],
    );
    final noteToCard =
        Note(title: 'Reading', blocks: [tb('see the [[Habits]] card')]);
    final state = await boot(
        AppData(notes: [note, noteToCard], spaces: [], cards: [card]));

    // A [[card title]] resolves to the card.
    final ref = state.resolveLink('habits');
    expect(ref?.kind, LinkKind.card);
    expect(ref?.id, card.id);

    // The note is mentioned by the card → backlink of kind card.
    final noteBacks = state.backlinksToTitle('Deep Work', excludeId: note.id);
    expect(noteBacks.map((r) => r.id), contains(card.id));
    expect(noteBacks.firstWhere((r) => r.id == card.id).kind, LinkKind.card);

    // The card is mentioned by a note → backlink of kind note.
    final cardBacks = state.backlinksToTitle('Habits', excludeId: card.id);
    expect(cardBacks.map((r) => r.id), contains(noteToCard.id));
  });

  test('impulses: daily is today-relative, checklist cumulative, persists',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    final daily = await state.addImpulse(
        title: 'Fitness', mode: ImpulseMode.daily, days: {1, 3, 5});
    await state.addThread(daily.id, 'Run');
    await state.addThread(daily.id, 'Stretch');
    final live = state.impulseById(daily.id)!;
    expect(live.threads.length, 2);
    expect(live.progress(state.todayKey), 0);

    await state.toggleThread(daily.id, live.threads.first.id);
    expect(state.impulseById(daily.id)!.progress(state.todayKey), 0.5);

    // Daily is today-relative: a thread ticked another day doesn't count today.
    live.threads[1].doneDays.add('2000-01-01');
    expect(live.doneCount(state.todayKey), 1);

    // Checklist mode: any non-null doneDate counts, for good.
    final list =
        await state.addImpulse(title: 'Launch', mode: ImpulseMode.checklist);
    await state.addThread(list.id, 'Design');
    await state.toggleThread(
        list.id, state.impulseById(list.id)!.threads.first.id);
    expect(state.impulseById(list.id)!.progress(state.todayKey), 1.0);
    expect(state.impulseById(list.id)!.isComplete, isTrue);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.impulses.length, 2);
    final reDaily = reloaded.impulses.firstWhere((i) => i.title == 'Fitness');
    expect(reDaily.days, {1, 3, 5});
    expect(reDaily.mode, ImpulseMode.daily);
  });

  test('daily day: hidden reflex, tasks and reminders persist', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    // Untouched, the daily day is transient and not listed among reflexes.
    expect(state.dailyDay.threads, isEmpty);
    expect(state.impulses, isEmpty);
    expect(state.impulseCount, 0);

    await state.addDailyTask('Wake up');
    await state.addDailyTask('Read');
    final day = state.dailyDay;
    expect(day.id, AppState.dailyDayId);
    expect(day.threads.map((t) => t.title), ['Wake up', 'Read']);
    // Still kept out of the Reflexes list / count.
    expect(state.impulses, isEmpty);
    expect(state.impulseCount, 0);

    // Ticking is today-relative (daily mode).
    await state.toggleThread(day.id, day.threads.first.id);
    expect(state.dailyDay.doneCount(state.todayKey), 1);

    // A reminder sets then clears the thread's minutes.
    final t = state.dailyDay.threads.first;
    await state.setThreadReminder(day.id, t.id, 7 * 60 + 30);
    expect(state.dailyDay.threads.first.reminderMinutes, 450);
    await state.setThreadReminder(day.id, t.id, null);
    expect(state.dailyDay.threads.first.reminderMinutes, isNull);

    // …and survives a save/load round-trip.
    await state.setThreadReminder(day.id, t.id, 9 * 60);
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final reDay =
        reloaded.impulses.firstWhere((i) => i.id == AppState.dailyDayId);
    expect(reDay.threads.first.reminderMinutes, 540);
  });

  test('daily day: per-day history and rich task fields persist', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    await state.addDailyTask('Wake up');
    final day = state.dailyDay;
    final t = day.threads.first;

    // Per-day history: two independent days, then untick just one.
    await state.toggleThreadOn(day.id, t.id, '2026-08-10');
    await state.toggleThreadOn(day.id, t.id, '2026-08-12');
    Thread cur() => state.dailyDay.threads.first;
    expect(state.dailyDay.threadDone(cur(), '2026-08-10'), isTrue);
    expect(state.dailyDay.threadDone(cur(), '2026-08-11'), isFalse);
    expect(state.dailyDay.threadDone(cur(), '2026-08-12'), isTrue);
    await state.toggleThreadOn(day.id, t.id, '2026-08-10');
    expect(state.dailyDay.threadDone(cur(), '2026-08-10'), isFalse);
    expect(state.dailyDay.threadDone(cur(), '2026-08-12'), isTrue);

    // Rich fields via updateThread round-trip.
    final edit = cur()
      ..description = 'Get up at dawn'
      ..flag = TaskFlag.important
      ..endMinutes = 14 * 60 + 30
      ..location = 'Central Park'
      ..links.add(TaskLink(label: 'Meet', url: 'https://meet.example'));
    await state.updateThread(day.id, edit);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final reThread = reloaded.impulses
        .firstWhere((i) => i.id == AppState.dailyDayId)
        .threads
        .first;
    expect(reThread.description, 'Get up at dawn');
    expect(reThread.flag, TaskFlag.important);
    expect(reThread.endMinutes, 870);
    expect(reThread.location, 'Central Park');
    expect(reThread.links.single.url, 'https://meet.example');
    expect(reThread.doneDays.contains('2026-08-12'), isTrue);
    expect(reThread.doneDays.contains('2026-08-10'), isFalse);
  });

  test('reflexes: daily day is first, pinning persists and survives delete',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));

    // The daily day always leads the reflex feed, and is pinned by default.
    await state.addImpulse(title: 'Fitness');
    expect(state.reflexes.first.id, AppState.dailyDayId);
    expect(state.reflexes.length, 2);
    expect(state.pinnedReflexId, AppState.dailyDayId);
    expect(state.isDailyDay(state.pinnedReflex.id), isTrue);

    // Pin the project — it now leads the journal feed and persists.
    final fitness = state.reflexes.firstWhere((i) => i.title == 'Fitness');
    await state.setPinnedReflex(fitness.id);
    expect(state.pinnedReflex.title, 'Fitness');
    await state.flushNow();
    final reloaded = AppState();
    await reloaded.init();
    expect(reloaded.pinnedReflexId, fitness.id);

    // Deleting the pinned reflex falls the pin back to the daily day.
    await reloaded.deleteImpulse(fitness.id);
    expect(reloaded.pinnedReflexId, AppState.dailyDayId);
    expect(reloaded.isDailyDay(reloaded.pinnedReflex.id), isTrue);
  });

  test('impulses can be paused and marked complete early, persisted', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final imp = await state.addImpulse(
        title: 'Launch', mode: ImpulseMode.checklist);
    await state.addThread(imp.id, 'Ship');
    expect(state.impulseById(imp.id)!.isComplete, isFalse);

    // Marked complete by hand (before the single thread is done).
    await state.setImpulseCompleted(imp.id, true);
    expect(state.impulseById(imp.id)!.isComplete, isTrue);
    expect(state.impulseById(imp.id)!.isCompletedManually, isTrue);

    await state.setImpulsePaused(imp.id, true);
    expect(state.impulseById(imp.id)!.paused, isTrue);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final re = reloaded.impulses.firstWhere((i) => i.id == imp.id);
    expect(re.paused, isTrue);
    expect(re.isCompletedManually, isTrue);
    expect(re.isComplete, isTrue);

    // Reopening clears the manual completion.
    await state.setImpulseCompleted(imp.id, false);
    expect(state.impulseById(imp.id)!.isCompletedManually, isFalse);
    expect(state.impulseById(imp.id)!.isComplete, isFalse);
  });

  test('threads cannot be marked complete for a future day', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    await state.addDailyTask('Wake up');
    final day = state.dailyDay;
    final t = day.threads.first;
    final future = AppState.dayKeyFor(
        DateTime.now().add(const Duration(days: 3)));

    await state.toggleThreadOn(day.id, t.id, future);
    expect(state.dailyDay.threads.first.doneDays.contains(future), isFalse);

    // But today can be ticked.
    await state.toggleThreadOn(day.id, t.id, state.todayKey);
    expect(state.dailyDay.threads.first.doneDays.contains(state.todayKey),
        isTrue);
  });

  test('daily day mark-all, impulse colour and journal order persist',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    await state.addDailyTask('A');
    await state.addDailyTask('B');
    final day = state.dailyDay;

    await state.markAllThreadsDone(day.id, state.todayKey, true);
    expect(state.dailyDay.doneCount(state.todayKey), 2);
    await state.markAllThreadsDone(day.id, state.todayKey, false);
    expect(state.dailyDay.doneCount(state.todayKey), 0);

    final imp = await state.addImpulse(title: 'Reading');
    await state.setImpulseColor(imp.id, 0xFFB3E5FC);
    expect(state.impulseById(imp.id)!.colorValue, 0xFFB3E5FC);

    await state.setJournalOrder(['entries', 'tasks', 'card']);
    expect(state.journalOrder, ['entries', 'tasks', 'card']);

    await state.flushNow();
    final reloaded = AppState();
    await reloaded.init();
    expect(reloaded.journalOrder, ['entries', 'tasks', 'card']);
    expect(reloaded.impulseById(imp.id)!.colorValue, 0xFFB3E5FC);
  });

  test('reflex archive, thread reorder/move and flag sort', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final imp = await state.addImpulse(title: 'Ship v1');
    await state.addThread(imp.id, 'A');
    await state.addThread(imp.id, 'B');
    await state.addThread(imp.id, 'C');
    final threads = state.impulseById(imp.id)!.threads;

    // Reorder: move the last thread to the front.
    await state.reorderThread(imp.id, 2, 0);
    expect(state.impulseById(imp.id)!.threads.map((t) => t.title),
        ['C', 'A', 'B']);

    // Flag sort: important floats to the top.
    threads.firstWhere((t) => t.title == 'B').flag = TaskFlag.important;
    await state.sortThreadsByFlag(imp.id);
    expect(state.impulseById(imp.id)!.threads.first.title, 'B');

    // Move a thread into the daily day.
    final moveId =
        state.impulseById(imp.id)!.threads.firstWhere((t) => t.title == 'A').id;
    await state.moveThread(imp.id, moveId, AppState.dailyDayId);
    expect(state.impulseById(imp.id)!.threads.any((t) => t.title == 'A'),
        isFalse);
    expect(state.dailyDay.threads.any((t) => t.title == 'A'), isTrue);

    // Archive hides it from the active list; pausing/archiving unpins it.
    await state.setPinnedReflex(imp.id);
    expect(state.pinnedReflexId, imp.id);
    await state.setImpulseArchived(imp.id, true);
    expect(state.reflexes.any((i) => i.id == imp.id), isFalse);
    expect(state.archivedReflexes.any((i) => i.id == imp.id), isTrue);
    expect(state.pinnedReflexId, AppState.dailyDayId);
  });

  test('streaks count complete days, over scheduled days, today in progress',
      () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    final imp = await state.addImpulse(title: 'Run', mode: ImpulseMode.daily);
    await state.addThread(imp.id, 'Jog');
    final t = state.impulseById(imp.id)!.threads.first;

    String key(DateTime d) => AppState.dayKeyFor(d);
    final today = DateTime.now();
    DateTime ago(int n) => today.subtract(Duration(days: n));

    // Complete yesterday, day-before and 3-days-ago (a 3-day run), miss 4/5.
    t.doneDays.addAll({key(ago(1)), key(ago(2)), key(ago(3))});
    var s = state.streakFor(state.impulseById(imp.id)!);
    expect(s.current, 3); // today not done yet → still counts through yesterday
    expect(s.best, 3);

    // Finishing today extends the current run to 4.
    t.doneDays.add(key(today));
    s = state.streakFor(state.impulseById(imp.id)!);
    expect(s.current, 4);
    expect(s.best, 4);

    // A gap in the middle breaks the run: today alone is the current streak,
    // and the best is the longer of the two remaining runs (08-18..08-19 = 2).
    t.doneDays.remove(key(ago(1)));
    s = state.streakFor(state.impulseById(imp.id)!);
    expect(s.current, 1);
    expect(s.best, 2);
  });

  test('scheduled days are skipped in the streak', () async {
    final state = await boot(AppData(notes: [], spaces: [], cards: []));
    // Only scheduled on the weekday that is exactly 2 days ago and today.
    final today = DateTime.now();
    final twoAgo = today.subtract(const Duration(days: 2));
    final imp = await state.addImpulse(
        title: 'Gym', mode: ImpulseMode.daily, days: {today.weekday, twoAgo.weekday});
    await state.addThread(imp.id, 'Lift');
    final t = state.impulseById(imp.id)!.threads.first;
    String key(DateTime d) => AppState.dayKeyFor(d);
    // Done today and two-days-ago; the unscheduled day between doesn't break it.
    t.doneDays.addAll({key(today), key(twoAgo)});
    final s = state.streakFor(state.impulseById(imp.id)!);
    expect(s.current >= 2, isTrue);
  });

  test('chapter versions save, restore and stay reversible', () async {
    final book = Book(title: 'B');
    final ch = Note(
      title: 'Chapter I',
      bookId: book.id,
      bookPageKind: BookPageKind.chapter,
      blocks: [tb('one two three')],
    );
    final state = await boot(
        AppData(notes: [ch], spaces: [], cards: [], books: [book]));

    // boot() serializes + reloads, so work against the live in-state note.
    final live = state.noteById(ch.id)!;
    await state.saveChapterVersion(ch.id);
    expect(live.history.length, 1);
    expect(live.history.first.wordCount, 3);
    final v1 = live.history.first.id;

    // Edit the chapter, then restore the saved version.
    live.blocks = [tb('one two three four five six')];
    await state.upsertNote(live);
    await state.restoreChapterVersion(ch.id, v1);

    // Content is back to the 3-word version...
    expect(state.noteById(ch.id)!.wordCount, 3);
    // ...and the pre-restore (6-word) state was snapshotted so it's undoable.
    expect(live.history.any((s) => s.wordCount == 6), isTrue);

    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    final page = reloaded.notes.firstWhere((n) => n.id == ch.id);
    expect(page.history, isNotEmpty);
  });

  test('journal on-this-day surfaces earlier years; reminder persists',
      () async {
    final now = DateTime.now();
    final lastYear = DateTime(now.year - 1, now.month, now.day);
    final twoYears = DateTime(now.year - 2, now.month, now.day);
    final otherDay = lastYear.add(const Duration(days: 3));
    final state = await boot(AppData(notes: [
      Note(journalDate: AppState.journalKey(lastYear), blocks: [tb('a')]),
      Note(journalDate: AppState.journalKey(twoYears), blocks: [tb('b')]),
      Note(journalDate: AppState.journalKey(otherDay), blocks: [tb('c')]),
      Note(journalDate: AppState.journalKey(now), blocks: [tb('today')]),
    ], spaces: [], cards: []));

    final otd = state.journalOnThisDay(now);
    // Only same-day, earlier-year entries — newest year first.
    expect(otd.map((n) => n.journalDate).toList(),
        [AppState.journalKey(lastYear), AppState.journalKey(twoYears)]);

    await state.setJournalReminder(on: true, minutes: 20 * 60 + 30);
    await state.flushNow();
    final reloaded = await StorageService.instance.load();
    expect(reloaded.journalReminderOn, isTrue);
    expect(reloaded.journalReminderMinutes, 20 * 60 + 30);
  });
}
