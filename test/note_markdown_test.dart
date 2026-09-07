import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/note_markdown.dart';

void main() {
  test('a markdown node round-trips its flag and raw source', () {
    const src = '# Title\n\nSome **raw** markdown with a [link](https://x.io).';
    final note = Note(
      markdown: true,
      title: 'Title',
      blocks: [NoteBlock(type: NoteBlockType.text, text: src)],
    );
    expect(note.markdown, isTrue);
    expect(note.markdownSource, src);

    final back = Note.fromJson(note.toJson());
    expect(back.markdown, isTrue);
    expect(back.markdownSource, src);
  });

  test('markdownPlainPreview strips syntax and skips the title', () {
    const md = '# My README\n'
        '\n'
        'A **bold** intro with `code` and a [link](https://x.io).\n'
        '\n'
        '- [ ] a task\n'
        '## Section\n'
        '> quoted\n';
    final preview = markdownPlainPreview(md, skipTitle: 'My README');
    expect(preview.contains('My README'), isFalse);
    expect(preview.contains('**'), isFalse);
    expect(preview.contains('`'), isFalse);
    expect(preview.contains(']('), isFalse);
    expect(preview.contains('- [ ]'), isFalse);
    expect(preview.contains('#'), isFalse);
    expect(preview.contains('A bold intro'), isTrue);
    expect(preview.contains('a task'), isTrue);
  });

  test('imported markdown renders formatted, not raw symbols', () {
    const md = '# My title\n'
        '\n'
        'Some **bold** and *italic* text.\n'
        '\n'
        '- [ ] a todo\n'
        '- [x] done thing\n'
        '- a bullet\n'
        '\n'
        '## A subheading\n'
        '\n'
        '> a quote line\n';

    final note = noteFromMarkdown(md);
    expect(note.title, 'My title');

    final lines = richToStyledLines(note.blocks.single.text);
    final joined = lines.map((l) => l.text).join('\n');

    // No raw markdown syntax should survive into the rendered text.
    expect(joined.contains('**'), isFalse);
    expect(joined.contains('- [ ]'), isFalse);
    expect(joined.contains('- [x]'), isFalse);
    expect(joined.contains('# '), isFalse);
    expect(joined.contains('> '), isFalse);

    // Structure is recovered as real block formats + inline runs.
    expect(lines.any((l) => l.header == 2), isTrue);
    expect(lines.any((l) => l.kind == RichLineKind.uncheckedItem), isTrue);
    expect(lines.any((l) => l.kind == RichLineKind.checkedItem), isTrue);
    expect(lines.any((l) => l.kind == RichLineKind.bullet), isTrue);
    expect(lines.any((l) => l.quote), isTrue);
    expect(lines.any((l) => l.runs.any((r) => r.bold)), isTrue);
    expect(lines.any((l) => l.runs.any((r) => r.italic)), isTrue);
  });

  test('links survive import as tappable runs, not raw [text](url)', () {
    const md = 'See [the docs](https://example.com/guide) here.';
    final note = noteFromMarkdown(md);
    final lines = richToStyledLines(note.blocks.single.text);
    final joined = lines.map((l) => l.text).join('\n');
    expect(joined.contains(']('), isFalse);
    expect(joined.contains('the docs'), isTrue);
    expect(
      lines.any((l) =>
          l.runs.any((r) => r.link == 'https://example.com/guide')),
      isTrue,
    );
  });

  test('title heading is flattened to plain text (no ** markers)', () {
    const md = '# Hello **world** and [docs](https://x.io)\n\nbody line\n';
    final note = noteFromMarkdown(md);
    expect(note.title, 'Hello world and docs');
    // The title line is not duplicated into the body.
    final lines = richToStyledLines(note.blocks.single.text);
    final joined = lines.map((l) => l.text).join('\n');
    expect(joined.contains('Hello world'), isFalse);
    expect(joined.contains('body line'), isTrue);
  });

  test('plain shared text imports unchanged, with no title lifted', () {
    const text = 'Buy milk and eggs\nremember the umbrella';
    final note = noteFromMarkdown(text);
    expect(note.title, '');
    final lines = richToStyledLines(note.blocks.single.text);
    expect(lines.map((l) => l.text).join('\n'), text);
    expect(lines.every((l) => l.kind == RichLineKind.plain), isTrue);
  });
}
