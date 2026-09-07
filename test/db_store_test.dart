import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/services/db/braim_database.dart';
import 'package:braim/services/db/db_store.dart';
import 'package:braim/services/seed_data.dart';
import 'package:braim/services/storage_service.dart';

AppData _library({List<Note>? notes, bool dark = false}) {
  final b = SeedData.build();
  return AppData(
    notes: notes ?? b.notes,
    spaces: b.spaces,
    cards: b.cards,
    books: b.books,
    darkMode: dark,
  );
}

Future<DbStore> _openShadow(AppData legacy) async {
  final store = DbStore();
  await store.init(
    loadLegacy: () async => legacy,
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  return store;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('shadow imports on init and reads back identical to the source',
      () async {
    final source = _library();
    final store = await _openShadow(source);
    expect(store.enabled, isTrue);

    final back = await store.readAppData();
    expect(jsonEncode(back!.toJson()), jsonEncode(source.toJson()));
    await store.close();
  });

  test('is usable as the read source once imported cleanly (Phase 2)',
      () async {
    // The flag ships on; flip it to fall back to JSON in the field.
    expect(DbStore.readFromDb, isTrue);

    final store = await _openShadow(_library());
    expect(store.usableForReads, isTrue);
    await store.close();
  });

  test('a restore that drops items reconciles the DB down to what is left',
      () async {
    // Start with the full seed library in the DB...
    final source = _library();
    final store = await _openShadow(source);

    // ...then "restore" a much smaller library over it (fewer notes, no cards).
    final restored = AppData(
      notes: source.notes.take(1).toList(),
      spaces: source.spaces,
      cards: const [],
      books: source.books,
    );
    await store.syncFromAppData(restored);

    final back = await store.readAppData();
    expect(jsonEncode(back!.toJson()), jsonEncode(restored.toJson()));
    await store.close();
  });

  test('a later save mirrors only the delta and stays consistent', () async {
    final source = _library();
    final store = await _openShadow(source);

    // Mutate: add a note, drop a card, flip a setting.
    final mutated = AppData(
      notes: [...source.notes, Note(title: 'Fresh note')],
      spaces: source.spaces,
      cards: source.cards.sublist(0, source.cards.length - 1),
      books: source.books,
      darkMode: true,
    );
    await store.syncFromAppData(mutated);

    final back = await store.readAppData();
    expect(jsonEncode(back!.toJson()), jsonEncode(mutated.toJson()));
    await store.close();
  });

  test('ftsMatchExpression: prefix terms, escaped quotes, junk dropped', () {
    expect(ftsMatchExpression('hello wor"ld #tag -'),
        '"hello"* "wor""ld"* "tag"*');
    expect(ftsMatchExpression('   '), '');
  });

  test('full-text search: ranked, prefix and accent-insensitive, kept in sync',
      () async {
    final grocery = Note(title: 'Grocery run', blocks: [
      NoteBlock(type: NoteBlockType.text, text: 'buy milk, eggs and bread'),
    ]);
    final cafe = Note(title: 'Café notes', tags: ['coffee'], blocks: [
      NoteBlock(type: NoteBlockType.text, text: 'the espresso was excellent'),
    ]);
    final card = TweetCard(
        url: 'https://example.com/milk-prices', text: 'Milk prices climb');
    final data = AppData(notes: [grocery, cafe], spaces: [], cards: [card]);
    final store = await _openShadow(data);
    expect(store.searchAvailable, isTrue);
    await store.ensureSearchIndex(data);

    Future<List<String>> ids(String q) async =>
        [for (final h in (await store.search(q))!) h.id];

    expect(await ids('groc'), [grocery.id]); // a word matches from its start
    expect(await ids('cafe'), [cafe.id]); // accents ignored
    expect(await ids('#coffee'), [cafe.id]); // tags, with the hash
    expect((await ids('milk')).toSet(), {grocery.id, card.id});
    expect(await ids('milk bread'), [grocery.id]); // every word must match
    expect(await ids('"unbalanced'), isEmpty); // input can't break the query

    // A rename shows after the next sync; a delete drops the doc.
    grocery.title = 'Farmers market';
    expect(await store.syncFromAppData(data), isTrue);
    expect(await ids('farmers'), [grocery.id]);
    expect(await ids('grocery'), isEmpty);
    data.notes.remove(cafe);
    await store.syncFromAppData(data);
    expect(await ids('cafe'), isEmpty);
    await store.close();
  });

  test('re-syncing unchanged data is a safe no-op', () async {
    final source = _library();
    final store = await _openShadow(source);
    await store.syncFromAppData(source);
    await store.syncFromAppData(source);
    final back = await store.readAppData();
    expect(jsonEncode(back!.toJson()), jsonEncode(source.toJson()));
    await store.close();
  });
}
