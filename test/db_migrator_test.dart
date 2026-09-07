import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/models/impulse.dart';
import 'package:braim/services/db/braim_database.dart';
import 'package:braim/services/db/db_migrator.dart';
import 'package:braim/services/db/db_snapshot.dart';
import 'package:braim/services/seed_data.dart';
import 'package:braim/services/storage_service.dart';

AppData _library() {
  final b = SeedData.build();
  return AppData(
    notes: b.notes,
    spaces: b.spaces,
    cards: b.cards,
    books: b.books,
    impulses: [
      Impulse(title: 'Habit', threads: [
        Thread(title: 'A', once: true, doneDays: {'2026-02-02'}),
        Thread(title: 'B', days: {2, 4}),
      ]),
    ],
    darkMode: true,
    typingMillis: 999,
    readerBookmarks: {
      'bk': [0.2, 0.8]
    },
  );
}

Future<BraimDatabase> _openMemory() =>
    BraimDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);

void main() {
  setUpAll(sqfliteFfiInit);

  test('imports the legacy library, verifies, and round-trips out of SQLite',
      () async {
    final db = await _openMemory();
    final source = _library();

    final result = await DbMigrator(db).ensureImported(
      loadLegacy: () async => source,
    );
    expect(result.outcome, ImportOutcome.imported, reason: result.detail);
    expect(await db.metaGet(DbMigrator.markerKey), 'true');

    // Read the whole library back out of SQLite and compare to the source.
    final back = appDataFromSnapshot(await db.readSnapshot());
    expect(jsonEncode(back.toJson()), jsonEncode(source.toJson()));

    await db.close();
  });

  test('is one-time: a second run reports alreadyImported and does not re-write',
      () async {
    final db = await _openMemory();
    final source = _library();
    await DbMigrator(db).ensureImported(loadLegacy: () async => source);

    final second =
        await DbMigrator(db).ensureImported(loadLegacy: () async => source);
    expect(second.outcome, ImportOutcome.alreadyImported);
    await db.close();
  });

  test('a brand-new install (no legacy store) marks done and starts empty',
      () async {
    final db = await _openMemory();
    final result =
        await DbMigrator(db).ensureImported(loadLegacy: () async => null);
    expect(result.outcome, ImportOutcome.freshUser);
    expect(await db.entityRowCount(), 0);
    expect(await db.metaGet(DbMigrator.markerKey), 'true');
    await db.close();
  });

  test('an empty but readable legacy library imports (zero rows) and marks done',
      () async {
    final db = await _openMemory();
    final result = await DbMigrator(db)
        .ensureImported(loadLegacy: () async => AppData.empty());
    expect(result.outcome, ImportOutcome.imported);
    expect(await db.entityRowCount(), 0);
    expect(await db.metaGet(DbMigrator.markerKey), 'true');
    await db.close();
  });

  test('a failing legacy read falls back without setting the marker', () async {
    final db = await _openMemory();
    final result = await DbMigrator(db).ensureImported(
      loadLegacy: () async => throw StateError('disk error'),
    );
    // The library is still intact on disk; marking done would hide it behind
    // an empty DB for good. Stay on JSON this launch and retry next time.
    expect(result.outcome, ImportOutcome.fallbackToJson);
    expect(result.dbUsable, isFalse);
    expect(await db.metaGet(DbMigrator.markerKey), isNull);
    expect(await db.entityRowCount(), 0);

    // Once the read works, the import goes through normally.
    final retry = await DbMigrator(db)
        .ensureImported(loadLegacy: () async => _library());
    expect(retry.outcome, ImportOutcome.imported);
    expect(await db.metaGet(DbMigrator.markerKey), 'true');
    await db.close();
  });

  test('queryable columns are populated for filtering', () async {
    final db = await _openMemory();
    await DbMigrator(db).ensureImported(loadLegacy: () async => _library());
    // Book pages carry their book_id; journal entries carry journal_date.
    final bookPages = await db.db
        .query('notes', where: 'book_id IS NOT NULL', limit: 1);
    expect(bookPages.isNotEmpty, isTrue);
    await db.close();
  });
}
