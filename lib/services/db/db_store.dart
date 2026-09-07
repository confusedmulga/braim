import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseFactory;

import '../../models/note.dart';
import '../../models/tweet_card.dart';
import '../storage_service.dart' show AppData;
import 'braim_database.dart';
import 'db_migrator.dart';
import 'db_snapshot.dart';

/// One full-text search hit: the entity id and which table it lives in
/// ('note' or 'card').
typedef SearchHit = ({String id, String kind});

/// The SQLite store for the library. [DbStore] opens the database, runs the
/// one-time import, and mirrors every save into SQLite by writing only what
/// changed. From migration Phase 2 the app also *reads* its library from here
/// at startup (guarded by [readFromDb] + [usableForReads]); the JSON file is
/// still written alongside as a belt-and-suspenders copy and the instant-revert
/// path. If sqflite is unavailable (e.g. in unit tests) it silently disables
/// itself, so nothing that depends on it can break the app.
class DbStore {
  /// [factory]/[path] override where the database lives: tests hand in the
  /// FFI factory and a temp path; the app takes sqflite's defaults.
  DbStore({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  final DatabaseFactory? _factory;
  final String? _path;

  BraimDatabase? _db;

  /// The read-from-DB flag (migration Phase 2). When true, the app loads its
  /// library from SQLite at startup. Flip to false to instantly fall back to
  /// reading the JSON store — the DB is still written either way, so this is the
  /// field revert the migration plan calls for if the DB ever misbehaves.
  static const bool readFromDb = true;

  /// The write-JSON-on-every-save flag (migration Phase 3). Ships false: SQLite
  /// is the sole per-save store (a single edit writes one row, not the whole
  /// library), and the JSON is refreshed only at checkpoints — app pause and
  /// before a backup — as a rollback + backup artifact. Flip true to restore the
  /// Phase 2 belt-and-suspenders (whole-file JSON on every save) without giving
  /// up DB reads.
  static const bool writeJsonOnSave = false;

  /// The outcome of the one-time import (for diagnostics / the shadow check).
  ImportResult? lastImport;

  /// Whether the search index still has to be built from the whole library
  /// (first open with FTS5 available, or after [ftsBuiltTag] is bumped).
  bool _needsIndexRebuild = false;
  static const ftsBuiltKey = 'fts_built';
  static const ftsBuiltTag = '1';

  // What the DB currently holds, so each sync writes only the delta.
  // key = "<table>:<id>".
  final Map<String, ({String table, String body})> _baseline = {};
  Map<String, String> _baselineSettings = {};

  bool get enabled => _db != null;

  /// Whether the DB is safe to read the whole library from: it's open and the
  /// one-time import finished cleanly (not a fallback-to-JSON). When false the
  /// caller must stay on the JSON load path.
  bool get usableForReads => _db != null && (lastImport?.dbUsable ?? false);

  static List<(String, List<Map<String, Object?>>)> _tablesOf(AppSnapshot s) =>
      [
        ('notes', s.notes),
        ('cards', s.cards),
        ('books', s.books),
        ('impulses', s.impulses),
        ('spaces', s.spaces),
      ];

  /// Opens the DB and runs the one-time JSON import. [loadLegacy] returns the
  /// current JSON library (the migration source). Never throws.
  Future<void> init({
    required Future<AppData?> Function() loadLegacy,
    DatabaseFactory? factory,
    String? path,
  }) async {
    // Idempotent: `AppState.init` runs again on a restore, and we must keep the
    // already-open handle and its baseline rather than re-opening/leaking one.
    if (_db != null) return;
    BraimDatabase? db;
    try {
      db = await BraimDatabase.open(
          factory: factory ?? _factory, path: path ?? _path);
      lastImport = await DbMigrator(db).ensureImported(loadLegacy: loadLegacy);
      _db = db;
      await _seedBaseline();
      _needsIndexRebuild =
          db.ftsAvailable && await db.metaGet(ftsBuiltKey) != ftsBuiltTag;
    } catch (_) {
      // sqflite unavailable or open failed: the shadow is simply off. Don't
      // leak a half-opened handle.
      _db = null;
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  Future<void> _seedBaseline() async {
    final snap = await _db!.readSnapshot();
    _baseline.clear();
    for (final (table, rows) in _tablesOf(snap)) {
      for (final row in rows) {
        _baseline['$table:${row['id']}'] =
            (table: table, body: row['body'] as String);
      }
    }
    _baselineSettings = Map.of(snap.settings);
  }

  /// Mirrors [data] into the DB, writing only rows/settings that changed since
  /// the last sync. Never throws; returns whether the DB now holds [data]
  /// (false when the store is off or the write failed, in which case the
  /// caller must keep treating JSON as the freshest copy; the write is retried
  /// on the next save).
  Future<bool> syncFromAppData(AppData data) async {
    final db = _db;
    if (db == null) return false;
    try {
      final snap = snapshotFromAppData(data);

      final current = <String, ({String table, Map<String, Object?> row})>{};
      for (final (table, rows) in _tablesOf(snap)) {
        for (final row in rows) {
          current['$table:${row['id']}'] = (table: table, row: row);
        }
      }

      final upserts = <({String table, Map<String, Object?> row})>[];
      current.forEach((key, v) {
        final base = _baseline[key];
        if (base == null || base.body != v.row['body']) upserts.add(v);
      });

      final deletes = <({String table, String id})>[];
      _baseline.forEach((key, v) {
        if (!current.containsKey(key)) {
          deletes.add((table: v.table, id: key.substring(v.table.length + 1)));
        }
      });

      final settingsUpserts = <MapEntry<String, String>>[];
      snap.settings.forEach((k, val) {
        if (_baselineSettings[k] != val) settingsUpserts.add(MapEntry(k, val));
      });

      if (upserts.isEmpty && deletes.isEmpty && settingsUpserts.isEmpty) {
        return true;
      }

      // Search docs only for the rows that changed (the index mirrors the
      // notes and cards tables; nothing else is searchable).
      final ftsOn = db.ftsAvailable;
      Map<String, Note>? notesById;
      Map<String, TweetCard>? cardsById;
      SearchDoc? docFor(String table, String id) {
        if (table == 'notes') {
          notesById ??= {for (final n in data.notes) n.id: n};
          final n = notesById![id];
          return n == null ? null : noteSearchDoc(n);
        }
        if (table == 'cards') {
          cardsById ??= {for (final c in data.cards) c.id: c};
          final c = cardsById![id];
          return c == null ? null : cardSearchDoc(c);
        }
        return null;
      }

      await db.db.transaction((txn) async {
        for (final u in upserts) {
          await txn.insert(u.table, u.row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          if (!ftsOn) continue;
          final id = u.row['id'] as String;
          final doc = docFor(u.table, id);
          if (doc == null) continue;
          await txn.delete(BraimDatabase.ftsTable,
              where: 'id = ?', whereArgs: [id]);
          await txn.insert(
              BraimDatabase.ftsTable, BraimDatabase.ftsRow(id, doc));
        }
        for (final d in deletes) {
          await txn.delete(d.table, where: 'id = ?', whereArgs: [d.id]);
          if (ftsOn && (d.table == 'notes' || d.table == 'cards')) {
            await txn.delete(BraimDatabase.ftsTable,
                where: 'id = ?', whereArgs: [d.id]);
          }
        }
        for (final s in settingsUpserts) {
          await txn.insert('settings', {'key': s.key, 'value': s.value},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      for (final u in upserts) {
        _baseline['${u.table}:${u.row['id']}'] =
            (table: u.table, body: u.row['body'] as String);
      }
      for (final d in deletes) {
        _baseline.remove('${d.table}:${d.id}');
      }
      for (final s in settingsUpserts) {
        _baselineSettings[s.key] = s.value;
      }
      return true;
    } catch (_) {
      // Shadow write failed; drop the baseline so the next sync re-diffs from
      // the DB's real state rather than a stale in-memory one.
      try {
        await _seedBaseline();
      } catch (_) {}
      return false;
    }
  }

  // ---- full-text search ---------------------------------------------------

  /// Whether full-text search is available (DB open and its SQLite has FTS5).
  bool get searchAvailable => _db?.ftsAvailable ?? false;

  /// Builds the search index the first time this DB is opened with FTS5
  /// available (or after [ftsBuiltTag] is bumped), from the library the app
  /// just loaded. A cheap no-op once built, or when FTS isn't available; a
  /// failed build is retried next launch and search falls back meanwhile.
  Future<void> ensureSearchIndex(AppData data) async {
    final db = _db;
    if (db == null || !db.ftsAvailable || !_needsIndexRebuild) return;
    try {
      await db.rebuildSearchIndex({
        for (final n in data.notes) n.id: noteSearchDoc(n),
        for (final c in data.cards) c.id: cardSearchDoc(c),
      });
      await db.metaSet(ftsBuiltKey, ftsBuiltTag);
      _needsIndexRebuild = false;
    } catch (_) {}
  }

  /// Ranked full-text hits for [query] (best first), or null when the index
  /// isn't available so the caller can fall back to its in-memory search.
  Future<List<SearchHit>?> search(String query) async {
    final db = _db;
    if (db == null || !db.ftsAvailable) return null;
    try {
      return await db.search(query);
    } catch (_) {
      return null;
    }
  }

  /// Reads the whole library back out of the DB. Used by the Phase 1 shadow
  /// consistency check and (in Phase 2) as the real read path. Null when the
  /// shadow is disabled.
  Future<AppData?> readAppData() async {
    final db = _db;
    if (db == null) return null;
    return appDataFromSnapshot(await db.readSnapshot());
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
