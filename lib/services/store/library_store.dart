import 'dart:async';

import '../db/db_store.dart' show SearchHit;
import '../storage_service.dart' show AppData;
import 'library_delta.dart';

/// Where the library lives. [AppState] holds the library in memory and talks
/// only to this: the phone's SQLite + JSON store, the browser's own IndexedDB
/// copy (web local mode), or the phone over the LAN (web remote mode).
abstract class LibraryStore {
  /// Opens the store and returns this launch's library. [restored] means a
  /// backup has just overwritten the store's files (phone only).
  Future<AppData> load({bool restored = false});

  /// Runs once the loaded library is live in memory (after trash purge,
  /// circuit repair and the share-inbox drain). [snapshot] builds the library
  /// as it now stands.
  Future<void> afterLoad(AppData Function() snapshot);

  /// Persists (or sends) whatever changed in [snapshot]. Fire-and-forget:
  /// writes are serialized inside the store and a failure is retried on the
  /// next save. [rev] is the library revision [snapshot] was taken at.
  void save(AppData snapshot, int rev);

  /// Waits until everything saved so far has landed (app pause, before a
  /// backup or restore). [snapshot] builds the current library if the store
  /// wants a checkpoint copy.
  Future<void> flushNow({
    required bool loaded,
    required int rev,
    required AppData Function() snapshot,
  });

  /// Ranked full-text hits for [query], or null when this store has no index
  /// (the caller falls back to its in-memory search).
  Future<List<SearchHit>?> search(String query);

  /// Changes made somewhere else (the phone, in remote mode). Local stores
  /// never emit.
  Stream<LibraryDelta> get incoming;

  /// Records rows [AppState] just took from [incoming] (re-serialized from
  /// memory), or dropped from memory without deleting them anywhere, as what
  /// the store already holds — so the next [save] neither echoes them back
  /// nor turns a dropped row into a delete.
  void adopt(LibraryDelta applied);
}
