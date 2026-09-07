import 'package:sqflite/sqflite.dart';

import 'db_snapshot.dart';

/// The SQLite store for the whole library. A thin, hybrid container: every
/// entity is kept as a JSON `body` column (so nothing is ever lost), with a few
/// real columns for the fields the feeds filter and sort on.
///
/// The [AppSnapshot] codec ([db_snapshot.dart]) does the entity <-> row mapping;
/// this class only moves those rows in and out of SQLite. The engine is
/// injectable so tests can run it on an in-memory FFI database.
class BraimDatabase {
  BraimDatabase._(this.db);

  final Database db;

  /// Whether this SQLite build has FTS5 and the search index exists. False on
  /// the rare device without FTS5; search then stays on the in-memory filter.
  bool ftsAvailable = false;

  /// Bump when the table shape changes; add an [onUpgrade] branch to match.
  static const schemaVersion = 1;

  /// The FTS5 virtual table mirroring notes and cards for search.
  static const ftsTable = 'search_fts';

  static const _entityTables = ['notes', 'cards', 'books', 'impulses', 'spaces'];

  static Future<BraimDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? '${await f.getDatabasesPath()}/braim.db';
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: (db, from, to) async {
          // No migrations yet. Future column additions go here; entity bodies
          // self-heal through `fromJson` defaults, so most changes are additive.
        },
      ),
    );
    final out = BraimDatabase._(db);
    out.ftsAvailable = await _ensureFts(db);
    return out;
  }

  /// Creates the FTS5 index if this SQLite has FTS5 (Android's has since 7.0;
  /// so does the FFI build the tests use). Returns false when it doesn't, and
  /// search falls back to the in-memory filter. The virtual table is created
  /// outside the schema batch on purpose: it must never gate opening the store.
  static Future<bool> _ensureFts(Database db) async {
    try {
      await db.execute(
          'CREATE VIRTUAL TABLE IF NOT EXISTS $ftsTable USING fts5('
          'title, body, id UNINDEXED, kind UNINDEXED, '
          'tokenize = "unicode61 remove_diacritics 1")');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        space_id TEXT,
        book_id TEXT,
        book_page_kind TEXT,
        book_order INTEGER,
        journal_date TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        body TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        space_id TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        url TEXT,
        body TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        title TEXT,
        body TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE impulses (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        paused INTEGER NOT NULL DEFAULT 0,
        category TEXT,
        body TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE spaces (
        id TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        deleted_at INTEGER,
        name TEXT,
        body TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    batch.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    // Indexes for the filters/sorts the feeds actually run.
    for (final t in _entityTables) {
      batch.execute('CREATE INDEX idx_${t}_updated ON $t (updated_at)');
      batch.execute('CREATE INDEX idx_${t}_deleted ON $t (deleted_at)');
      batch.execute('CREATE INDEX idx_${t}_archived ON $t (archived)');
    }
    batch.execute('CREATE INDEX idx_notes_space ON notes (space_id)');
    batch.execute('CREATE INDEX idx_notes_book ON notes (book_id)');
    batch.execute('CREATE INDEX idx_notes_journal ON notes (journal_date)');
    batch.execute('CREATE INDEX idx_notes_pinned ON notes (pinned)');
    batch.execute('CREATE INDEX idx_cards_space ON cards (space_id)');
    batch.execute('CREATE INDEX idx_cards_pinned ON cards (pinned)');
    batch.execute('CREATE INDEX idx_impulses_category ON impulses (category)');

    await batch.commit(noResult: true);
  }

  // ---- meta ---------------------------------------------------------------

  Future<String?> metaGet(String key) async {
    final rows =
        await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> metaSet(String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Total entity rows across all tables — used by the importer's count check.
  Future<int> entityRowCount() async {
    var total = 0;
    for (final t in _entityTables) {
      final c = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $t'));
      total += c ?? 0;
    }
    return total;
  }

  // ---- bulk write / read (import + startup load) --------------------------

  /// Writes an entire [AppSnapshot] in one transaction. Existing rows with the
  /// same id are replaced, so this is safe to re-run.
  Future<void> writeSnapshot(AppSnapshot snap) async {
    await db.transaction((txn) async {
      Future<void> put(String table, List<Map<String, Object?>> rows) async {
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(table, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }

      await put('notes', snap.notes);
      await put('cards', snap.cards);
      await put('books', snap.books);
      await put('impulses', snap.impulses);
      await put('spaces', snap.spaces);

      final settingsBatch = txn.batch();
      for (final e in snap.settings.entries) {
        settingsBatch.insert('settings', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await settingsBatch.commit(noResult: true);
    });
  }

  /// Reads the whole library back out as an [AppSnapshot].
  Future<AppSnapshot> readSnapshot() async {
    final settingsRows = await db.query('settings');
    return AppSnapshot(
      notes: await db.query('notes'),
      cards: await db.query('cards'),
      books: await db.query('books'),
      impulses: await db.query('impulses'),
      spaces: await db.query('spaces'),
      settings: {
        for (final r in settingsRows)
          r['key'] as String: (r['value'] as String?) ?? 'null',
      },
    );
  }

  // ---- incremental writes (used by the dirty-diff flush in Phase 2) -------

  Future<void> upsertRow(String table, Map<String, Object?> row) =>
      db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteRow(String table, String id) =>
      db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<void> putSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- full-text search ---------------------------------------------------

  static Map<String, Object?> ftsRow(String id, SearchDoc d) =>
      {'id': id, 'kind': d.kind, 'title': d.title, 'body': d.body};

  /// Replaces the whole search index with [docs] (id -> doc), in one
  /// transaction.
  Future<void> rebuildSearchIndex(Map<String, SearchDoc> docs) async {
    if (!ftsAvailable) return;
    await db.transaction((txn) async {
      await txn.delete(ftsTable);
      final batch = txn.batch();
      docs.forEach((id, d) => batch.insert(ftsTable, ftsRow(id, d)));
      await batch.commit(noResult: true);
    });
  }

  /// Ranked hits (best first) for free-text [query]: every word must match,
  /// each as a prefix, diacritics are ignored, and titles weigh more than
  /// bodies. Empty when FTS is unavailable or the query has no words.
  Future<List<({String id, String kind})>> search(String query,
      {int limit = 200}) async {
    if (!ftsAvailable) return const [];
    final match = ftsMatchExpression(query);
    if (match.isEmpty) return const [];
    final rows = await db.rawQuery(
        'SELECT id, kind FROM $ftsTable WHERE $ftsTable MATCH ? '
        'ORDER BY bm25($ftsTable, 4.0, 1.0) LIMIT ?',
        [match, limit]);
    return [
      for (final r in rows) (id: r['id'] as String, kind: r['kind'] as String)
    ];
  }

  Future<void> close() => db.close();
}

/// Turns free text into an FTS5 MATCH expression: each word becomes a quoted
/// prefix term (`"wor"*`), all joined by FTS5's implicit AND. Quotes inside a
/// word are doubled and words without a letter or digit are dropped, so user
/// input can never break out of, or break, the expression. A leading `#` or
/// `@` is stripped so a `#tag` query finds the tag.
String ftsMatchExpression(String query) {
  final word = RegExp(r'[\p{L}\p{N}]', unicode: true);
  final terms = <String>[];
  for (final raw in query.split(RegExp(r'\s+'))) {
    final w = raw.replaceFirst(RegExp(r'^[#@]+'), '');
    if (!word.hasMatch(w)) continue;
    terms.add('"${w.replaceAll('"', '""')}"*');
  }
  return terms.join(' ');
}
