import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/space.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/platform/image_store.dart';
import 'package:braim/platform/image_store_device.dart';
import 'package:braim/services/db/db_snapshot.dart';
import 'package:braim/services/db/db_store.dart' show SearchHit;
import 'package:braim/services/storage_service.dart';
import 'package:braim/services/store/library_delta.dart';
import 'package:braim/services/store/library_store.dart';
import 'package:braim/services/store/library_zip.dart';
import 'package:braim/state/app_state.dart';

/// A store that keeps its "persisted" rows in memory, the way the browser and
/// remote stores do, so AppState's store contract can be tested headless.
class MemoryLibraryStore implements LibraryStore {
  MemoryLibraryStore(this.initial);

  final AppData initial;
  final differ = SnapshotDiffer();
  final incomingCtrl = StreamController<LibraryDelta>.broadcast();
  final saved = <LibraryDelta>[];

  @override
  Future<AppData> load({bool restored = false}) async {
    differ.reseed(snapshotFromAppData(initial));
    return initial;
  }

  @override
  Future<void> afterLoad(AppData Function() snapshot) async {}

  @override
  void save(AppData snapshot, int rev) {
    final delta = differ.diff(snapshotFromAppData(snapshot));
    if (delta.isEmpty) return;
    saved.add(delta);
    differ.commit(delta);
  }

  @override
  Future<void> flushNow({
    required bool loaded,
    required int rev,
    required AppData Function() snapshot,
  }) async {}

  @override
  Future<List<SearchHit>?> search(String query) async => null;

  @override
  Stream<LibraryDelta> get incoming => incomingCtrl.stream;

  @override
  void adopt(LibraryDelta applied) => differ.commit(applied);
}

AppData _lib({List<Note>? notes, List<TweetCard>? cards, List<Space>? spaces}) =>
    AppData(notes: notes ?? [], spaces: spaces ?? [], cards: cards ?? []);

RowChange _noteChange(Note n) =>
    (table: 'notes', id: n.id, row: noteRow(n));

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_store_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SnapshotDiffer', () {
    test('an empty baseline sees every row as new; a commit settles it', () {
      final differ = SnapshotDiffer();
      final snap = snapshotFromAppData(_lib(notes: [Note(title: 'a')]));
      final first = differ.diff(snap);
      expect(first.rows, hasLength(1));
      expect(first.rows.single.row, isNotNull);
      expect(first.settings, isNotEmpty);
      differ.commit(first);
      expect(differ.diff(snap).isEmpty, isTrue);
    });

    test('changed body, vanished row and changed setting are all it reports',
        () {
      final a = Note(title: 'a');
      final b = Note(title: 'b');
      final data = _lib(notes: [a, b]);
      final differ = SnapshotDiffer()..reseed(snapshotFromAppData(data));

      a.title = 'a2';
      data.notes.remove(b);
      data.darkMode = !data.darkMode;
      final delta = differ.diff(snapshotFromAppData(data));

      expect(delta.rows.where((r) => r.row != null).map((r) => r.id), [a.id]);
      expect(delta.rows.where((r) => r.row == null).map((r) => r.id), [b.id]);
      expect(delta.settings.keys, ['darkMode']);
    });

    test('a delta survives the wire (JSON round trip)', () {
      final n = Note(title: 'wire');
      final delta = LibraryDelta(
        rows: [_noteChange(n), (table: 'cards', id: 'gone', row: null)],
        settings: {'readerFont': jsonEncode('Lora')},
      );
      final back = LibraryDelta.fromJson(
          jsonDecode(jsonEncode(delta.toJson())) as Map<String, dynamic>);
      expect(back.rows.first.row!['body'], noteRow(n)['body']);
      expect(back.rows.last.row, isNull);
      expect(back.settings, delta.settings);
    });
  });

  group('AppState.applyIncoming', () {
    late MemoryLibraryStore store;
    late AppState state;

    Future<void> boot(AppData data) async {
      store = MemoryLibraryStore(data);
      state = AppState(store: store);
      await state.init();
      await state.flushNow();
      store.saved.clear();
    }

    tearDown(() async {
      await state.flushNow();
      state.dispose();
    });

    test('inserts, replaces and hard-deletes by id, without echoing back',
        () async {
      final keep = Note(title: 'keep');
      final gone = Note(title: 'gone');
      await boot(_lib(notes: [keep, gone]));

      final added = Note(title: 'from the phone');
      final changed = Note.fromJson(keep.toJson())..title = 'keep, edited';
      state.applyIncoming(LibraryDelta(rows: [
        _noteChange(added),
        _noteChange(changed),
        (table: 'notes', id: gone.id, row: null),
      ]));

      expect(state.noteById(added.id)?.title, 'from the phone');
      expect(state.noteById(keep.id)?.title, 'keep, edited');
      expect(state.noteById(gone.id), isNull);

      // Nothing to send back: the store already holds what just arrived.
      await state.flushNow();
      state.upsertNote(state.noteById(added.id)!); // any later save
      await state.flushNow();
      final sent = store.saved.expand((d) => d.rows).map((r) => r.id).toSet();
      expect(sent, {added.id}, reason: 'only the note saved afterwards');
    });

    test('settings from elsewhere apply and are not echoed', () async {
      await boot(_lib());
      state.applyIncoming(
          LibraryDelta(settings: {'readerFont': jsonEncode('Merriweather')}));
      expect(state.readerFont, 'Merriweather');
      state.setCardsCompact(true);
      await state.flushNow();
      final keys = store.saved.expand((d) => d.settings.keys).toSet();
      expect(keys, {'cardsCompact'});
    });

    test('persist: true saves the change through the normal path', () async {
      await boot(_lib());
      final n = Note(title: 'typed in a browser');
      state.applyIncoming(LibraryDelta(rows: [_noteChange(n)]), persist: true);
      await state.flushNow();
      expect(store.saved.expand((d) => d.rows).map((r) => r.id), [n.id]);
    });

    test('an open editor with unsaved work keeps its note until it loads',
        () async {
      final n = Note(title: 'draft');
      await boot(_lib(notes: [n]));
      bool editing() => true;
      state.registerOpenEditor(n.id, editing);
      final seen = <String>[];
      final sub = state.incomingNoteChanges.listen(seen.add);

      final remote = Note.fromJson(n.toJson())..title = 'changed on phone';
      state.applyIncoming(LibraryDelta(rows: [_noteChange(remote)]));
      await Future<void>.delayed(Duration.zero);

      expect(state.noteById(n.id), same(n), reason: 'not swapped under it');
      expect(seen, [n.id]);
      expect(state.hasIncomingFor(n.id), isTrue);

      final loaded = state.takeIncomingNote(n.id);
      expect(loaded?.title, 'changed on phone');
      expect(state.noteById(n.id)?.title, 'changed on phone');
      await sub.cancel();
      // A replaced editor unregistering late leaves the new one in place.
      bool other() => true;
      state.registerOpenEditor(n.id, other);
      state.unregisterOpenEditor(n.id, editing);
      state.applyIncoming(LibraryDelta(rows: [
        _noteChange(Note.fromJson(remote.toJson())..title = 'again'),
      ]));
      expect(state.noteById(n.id)?.title, 'changed on phone',
          reason: 'the new editor is still writing, so the change is held');
      expect(state.hasIncomingFor(n.id), isTrue);
      state.unregisterOpenEditor(n.id, other);
      expect(state.hasIncomingFor(n.id), isFalse);
    });

    test('forgetLocally drops rows without ever deleting them', () async {
      final secret = Note(title: 'crypt', spaceId: kCryptSpaceId);
      await boot(_lib(notes: [secret, Note(title: 'plain')]));
      state.forgetLocally({secret.id});
      expect(state.noteById(secret.id), isNull);
      state.setCardsCompact(true);
      await state.flushNow();
      expect(store.saved.expand((d) => d.rows).where((r) => r.row == null),
          isEmpty);
    });

    test('incoming changes from the store stream are applied', () async {
      await boot(_lib());
      final n = Note(title: 'streamed');
      store.incomingCtrl.add(LibraryDelta(rows: [_noteChange(n)]));
      await Future<void>.delayed(Duration.zero);
      expect(state.noteById(n.id)?.title, 'streamed');
    });
  });

  group('backup zip + crypt', () {
    test('encode/decode round-trips data and images', () {
      final n = Note(title: 'zip', blocks: [
        NoteBlock(type: NoteBlockType.image, imagePath: 'images/a.jpg'),
      ]);
      final data = _lib(notes: [n]);
      final bytes = LibraryZip.encode(
          data, {'a.jpg': Uint8List.fromList([1, 2, 3])});
      final back = LibraryZip.decode(bytes);
      expect(back.data.notes.single.title, 'zip');
      expect(back.images['a.jpg'], [1, 2, 3]);
      expect(referencedImagePaths(back.data), {'images/a.jpg'});
    });

    test('a zip without data.json is refused', () {
      expect(() => LibraryZip.decode(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });

    test('withoutCrypt drops crypt notes, their branches and crypt cards', () {
      final root = Note(title: 'root', spaceId: kCryptSpaceId);
      root.circuitId = root.id;
      final branch = Note(title: 'branch')..circuitId = root.id;
      final plain = Note(title: 'plain');
      final card = TweetCard(url: 'https://x.test', spaceId: kCryptSpaceId);
      final data = _lib(notes: [root, branch, plain], cards: [card]);
      expect(cryptEntityIds(data), {root.id, branch.id, card.id});
      final out = withoutCrypt(data);
      expect(out.notes.map((n) => n.title), ['plain']);
      expect(out.cards, isEmpty);
    });
  });

  group('image paths', () {
    test('identity is the file name', () {
      expect(imageKey('/data/user/0/x/app_flutter/images/abc.jpg'), 'abc.jpg');
      expect(imageKey('images/abc.jpg'), 'abc.jpg');
      expect(imageKey(r'C:\x\images\abc.png'), 'abc.png');
      expect(relativeImagePath('abc.jpg'), 'images/abc.jpg');
      expect(extensionOf('photo.JPEG'), '.jpeg');
      expect(extensionOf('blob'), '.jpg');
    });

    test('relative paths resolve against the phone images folder', () {
      final before = DeviceImagePaths.imagesDir;
      DeviceImagePaths.imagesDir = '/phone/images';
      expect(DeviceImagePaths.resolve('images/abc.jpg'), '/phone/images/abc.jpg');
      expect(DeviceImagePaths.resolve('/abs/abc.jpg'), '/abs/abc.jpg');
      DeviceImagePaths.imagesDir = before;
    });
  });
}
