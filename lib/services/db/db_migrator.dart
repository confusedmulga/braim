import '../storage_service.dart' show AppData;
import 'braim_database.dart';
import 'db_snapshot.dart';

/// What the one-time JSON -> SQLite import did on a given launch.
enum ImportOutcome {
  /// The marker was already set; nothing to do.
  alreadyImported,

  /// No legacy store to import at all (a brand-new install).
  freshUser,

  /// Legacy data was imported and verified into the DB.
  imported,

  /// Something went wrong; the caller must keep running on the JSON store this
  /// launch and retry next time. The DB is NOT trusted and the marker is unset.
  fallbackToJson,
}

class ImportResult {
  const ImportResult(this.outcome, this.detail);
  final ImportOutcome outcome;
  final String detail;

  bool get dbUsable =>
      outcome == ImportOutcome.imported ||
      outcome == ImportOutcome.alreadyImported ||
      outcome == ImportOutcome.freshUser;

  @override
  String toString() => 'ImportResult(${outcome.name}: $detail)';
}

/// Runs the one-time migration of the legacy `keepy_data.json` library into the
/// SQLite store, with the data-safety guarantees from the migration plan:
///
/// - The legacy JSON is only ever READ, never deleted or modified.
/// - The import runs exactly once, guarded by a marker in the `meta` table.
/// - Row counts are verified against the source before the DB is trusted.
/// - Any failure leaves the marker unset and returns [ImportOutcome.fallbackToJson]
///   so the app keeps running on the JSON store and retries next launch.
class DbMigrator {
  DbMigrator(this.db);

  final BraimDatabase db;

  static const markerKey = 'json_import_done';
  static const summaryKey = 'json_import_summary';

  Future<ImportResult> ensureImported({
    required Future<AppData?> Function() loadLegacy,
  }) async {
    // 1. Already migrated?
    if (await db.metaGet(markerKey) == 'true') {
      return const ImportResult(ImportOutcome.alreadyImported, 'marker set');
    }

    // 2. Read the legacy JSON store (never mutated). [loadLegacy] yields null
    //    when there is no legacy store at all, and throws when one exists but
    //    can't be read right now.
    AppData? data;
    try {
      data = await loadLegacy();
    } catch (e) {
      // A store is there but unreadable (torn file, I/O hiccup). Marking done
      // here would hide that still-intact library behind an empty DB for good,
      // so stay on the JSON path this launch and retry next time.
      return ImportResult(
          ImportOutcome.fallbackToJson, 'legacy read failed: $e');
    }

    if (data == null) {
      // Brand-new install: nothing to import. Mark done and start on the
      // (empty) DB.
      await db.metaSet(markerKey, 'true');
      return const ImportResult(ImportOutcome.freshUser, 'no legacy store');
    }
    // A readable store, even an empty library, is imported below, so an empty
    // file is never mistaken for a fresh install.

    // 3. Import + verify. On any problem, do NOT set the marker.
    try {
      final snap = snapshotFromAppData(data);

      final mapCheck = verifySnapshot(data, snap);
      if (!mapCheck.ok) {
        return ImportResult(
            ImportOutcome.fallbackToJson, 'snapshot mismatch: ${mapCheck.summary}');
      }

      await db.writeSnapshot(snap);

      // Verify what actually landed in SQLite matches what we meant to write.
      final landed = await db.entityRowCount();
      final expected = snap.entityCount;
      if (landed != expected) {
        return ImportResult(ImportOutcome.fallbackToJson,
            'db has $landed entity rows, expected $expected');
      }

      await db.metaSet(summaryKey, mapCheck.summary);
      await db.metaSet(markerKey, 'true');
      return ImportResult(
          ImportOutcome.imported, 'imported $expected entities');
    } catch (e) {
      return ImportResult(ImportOutcome.fallbackToJson, 'import threw: $e');
    }
  }
}
