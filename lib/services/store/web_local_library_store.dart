import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:uuid/uuid.dart';

import '../../platform/image_store.dart';
import '../../platform/web_bridge.dart';
import '../db/db_snapshot.dart';
import '../db/db_store.dart' show SearchHit;
import '../storage_service.dart' show AppData;
import 'library_delta.dart';
import 'library_store.dart';
import 'library_zip.dart';

/// The browser's own copy of the library, in IndexedDB. Rows keep the exact
/// shape of the phone's SQLite rows (`"<table>:<id>" -> row` with the entity's
/// full JSON in `body`), so the same [SnapshotDiffer] turns every save into a
/// row-level delta — the unit a later phone <-> browser sync will exchange.
class WebLibraryDb {
  WebLibraryDb._();

  static const name = 'braim_library';
  static const version = 1;
  static const rows = 'rows';
  static const settings = 'settings';
  static const images = 'images';
  static const meta = 'meta';

  static Future<WebIdb>? _open;

  static Future<WebIdb> open() => _open ??=
      WebIdb.open(name, version, const [rows, settings, images, meta]);
}

class WebLocalLibraryStore implements LibraryStore {
  final _differ = SnapshotDiffer();
  Future<void> _chain = Future.value();
  WebIdb? _db;

  /// Whether the browser has agreed to keep this site's storage (not evict it
  /// under pressure). Null until the first write asks.
  bool? persisted;
  bool _askedPersist = false;

  Future<WebIdb> get _idb async => _db ??= await WebLibraryDb.open();

  @override
  Future<AppData> load({bool restored = false}) async {
    final db = await _idb;
    final snap = await _readSnapshot(db);
    _differ.reseed(snap);
    return appDataFromSnapshot(snap);
  }

  static Future<AppSnapshot> _readSnapshot(WebIdb db) async {
    final rowMap = await db.readAllStrings(WebLibraryDb.rows);
    final settings = await db.readAllStrings(WebLibraryDb.settings);
    final by = <String, List<Map<String, Object?>>>{
      for (final t in SnapshotDiffer.tables) t: [],
    };
    rowMap.forEach((key, value) {
      final table = key.substring(0, key.indexOf(':'));
      by[table]?.add((jsonDecode(value) as Map).cast<String, Object?>());
    });
    return AppSnapshot(
      notes: by['notes']!,
      cards: by['cards']!,
      books: by['books']!,
      impulses: by['impulses']!,
      spaces: by['spaces']!,
      settings: settings,
    );
  }

  @override
  Future<void> afterLoad(AppData Function() snapshot) async {}

  @override
  void save(AppData snapshot, int rev) {
    _chain = _chain.then((_) async {
      final delta = _differ.diff(snapshotFromAppData(snapshot));
      if (delta.isEmpty) return;
      await (await _idb).commit(_ops(delta));
      _differ.commit(delta);
      _maybeAskPersist();
    }).catchError((_) {});
  }

  static List<IdbOp> _ops(LibraryDelta delta) => [
        for (final r in delta.rows)
          (
            store: WebLibraryDb.rows,
            key: '${r.table}:${r.id}',
            value: r.row == null ? null : jsonEncode(r.row),
          ),
        for (final e in delta.settings.entries)
          (store: WebLibraryDb.settings, key: e.key, value: e.value),
      ];

  void _maybeAskPersist() {
    if (_askedPersist) return;
    _askedPersist = true;
    unawaited(webPersistStorage().then((v) => persisted = v));
  }

  @override
  Future<void> flushNow({
    required bool loaded,
    required int rev,
    required AppData Function() snapshot,
  }) =>
      _chain;

  /// No full-text index in the browser; search stays in memory.
  @override
  Future<List<SearchHit>?> search(String query) async => null;

  @override
  Stream<LibraryDelta> get incoming => const Stream.empty();

  @override
  void adopt(LibraryDelta applied) => _differ.commit(applied);

  /// Replaces everything in this browser with [bundle] (a phone backup):
  /// rows, settings and images, in one transaction. Crypt entities are left
  /// out — they stay behind the phone's lock.
  Future<void> replaceAll(LibraryBundle bundle) async {
    await _chain;
    final data = withoutCrypt(bundle.data);
    final snap = snapshotFromAppData(data);
    final delta = LibraryDelta.ofSnapshot(snap);
    final keep = {for (final p in referencedImagePaths(data)) imageKey(p)};
    await (await _idb).commit([
      ..._ops(delta),
      for (final e in bundle.images.entries)
        if (keep.contains(e.key))
          (store: WebLibraryDb.images, key: e.key, value: e.value),
    ], clear: const [
      WebLibraryDb.rows,
      WebLibraryDb.settings,
      WebLibraryDb.images,
    ]);
    _differ.reseed(snap);
    _maybeAskPersist();
  }

  /// Every stored image, for a backup export.
  Future<Map<String, Uint8List>> allImages() async {
    final db = await _idb;
    final out = <String, Uint8List>{};
    for (final k in await db.keys(WebLibraryDb.images)) {
      final b = await db.getBytes(WebLibraryDb.images, k);
      if (b != null) out[k] = b;
    }
    return out;
  }
}

/// Images for the browser's own library, in the same IndexedDB database,
/// keyed by file name (see [imageKey]).
class WebLocalImageStore implements ImageStore {
  static const _uuid = Uuid();

  @override
  Future<String> saveBytes(Uint8List bytes, {String ext = '.png'}) async {
    final key = '${_uuid.v4()}$ext';
    await (await WebLibraryDb.open())
        .commit([(store: WebLibraryDb.images, key: key, value: bytes)]);
    return relativeImagePath(key);
  }

  @override
  Future<String> savePicked(XFile file) async =>
      saveBytes(await file.readAsBytes(), ext: extensionOf(file.name));

  @override
  Future<Uint8List?> load(String path) async {
    try {
      return await (await WebLibraryDb.open())
          .getBytes(WebLibraryDb.images, imageKey(path));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await (await WebLibraryDb.open())
          .commit([(store: WebLibraryDb.images, key: imageKey(path), value: null)]);
    } catch (_) {}
  }
}
