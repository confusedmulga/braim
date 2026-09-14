import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/note_pdf.dart';

void main() {
  test('a rich markdown note exports to a valid, non-trivial PDF', () async {
    const md = '# Project Braim\n'
        '\n'
        'A **local-first** notes app with a [link](https://braim.app) and '
        '`inline code`.\n'
        '\n'
        '## Features\n'
        '\n'
        '- [x] Notes and sparks\n'
        '- [ ] Cloud sync\n'
        '- Fast search\n'
        '\n'
        '| Feature | Braim |\n'
        '| --- | --- |\n'
        '| Local-first | Yes |\n'
        '\n'
        '> Built with care.\n'
        '\n'
        '```dart\n'
        'void main() {\n'
        '  run();\n'
        '}\n'
        '```\n';

    final bytes = await NotePdf.fromMarkdown(md, title: 'Project Braim');

    // Valid PDF header and a real document (not an empty stub).
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1500));
  });

  test('plain text and empty input do not throw', () async {
    expect((await NotePdf.fromMarkdown('just a line of text')).length,
        greaterThan(500));
    expect((await NotePdf.fromMarkdown('')).isNotEmpty, isTrue);
  });
}
