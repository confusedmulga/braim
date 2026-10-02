import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/circuit_file.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// A zip holding [files] (name -> JSON value or raw bytes).
List<int> _zip(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, value) {
    final bytes =
        value is List<int> ? value : utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}

Map<String, Object> _manifest({int version = 1}) => {
      'format': 'braim-circuit',
      'version': version,
      'source': 'orig-root',
      'title': 'Trip',
    };

Map<String, Object> _note(String id,
        {String? parent, String title = 'n', Map<String, Object>? extra}) =>
    {
      'id': id,
      'title': title,
      'blocks': <Object>[],
      'circuitId': 'r',
      'circuitParentId': ?parent,
      ...?extra,
    };

CircuitFileProblem? _problem(List<int> bytes) {
  try {
    decodeCircuitFile(bytes);
    return null;
  } on CircuitFileException catch (e) {
    return e.problem;
  }
}

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_circuit_file_test');
    Directory('${root.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Empties the library on disk, like a different phone.
  void wipeLibrary() {
    for (final name in ['keepy_data.json', 'keepy_data.bak', 'keepy_json_ahead']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    final images = Directory('${root.path}/images');
    if (images.existsSync()) images.deleteSync(recursive: true);
  }

  Future<AppState> freshState() async {
    final s = AppState();
    await s.init();
    return s;
  }

  setUp(wipeLibrary);

  group('round trip', () {
    test('a circuit exported on one phone imports exactly on another',
        () async {
      // ---- Phone A: a circuit using everything that should travel. ----
      final a = await freshState();
      final picture = File('${root.path}/tmp/photo.png')
        ..writeAsBytesSync([137, 80, 78, 71, 1, 2, 3]);
      final first = a.newCircuitRootDraft()
        ..title = 'Trip'
        ..colorValue = 0xFF336699
        ..tags = ['travel']
        ..reminderAt = DateTime(2030) // must stay on phone A
        ..pinned = true; // must stay on phone A
      await a.ensureCircuitRootSaved(first);
      await a.setCircuitLayout(first.id, 'radial');
      final flights = await a.addCircuitChild(first.id);
      flights.title = 'Flights';
      flights.blocks = [
        NoteBlock(type: NoteBlockType.text, text: 'see [[Hotels]]'),
        NoteBlock(type: NoteBlockType.image, imagePath: picture.path),
      ];
      await a.setCircuitShowInFeed(flights.id, true);
      final hotels = await a.addCircuitChild(first.id, markdown: true);
      await a.renameCircuitNode(hotels.id, 'Hotels');
      final deep = await a.addCircuitChild(hotels.id);
      deep.title = 'Deep';
      // A placeholder holding a child, from deleting a note but keeping its slot.
      final gone = await a.addCircuitChild(first.id);
      await a.addCircuitChild(gone.id);
      await a.deleteCircuitNodeKeepSlot(gone.id);
      await a.upsertNote(flights);

      final bytes = await a.exportCircuitBytes(first.id);
      final sentShape = _shape(a, first.id);
      final sentCount = a.circuitNodes(first.id).length;
      await a.flushNow();
      a.dispose();

      // ---- Phone B: an empty library receives the file. ----
      wipeLibrary();
      final b = await freshState();
      final file = File('${root.path}/tmp/Trip.braim')..writeAsBytesSync(bytes);
      final bundle = await b.readCircuitFile(file.path);
      expect(bundle.title, 'Trip');
      expect(b.circuitMatching(bundle.source), isNull);
      final got = await b.importCircuit(bundle);

      // The same tree, the same notes in the same order...
      expect(_shape(b, got.id), sentShape);
      expect(b.circuitNodes(got.id).length, sentCount);
      // ...with the same look and settings...
      expect(got.isCircuitRoot, isTrue);
      expect(got.circuitLayout, 'radial');
      expect(got.colorValue, 0xFF336699);
      expect(got.tags, ['travel']);
      final gotFlights = _child(b, got.id, 'Flights');
      expect(gotFlights.circuitShowInFeed, isTrue);
      expect(gotFlights.blocks.first.text, 'see [[Hotels]]');
      expect(_child(b, got.id, 'Hotels').markdown, isTrue);
      final slot = b.circuitChildren(got.id).firstWhere((n) => n.circuitPlaceholder);
      expect(b.circuitChildren(slot.id), hasLength(1));
      // ...its picture copied into this phone's own storage...
      final img = gotFlights.blocks.firstWhere((x) => x.isImage).imagePath;
      expect(img, isNot(picture.path));
      expect(File(img).readAsBytesSync(), [137, 80, 78, 71, 1, 2, 3]);
      // ...new ids, on Home, and nothing that belonged to the sender's phone.
      expect(got.id, isNot(first.id));
      expect(got.spaceId, isNull);
      expect(got.reminderAt, isNull);
      expect(got.pinned, isFalse);
      expect(got.circuitSource, first.id);
      expect(b.notes.map((n) => n.id), contains(got.id));
      b.dispose();
    });

    test('importing the same circuit again finds the earlier copy', () async {
      final a = await freshState();
      final first = a.newCircuitRootDraft()..title = 'Trip';
      await a.ensureCircuitRootSaved(first);
      await a.addCircuitChild(first.id);
      final bytes = await a.exportCircuitBytes(first.id);
      a.dispose();

      wipeLibrary();
      final b = await freshState();
      final file = File('${root.path}/tmp/again.braim')..writeAsBytesSync(bytes);
      final once = await b.importCircuit(await b.readCircuitFile(file.path));

      final bundle = await b.readCircuitFile(file.path);
      expect(b.circuitMatching(bundle.source)?.id, once.id);

      // Keep both: a second, independent copy.
      final copy = await b.importCircuit(bundle);
      expect(copy.id, isNot(once.id));
      expect(b.noteById(once.id)!.deletedAt, isNull);

      // Replace: the earlier copy goes to Recently Deleted, restorable.
      final replaced =
          await b.importCircuit(bundle, replaceRootId: once.id);
      expect(b.noteById(once.id)!.deletedAt, isNotNull);
      expect(b.deletedNoteGroups.map((g) => g.top.id), contains(once.id));
      expect(b.noteById(replaced.id)!.deletedAt, isNull);
      b.dispose();
    });

    test('a copy shared on keeps the original circuit identity', () async {
      final a = await freshState();
      final first = a.newCircuitRootDraft()..title = 'Trip';
      await a.ensureCircuitRootSaved(first);
      final fromA = await a.exportCircuitBytes(first.id);
      a.dispose();

      wipeLibrary();
      final b = await freshState(); // B imports A's circuit, then shares it on
      final f1 = File('${root.path}/tmp/a.braim')..writeAsBytesSync(fromA);
      final onB = await b.importCircuit(await b.readCircuitFile(f1.path));
      final fromB = await b.exportCircuitBytes(onB.id);
      b.dispose();

      final viaB = decodeCircuitFile(fromB);
      expect(viaB.source, first.id); // still A's original
    });

    test('a circuit imported on the phone it came from matches the original',
        () async {
      final a = await freshState();
      final first = a.newCircuitRootDraft()..title = 'Trip';
      await a.ensureCircuitRootSaved(first);
      final bundle = decodeCircuitFile(await a.exportCircuitBytes(first.id));
      expect(a.circuitMatching(bundle.source)?.id, first.id);
      a.dispose();
    });

    test('the file leaves the sender\'s private fields behind', () async {
      final a = await freshState();
      final first = a.newCircuitRootDraft()
        ..title = 'Trip'
        ..reminderAt = DateTime(2030)
        ..pinned = true;
      await a.ensureCircuitRootSaved(first);
      final bytes = await a.exportCircuitBytes(first.id);
      a.dispose();
      final archive = ZipDecoder().decodeBytes(bytes);
      final circuit = utf8.decode(archive
          .firstWhere((f) => f.name == 'circuit.json')
          .content as List<int>);
      for (final key in ['reminderAt', 'pinned', 'spaceId', 'history']) {
        expect(circuit, isNot(contains('"$key"')), reason: key);
      }
    });
  });

  group('reading a received file', () {
    final ok = {
      'manifest.json': _manifest(),
      'circuit.json': {
        'rootId': 'r',
        'notes': [_note('r', title: 'Trip'), _note('a', parent: 'r')],
      },
    };

    test('a well-formed file reads', () {
      final b = decodeCircuitFile(_zip(ok));
      expect(b.noteCount, 2);
      expect(b.source, 'orig-root');
    });

    test('not a zip, or not a circuit', () {
      expect(_problem([1, 2, 3, 4]), CircuitFileProblem.notACircuit);
      expect(_problem(_zip({'readme.txt': 'hi'})),
          CircuitFileProblem.notACircuit);
      expect(
          _problem(_zip({
            'manifest.json': {'format': 'something-else', 'version': 1},
          })),
          CircuitFileProblem.notACircuit);
    });

    test('made by a newer Braim', () {
      expect(_problem(_zip({...ok, 'manifest.json': _manifest(version: 2)})),
          CircuitFileProblem.newerVersion);
    });

    test('damaged: missing parts, wrong types, broken references', () {
      expect(_problem(_zip({'manifest.json': _manifest()})),
          CircuitFileProblem.damaged);
      expect(
          _problem(_zip({
            'manifest.json': _manifest(),
            'circuit.json': {
              'rootId': 'missing',
              'notes': [_note('r')],
            },
          })),
          CircuitFileProblem.damaged);
      expect(
          _problem(_zip({
            'manifest.json': _manifest(),
            'circuit.json': {
              'rootId': 'r',
              'notes': [
                {'id': 'r', 'title': 5},
              ],
            },
          })),
          CircuitFileProblem.damaged);
      expect(
          _problem(_zip({
            'manifest.json': _manifest(),
            'circuit.json': {
              'rootId': 'r',
              'notes': [_note('r'), _note('r')],
            },
          })),
          CircuitFileProblem.damaged);
    });

    test('too many notes', () {
      expect(
          _problem(_zip({
            'manifest.json': _manifest(),
            'circuit.json': {
              'rootId': 'r0',
              'notes': [
                for (var i = 0; i <= CircuitFile.maxNotes; i++) _note('r$i'),
              ],
            },
          })),
          CircuitFileProblem.tooLarge);
    });

    test('image entries that try to leave the images folder are ignored', () {
      final b = decodeCircuitFile(_zip({
        ...ok,
        'images/1.png': [1, 2, 3],
        'images/../escape.png': [6, 6, 6],
        'images/sub/x.png': [6, 6, 6],
        'images/notes.txt': [6, 6, 6],
      }));
      expect(b.images.keys, ['1.png']);
    });
  });

  group('building the notes', () {
    Future<List<Note>> build(Map<String, Object> circuit,
        {Map<String, Object> extra = const {}}) {
      final bundle = decodeCircuitFile(
          _zip({'manifest.json': _manifest(), 'circuit.json': circuit, ...extra}));
      return materializeCircuit(bundle,
          saveImage: (name, _) async => '/saved/$name');
    }

    test('a path outside the file is never followed', () async {
      final notes = await build({
        'rootId': 'r',
        'notes': [
          _note('r', extra: {
            'blocks': [
              {'type': 'image', 'imagePath': '/data/data/other.app/secret.png'},
              {'type': 'image', 'imagePath': 'images/1.png'},
            ],
          }),
        ],
      }, extra: {
        'images/1.png': [1, 2, 3],
      });
      final paths = notes.single.blocks.map((b) => b.imagePath).toList();
      expect(paths, ['', '/saved/1.png']);
    });

    test('an unknown layout falls back to left-to-right', () async {
      final notes = await build({
        'rootId': 'r',
        'notes': [
          _note('r', extra: {'circuitLayout': 'spiral'}),
        ],
      });
      expect(notes.first.circuitLayout, 'ltr');
    });

    test('a field this build no longer has (a note background) is ignored',
        () async {
      // Files from builds that still had note backgrounds carry the key.
      final notes = await build({
        'rootId': 'r',
        'notes': [
          _note('r', title: 'Trip', extra: {'backgroundAsset': 'assets/BACK01.jpg'}),
        ],
      });
      expect(notes.single.title, 'Trip');
      expect(notes.single.toJson().containsKey('backgroundAsset'), isFalse);
    });

    test('a broken tree is repaired under the first note', () async {
      final notes = await build({
        'rootId': 'r',
        'notes': [
          _note('r', extra: {'circuitPlaceholder': true}),
          _note('orphan', parent: 'nowhere', title: 'orphan'),
          _note('x', parent: 'y', title: 'x'), // x and y point at each other
          _note('y', parent: 'x', title: 'y'),
          _note('ok', parent: 'r', extra: {'circuitOrder': 7}),
        ],
      });
      final rootNote = notes.first;
      Note byTitle(String t) => notes.firstWhere((n) => n.title == t);
      expect(rootNote.circuitParentId, isNull);
      expect(rootNote.circuitPlaceholder, isFalse);
      // The orphan goes under the root; the loop is broken by moving one of
      // its notes there, the other keeping its place beneath it.
      expect(byTitle('orphan').circuitParentId, rootNote.id);
      expect(byTitle('x').circuitParentId, rootNote.id);
      expect(byTitle('y').circuitParentId, byTitle('x').id);
      final underRoot = notes
          .where((n) => n.circuitParentId == rootNote.id)
          .map((n) => n.circuitOrder)
          .toList()
        ..sort();
      expect(underRoot, [0, 1, 2]); // numbered 0..n-1
      expect(notes.every((n) => n.circuitId == rootNote.id), isTrue);
    });
  });
}

/// The circuit under [rootId] as nested titles, in sibling order.
List<Object> _shape(AppState s, String rootId) {
  List<Object> kids(String id) => [
        for (final c in s.circuitChildren(id))
          {c.circuitPlaceholder ? '[slot]' : c.title: kids(c.id)},
      ];
  return [s.noteById(rootId)!.title, kids(rootId)];
}

Note _child(AppState s, String rootId, String title) =>
    s.circuitNodes(rootId).firstWhere((n) => n.title == title);
