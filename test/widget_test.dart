import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';

void main() {
  test('Note thumbnail picks the first image block', () {
    final note = Note(blocks: [
      NoteBlock(type: NoteBlockType.text, text: 'hello'),
      NoteBlock(type: NoteBlockType.image, imagePath: '/a/b.jpg'),
      NoteBlock(type: NoteBlockType.image, imagePath: '/a/c.jpg'),
    ]);
    expect(note.thumbnailPath, '/a/b.jpg');
    expect(note.imagePaths.length, 2);
  });

  test('Note serialization round-trips', () {
    final note = Note(title: 'T', blocks: [
      NoteBlock(type: NoteBlockType.text, text: 'body'),
    ]);
    final restored = Note.fromJson(note.toJson());
    expect(restored.title, 'T');
    expect(restored.blocks.first.text, 'body');
  });
}
