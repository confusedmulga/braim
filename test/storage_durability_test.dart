import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/models/note.dart';
import 'package:braim/services/archive_safety.dart';
import 'package:braim/services/backup_service.dart';
import 'package:braim/services/db/db_store.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getExternalStoragePath() async => '$root/external';
}

/// A real SQLite store that can be told to fail its writes or its read.
class _FlakyStore extends DbStore {
  _FlakyStore({super.factory, super.path});

  bool failSync = false;
  bool failRead = false;

  @override
  Future<bool> syncFromAppData(AppData data) async =>
      failSync ? false : super.syncFromAppData(data);

  @override
  Future<AppData?> readAppData() async {
    if (failRead) throw const FormatException('a damaged row');
    return super.readAppData();
  }
}

/// The library survives a damaged store, a failing database and a crash
/// right after a restore.
void main() {
  late Directory root;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    root = Directory.systemTemp.createTempSync('braim_durability_test');
    Directory('${root.path}/tmp').createSync();
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    dbPath = '${root.path}/durability.db';
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  final stores = <DbStore>[];
  AppState newState({DbStore? dbStore}) {
    final s = AppState(dbStore: dbStore);
    states.add(s);
    return s;
  }

  setUp(() async {
    for (final f in root.listSync().whereType<File>()) {
      f.deleteSync();
    }
    await StorageService.instance.clearJsonAhead();
  });

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
    for (final s in stores) {
      await s.close();
    }
    stores.clear();
  });

  _FlakyStore store() {
    final s = _FlakyStore(factory: databaseFactoryFfi, path: dbPath);
    stores.add(s);
    return s;
  }

  test('an unreadable store is kept aside before saves replace it', () async {
    File('${root.path}/keepy_data.json').writeAsStringSync('{not json');
    File('${root.path}/keepy_data.bak').writeAsStringSync('{not json');

    final state = newState();
    await state.init();
    await state.upsertNote(Note(title: 'one'));
    await state.flushNow();
    await state.upsertNote(Note(title: 'two'));
    await state.flushNow();

    final kept = root
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('keepy_data.unreadable'))
        .map((f) => f.readAsStringSync());
    expect(kept, contains('{not json'));
  });

  test('a failed database save marks the JSON as the newer copy', () async {
    await StorageService.instance.save(
      AppData(notes: [Note(title: 'A')], spaces: [], cards: []),
    );
    final first = store();
    final s1 = newState(dbStore: first);
    await s1.init();
    expect(s1.notes.map((n) => n.title), ['A']);

    first.failSync = true;
    await s1.upsertNote(Note(title: 'B'));
    await s1.flushNow();
    expect(await StorageService.instance.jsonAhead, isTrue);
    await first.close();

    // Next launch, the database works again and must not hide B.
    final s2 = newState(dbStore: store());
    await s2.init();
    expect(s2.notes.map((n) => n.title).toSet(), {'A', 'B'});
  });

  test('a database that cannot be read falls back to the JSON', () async {
    await StorageService.instance.save(
      AppData(notes: [Note(title: 'A')], spaces: [], cards: []),
    );
    final s1 = newState(dbStore: store());
    await s1.init();
    await s1.flushNow();
    await stores.last.close();

    final broken = store()..failRead = true;
    final s2 = newState(dbStore: broken);
    await s2.init();
    expect(s2.loaded, isTrue);
    expect(s2.notes.map((n) => n.title), ['A']);

    // Edits made meanwhile land in the JSON and are flagged as newer.
    await s2.upsertNote(Note(title: 'C'));
    await s2.flushNow();
    expect(await StorageService.instance.jsonAhead, isTrue);
    await broken.close();

    final s3 = newState(dbStore: store());
    await s3.init();
    expect(s3.notes.map((n) => n.title).toSet(), {'A', 'C'});
  });

  test('a row that cannot be read is kept in the database, the rest loads',
      () async {
    await StorageService.instance.save(AppData(
      notes: [Note(id: 'a', title: 'A'), Note(id: 'b', title: 'B')],
      spaces: [],
      cards: [],
    ));
    final s1 = newState(dbStore: store());
    await s1.init();
    await s1.flushNow();
    await stores.last.close();

    // Row b gets a body this build can't read (a title that isn't text).
    final raw = await databaseFactoryFfi.openDatabase(dbPath);
    const bad = '{"id":"b","title":5}';
    await raw.update('notes', {'body': bad}, where: 'id = ?', whereArgs: ['b']);
    await raw.close();

    final s2 = newState(dbStore: store());
    await s2.init();
    expect(s2.notes.map((n) => n.id), ['a']);
    await s2.upsertNote(Note(id: 'c', title: 'C'));
    await s2.flushNow();
    await stores.last.close();

    final check = await databaseFactoryFfi.openDatabase(dbPath);
    final rows = await check.query('notes', where: 'id = ?', whereArgs: ['b']);
    await check.close();
    expect(rows.single['body'], bad);
  });

  test('a restore marks the JSON as newer until the database has it', () async {
    final data = AppData(notes: [Note(title: 'Restored')], spaces: [], cards: []);
    final archive = Archive()
      ..add(ArchiveFile.bytes('data.json', utf8.encode(jsonEncode(data.toJson()))));
    await BackupService.instance.restoreFromZipBytes(ZipEncoder().encode(archive));
    expect(await StorageService.instance.jsonAhead, isTrue);
  });

  test('a backup restores from a file on disk', () async {
    final data = AppData(notes: [Note(title: 'From file')], spaces: [], cards: []);
    final archive = Archive()
      ..add(ArchiveFile.bytes('data.json', utf8.encode(jsonEncode(data.toJson()))))
      ..add(ArchiveFile.bytes('images/photo.png', List.filled(64, 7)));
    final zip = File('${root.path}/tmp/in.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    await BackupService.instance.restoreFromFile(zip.path);

    final loaded = await StorageService.instance.load();
    expect(loaded.notes.single.title, 'From file');
    expect(File('${root.path}/images/photo.png').readAsBytesSync(),
        List.filled(64, 7));
  });

  test('two backups in the same minute get their own temp files', () async {
    final a = await BackupService.instance.exportToTempFile();
    final b = await BackupService.instance.exportToTempFile();
    expect(a.path, isNot(b.path));
  });

  test('an inflating entry is stopped at its limit', () {
    final zip = ZipEncoder().encode(
        Archive()..add(ArchiveFile.bytes('images/a.png', List.filled(5000, 7))));
    final entry = ZipDecoder().decodeBytes(zip).files.single;
    final got = <int>[];
    inflateEntry(entry, 5000, got.addAll);
    expect(got, List.filled(5000, 7));
    expect(() => inflateEntry(entry, 4999, (_) {}),
        throwsA(isA<EntryTooLarge>()));
  });
}
