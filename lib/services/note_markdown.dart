import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../models/note.dart';
import '../models/note_block.dart';
import '../models/tweet_card.dart';

/// Converts notes to and from Markdown, for sharing a note as a `.md` file and
/// for saving a shared `.md`/`.txt` file back as a note. Text-only: image blocks
/// are marked with a placeholder rather than embedded.

// ---- Note / Spark -> Markdown -----------------------------------------------

String noteToMarkdown(Note note) =>
    _compose(note.title, null, note.blocks);

/// A note's text as Markdown, without its title.
String noteBodyToMarkdown(Note note) {
  if (!note.markdown) return _compose('', null, note.blocks).trim();
  // A Markdown note's own leading `# Title` repeats the title; drop it.
  final lines = note.markdownSource.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  if (start < lines.length && RegExp(r'^#\s+').hasMatch(lines[start].trim())) {
    start++;
  }
  return lines.sublist(start).join('\n').trim();
}

/// A circuit — or one branch and everything under it — as one Markdown
/// document: [from] as H1, each note below it as a heading by its depth
/// (bullets once past H6), each note's text under its heading. Placeholders
/// are skipped, their children taking their level. [childrenOf] lists a
/// note's branches in order.
String circuitOutline(
  Note from,
  List<Note> Function(String id) childrenOf, {
  required String untitledCircuit,
  required String untitledNote,
}) {
  final buf = StringBuffer();
  void visit(Note n, int depth) {
    if (n.circuitPlaceholder) {
      for (final c in childrenOf(n.id)) {
        visit(c, depth);
      }
      return;
    }
    final title = n.title.trim().isEmpty
        ? (n.isCircuitRoot ? untitledCircuit : untitledNote)
        : n.title.trim();
    if (depth <= 5) {
      buf.writeln('${'#' * (depth + 1)} $title');
    } else {
      buf.writeln('${'  ' * (depth - 6)}- $title');
    }
    final body = noteBodyToMarkdown(n);
    if (body.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(body);
    }
    buf.writeln();
    for (final c in childrenOf(n.id)) {
      visit(c, depth + 1);
    }
  }

  visit(from, 0);
  return buf.toString().trim();
}

String cardToMarkdown(TweetCard card) => _compose(
      card.noteTitle.trim().isNotEmpty ? card.noteTitle : card.url,
      card.url,
      card.blocks,
    );

String _compose(String title, String? url, List<NoteBlock> blocks) {
  final buf = StringBuffer();
  final t = title.trim();
  if (t.isNotEmpty) {
    buf
      ..writeln('# $t')
      ..writeln();
  }
  if (url != null && url.trim().isNotEmpty) {
    buf
      ..writeln('<${url.trim()}>')
      ..writeln();
  }
  for (final block in blocks) {
    if (block.isImage) {
      buf
        ..writeln('_[image]_')
        ..writeln();
      continue;
    }
    if (!block.isText) continue;
    final lines = richToStyledLines(block.text);
    if (lines.isEmpty) continue;
    for (final line in lines) {
      buf.writeln(_lineToMarkdown(line));
    }
    buf.writeln();
  }
  return '${buf.toString().trimRight()}\n';
}

String _lineToMarkdown(RichLine line) {
  final text = _runsToMarkdown(line.runs, line.text);
  if (line.header == 1) return '# $text';
  if (line.header == 2) return '## $text';
  if (line.quote) return '> $text';
  switch (line.kind) {
    case RichLineKind.checkedItem:
      return '- [x] $text';
    case RichLineKind.uncheckedItem:
      return '- [ ] $text';
    case RichLineKind.bullet:
      return '- $text';
    case RichLineKind.ordered:
      return '1. $text';
    case RichLineKind.plain:
      return text;
  }
}

String _runsToMarkdown(List<RichRun> runs, String fallback) {
  if (runs.isEmpty) return fallback;
  final buf = StringBuffer();
  for (final r in runs) {
    var t = r.text;
    if (t.isEmpty) continue;
    // Preserve leading/trailing spaces around the emphasis markers.
    final lead = t.substring(0, t.length - t.trimLeft().length);
    final trail = t.substring(t.trimRight().length);
    var core = t.trim();
    if (core.isNotEmpty) {
      if (r.strike) core = '~~$core~~';
      if (r.bold) core = '**$core**';
      if (r.italic) core = '*$core*';
      if (r.link != null && r.link!.trim().isNotEmpty) {
        core = '[$core](${r.link!.trim()})';
      }
    }
    buf.write('$lead$core$trail');
  }
  return buf.toString();
}

// ---- Markdown -> Note -------------------------------------------------------

/// The first `# heading` becomes the note title (best-effort).
String markdownTitle(String md) {
  // Lazily: the title leads, so a long document is never split whole.
  for (final raw in LineSplitter.split(md)) {
    final line = raw.trimRight();
    final m = RegExp(r'^#\s+(.*)$').firstMatch(line);
    if (m != null) return m.group(1)!.trim();
    if (line.trim().isNotEmpty) break; // title must lead
  }
  return '';
}

/// Builds a note body block (a Quill Delta JSON string) from [md], skipping the
/// leading title line if [skipTitle] matched it. Handles headings, checkboxes,
/// bullets, numbered items, quotes, and inline bold/italic/strikethrough/links.
String markdownToDeltaJson(String md, {String? skipTitle}) {
  final ops = <Map<String, Object?>>[];
  final lines = const LineSplitter().convert(md);
  var skippedTitle = false;
  for (final raw in lines) {
    var line = raw;
    // Drop the one title line we lifted into the note title.
    if (!skippedTitle && skipTitle != null && skipTitle.isNotEmpty) {
      final m = RegExp(r'^#\s+(.*)$').firstMatch(line.trim());
      if (m != null && m.group(1)!.trim() == skipTitle) {
        skippedTitle = true;
        continue;
      }
    }

    Map<String, Object?>? lineAttr;
    // Block-level prefixes.
    final h1 = RegExp(r'^#\s+(.*)$').firstMatch(line);
    final h2 = RegExp(r'^##\s+(.*)$').firstMatch(line);
    final checked = RegExp(r'^\s*[-*]\s+\[[xX]\]\s+(.*)$').firstMatch(line);
    final unchecked = RegExp(r'^\s*[-*]\s+\[ \]\s+(.*)$').firstMatch(line);
    final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
    final ordered = RegExp(r'^\s*\d+\.\s+(.*)$').firstMatch(line);
    final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);

    if (h2 != null) {
      line = h2.group(1)!;
      lineAttr = {'header': 2};
    } else if (h1 != null) {
      line = h1.group(1)!;
      lineAttr = {'header': 1};
    } else if (checked != null) {
      line = checked.group(1)!;
      lineAttr = {'list': 'checked'};
    } else if (unchecked != null) {
      line = unchecked.group(1)!;
      lineAttr = {'list': 'unchecked'};
    } else if (ordered != null) {
      line = ordered.group(1)!;
      lineAttr = {'list': 'ordered'};
    } else if (bullet != null) {
      line = bullet.group(1)!;
      lineAttr = {'list': 'bullet'};
    } else if (quote != null) {
      line = quote.group(1)!;
      lineAttr = {'blockquote': true};
    }

    for (final run in _inlineRuns(line)) {
      ops.add(run);
    }
    ops.add(lineAttr == null
        ? {'insert': '\n'}
        : {'insert': '\n', 'attributes': lineAttr});
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return jsonEncode(ops);
}

/// Splits one line's inline Markdown (`**bold**`, `*italic*`, `~~strike~~`,
/// `[text](url)`) into Quill insert ops.
List<Map<String, Object?>> _inlineRuns(String line) {
  final out = <Map<String, Object?>>[];
  // Ordered so ** is tried before *.
  final pattern = RegExp(
      r'(\*\*(?<b>.+?)\*\*)|(\*(?<i>.+?)\*)|(~~(?<s>.+?)~~)|(\[(?<lt>[^\]]+)\]\((?<lu>[^)]+)\))');
  var idx = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > idx) {
      out.add({'insert': line.substring(idx, m.start)});
    }
    if (m.namedGroup('b') != null) {
      out.add({'insert': m.namedGroup('b'), 'attributes': {'bold': true}});
    } else if (m.namedGroup('i') != null) {
      out.add({'insert': m.namedGroup('i'), 'attributes': {'italic': true}});
    } else if (m.namedGroup('s') != null) {
      out.add({'insert': m.namedGroup('s'), 'attributes': {'strike': true}});
    } else if (m.namedGroup('lt') != null) {
      out.add({
        'insert': m.namedGroup('lt'),
        'attributes': {'link': m.namedGroup('lu')}
      });
    }
    idx = m.end;
  }
  if (idx < line.length) out.add({'insert': line.substring(idx)});
  if (out.isEmpty) out.add({'insert': ''});
  return out;
}

/// Flattens one line's inline Markdown to plain text (drops `**`/`*`/`~~`,
/// unwraps `[text](url)` to `text`). Used for the note title, which is a plain
/// string and can't carry formatting.
String _stripInline(String line) =>
    _inlineRuns(line).map((op) => (op['insert'] as String?) ?? '').join();

/// A short, symbol-free plain preview of raw markdown for the feed card —
/// strips block prefixes (#, >, -, 1., - [ ]) and inline markers, skips the
/// leading title heading, and collapses blank lines.
String markdownPlainPreview(String md, {String? skipTitle}) {
  final out = <String>[];
  var skipped = false;
  // Lazily: it stops after a few lines, and a feed tile asks on every
  // rebuild, so a long document must not be split whole each time.
  for (final raw in LineSplitter.split(md)) {
    var line = raw.trim();
    if (!skipped && skipTitle != null && skipTitle.isNotEmpty) {
      final m = RegExp(r'^#\s+(.*)$').firstMatch(line);
      if (m != null && m.group(1)!.trim() == skipTitle) {
        skipped = true;
        continue;
      }
    }
    if (line.isEmpty) continue;
    // Fenced code / thematic breaks add no preview value.
    if (RegExp(r'^(```|~~~|---+|\*\*\*+|===+)$').hasMatch(line)) continue;
    line = line
        .replaceAll(RegExp(r'^#{1,6}\s+'), '')
        .replaceAll(RegExp(r'^>\s?'), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+\[[ xX]\]\s+'), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+'), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+'), '');
    line = _stripInline(line).replaceAll(RegExp(r'`'), '').trim();
    if (line.isNotEmpty) out.add(line);
    if (out.length >= 8) break;
  }
  return out.join('\n');
}

/// A whole note reconstructed from a shared `.md`/`.txt` file. A [title]
/// given with the share wins over the text's own leading heading, which then
/// stays in the body.
Note noteFromMarkdown(String md, {String? spaceId, String? title}) {
  if (title != null && title.trim().isNotEmpty) {
    return Note(
      title: title.trim(),
      blocks: [
        NoteBlock(type: NoteBlockType.text, text: markdownToDeltaJson(md)),
      ],
      spaceId: spaceId,
    );
  }
  // The raw heading text matches the body line we skip; the stored title is
  // flattened so markers like ** never show up in it.
  final rawTitle = markdownTitle(md);
  final delta = markdownToDeltaJson(md, skipTitle: rawTitle);
  return Note(
    title: _stripInline(rawTitle),
    blocks: [NoteBlock(type: NoteBlockType.text, text: delta)],
    spaceId: spaceId,
  );
}

// ---- Markdown -> plain text --------------------------------------------------

/// A note's Markdown as plain text, for sharing into apps that take text:
/// no `#` or `**` symbols, list items as "• " or "1. ", task items as "☐ " or
/// "☑ ", a link as "text (address)", blocks separated by blank lines.
String markdownToPlainText(String source) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(source);

  String inline(List<md.Node>? nodes) {
    final out = StringBuffer();
    for (final node in nodes ?? const <md.Node>[]) {
      if (node is md.Text) {
        // A soft line break inside a paragraph reads as a space.
        out.write(node.text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' '));
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'br':
            out.write('\n');
          case 'img':
            out.write('[image]');
          case 'input':
            out.write(node.attributes.containsKey('checked') ? '☑ ' : '☐ ');
          case 'a':
            final text = inline(node.children);
            final href = node.attributes['href'] ?? '';
            out.write(href.isEmpty || href == text || href == 'mailto:$text'
                ? text
                : '$text ($href)');
          default:
            out.write(inline(node.children));
        }
      }
    }
    return out.toString();
  }

  List<String> list(md.Element el, String indent) {
    final lines = <String>[];
    var number = int.tryParse(el.attributes['start'] ?? '') ?? 1;
    for (final item in el.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      final text = StringBuffer();
      final nested = <String>[];
      for (final child in item.children ?? const <md.Node>[]) {
        if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
          nested.addAll(list(child, '$indent  '));
        } else if (child is md.Element && child.tag == 'p') {
          if (text.isNotEmpty) text.write(' ');
          text.write(inline(child.children));
        } else {
          text.write(inline([child]));
        }
      }
      final line = text.toString().trim();
      // A task item already starts with its box.
      final task = line.startsWith('☐ ') || line.startsWith('☑ ');
      final marker = task ? '' : (el.tag == 'ol' ? '${number++}. ' : '• ');
      lines
        ..add('$indent$marker$line')
        ..addAll(nested);
    }
    return lines;
  }

  final blocks = <String>[];
  void block(md.Node node) {
    if (node is md.Text) {
      blocks.add(node.text.trim());
      return;
    }
    if (node is! md.Element) return;
    switch (node.tag) {
      case 'ul':
      case 'ol':
        blocks.add(list(node, '').join('\n'));
      case 'pre':
        blocks.add(node.textContent.replaceAll(RegExp(r'\n$'), ''));
      case 'hr':
        blocks.add('———');
      case 'table':
        final rows = <String>[];
        void collect(md.Element el) {
          for (final child in el.children ?? const <md.Node>[]) {
            if (child is! md.Element) continue;
            if (child.tag == 'tr') {
              rows.add([
                for (final cell in child.children ?? const <md.Node>[])
                  if (cell is md.Element) inline(cell.children).trim()
              ].join(' | '));
            } else {
              collect(child);
            }
          }
        }
        collect(node);
        blocks.add(rows.join('\n'));
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
      case 'p':
        blocks.add(inline(node.children).trim());
      default:
        // A quote and anything else: its blocks, in order.
        for (final child in node.children ?? const <md.Node>[]) {
          block(child);
        }
    }
  }

  for (final node in nodes) {
    block(node);
  }
  return blocks.where((b) => b.isNotEmpty).join('\n\n');
}
