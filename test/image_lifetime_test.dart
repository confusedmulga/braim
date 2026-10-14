import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// An image file stays while anything in the library still shows it.
void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_images_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  Future<AppState> boot(List<Note> notes) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(
      AppData(notes: notes, spaces: [], cards: []),
    );
    final state = AppState();
    states.add(state);
    await state.init();
    return state;
  }

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  String photo(String name) {
    final f = File('${root.path}/$name')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }

  NoteBlock image(String path) =>
      NoteBlock(type: NoteBlockType.image, imagePath: path);

  test('a photo removed from a chapter stays for its saved version', () async {
    final path = photo('chapter.png');
    final chapter = Note(
      id: 'c',
      title: 'Chapter I',
      blocks: [image(path)],
      history: [
        NoteSnapshot(title: 'Chapter I', blocks: [image(path)]),
      ],
    );
    final state = await boot([chapter]);

    // The editor drops the photo from the chapter itself.
    state.noteById('c')!.blocks.clear();
    await state.refreshAfterImageRemoval(path);
    expect(File(path).existsSync(), isTrue);
  });

  test('a photo two notes share outlives one of them', () async {
    final path = photo('shared.png');
    final state = await boot([
      Note(id: 'a', title: 'A', blocks: [image(path)]),
      Note(id: 'b', title: 'B', blocks: [image(path)]),
    ]);
    await state.deleteNote('a');
    await state.permanentlyDeleteNote('a');
    expect(File(path).existsSync(), isTrue);

    await state.deleteNote('b');
    await state.permanentlyDeleteNote('b');
    expect(File(path).existsSync(), isFalse);
  });

  test('a photo nothing uses any more is deleted', () async {
    final path = photo('alone.png');
    final state = await boot([
      Note(id: 'a', title: 'A', blocks: [image(path)]),
    ]);
    state.noteById('a')!.blocks.clear();
    await state.refreshAfterImageRemoval(path);
    expect(File(path).existsSync(), isFalse);
  });
}
