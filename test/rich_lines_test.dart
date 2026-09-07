import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:braim/models/impulse.dart';
import 'package:braim/models/note.dart';

void main() {
  group('Thread flag', () {
    test('migrates the old important bool to the important flag', () {
      final t = Thread.fromJson({'id': 'x', 'title': 'a', 'important': true});
      expect(t.flag, TaskFlag.important);
    });

    test('a new flag round-trips and wins over legacy important', () {
      final t = Thread.fromJson({
        'id': 'x',
        'title': 'a',
        'important': true,
        'flag': TaskFlag.best,
      });
      expect(t.flag, TaskFlag.best);
      expect(Thread.fromJson(t.toJson()).flag, TaskFlag.best);
    });

    test('no flag stays empty and is omitted from json', () {
      final t = Thread(title: 'a');
      expect(t.flag, TaskFlag.none);
      expect(t.toJson().containsKey('flag'), isFalse);
    });
  });

  // A Quill delta with a plain line, an unchecked item and a checked item.
  String delta() => jsonEncode([
        {'insert': 'Groceries'},
        {
          'insert': '\n',
        },
        {'insert': 'Milk'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
        {'insert': 'Eggs'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
      ]);

  group('richToLines', () {
    test('recovers checkbox markers a plain flatten would drop', () {
      final lines = richToLines(delta());
      expect(lines.map((l) => l.text).toList(), ['Groceries', 'Milk', 'Eggs']);
      expect(lines[0].kind, RichLineKind.plain);
      expect(lines[1].kind, RichLineKind.uncheckedItem);
      expect(lines[2].kind, RichLineKind.checkedItem);
    });

    test('plain text (non-delta) splits on newlines', () {
      final lines = richToLines('one\ntwo');
      expect(lines.map((l) => l.text).toList(), ['one', 'two']);
      expect(lines.every((l) => l.kind == RichLineKind.plain), isTrue);
    });

    test('drops the trailing empty paragraph Quill always appends', () {
      final raw = jsonEncode([
        {'insert': 'solo\n'},
      ]);
      final lines = richToLines(raw);
      expect(lines.length, 1);
      expect(lines.single.text, 'solo');
    });
  });

  group('richToStyledLines', () {
    test('keeps inline marks a plain flatten would drop', () {
      final raw = jsonEncode([
        {'insert': 'Plain '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': ' and '},
        {
          'insert': 'italic',
          'attributes': {'italic': true},
        },
        {'insert': '\n'},
      ]);
      final lines = richToStyledLines(raw);
      expect(lines.length, 1);
      expect(lines.single.text, 'Plain bold and italic');
      final runs = lines.single.runs;
      expect(runs.firstWhere((r) => r.text == 'bold').bold, isTrue);
      expect(runs.firstWhere((r) => r.text == 'italic').italic, isTrue);
      expect(runs.firstWhere((r) => r.text == 'Plain ').bold, isFalse);
    });

    test('recovers heading, quote, indent and alignment block formats', () {
      final raw = jsonEncode([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {'insert': 'A quote'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true, 'align': 'center', 'indent': 2},
        },
      ]);
      final lines = richToStyledLines(raw);
      expect(lines[0].header, 1);
      expect(lines[1].quote, isTrue);
      expect(lines[1].align, 'center');
      expect(lines[1].indent, 2);
    });

    test('a justified paragraph keeps its alignment', () {
      final raw = jsonEncode([
        {'insert': 'Justified body text that wraps.'},
        {
          'insert': '\n',
          'attributes': {'align': 'justify'},
        },
      ]);
      expect(richToStyledLines(raw).single.align, 'justify');
    });

    test('line order matches richToLines so checkbox indexes stay in sync', () {
      final styled = richToStyledLines(delta());
      final plain = richToLines(delta());
      expect(styled.map((l) => l.text).toList(),
          plain.map((l) => l.text).toList());
      expect(styled.map((l) => l.kind).toList(),
          plain.map((l) => l.kind).toList());
    });

    test('a bold word inside a checklist item keeps both marks', () {
      final raw = jsonEncode([
        {'insert': 'buy '},
        {
          'insert': 'milk',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);
      final lines = richToStyledLines(raw);
      expect(lines.single.kind, RichLineKind.uncheckedItem);
      expect(lines.single.runs.firstWhere((r) => r.text == 'milk').bold, isTrue);
    });
  });

  group('toggleChecklistLine', () {
    test('flips unchecked to checked and back', () {
      final toggled = toggleChecklistLine(delta(), 1); // the "Milk" line
      expect(richToLines(toggled)[1].kind, RichLineKind.checkedItem);
      // Other lines are untouched.
      expect(richToLines(toggled)[0].kind, RichLineKind.plain);
      expect(richToLines(toggled)[2].kind, RichLineKind.checkedItem);

      final back = toggleChecklistLine(toggled, 1);
      expect(richToLines(back)[1].kind, RichLineKind.uncheckedItem);
    });

    test('checked line flips to unchecked', () {
      final toggled = toggleChecklistLine(delta(), 2); // the "Eggs" line
      expect(richToLines(toggled)[2].kind, RichLineKind.uncheckedItem);
    });

    test('leaves a non-checkbox line untouched', () {
      final raw = delta();
      expect(toggleChecklistLine(raw, 0), raw); // "Groceries" is plain
    });

    test('leaves plain (non-delta) text untouched', () {
      expect(toggleChecklistLine('just text', 0), 'just text');
    });

    test('splits a shared multi-newline op so only one line flips', () {
      // Two empty unchecked items whose newlines were normalised into a single
      // "\n\n" op — toggling one must not carry the other along.
      final raw = jsonEncode([
        {
          'insert': '\n\n',
          'attributes': {'list': 'unchecked'},
        },
      ]);
      final lines = richToLines(raw);
      expect(lines.length, 2);
      expect(lines.every((l) => l.kind == RichLineKind.uncheckedItem), isTrue);
      final toggled = toggleChecklistLine(raw, 0);
      final after = richToLines(toggled);
      expect(after[0].kind, RichLineKind.checkedItem);
      expect(after[1].kind, RichLineKind.uncheckedItem);
    });
  });
}
