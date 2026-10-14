import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/widgets/note_body_editor.dart';

/// Joining two text blocks (a photo between them removed, or a Backspace at
/// the start of the lower one) keeps each line's own kind.
void main() {
  Delta d(List<Map<String, dynamic>> ops) => Delta.fromJson(ops);

  test('a blank block below a checklist goes without unticking it', () {
    final above = d([
      {'insert': 'Groceries\nmilk'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
    ]);
    final blank = d([
      {'insert': '\n'},
    ]);
    expect(joinBlockDeltas(above, blank).toJson(), above.toJson());
  });

  test('a blank block above a heading goes without flattening it', () {
    final blank = d([
      {'insert': '\n'},
    ]);
    final below = d([
      {'insert': 'Title'},
      {
        'insert': '\n',
        'attributes': {'header': 1},
      },
    ]);
    expect(joinBlockDeltas(blank, below).toJson(), below.toJson());
  });

  test('joined lines take the upper line\'s kind, as the editor does', () {
    final above = d([
      {'insert': 'milk'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
    ]);
    final below = d([
      {'insert': ' and eggs\nnext line\n'},
    ]);
    expect(joinBlockDeltas(above, below).toJson(), [
      {'insert': 'milk and eggs'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'next line\n'},
    ]);
  });
}
