import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/space.dart';
import 'package:braim/services/db/db_store.dart';
import 'package:braim/services/note_markdown.dart';
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

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_circuit_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  final states = <AppState>[];
  AppState newState({DbStore? dbStore}) {
    final s = AppState(dbStore: dbStore);
    states.add(s);
    return s;
  }

  tearDown(() async {
    for (final s in states) {
      await s.flushNow();
      s.dispose();
    }
    states.clear();
  });

  setUp(() {
    for (final name in ['keepy_data.json', 'keepy_data.bak', 'keepy_json_ahead']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    final inbox = Directory('${root.path}/share_inbox');
    if (inbox.existsSync()) inbox.deleteSync(recursive: true);
  });

  Future<AppState> boot(AppData data) async {
    await StorageService.instance.save(data);
    final state = newState();
    await state.init();
    return state;
  }

  Future<AppState> emptyState() async {
    final s = newState();
    await s.init();
    return s;
  }

  Future<Note> newCircuit(AppState s, {String title = 'Root'}) async {
    final rootNote = s.newCircuitRootDraft()..title = title;
    await s.ensureCircuitRootSaved(rootNote);
    return rootNote;
  }

  List<String> ids(Iterable<Note> notes) => notes.map((n) => n.id).toList();

  // ---- Structure ----------------------------------------------------------

  test('add children and siblings; orders stay contiguous', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    expect(a.title, 'Note #1');
    expect(b.title, 'Note #2');
    expect(ids(s.circuitChildren(r.id)), [a.id, b.id]);
    expect(s.circuitChildren(r.id).map((n) => n.circuitOrder), [0, 1]);

    final between = await s.addCircuitSibling(a.id);
    expect(ids(s.circuitChildren(r.id)), [a.id, between.id, b.id]);
    expect(s.circuitChildren(r.id).map((n) => n.circuitOrder), [0, 1, 2]);

    // A sibling of the first note has nowhere to go but under it.
    final childOfRoot = await s.addCircuitSibling(r.id);
    expect(childOfRoot.circuitParentId, r.id);
  });

  test('move up and down clamps and renumbers', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    final c = await s.addCircuitChild(r.id);

    await s.moveCircuitNode(c.id, -1);
    expect(ids(s.circuitChildren(r.id)), [a.id, c.id, b.id]);
    await s.moveCircuitNode(a.id, -5); // clamps at the top
    expect(ids(s.circuitChildren(r.id)), [a.id, c.id, b.id]);
    await s.moveCircuitNode(a.id, 10); // clamps at the bottom
    expect(ids(s.circuitChildren(r.id)), [c.id, b.id, a.id]);
    expect(s.circuitChildren(r.id).map((n) => n.circuitOrder), [0, 1, 2]);
  });

  test('indent nests under previous sibling; outdent lifts to grandparent',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);

    await s.indentCircuitNode(b.id);
    expect(b.circuitParentId, a.id);
    expect(ids(s.circuitChildren(r.id)), [a.id]);
    expect(ids(s.circuitChildren(a.id)), [b.id]);

    await s.indentCircuitNode(a.id); // first child: no-op
    expect(a.circuitParentId, r.id);

    await s.outdentCircuitNode(b.id);
    expect(b.circuitParentId, r.id);
    expect(ids(s.circuitChildren(r.id)), [a.id, b.id]);

    await s.outdentCircuitNode(a.id); // parent is the root: no-op
    expect(a.circuitParentId, r.id);
  });

  test('moveCircuitNodeTo moves a subtree and rejects invalid targets',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);

    expect(await s.moveCircuitNodeTo(b.id, a.id), isTrue);
    expect(b.circuitParentId, a.id);

    expect(await s.moveCircuitNodeTo(a.id, a.id), isFalse); // into itself
    expect(await s.moveCircuitNodeTo(a.id, a1.id), isFalse); // into a descendant
    expect(await s.moveCircuitNodeTo(r.id, a.id), isFalse); // the root
  });

  // ---- Visibility ---------------------------------------------------------

  test('branches stay out of the feed unless shown; tags follow', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    a.tags = ['circuit'];

    expect(ids(s.notes).contains(r.id), isTrue);
    expect(ids(s.notes).contains(a.id), isFalse);
    expect(s.allTags.contains('circuit'), isFalse);
    // A branch is searchable whether or not it is shown in the feed.
    expect(ids(s.searchableNotes).contains(a.id), isTrue);

    await s.setCircuitShowInFeed(a.id, true);
    expect(ids(s.notes).contains(a.id), isTrue);
    expect(s.allTags.contains('circuit'), isTrue);
  });

  test('Crypt barrier refuses circuits everywhere', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);

    await s.moveNoteToSpace(r.id, kCryptSpaceId); // first note into Crypt: no
    expect(r.spaceId, isNull);
    await s.moveNoteToSpace(a.id, 'folder'); // any branch: no
    expect(a.spaceId, isNull);

    final folder = await s.addSpace('Work');
    await s.moveNoteToSpace(r.id, folder.id); // ordinary folder: allowed
    expect(r.spaceId, folder.id);

    await s.bulkMoveNotes({r.id}, kCryptSpaceId);
    expect(r.spaceId, folder.id); // still not in Crypt
    await s.bulkMoveNotes({a.id}, folder.id);
    expect(a.spaceId, isNull); // branch skipped

    final cryptNote = Note(title: 'secret', spaceId: kCryptSpaceId);
    await s.upsertNote(cryptNote);
    expect(ids(s.notesPlaceableInCircuit()).contains(cryptNote.id), isFalse);
  });

  test('Crypt safety net: a first note in the Crypt keeps its branches hidden',
      () async {
    final rootN = Note(id: 'r', title: 'Trip', spaceId: kCryptSpaceId)
      ..circuitId = 'r';
    final branch = Note(id: 'b', title: 'Note #1')
      ..circuitId = 'r'
      ..circuitParentId = 'r'
      ..circuitShowInFeed = true;
    final s = await boot(AppData(notes: [rootN, branch], spaces: [], cards: []));

    expect(ids(s.searchableNotes).contains('b'), isFalse);
    expect(ids(s.linkTargets()).contains('b'), isFalse);
    expect(ids(s.notes).contains('b'), isFalse);
    // Repair leaves the root in the Crypt and keeps the branch attached.
    expect(s.noteById('r')!.spaceId, kCryptSpaceId);
    expect(s.noteById('b')!.inCircuit, isTrue);
  });

  test('an archived first note hides its branches from search', () async {
    final rootN = Note(id: 'r', title: 'R')
      ..circuitId = 'r'
      ..archived = true;
    final branch = Note(id: 'b', title: 'Note #1')
      ..circuitId = 'r'
      ..circuitParentId = 'r';
    final s = await boot(AppData(notes: [rootN, branch], spaces: [], cards: []));
    expect(ids(s.searchableNotes).contains('b'), isFalse);
  });

  test('a shown branch stays out of the feed when its root is in a hidden folder',
      () async {
    final folder = Space(id: 'f', name: 'Hidden', hiddenFromFeed: true);
    final rootN = Note(id: 'r', title: 'R', spaceId: 'f')..circuitId = 'r';
    final branch = Note(id: 'b', title: 'Note #1')
      ..circuitId = 'r'
      ..circuitParentId = 'r'
      ..circuitShowInFeed = true;
    final s = await boot(
        AppData(notes: [rootN, branch], spaces: [folder], cards: []));

    expect(ids(s.notes).contains('r'), isFalse);
    expect(ids(s.notes).contains('b'), isFalse);
    // Search still reaches into hidden folders.
    expect(ids(s.searchableNotes).contains('b'), isTrue);
  });

  // ---- Titles -------------------------------------------------------------

  test('new branches are titled and reuse a freed number', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    expect(a.title, 'Note #1');
    expect(b.title, 'Note #2');
    expect(a.isEmpty, isFalse);

    await s.deleteCircuitSubtree(a.id); // frees "Note #1"
    final c = await s.addCircuitChild(r.id);
    expect(c.title, 'Note #1');
  });

  test('a markdown branch carries its title in the source heading', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final md = await s.addCircuitChild(r.id, markdown: true);
    expect(md.markdown, isTrue);
    expect(md.title, 'Note #1');
    expect(md.markdownSource, '# Note #1\n');
    expect(markdownTitle(md.markdownSource), 'Note #1');
    expect(md.isEmpty, isFalse);
  });

  test('note and placeholder numbering are independent', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    await s.addCircuitChild(r.id); // Note #1 (live)
    final b = await s.addCircuitChild(r.id); // Note #2 (live)
    await s.addCircuitChild(b.id);
    await s.deleteCircuitNodeKeepSlot(b.id);
    final ph = s
        .circuitChildren(r.id)
        .firstWhere((n) => n.circuitPlaceholder);
    expect(ph.title, 'Placeholder #1'); // not pushed by the live "Note #" titles
  });

  // ---- Placeholders -------------------------------------------------------

  test('placeholder titles number up and reuse a freed number', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    await s.addCircuitChild(a.id);
    final b = await s.addCircuitChild(r.id);
    await s.addCircuitChild(b.id);

    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph1 = s.circuitChildren(r.id).firstWhere(
        (n) => n.circuitPlaceholder && n.circuitPlaceholderFor == a.id);
    expect(ph1.title, 'Placeholder #1');

    await s.deleteCircuitNodeKeepSlot(b.id);
    final ph2 = s.circuitChildren(r.id).firstWhere(
        (n) => n.circuitPlaceholder && n.circuitPlaceholderFor == b.id);
    expect(ph2.title, 'Placeholder #2');

    await s.deletePlaceholder(ph1.id); // frees #1
    final c = await s.addCircuitChild(r.id);
    await s.addCircuitChild(c.id);
    await s.deleteCircuitNodeKeepSlot(c.id);
    final ph3 = s.circuitChildren(r.id).firstWhere(
        (n) => n.circuitPlaceholder && n.circuitPlaceholderFor == c.id);
    expect(ph3.title, 'Placeholder #1');
  });

  test('placeholders stay out of feed, search and links and refuse show-in-feed',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    await s.addCircuitChild(a.id);
    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);

    expect(ph.isEmpty, isFalse);
    expect(ids(s.notes).contains(ph.id), isFalse);
    expect(ids(s.searchableNotes).contains(ph.id), isFalse);
    expect(ids(s.linkTargets()).contains(ph.id), isFalse);

    await s.setCircuitShowInFeed(ph.id, true);
    expect(ph.circuitShowInFeed, isFalse);
  });

  test('a blanked placeholder title is restored by repair on load', () async {
    final rootN = Note(id: 'r', title: 'R')..circuitId = 'r';
    final ph = Note(id: 'ph', title: '')
      ..circuitId = 'r'
      ..circuitParentId = 'r'
      ..circuitPlaceholder = true
      ..circuitPlaceholderFor = 'x';
    final s = await boot(AppData(notes: [rootN, ph], spaces: [], cards: []));
    expect(s.noteById('ph')!.title, 'Placeholder #1');
  });

  test('fillPlaceholder from the same circuit and from a Home note', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);
    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);
    final b = await s.addCircuitChild(r.id);

    // A branch of the same circuit fills the slot and adopts its children.
    expect(await s.fillPlaceholder(ph.id, b.id), isTrue);
    expect(s.noteById(ph.id), isNull);
    expect(b.circuitParentId, r.id);
    expect(ids(s.circuitChildren(b.id)).contains(a1.id), isTrue);

    // A Home note can be placed into a placeholder.
    final r2 = await newCircuit(s, title: 'C2');
    final x = await s.addCircuitChild(r2.id);
    await s.addCircuitChild(x.id);
    await s.deleteCircuitNodeKeepSlot(x.id);
    final ph2 = s.circuitChildren(r2.id).firstWhere((n) => n.circuitPlaceholder);
    final home = Note(title: 'Loose');
    await s.upsertNote(home);
    expect(await s.fillPlaceholder(ph2.id, home.id), isTrue);
    expect(home.circuitId, r2.id);
    expect(home.spaceId, isNull);

    // Invalid: the root can never fill a slot.
    final r3 = await newCircuit(s, title: 'C3');
    final y = await s.addCircuitChild(r3.id);
    await s.addCircuitChild(y.id);
    await s.deleteCircuitNodeKeepSlot(y.id);
    final ph3 = s.circuitChildren(r3.id).firstWhere((n) => n.circuitPlaceholder);
    expect(await s.fillPlaceholder(ph3.id, r3.id), isFalse);
  });

  test('writeIntoPlaceholder turns a placeholder into a titled note in place',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);
    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);

    final written = await s.writeIntoPlaceholder(ph.id);
    expect(written.id, ph.id);
    expect(written.circuitPlaceholder, isFalse);
    expect(written.circuitPlaceholderFor, isNull);
    expect(written.title, 'Note #1'); // reuses the number freed by deleting a
    expect(written.isEmpty, isFalse);
    expect(ids(s.circuitChildren(written.id)), [a1.id]); // children kept
    expect(ids(s.searchableNotes).contains(written.id), isTrue);
  });

  test('writeIntoPlaceholder can seed a Markdown note', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    await s.addCircuitChild(a.id);
    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);

    final md = await s.writeIntoPlaceholder(ph.id, markdown: true);
    expect(md.markdown, isTrue);
    expect(md.markdownSource, '# Note #1\n');
    expect(markdownTitle(md.markdownSource), 'Note #1');
    expect(md.circuitPlaceholder, isFalse);
  });

  // ---- Existing notes -----------------------------------------------------

  test('placeNoteInCircuit pulls a note in; removeFromCircuit lifts children',
      () async {
    final s = await emptyState();
    final folder = await s.addSpace('Work');
    final r = await newCircuit(s);
    final home = Note(title: 'Loose', spaceId: folder.id);
    await s.upsertNote(home);

    expect(await s.placeNoteInCircuit(home.id, r.id), isTrue);
    expect(home.spaceId, isNull);
    expect(home.circuitId, r.id);
    expect(home.circuitShowInFeed, isFalse);
    expect(ids(s.notes).contains(home.id), isFalse); // left the feed

    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);
    final a2 = await s.addCircuitChild(a.id);
    await s.removeFromCircuit(a.id);
    expect(a.inCircuit, isFalse);
    expect(a1.circuitParentId, r.id);
    expect(ids(s.circuitChildren(r.id)).toSet().containsAll({a1.id, a2.id}),
        isTrue);
  });

  // ---- Deletion & trash ---------------------------------------------------

  test('deleteCircuitSubtree groups node and descendants', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);
    final a2 = await s.addCircuitChild(a.id);

    await s.deleteCircuitSubtree(a.id);
    expect(a.deletedAt, isNotNull);
    expect(a1.deletedAt, isNotNull);
    expect(a2.deletedAt, isNotNull);
    expect(r.deletedAt, isNull);

    final groups = s.deletedNoteGroups;
    expect(groups.length, 1);
    expect(groups.first.members.map((m) => m.id).toSet(), {a.id, a1.id, a2.id});
    expect(groups.first.top.id, a.id);
  });

  test('deleteCircuit trashes the whole circuit as one group', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    await s.deleteCircuit(r.id);
    final groups = s.deletedNoteGroups;
    expect(groups.length, 1);
    expect(groups.first.members.map((m) => m.id).toSet(), {r.id, a.id, b.id});
    expect(groups.first.top.id, r.id);
  });

  test('deleteNote routes root to deleteCircuit and keeps a slot for a parent',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);

    await s.deleteNote(a.id); // branch with a child → keep-slot
    expect(a.deletedAt, isNotNull);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);
    expect(ph.circuitPlaceholderFor, a.id);
    expect(ids(s.circuitChildren(ph.id)), [a1.id]);

    await s.deleteNote(r.id); // root → whole circuit
    expect(r.deletedAt, isNotNull);
    expect(s.circuitNodes(r.id).where((n) => n.deletedAt == null), isEmpty);
  });

  test('restore rule 1: a plain note restores unchanged', () async {
    final s = await emptyState();
    final n = Note(title: 'plain');
    await s.upsertNote(n);
    await s.deleteNote(n.id);
    expect(ids(s.deletedNotes), [n.id]);
    await s.restoreNote(n.id);
    expect(n.deletedAt, isNull);
    expect(ids(s.notes).contains(n.id), isTrue);
  });

  test('restore rule 2: restoring a deleted circuit brings every node back',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    await s.deleteCircuit(r.id);
    await s.restoreTrashGroup(s.deletedNoteGroups.first.key);
    expect(r.deletedAt, isNull);
    expect(a.deletedAt, isNull);
    expect(ids(s.circuitChildren(r.id)), [a.id]);
  });

  test('restore rule 3: restoring a branch group revives its trashed root',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);

    await s.deleteCircuitSubtree(a.id);
    final subKey = s.deletedNoteGroups
        .firstWhere((g) => g.members.any((m) => m.id == a.id))
        .key;
    await s.deleteNote(r.id); // trashes the root (a, a1 already gone)

    await s.restoreTrashGroup(subKey);
    expect(r.deletedAt, isNull);
    expect(a.deletedAt, isNull);
    expect(a1.deletedAt, isNull);
  });

  test('restore rule 4: a deleted node reclaims its placeholder slot', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);
    await s.deleteCircuitNodeKeepSlot(a.id);
    final ph = s.circuitChildren(r.id).firstWhere((n) => n.circuitPlaceholder);

    await s.restoreNote(a.id);
    expect(a.deletedAt, isNull);
    expect(s.noteById(ph.id), isNull); // placeholder consumed
    expect(ids(s.circuitChildren(r.id)), [a.id]);
    expect(ids(s.circuitChildren(a.id)), [a1.id]);
  });

  test('restore rule 5: a childless branch returns under its live parent',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final b = await s.addCircuitChild(r.id);
    await s.deleteNote(b.id); // childless branch: a group of one
    await s.restoreNote(b.id);
    expect(b.deletedAt, isNull);
    expect(b.circuitParentId, r.id);
    expect(ids(s.circuitChildren(r.id)).toSet(), {a.id, b.id});
  });

  test('restore rule 7: an orphaned branch group becomes a new circuit',
      () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    final a1 = await s.addCircuitChild(a.id);

    await s.deleteCircuitSubtree(a.id);
    final subKey = s.deletedNoteGroups
        .firstWhere((g) => g.members.any((m) => m.id == a.id))
        .key;
    await s.deleteNote(r.id);
    final rootKey = s.deletedNoteGroups
        .firstWhere((g) => g.members.any((m) => m.id == r.id))
        .key;
    await s.permanentlyDeleteTrashGroup(rootKey);
    expect(s.noteById(r.id), isNull);

    await s.restoreTrashGroup(subKey);
    expect(a.deletedAt, isNull);
    expect(a.isCircuitRoot, isTrue);
    expect(a.circuitId, a.id);
    expect(a1.circuitId, a.id);
    expect(ids(s.circuitChildren(a.id)), [a1.id]);
  });

  test('permanently deleting a group removes every member', () async {
    final s = await emptyState();
    final r = await newCircuit(s);
    final a = await s.addCircuitChild(r.id);
    await s.deleteCircuit(r.id);
    await s.permanentlyDeleteTrashGroup(s.deletedNoteGroups.first.key);
    expect(s.noteById(r.id), isNull);
    expect(s.noteById(a.id), isNull);
    expect(s.deletedNoteGroups, isEmpty);
  });

  test('the 30-day purge removes a whole deleted circuit together', () async {
    final old = DateTime.now().subtract(const Duration(days: 40));
    final rootN = Note(id: 'r', title: 'R', deletedAt: old)
      ..circuitId = 'r'
      ..trashGroupId = 'g';
    final branch = Note(id: 'b', title: 'Note #1', deletedAt: old)
      ..circuitId = 'r'
      ..circuitParentId = 'r'
      ..trashGroupId = 'g';
    final s = await boot(AppData(notes: [rootN, branch], spaces: [], cards: []));
    expect(s.noteById('r'), isNull);
    expect(s.noteById('b'), isNull);
  });

  // ---- Integrity repair ---------------------------------------------------

  test('repair reparents a branch with a missing parent, clears its folder '
      'and fixes gapped orders', () async {
    final rootN = Note(id: 'r', title: 'R')..circuitId = 'r';
    final stray = Note(id: 'p', title: 'Note #1', spaceId: 'somefolder')
      ..circuitId = 'r'
      ..circuitParentId = 'ghost'
      ..circuitOrder = 5;
    final s = await boot(AppData(notes: [rootN, stray], spaces: [], cards: []));
    final fixed = s.noteById('p')!;
    expect(fixed.circuitParentId, 'r');
    expect(fixed.spaceId, isNull);
    expect(fixed.circuitOrder, 0);
  });

  test('repair promotes a surviving ancestor when the root is missing',
      () async {
    final b = Note(id: 'b', title: 'Note #1')
      ..circuitId = 'ghost'
      ..circuitParentId = 'ghost';
    final c = Note(id: 'c', title: 'Note #2')
      ..circuitId = 'ghost'
      ..circuitParentId = 'b';
    final s = await boot(AppData(notes: [b, c], spaces: [], cards: []));
    expect(s.noteById('b')!.isCircuitRoot, isTrue);
    expect(s.noteById('b')!.circuitId, 'b');
    expect(s.noteById('c')!.circuitId, 'b');
    expect(s.noteById('c')!.circuitParentId, 'b');
  });

  test('repair breaks a parent cycle', () async {
    final rootN = Note(id: 'r', title: 'R')..circuitId = 'r';
    final x = Note(id: 'x', title: 'Note #1')
      ..circuitId = 'r'
      ..circuitParentId = 'y';
    final y = Note(id: 'y', title: 'Note #2')
      ..circuitId = 'r'
      ..circuitParentId = 'x';
    final s = await boot(AppData(notes: [rootN, x, y], spaces: [], cards: []));
    expect(s.isCircuitAncestor('r', 'x'), isTrue);
    expect(s.isCircuitAncestor('r', 'y'), isTrue);
  });

  // ---- Persistence --------------------------------------------------------

  test('a circuit survives a flush and reload (JSON store)', () async {
    final s1 = await emptyState();
    final r = await newCircuit(s1, title: 'Trip');
    final a = await s1.addCircuitChild(r.id);
    final a1 = await s1.addCircuitChild(a.id);
    final md = await s1.addCircuitChild(r.id, markdown: true);
    await s1.setCircuitShowInFeed(a.id, true);
    await s1.setCircuitLayout(r.id, 'radial');
    await s1.flushNow();

    final s2 = newState();
    await s2.init();
    expect(s2.noteById(r.id)!.isCircuitRoot, isTrue);
    expect(s2.noteById(r.id)!.circuitLayout, 'radial');
    expect(ids(s2.circuitChildren(r.id)), [a.id, md.id]);
    expect(ids(s2.circuitChildren(a.id)), [a1.id]);
    expect(s2.noteById(a.id)!.circuitShowInFeed, isTrue);
    expect(s2.noteById(md.id)!.markdown, isTrue);
  });

  test('a circuit round-trips through the FFI SQLite store', () async {
    sqfliteFfiInit();
    final dbPath = '${root.path}/circuit_db_test.db';
    final dbFile = File(dbPath);
    if (dbFile.existsSync()) dbFile.deleteSync();

    final store1 = DbStore(factory: databaseFactoryFfi, path: dbPath);
    final s1 = newState(dbStore: store1);
    await s1.init();
    final r = await newCircuit(s1, title: 'Trip');
    final a = await s1.addCircuitChild(r.id);
    final a1 = await s1.addCircuitChild(a.id);
    await s1.setCircuitLayout(r.id, 'ttb');
    await s1.flushNow();
    await store1.close();

    final store2 = DbStore(factory: databaseFactoryFfi, path: dbPath);
    final s2 = newState(dbStore: store2);
    await s2.init();
    expect(s2.noteById(r.id), isNotNull);
    expect(s2.noteById(r.id)!.circuitLayout, 'ttb');
    expect(ids(s2.circuitChildren(r.id)), [a.id]);
    expect(ids(s2.circuitChildren(a.id)), [a1.id]);
    await store2.close();
  });
}
