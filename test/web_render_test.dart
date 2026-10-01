import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/note.dart';
import 'package:braim/web/web_html.dart';

/// A Quill Delta as the editor stores it.
String delta(List<Map<String, Object>> ops) => jsonEncode(ops);

void main() {
  group('rich text (Delta) to HTML', () {
    test('headings, quotes and paragraphs', () {
      final html = richBlockHtml(
        delta([
          {'insert': 'Big'},
          {
            'insert': '\n',
            'attributes': {'header': 1},
          },
          {'insert': 'Smaller'},
          {
            'insert': '\n',
            'attributes': {'header': 2},
          },
          {'insert': 'Said someone'},
          {
            'insert': '\n',
            'attributes': {'blockquote': true},
          },
          {'insert': 'Plain\n\nAfter a blank\n'},
        ]),
        blockIndex: 0,
      );
      expect(
        html,
        '<h2>Big</h2><h3>Smaller</h3><blockquote>Said someone</blockquote>'
        '<p>Plain</p><p class="blank"><br></p><p>After a blank</p>',
      );
    });

    test('lists are grouped; consecutive kinds share one list', () {
      final html = richBlockHtml(
        delta([
          {'insert': 'a'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
          {'insert': 'b'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
          {'insert': 'one'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'two'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'end\n'},
        ]),
        blockIndex: 0,
      );
      expect(
        html,
        '<ul><li>a</li><li>b</li></ul><ol><li>one</li><li>two</li></ol>'
        '<p>end</p>',
      );
    });

    test(
      'checklist boxes carry block and line indexes as richToLines counts',
      () {
        final raw = delta([
          {'insert': 'Shopping\n'},
          {'insert': 'Milk'},
          {
            'insert': '\n',
            'attributes': {'list': 'checked'},
          },
          {'insert': 'Eggs'},
          {
            'insert': '\n',
            'attributes': {'list': 'unchecked'},
          },
        ]);
        final html = richBlockHtml(raw, blockIndex: 2);
        expect(html, contains('<p>Shopping</p><ul class="checklist">'));
        expect(
          html,
          contains(
            '<li class="done"><input type="checkbox" data-block="2" '
            'data-line="1" checked disabled> <span>Milk</span></li>',
          ),
        );
        expect(
          html,
          contains(
            '<li><input type="checkbox" data-block="2" data-line="2" '
            'disabled> <span>Eggs</span></li>',
          ),
        );
        // The indexes are the ones toggleChecklistLine flips.
        expect(richToLines(raw)[1].text, 'Milk');
        expect(
          richToLines(toggleChecklistLine(raw, 2))[2].kind,
          RichLineKind.checkedItem,
        );
        // Pages that may tick (Phase 4) drop the disabled flag.
        expect(
          richBlockHtml(raw, blockIndex: 2, interactive: true),
          isNot(contains('disabled')),
        );
      },
    );

    test('ticked items can sink to the bottom, keeping their line numbers', () {
      final html = richBlockHtml(
        delta([
          {'insert': 'Done'},
          {
            'insert': '\n',
            'attributes': {'list': 'checked'},
          },
          {'insert': 'Todo'},
          {
            'insert': '\n',
            'attributes': {'list': 'unchecked'},
          },
        ]),
        blockIndex: 0,
        checkedToBottom: true,
      );
      expect(html.indexOf('Todo'), lessThan(html.indexOf('Done')));
      expect(html, contains('data-line="0" checked'));
      expect(html, contains('data-line="1" disabled'));
    });

    test('indent and alignment become classes', () {
      final html = richBlockHtml(
        delta([
          {'insert': 'in'},
          {
            'insert': '\n',
            'attributes': {'indent': 2},
          },
          {'insert': 'mid'},
          {
            'insert': '\n',
            'attributes': {'align': 'center'},
          },
          {'insert': 'right'},
          {
            'insert': '\n',
            'attributes': {'align': 'right'},
          },
          {'insert': 'just'},
          {
            'insert': '\n',
            'attributes': {'align': 'justify'},
          },
          {'insert': 'deep'},
          {
            'insert': '\n',
            'attributes': {'indent': 9, 'list': 'bullet'},
          },
        ]),
        blockIndex: 0,
      );
      expect(html, contains('<p class="indent-2">in</p>'));
      expect(html, contains('<p class="align-center">mid</p>'));
      expect(html, contains('<p class="align-right">right</p>'));
      expect(html, contains('<p class="align-justify">just</p>'));
      expect(html, contains('<li class="indent-3">deep</li>')); // capped at 3
    });

    test('inline marks: bold, italic, underline, strike, highlight, links', () {
      final html = richBlockHtml(
        delta([
          {
            'insert': 'B',
            'attributes': {'bold': true},
          },
          {
            'insert': 'I',
            'attributes': {'italic': true},
          },
          {
            'insert': 'U',
            'attributes': {'underline': true},
          },
          {
            'insert': 'S',
            'attributes': {'strike': true},
          },
          {
            'insert': 'H',
            'attributes': {'background': '#FFE082', 'color': '#202124'},
          },
          {
            'insert': 'L',
            'attributes': {'link': 'https://example.com/a?b=1&c=2'},
          },
          {
            'insert': 'X',
            'attributes': {'link': 'javascript:alert(1)'},
          },
          {
            'insert': 'all',
            'attributes': {
              'bold': true,
              'italic': true,
              'underline': true,
              'strike': true,
              'background': '#FFE082',
            },
          },
          {'insert': '\n'},
        ]),
        blockIndex: 0,
      );
      expect(html, contains('<strong>B</strong>'));
      expect(html, contains('<em>I</em>'));
      expect(html, contains('<u>U</u>'));
      expect(html, contains('<s>S</s>'));
      expect(html, contains('<mark>H</mark>'));
      expect(
        html,
        contains(
          '<a href="https:&#47;&#47;example.com&#47;a?b=1&amp;c=2" '
          'rel="noopener noreferrer" target="_blank">L</a>',
        ),
      );
      expect(html, isNot(contains('javascript')));
      expect(html, contains('X'));
      expect(
        html,
        contains('<mark><strong><em><u><s>all</s></u></em></strong></mark>'),
      );
    });

    test('wiki-links go to /link; mentions are styled text', () {
      final html = richBlockHtml(
        delta([
          {'insert': 'See [[Trip plan]] with [[@Gym]].\n'},
        ]),
        blockIndex: 0,
      );
      expect(
        html,
        contains('<a class="wiki" href="&#47;link?to=Trip+plan">Trip plan</a>'),
      );
      expect(html, contains('<span class="mention">Gym</span>'));
    });

    test('text that looks like HTML is escaped', () {
      final html = richBlockHtml(
        delta([
          {'insert': '<script>alert(1)</script> & <b onclick="x">\n'},
        ]),
        blockIndex: 0,
      );
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<b ')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('&amp;'));
    });

    test('legacy plain text', () {
      expect(
        richBlockHtml('First line\nSecond <i>line</i>', blockIndex: 0),
        '<p>First line</p><p>Second &lt;i&gt;line&lt;&#47;i&gt;</p>',
      );
      expect(richBlockHtml('', blockIndex: 0), '');
    });
  });

  group('Markdown sanitiser', () {
    test('keeps the allowed GitHub-flavoured Markdown', () {
      final html = markdownToSafeHtml('''
# Title

Some **bold**, *italic*, ~~gone~~ and `code`.

> quoted

- one
- [x] done
- [ ] todo

1. first

| a | b |
|:-:|--:|
| 1 | 2 |

```
let x = 1;
```

---

[site](https://example.com) and ![pic](https://example.com/p.png)
''');
      expect(html, contains('<h1>Title</h1>'));
      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains('<em>italic</em>'));
      expect(html, contains('<del>gone</del>'));
      expect(html, contains('<code>code</code>'));
      expect(html, contains('<blockquote>'));
      expect(html, contains('<li>one</li>'));
      expect(html, contains('<input type="checkbox" checked disabled>'));
      expect(html, contains('<input type="checkbox" disabled>'));
      expect(html, contains('<ol>'));
      expect(html, contains('<table>'));
      expect(html, contains('<th class="align-center">a</th>'));
      expect(html, contains('<td class="align-right">2</td>'));
      expect(html, contains('<pre><code>let x = 1;'));
      expect(html, contains('<hr>'));
      expect(
        html,
        contains(
          '<a href="https:&#47;&#47;example.com" '
          'rel="noopener noreferrer" target="_blank">site</a>',
        ),
      );
      expect(
        html,
        contains('<img src="https:&#47;&#47;example.com&#47;p.png" alt="pic"'),
      );
    });

    test('strips scripts, event handlers, javascript: links and raw HTML', () {
      final html = markdownToSafeHtml('''
Hello <script>alert("x")</script> world.

<img src="x" onerror="alert(1)">
<img src="https://example.com/ok.png" onerror="alert(2)">

[click](javascript:alert(3)) [data](data:text/html;base64,PHNjcmlwdD4=)
[tab](jav&#x09;ascript:alert(4)) [proto](//evil.example/x)

<div onclick="alert(5)" style="color:red">raw block</div>

<iframe src="https://evil.example"></iframe>
<a href="https://example.com" onmouseover="alert(6)">hover</a>
<span class="evil" style="x">kept text</span>
''');
      expect(html, isNot(contains('script')));
      expect(html, isNot(contains('onerror')));
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('onmouseover')));
      expect(html, isNot(contains('javascript')));
      expect(html, isNot(contains('data:')));
      expect(html, isNot(contains('evil.example')));
      expect(html, isNot(contains('<div')));
      expect(html, isNot(contains('<iframe')));
      expect(html, isNot(contains('style=')));
      expect(html, isNot(contains('class="evil"')));
      expect(html, isNot(contains('alert(')));
      // Text inside removed elements is kept, escaped.
      expect(html, contains('raw block'));
      expect(html, contains('click'));
      expect(html, contains('kept text'));
      expect(html, contains('<span>kept text</span>'));
      // The relative "x" image is dropped; the https one stays, without its
      // handler.
      expect(html, isNot(contains('src="x"')));
      expect(html, contains('ok.png'));
      expect(
        html,
        contains(
          '<a href="https:&#47;&#47;example.com" '
          'rel="noopener noreferrer" target="_blank">hover</a>',
        ),
      );
    });

    test('wiki-links become /link links, except inside code', () {
      final html = markdownToSafeHtml(
        'Go to [[Trip plan]].\n\n`[[not a link]]`\n\n```\n[[nor this]]\n```\n',
      );
      expect(
        html,
        contains('<a class="wiki" href="&#47;link?to=Trip+plan">Trip plan</a>'),
      );
      expect(html, contains('<code>[[not a link]]</code>'));
      expect(html, contains('[[nor this]]'));
    });
  });

  group('scraped text', () {
    test('is escaped, never read as HTML', () {
      final html = plainTextHtml(
        'Intro <script>alert(1)</script>\n<img src=x onerror=alert(2)>\n\n'
        'Second paragraph',
      );
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<img')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, startsWith('<p>Intro'));
      expect(html, contains('<br>'));
      expect(html, endsWith('<p>Second paragraph</p>'));
    });
  });

  test('safeUrl allows web and mail links and, when asked, site paths', () {
    expect(safeUrl('https://a.b/c'), 'https://a.b/c');
    expect(safeUrl('HTTP://a.b'), 'HTTP://a.b');
    expect(safeUrl('mailto:x@y.z'), 'mailto:x@y.z');
    expect(safeUrl('javascript:alert(1)'), isNull);
    expect(safeUrl(' java\tscript:alert(1)'), isNull);
    expect(safeUrl('data:text/html,x'), isNull);
    expect(safeUrl('vbscript:x'), isNull);
    expect(safeUrl('/notes/1'), isNull);
    expect(safeUrl('/notes/1', allowRelative: true), '/notes/1');
    expect(safeUrl('//evil.example', allowRelative: true), isNull);
    expect(safeUrl('/\\evil.example', allowRelative: true), isNull);
    expect(safeUrl('notes/1', allowRelative: true), isNull);
  });
}
