# SQLite Migration Plan (Braim)

A build reference for moving Braim's local storage from a single `keepy_data.json`
blob to an embedded SQLite database, without losing any data testers already have.

Follow the phases in order. Do not start a phase until the previous phase's
checklist is fully ticked and its tests are green. The single most important rule
is in Phase 4: **the migration never deletes the original JSON.**

---

## 1. Goals and non-goals

### Goals
- Kill write amplification: an edit writes one row, not the whole library.
- Contain corruption: a fault damages a row, not the entire library (ACID + WAL).
- Scale to large libraries without slow startup or heavy autosaves.
- Preserve 100% of existing tester data through the upgrade.
- Keep a JSON export for backups and portability.

### Non-goals (explicitly out of scope for this migration)
- Moving search / backlinks / wiki-link resolution / feed sorting off the
  in-memory lists. `AppState` stays in memory. Those become DB-powered later, if
  ever, as a separate project.
- Changing the on-device image storage. Images stay as files in `/images`,
  referenced by path. The DB stores paths only, never image bytes.
- Cross-device live sync. (The `updatedAt` last-write-wins fields are preserved so
  a future sync layer still has what it needs.)

---

## 2. Guiding principle: data safety first

Every decision below is subordinate to this: **a tester must never lose data, and
the worst realistic outcome of a bad build is "the app keeps running on the old
JSON store," never "the app is empty."**

Concretely, that means:
1. The importer only ever **reads** `keepy_data.json`. It is never deleted or
   overwritten by the migration.
2. The import runs **exactly once**, guarded by a marker.
3. After import, **row counts are verified** against the JSON before the DB is
   trusted as the source of truth.
4. If the DB is missing/empty or the import throws, the app **falls back** to the
   existing JSON load path.
5. The JSON file is retained after a successful import as a **rollback artifact**
   (can be pruned in a later release once the DB has proven itself).

---

## 3. Current architecture (as-is)

- One file: `keepy_data.json` in `getApplicationDocumentsDirectory()`, plus a
  `keepy_data.bak` rotated copy. Images live separately in `/images`.
  (`lib/services/storage_service.dart`)
- `StorageService.save(AppData)` serializes the **entire** `AppData` to JSON and
  writes it: temp file (`flush: true`) -> rotate current to `.bak` -> rename temp
  into place. JSON encode/decode runs on a background isolate.
- `StorageService.load()` tries the main file, then `.bak`, then `AppData.empty()`.
- `AppState` holds the whole library in memory (`_notes`, `_cards`, `_books`,
  `_impulses`, `_spaces`, plus ~30 settings fields). Every mutation calls
  `_persist()`, which marks dirty and debounces a full-file flush by 400 ms
  (`_flush()` -> `StorageService.save`). `flushNow()` forces an immediate write.
- Models expose `toJson()` / `fromJson()`. `AppData` (in `storage_service.dart`)
  aggregates the 5 entity lists plus the settings fields.

Entities and their shared shape:

| Entity      | Notes                                                                 |
|-------------|-----------------------------------------------------------------------|
| `Note`      | Home notes **and** journal entries (`journalDate`) **and** book pages (`bookId`, `bookPageKind`, `bookOrder`). Holds `blocks`, `annotations`, `history`, `tags`. |
| `TweetCard` | Sparks. Holds `blocks`, `fontScale`, author metadata.                 |
| `Book`      | Book metadata only (its pages are `Note`s with `bookId`).             |
| `Impulse`   | Reflex. Nested `sections -> subsections -> threads`, plus flat `threads`. |
| `Space`     | Folder (Cortex).                                                      |

All five carry `id`, `createdAt`, `updatedAt`, `archived`, `deletedAt`.

---

## 4. Target architecture (to-be)

A **hybrid** design: SQLite is the durable container; the rich, deeply nested
bodies stay as JSON in a column.

- One table per top-level entity: `notes`, `cards`, `books`, `impulses`, `spaces`.
- Each row = a small set of **real columns** for the fields we filter/sort/scan on,
  plus a `body` TEXT column holding that entity's full `toJson()` string.
- The models keep their existing `toJson` / `fromJson` unchanged. Reading a row =
  `fromJson(jsonDecode(body))`. Writing a row = set columns + `body = jsonEncode(toJson())`.
- A `settings` key/value table for the ~30 app-level preferences.
- A `meta` table for schema version and the one-time migration marker.
- `AppState` still loads all rows into memory at startup and serves feeds/search
  from memory, exactly as today. Only the persistence layer changes.

Why hybrid and not fully relational: Quill deltas, `NoteBlock` lists, annotations,
and the `Section -> Subsection -> Thread` tree do not map cleanly to columns.
Storing them as JSON keeps the model code intact and still delivers the two wins
that matter (incremental writes + corruption containment). Real columns are added
only for what we actually query.

---

## 5. Technology choice

**Recommended: Drift** (`drift`, `drift_flutter` / `sqlite3_flutter_libs`).
- Typed tables and queries, compile-time checked.
- First-class **schema migrations** with versioning and migration tests.
- Runs the DB on a background isolate.
- Bundles a modern SQLite via `sqlite3_flutter_libs` (predictable across devices).
- Cost: `build_runner` code generation.

Alternative: **sqflite** (thinner, no code-gen, you write SQL by hand and manage
migrations manually).

**DECIDED (Phase 0): sqflite.** Because every entity is stored as a JSON `body`
column, SQLite is a dumb durable container and Drift's typed-query strength is
mostly wasted, so the leaner, code-gen-free option was chosen. Schema migrations
here are trivial (add a column; bodies self-heal via `fromJson` defaults). Added
`sqflite` (app) + `sqflite_common_ffi` (dev, for host tests).

---

## 6. Schema (v1)

Common columns per entity table (indexed where noted):

- `id TEXT PRIMARY KEY`
- `updated_at INTEGER` (epoch ms; index) - ordering, last-write-wins
- `created_at INTEGER`
- `archived INTEGER` (0/1; index)
- `deleted_at INTEGER NULL` (epoch ms; index) - Recently Deleted
- `body TEXT NOT NULL` - `jsonEncode(entity.toJson())`

Per-entity extra columns (for the filters/sorts the feeds actually use):

**notes**
- `space_id TEXT NULL` (index) - folder feed
- `book_id TEXT NULL` (index) - book pages
- `book_page_kind TEXT` , `book_order INTEGER` - book ordering
- `journal_date TEXT NULL` (index) - journal-by-day
- `pinned INTEGER` (index)
- `title TEXT` - optional, for future FTS
- (later, optional) an FTS5 virtual table `notes_fts(title, plain)` for search.

**cards**
- `space_id TEXT NULL` (index)
- `pinned INTEGER` (index)
- `url TEXT` - dedupe/lookups

**books**
- (title in `body`; add `title TEXT` only if needed for lists)

**impulses**
- `paused INTEGER`
- `category TEXT` (index) - category tabs

**spaces**
- `name TEXT`

**settings** (key/value)
- `key TEXT PRIMARY KEY`
- `value TEXT` (JSON-encoded scalar or object)
- Holds every `AppData` non-entity field: `darkMode`, `noteBodyFont`, reader prefs,
  `readerPositions`, `readerBookmarks`, `pinnedReflexId`, `journalOrder`, etc.

**meta**
- `key TEXT PRIMARY KEY`, `value TEXT`
- Rows: `schema_version`, `json_import_done`, `json_import_summary`.

Indexes to create: `updated_at`, `deleted_at`, `archived` on all entity tables;
plus `space_id`, `book_id`, `journal_date`, `pinned` on `notes`; `space_id`,
`pinned` on `cards`; `category` on `impulses`.

---

## 7. Persistence strategy

### Read path (startup)
- Open DB. Read all rows from the five tables, `fromJson(jsonDecode(body))` each
  into the in-memory lists (same lists `AppState` uses today). Read `settings`
  into the corresponding `AppState` fields.
- This is O(library size) once at startup, same as decoding the JSON today, but
  can later be made lazy/paged. Not required for v1.

### Write path (the key change)
Replace the whole-file flush with a **dirty-diff flush** so only changed rows are
written. This is centralized in `_flush()` and needs **no changes** to the ~100
mutation methods in `AppState`:

1. Keep a snapshot map `lastSaved[id] = contentHash(entity)` per table, captured
   at the end of each successful flush.
2. On `_flush()`, for each table, compute the current `contentHash` per entity and
   diff against `lastSaved`:
   - new or changed id -> `upsert` row
   - id present last time but gone now -> `delete` row (respecting soft-delete:
     soft-deleted items still exist as rows with `deleted_at` set; hard purge
     deletes the row)
3. Apply all upserts/deletes in **one transaction**. Update `lastSaved`.
4. `settings` are small; write them wholesale each flush (cheap) or diff similarly.

`contentHash` = a stable hash of `jsonEncode(toJson())` (the same JSON we store).
Computing it for every entity each flush is in-memory and cheap relative to the
disk write it saves. Keep the existing 400 ms debounce and `flushNow()`.

Future optimization (not v1): write-through DAOs called directly from mutation
methods, removing the diff. Only worth it if the diff ever shows up in profiling.

---

## 8. Migration and data-safety plan (critical)

This is what protects tester data. Build and test it before anything reads from
the DB in anger.

### One-time importer (`json_import_done` guarded)
On first launch after the update:

1. Open (create) the DB. Read `meta.json_import_done`.
2. If `json_import_done == true` -> skip import, load from DB. Done.
3. Else, look for the legacy store via the existing loader
   (`StorageService.load()` reads `keepy_data.json`, then `.bak`).
   - If no legacy data and no DB rows -> brand-new user; mark `json_import_done`,
     start empty. Done.
4. If legacy `AppData` found:
   a. In a single transaction, insert every entity as a row
      (`body = jsonEncode(entity.toJson())`, columns filled) and every settings
      field into `settings`.
   b. **Verify**: count rows per table and compare to the legacy list lengths;
      compare a checksum of settings. Store the summary in `meta.json_import_summary`.
   c. If counts match -> set `json_import_done = true`, commit. The app now reads
      from the DB.
   d. If counts do NOT match or the transaction throws -> **roll back the
      transaction, do NOT set the marker, and fall back to the JSON load path** for
      this launch. Log/telemetry the failure. Retry on next launch. The user runs
      on JSON the whole time; nothing is lost.
5. **Never delete `keepy_data.json` / `.bak`.** After a successful import, keep them
   as a rollback artifact. A later, separate release may rename them to
   `keepy_data.migrated.json` once the DB has proven stable in the field.

### Fallback and rollback
- Fallback (per launch): any import failure or DB-open failure -> read JSON, keep
  the app fully usable, retry migration next launch.
- Rollback (per release): because the JSON is intact, a hotfix that reverts to the
  JSON store loses nothing. Keep the JSON code path compiled in for at least one
  release after the DB ships.

### External precondition (call it out to whoever ships the release)
Android only preserves app storage across an **in-place update**: same
`applicationId` (`com.solo.braim`) and the **same upload keystore**. A different
key or package forces an uninstall that wipes storage *before* any of this code
runs. This is the normal update rule, unchanged by the migration.

---

## 9. Backup and restore

- Keep the backup/export format as **JSON** for portability and Drive
  compatibility: the exporter builds `AppData` from the in-memory lists (or reads
  all rows and `fromJson`s them) and writes the same JSON structure as today, zipped
  with `/images`. No change to the backup file format testers/Drive already use.
- Restore imports that JSON straight into the DB via the same importer routine
  (treat the restore file exactly like the legacy `keepy_data.json`).
- Net effect: the on-disk primary store changes; the backup artifact does not.

---

## 10. Phased rollout

Each phase is independently shippable-safe (nothing destructive until the importer
is proven).

- **Phase 0 - Spike (no app wiring).** Add Drift, define schema, write the importer
  and the round-trip test against seed data + a captured real export. Prove
  import + verify + fallback in tests only. Nothing in the running app changes yet.
- **Phase 1 - DB behind a flag, JSON still source of truth.** On launch, run the
  importer into the DB, but the app still **reads and writes JSON** as today. The
  DB is written as a shadow. Compare shadow vs JSON in tests/telemetry. Zero risk.
- **Phase 2 - Flip reads to DB, keep JSON shadow-write.** App reads from DB;
  continues writing JSON too (belt-and-suspenders) for one release. If anything is
  wrong in the field, revert the flag -> back on JSON instantly.
- **Phase 3 - DB is sole store.** Stop writing JSON on save. Keep the importer,
  the JSON fallback, and export-to-JSON for backups. Retain the legacy file as a
  rollback artifact.
- **Phase 4 - Cleanup (later release).** Once stable, drop the shadow paths; rename
  the legacy JSON to an archived name. Optionally add FTS5 search.

---

## 11. Testing strategy

Add these before the corresponding phase ships:

- **Round-trip import (Phase 0, blocking):** build a full library (use
  `SeedData.build` plus a checked-in real export fixture) -> write it as JSON ->
  run the importer -> assert every note/card/book/impulse/space and its fields
  (blocks, annotations, history, tags, threads, sections, fontScale,
  checkedToBottom, journalDate, bookId/pageKind/order, reminders, reader
  bookmarks/positions, all settings) survives byte-for-byte through `toJson`.
- **Count verification path:** simulate a short import (fewer rows than JSON) ->
  assert the marker is NOT set and the app falls back to JSON.
- **Idempotency:** run the importer twice -> no duplicates, marker respected.
- **Dirty-diff flush correctness:** mutate one note -> assert exactly one row
  upserted, others untouched; delete/purge -> row removed; soft-delete -> row kept
  with `deleted_at`.
- **Schema migration test (Drift):** verify v(n-1) -> v(n) upgrades on a populated
  DB without loss (Drift's migration test harness).
- **Corruption/fallback:** corrupt the DB file -> app opens, detects, falls back to
  JSON (or rebuilds from the last good JSON), never shows empty.
- **Existing suite stays green** (`flutter test`), including the current
  serialization round-trip tests.

---

## 12. Build checklist (tick in order)

Phase 0 — DONE (all green)
- [x] Decide Drift vs sqflite -> **sqflite**. Added `sqflite` + dev `sqflite_common_ffi`.
- [x] Single source of truth for serialization: `AppData.toJson` / `AppData.fromJson`
      + `settingsToJson()`, with the JSON `save`/`load` pointed at them
      (`lib/services/storage_service.dart`).
- [x] `body`-column codec: `lib/services/db/db_snapshot.dart` (`AppSnapshot`,
      `snapshotFromAppData`, `appDataFromSnapshot`, `verifySnapshot`), reusing the
      existing model serializers unchanged.
- [x] Schema v1 (`meta`, `settings`, 5 entity tables + indexes) and bulk
      write/read + incremental upsert/delete: `lib/services/db/braim_database.dart`.
- [x] One-time importer (guard, transaction, snapshot verify, DB row-count verify,
      fallback, never deletes JSON): `lib/services/db/db_migrator.dart`.
- [x] Tests green: `test/db_snapshot_test.dart` (pure round-trip / idempotency /
      count-verify) and `test/db_migrator_test.dart` (real SQLite via FFI: import,
      read-back byte-for-byte, one-time guard, fresh user, safe fallback).

Phase 1 — DONE (verified on device)
- [x] `DbStore` (`lib/services/db/db_store.dart`): opens the DB, runs the one-time
      import, and mirrors each save via a dirty-diff (only changed rows/settings).
      Self-disables where sqflite is unavailable (unit tests).
- [x] Wired into `AppState`: `init()` brings up the shadow in the background from
      the just-loaded JSON (never blocks startup); `_flush()` mirrors every save
      onto a separate write chain. JSON remains the source of truth.
- [x] Shadow-consistency test `test/db_store_test.dart` (real SQLite via FFI):
      import reads back identical, a later save mirrors only the delta and stays
      consistent, re-syncing unchanged data is a safe no-op.
- [x] On-device check: app rebuilt with sqflite, no startup crash; `braim.db`
      created; `meta.json_import_done=true`; row counts (20/5/1/1/3) and the
      verify summary all `ok`. JSON untouched.

Phase 2 — DONE (read flip proven on device)
- [x] Read path flipped: `AppState.init` loads the library from the DB when it's
      imported cleanly and `DbStore.readFromDb` is on (`DbStore.usableForReads`),
      else falls back to JSON. The JSON is now read lazily — only as the import
      source, the fallback, or a restore's authoritative copy — so a normal
      launch skips the JSON decode entirely. Load/apply split into
      `_applyData` (shared by cold start and post-restore reload).
- [x] Writes unchanged from Phase 1: the dirty-diff `DbStore.syncFromAppData` is
      the primary store write; the whole-file JSON `save` is kept alongside as a
      belt-and-suspenders copy and the instant-revert path. Both serialize the
      same `_snapshot()`. `flushNow()` now awaits the DB chain too (the next
      launch reads from it). `DbStore.init` is idempotent so a restore re-init
      keeps the open handle + baseline.
- [x] Restore reconciled: local-file and Drive restore call `init(restored:true)`,
      which reloads the restored JSON, applies it, and dirty-diffs it into the DB
      (dropping rows the restore removed) so the next DB read reflects the
      restore. Routed through the write chain so it can't overlap a debounced save.
- [x] The instant-revert flag: `DbStore.readFromDb` (const). Flip to false +
      rebuild to read JSON again; the DB keeps being written, so no data is
      stranded either way.
- [x] Tests green (74): `test/db_store_test.dart` adds `usableForReads` after a
      clean import + a restore-shaped reconcile that drops items and reads back
      the smaller library; existing app_state suite still exercises the JSON
      fallback path (sqflite is off in unit tests).
- [x] On-device proof (braim_test AVD, in-place update, data preserved
      20/5/1/1/3): renamed a note in the DB only, forced a flush via the share
      inbox, and the DB-only title surfaced in `keepy_data.json` after launch —
      i.e. the app loaded it from the DB. No crash; JSON untouched as a store.
- [ ] Ship to closed testing; watch for issues; `readFromDb` can revert to JSON.

Phase 3 — DONE (DB-only saves proven on device)
- [x] Per-save JSON write turned off: `_flush()` writes only the DB when it's the
      live store (`_dbIsPrimary`), so one edit writes one row — the write
      amplification the migration set out to kill. JSON still writes per-save in
      fallback mode (DB unusable) and in unit tests, so those paths are unchanged.
- [x] JSON kept fresh at checkpoints, not frozen: `flushNow()` (app pause, and
      before every backup/restore — all three export call sites already call it)
      re-writes the whole `keepy_data.json` from the current library, guarded by a
      `_rev` check so idle pauses don't rewrite an identical file. This keeps the
      backup zip current and the rollback artifact fresh, and refreshes the JSON
      fallback so an emergency `readFromDb=false` revert lands on near-current
      data. A `_loaded` guard skips the write mid-init.
- [x] Backup export unchanged and correct: because `flushNow()` refreshes the
      JSON immediately before `exportToTempFile()` zips it, the backup reflects
      current data with no change to `BackupService`. Restore still writes
      `keepy_data.json` then `init(restored: true)` reconciles it into the DB
      (Phase 2 wiring) — so restore-into-DB already works.
- [x] Granular revert flag `DbStore.writeJsonOnSave` (ships false). Flip true to
      restore the Phase 2 whole-file-JSON-per-save mirror without giving up DB
      reads; `readFromDb=false` remains the coarser full-JSON revert.
- [x] Tests green (74) incl. the file-level backup export/restore + `/images`
      round-trip (`test/backup_service_test.dart`); `BackupService` untouched.
- [x] On-device proof (braim_test AVD): an edit updated the DB (20->21) while
      `keepy_data.json` stayed byte-for-byte unchanged (per-save is DB-only);
      backgrounding then refreshed the JSON to the current library. No crash;
      data intact (20/5/1/1/3). Legacy JSON retained on disk as rollback.

Post-Phase 3 hardening (data-safety review)
- [x] Import guard: `StorageService.loadLegacyForImport()` returns null only when
      no legacy file exists; a present-but-unreadable store throws, and the
      importer then returns `fallbackToJson` without setting the marker (it used
      to mark an unreadable store as a "fresh user", hiding the intact JSON
      behind an empty DB for good). An empty-but-readable library imports as
      zero rows and is marked done.
- [x] JSON-ahead flag (`keepy_json_ahead`): raised by `_flush()` whenever a save
      goes to JSON because the DB isn't the live store; on the next launch
      `init()` reads the JSON, folds it into the DB (`syncFromAppData` now
      reports success) and lowers the flag. Closes the hole where a launch on
      JSON followed by a launch on the DB read the stale DB over the JSON-only
      edits and then overwrote the JSON at the next checkpoint.
- [x] `_writeChain` links carry `catchError` so one failed JSON write can't
      poison the chain and silently skip every later save.
- [x] Tests: `test/db_migrator_test.dart` (fallback keeps marker unset, retry
      imports; empty library imports) and `test/app_state_test.dart`
      (`loadLegacyForImport` cases; JSON-ahead end-to-end on a real FFI DB).

Phase 4 (later)
- [ ] Remove shadow/fallback scaffolding once field-stable.
- [ ] Archive/rename legacy JSON.
- [x] FTS5 search: `search_fts` (title, body, id, kind; unicode61 with
      diacritics removed) mirrors notes and cards. Created opportunistically
      after open, never inside the schema batch, so a SQLite without FTS5
      leaves the store working and search on the in-memory filter. Built once
      from the loaded library (`meta.fts_built`), then kept in step by the
      dirty-diff sync. Results are bm25-ranked (title x4) and merged with the
      substring filter in `UniversalSearchResults`.
- [ ] (Optional) lazy/paged startup load.

---

## 13. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Importer bug loses/mangles data | Never delete JSON; count-verify before trusting DB; fall back to JSON on any failure; round-trip test is a release blocker. |
| Partial write / power loss | SQLite WAL + transactions (ACID) - strictly better than today's temp+rename+.bak. |
| Write amplification returns | Dirty-diff flush writes only changed rows; verified by test. |
| Different signing key on release wipes storage | Ship with the existing upload key + `com.solo.braim`; document in the release checklist. |
| Schema change later breaks upgrade | Drift versioned migrations + migration tests; bodies are JSON so field additions stay backward-compatible via `fromJson` defaults. |
| Backup format drift | Keep exporting JSON (unchanged format); restore reuses the importer. |
| DB file itself corrupts | Fallback to last JSON/backup; keep periodic JSON export (finish Drive auto-backup as the off-device net). |

---

## 14. Effort estimate

Roughly a few focused days of work, spread across the phases:
- Phase 0 (schema + importer + tests): ~1-1.5 days.
- Phase 1-2 (wire read/write, dirty-diff, tests): ~1-1.5 days.
- Phase 3 (backup repoint, end-to-end verify): ~0.5-1 day.
- Phase 4: later, small.

The risk is front-loaded into Phase 0's importer; the rest is mechanical once that
is proven.

---

## 15. Open decisions (resolve before Phase 1)

1. ~~Drift vs sqflite.~~ **RESOLVED: sqflite** (JSON-body container; no code-gen).
2. **FTS5 search now or later?** Default: later (Phase 4). Keep `title` column so
   it's cheap to add.
3. **When to physically retire the legacy JSON?** Default: not before Phase 4, and
   only by renaming, never deleting in the same release that flips the store.
4. **Startup load: eager (v1) vs lazy/paged (later)?** Default: eager, matches
   today; revisit only if startup time regresses on large libraries.

---

_Companion doc: `docs/google_drive_setup.md` (off-device backup — finishing this is
the cheapest independent safety win, and it underpins the fallback story above)._
