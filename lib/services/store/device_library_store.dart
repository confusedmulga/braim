import 'dart:async';

import '../db/db_store.dart';
import '../storage_service.dart';
import 'library_delta.dart';
import 'library_store.dart';

/// The phone's store, exactly as the app has always persisted: SQLite is the
/// live store (one edit writes one row), with the whole-library JSON file as
/// the one-time import source, the fallback when the DB isn't usable, and a
/// checkpoint copy refreshed on pause and before backups.
class DeviceLibraryStore implements LibraryStore {
  /// [dbStore] lets tests hand in a store on an FFI / temp-file database; the
  /// app uses the default (the device's `braim.db`).
  DeviceLibraryStore({DbStore? dbStore}) : _dbStore = dbStore ?? DbStore();

  final _storage = StorageService.instance;

  /// SQLite store of the library: the app loads from here at startup and
  /// mirrors every save into it. Disabled where sqflite is unavailable (unit
  /// tests), where the app simply stays on the JSON store.
  final DbStore _dbStore;

  Future<void> _writeChain = Future.value();
  Future<void> _dbWriteChain = Future.value();

  /// The `rev` captured at the last whole-file JSON checkpoint, so repeated
  /// pauses with no edits in between don't re-write an identical file.
  int _revAtJsonCheckpoint = -1;

  /// Whether this launch has already raised the JSON-ahead flag (it only needs
  /// raising once per stretch of JSON-mode saves).
  bool _jsonAheadMarked = false;

  /// Whether the JSON read at [load] was ahead of the DB (a restore, or saves
  /// from a launch where the DB was down) and must be folded back into it.
  bool _jsonAhead = false;

  /// Whether SQLite is the live store this launch: it imported cleanly and the
  /// read flag is on. When false (fallback, or unit tests where sqflite is off)
  /// the app runs on the JSON store exactly as it did before the migration.
  bool get _dbIsPrimary => DbStore.readFromDb && _dbStore.usableForReads;

  /// Migration Phase 2: SQLite is the source of truth once it has imported
  /// cleanly and [DbStore.readFromDb] is on; otherwise we fall back to the JSON
  /// store. After a restore ([restored]) the JSON on disk is reloaded and
  /// folded back into the DB (which the restore didn't touch) in [afterLoad],
  /// so the next launch, reading from the DB, sees it.
  @override
  Future<AppData> load({bool restored = false}) async {
    // Lazily load the legacy JSON: it's the one-time import source, the fallback
    // when the DB isn't usable, and the authoritative copy right after a
    // restore. On a normal launch with the DB in charge it isn't read at all.
    AppData? legacyCache;
    // The importer's view of the JSON: null = no legacy store at all (a fresh
    // install), throws = a store exists but can't be read. The importer must
    // not mark done on a throw, or the intact library would sit hidden behind
    // an empty DB.
    Future<AppData?> loadForImport() async =>
        legacyCache ??= await _storage.loadLegacyForImport();
    // The app's own view: always yields a library (empty at worst).
    Future<AppData> loadLegacy() async =>
        legacyCache ??= await _storage.load();

    // Bring up the SQLite store and run the one-time import. Idempotent (a
    // no-op once open), never throws, and disables itself where sqflite is
    // missing (unit tests) so we transparently stay on JSON there.
    await _dbStore.init(loadLegacy: loadForImport);

    // Whether the on-disk JSON is the freshest copy of the library: right after
    // a restore, or when an earlier launch had to save to JSON because the DB
    // wasn't usable then (see StorageService.markJsonAhead). Either way the
    // JSON is read and folded back into the DB in [afterLoad].
    _jsonAhead = restored || await _storage.jsonAhead;

    // Pick this launch's source of truth.
    if (!_jsonAhead && DbStore.readFromDb && _dbStore.usableForReads) {
      return (await _dbStore.readAppData()) ?? await loadLegacy();
    }
    return loadLegacy();
  }

  @override
  Future<void> afterLoad(AppData Function() snapshot) async {
    if (_jsonAhead && _dbStore.enabled) {
      // The JSON is ahead of the DB (a restore, or JSON-only edits from a
      // launch where the DB was down); reconcile the DB from it. The dirty-diff
      // handles both added and removed items, so a smaller restored library
      // correctly drops the extra DB rows. Routed through the same write chain
      // as [save] so it can't overlap a debounced save firing right after,
      // then awaited so the DB is consistent on return. The flag is lowered
      // only once the DB really holds the library.
      final snap = snapshot();
      var synced = false;
      _dbWriteChain = _dbWriteChain.then((_) async {
        synced = await _dbStore.syncFromAppData(snap);
      }).catchError((_) {});
      await _dbWriteChain;
      if (synced) {
        await _storage.clearJsonAhead();
        _jsonAheadMarked = false;
      }
    }

    // First launch with full-text search available (or after an index bump):
    // index the library the app just loaded. Chained after any reconcile above
    // and ahead of any later save, so the index never lags a newer row.
    if (_dbStore.enabled) {
      final snap = snapshot();
      _dbWriteChain = _dbWriteChain
          .then((_) => _dbStore.ensureSearchIndex(snap))
          .catchError((_) {});
    }
  }

  @override
  void save(AppData snapshot, int rev) {
    // Phase 3: SQLite is the sole per-save store — one edit writes one row, not
    // the whole library. Serialized on its own chain; a failed DB write is
    // retried on the next save and never surfaces.
    _dbWriteChain = _dbWriteChain.then((_) async {
      await _dbStore.syncFromAppData(snapshot);
    }).catchError((_) {});
    // The whole-file JSON is written per save only when the DB isn't the live
    // store (fallback / unit tests) or the Phase 2 mirror is kept on; otherwise
    // it's refreshed at checkpoints in flushNow() as a rollback + backup copy.
    if (!_dbIsPrimary || DbStore.writeJsonOnSave) {
      _revAtJsonCheckpoint = rev;
      // Saving to JSON because the DB isn't the live store: flag the JSON as
      // ahead (once per stretch), so the next launch that does get the DB
      // folds these edits into it instead of reading the stale DB over them.
      final markAhead = !_dbIsPrimary && !_jsonAheadMarked;
      if (markAhead) _jsonAheadMarked = true;
      // catchError: one failed write (disk full, say) must not poison the
      // chain and silently skip every save after it.
      _writeChain = _writeChain.then((_) async {
        if (markAhead) await _storage.markJsonAhead();
        await _storage.save(snapshot);
      }).catchError((_) {});
    }
  }

  @override
  Future<void> flushNow({
    required bool loaded,
    required int rev,
    required AppData Function() snapshot,
  }) async {
    // Phase 3 checkpoint: per-save JSON writes are off, so refresh the on-disk
    // JSON here (pause, before a backup/restore) — it keeps `keepy_data.json`
    // current for the backup zip and as the rollback artifact. Skipped when the
    // library hasn't changed since the last checkpoint, or when [save] already
    // wrote JSON at this revision.
    if (loaded &&
        _dbIsPrimary &&
        !DbStore.writeJsonOnSave &&
        rev != _revAtJsonCheckpoint) {
      _revAtJsonCheckpoint = rev;
      final snap = snapshot();
      _writeChain =
          _writeChain.then((_) => _storage.save(snap)).catchError((_) {});
    }
    await _writeChain;
    await _dbWriteChain;
  }

  @override
  Future<List<SearchHit>?> search(String query) => _dbStore.search(query);

  /// The phone is the library of record: nothing arrives from elsewhere
  /// through the store (browser edits come in via the phone server, which
  /// applies them to [AppState] like any local edit).
  @override
  Stream<LibraryDelta> get incoming => const Stream.empty();

  @override
  void adopt(LibraryDelta applied) {}
}
