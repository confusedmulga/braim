import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/book.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/book_export.dart';
import 'package:braim/services/note_markdown.dart';

/// A note's separate lines stay separate in every export.
void main() {
  Note rich(List<Map<String, Object?>> ops) => Note(
        title: 'List',
        blocks: [NoteBlock(type: NoteBlockType.text, text: jsonEncode(ops))],
      );

  test('separate lines stay separate as plain text', () {
    final note = rich([
      {'insert': 'Milk\nEggs\nBread\n'},
    ]);
    expect(markdownToPlainText(noteBodyToMarkdown(note)), 'Milk\nEggs\nBread');
  });

  test('a line after a list is not folded into its last item', () {
    final note = rich([
      {'insert': 'Buy'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'after the list\n'},
    ]);
    final text = markdownToPlainText(noteBodyToMarkdown(note));
    expect(text, contains('after the list'));
    expect(text.split('\n').last.trim(), 'after the list');
  });

  test('quoted lines stay separate and end with the quote', () {
    final note = rich([
      {'insert': 'one'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'two'},
      {
        'insert': '\n',
        'attributes': {'blockquote': true},
      },
      {'insert': 'plain\n'},
    ]);
    final md = noteBodyToMarkdown(note);
    expect(markdownToPlainText(md).split('\n').map((l) => l.trim()),
        containsAllInOrder(['one', 'two', 'plain']));
  });

  test('the book Markdown export keeps each line its own paragraph', () {
    final chapter = Note(
      title: 'Chapter I',
      bookId: 'b',
      bookPageKind: BookPageKind.chapter,
      blocks: [
        NoteBlock(
          type: NoteBlockType.text,
          text: jsonEncode([
            {'insert': 'It was dark.\nShe waited.\n'},
          ]),
        ),
      ],
    );
    final md = BookExport.markdownOf(
      book: Book(title: 'Ink'),
      pages: [chapter],
      author: '',
      untitledLabel: 'Untitled',
    );
    expect(markdownToPlainText(md), contains('It was dark.\nShe waited.'));
  });
}
