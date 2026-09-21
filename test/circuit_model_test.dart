import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';

// Model-level tests for the circuit fields on [Note]: JSON compatibility and
// the root/branch getters. The behavioural (AppState) tests live in
// circuit_state_test.dart.
void main() {
  const circuitKeys = [
    'circuitId',
    'circuitParentId',
    'circuitOrder',
    'circuitShowInFeed',
    'circuitPlaceholder',
    'circuitPlaceholderFor',
    'circuitLayout',
    'trashGroupId',
  ];

  test('a note not in a circuit serializes byte-for-byte as before', () {
    final json = Note(
      id: 'n1',
      title: 'plain',
      blocks: [NoteBlock(type: NoteBlockType.text, text: 'hello')],
    ).toJson();
    for (final key in circuitKeys) {
      expect(json.containsKey(key), isFalse, reason: 'unexpected key $key');
    }
  });

  test('old JSON without the new keys loads with defaults', () {
    final n = Note.fromJson({
      'id': 'a',
      'title': 'legacy',
      'blocks': <dynamic>[],
    });
    expect(n.circuitId, isNull);
    expect(n.circuitParentId, isNull);
    expect(n.circuitOrder, 0);
    expect(n.circuitShowInFeed, isFalse);
    expect(n.circuitPlaceholder, isFalse);
    expect(n.circuitPlaceholderFor, isNull);
    expect(n.circuitLayout, 'ltr');
    expect(n.trashGroupId, isNull);
    expect(n.inCircuit, isFalse);
    expect(n.isCircuitRoot, isFalse);
    expect(n.isCircuitNode, isFalse);
  });

  test('every circuit field round-trips through JSON', () {
    final root = Note(id: 'root', title: 'Root')
      ..circuitId = 'root'
      ..circuitLayout = 'radial';
    final branch = Note(id: 'c1', title: 'Note #1')
      ..circuitId = 'root'
      ..circuitParentId = 'root'
      ..circuitOrder = 2
      ..circuitShowInFeed = true
      ..trashGroupId = 'grp-7';
    final placeholder = Note(id: 'ph', title: 'Placeholder #1')
      ..circuitId = 'root'
      ..circuitParentId = 'root'
      ..circuitOrder = 1
      ..circuitPlaceholder = true
      ..circuitPlaceholderFor = 'gone';

    for (final original in [root, branch, placeholder]) {
      final back = Note.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(back.circuitId, original.circuitId);
      expect(back.circuitParentId, original.circuitParentId);
      expect(back.circuitOrder, original.circuitOrder);
      expect(back.circuitShowInFeed, original.circuitShowInFeed);
      expect(back.circuitPlaceholder, original.circuitPlaceholder);
      expect(back.circuitPlaceholderFor, original.circuitPlaceholderFor);
      expect(back.circuitLayout, original.circuitLayout);
      expect(back.trashGroupId, original.trashGroupId);
    }
  });

  test('circuit keys are written only when non-default', () {
    // A root writes circuitId (equals its own id) but not the default layout.
    final rootJson = (Note(id: 'r')..circuitId = 'r').toJson();
    expect(rootJson['circuitId'], 'r');
    expect(rootJson.containsKey('circuitLayout'), isFalse);
    expect(rootJson.containsKey('circuitOrder'), isFalse);
    expect(rootJson.containsKey('circuitShowInFeed'), isFalse);

    final radial = (Note(id: 'r')
          ..circuitId = 'r'
          ..circuitLayout = 'radial')
        .toJson();
    expect(radial['circuitLayout'], 'radial');
  });

  test('root, branch and loose-note getters', () {
    final root = Note(id: 'r')..circuitId = 'r';
    final branch = Note(id: 'b')
      ..circuitId = 'r'
      ..circuitParentId = 'r';
    final loose = Note(id: 'x');

    expect(root.inCircuit, isTrue);
    expect(root.isCircuitRoot, isTrue);
    expect(root.isCircuitNode, isFalse);

    expect(branch.inCircuit, isTrue);
    expect(branch.isCircuitRoot, isFalse);
    expect(branch.isCircuitNode, isTrue);

    expect(loose.inCircuit, isFalse);
    expect(loose.isCircuitRoot, isFalse);
    expect(loose.isCircuitNode, isFalse);
  });

  test('a titled branch is never empty (so cleanup never deletes it)', () {
    final branch = Note(
      title: 'Note #1',
      blocks: [NoteBlock(type: NoteBlockType.text)],
    );
    expect(branch.isEmpty, isFalse);
    final placeholder = Note(title: 'Placeholder #1');
    expect(placeholder.isEmpty, isFalse);
  });
}
