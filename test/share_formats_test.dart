import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/services/note_docx.dart';
import 'package:braim/services/note_markdown.dart';
import 'package:braim/widgets/share_as.dart';

/// A note with one of everything the exports handle.
const _note = '''# Trip plan

Book **flights** and *hotels*, ~~not trains~~, see `notes.txt`
and [the guide](https://example.com/guide). Fish & chips < 10 > 5.

## Packing

- Passport
- Chargers
  - Phone
- [x] Visa
- [ ] Insurance

3. Third
4. Fourth

> Travel light.

```
print("hi");
```

| City | Nights |
| --- | --- |
| Rome | 3 |

---

![map](map.png)
''';

void main() {
  group('Document (.docx)', () {
    late Map<String, String> parts;

    setUpAll(() {
      final bytes = NoteDocx.fromMarkdown('$_note\u0007', title: 'Trip plan');
      final zip = ZipDecoder().decodeBytes(bytes);
      parts = {
        for (final f in zip.files)
          if (f.isFile) f.name: utf8.decode(f.content as List<int>),
      };
    });

    test('has every part Word needs, each well-formed XML', () {
      expect(
          parts.keys,
          containsAll([
            '[Content_Types].xml',
            '_rels/.rels',
            'docProps/core.xml',
            'word/document.xml',
            'word/styles.xml',
            'word/numbering.xml',
            'word/_rels/document.xml.rels',
          ]));
      for (final entry in parts.entries) {
        expect(() => XmlDocument.parse(entry.value), returnsNormally,
            reason: entry.key);
      }
      expect(parts['docProps/core.xml'], contains('<dc:title>Trip plan'));
    });

    test('keeps headings, formatting, lists, links, quote, code and table',
        () {
      final doc = parts['word/document.xml']!;
      expect(doc, contains('<w:pStyle w:val="Heading1"/>'));
      expect(doc, contains('<w:pStyle w:val="Heading2"/>'));
      expect(doc, contains('<w:b/>'));
      expect(doc, contains('<w:i/>'));
      expect(doc, contains('<w:strike/>'));
      expect(doc, contains('Consolas'));
      expect(doc, contains('<w:pStyle w:val="Quote"/>'));
      expect(doc, contains('<w:pStyle w:val="CodeBlock"/>'));
      expect(doc, contains('<w:tbl>'));
      expect(doc, contains('Rome'));
      expect(doc, contains('☑ '));
      expect(doc, contains('☐ '));
      expect(doc, contains('[image: map]'));
      expect(doc, contains('Fish &amp; chips &lt; 10 &gt; 5.'));
      expect(doc, isNot(contains('\u0007'))); // XML can't hold it

      // The link points at its address.
      final rel = RegExp(r'<w:hyperlink r:id="(\w+)"').firstMatch(doc)!;
      expect(parts['word/_rels/document.xml.rels'],
          contains('Id="${rel.group(1)}" Type="http://schemas.openxmlformats.'
              'org/officeDocument/2006/relationships/hyperlink" '
              'Target="https://example.com/guide"'));

      // Bullets nest a level; the numbered list starts at 3.
      expect(doc, contains('<w:ilvl w:val="1"/>'));
      expect(parts['word/numbering.xml'], contains('<w:startOverride w:val="3"/>'));
    });
  });

  test('plain text drops the symbols and keeps the shape', () {
    final text = markdownToPlainText(_note);
    expect(text, startsWith('Trip plan\n\nBook flights and hotels, not trains,'));
    expect(text, contains('the guide (https://example.com/guide)'));
    expect(text, contains('• Passport\n• Chargers\n  • Phone\n☑ Visa\n☐ Insurance'));
    expect(text, contains('3. Third\n4. Fourth'));
    expect(text, contains('Travel light.'));
    expect(text, contains('print("hi");'));
    expect(text, contains('City | Nights\nRome | 3'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('## ')));
  });

  testWidgets('Share as: the row shares .md; the list offers every format',
      (tester) async {
    final shared = <ShareFormat>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ShareAsTile(onShare: shared.add)),
    ));
    expect(find.text('Share as'), findsOneWidget);
    expect(find.text('.md'), findsOneWidget);

    await tester.tap(find.text('Share as'));
    expect(shared, [ShareFormat.markdown]);

    await tester.tap(find.text('.md'));
    await tester.pumpAndSettle();
    for (final label in [
      'Markdown (.md)',
      'Plain text',
      'PDF (.pdf)',
      'Document (.docx)',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Document (.docx)'));
    await tester.pumpAndSettle();
    expect(shared, [ShareFormat.markdown, ShareFormat.docx]);
  });
}
