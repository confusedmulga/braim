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
/// leading title line if [skipTitle] matched it.
///
/// Markdown as people and AI chats write it, mapped onto what a note can show:
/// headings (`#` a heading; `##`/`###` a sub-heading; deeper, a bold line),
/// bullets (`-`, `*`, `+`), numbered items, checkboxes and quotes, nested by
/// indentation; inline bold, italic, strikethrough and links. A note has no
/// code style, so code keeps its text without the backticks (and a fenced
/// block isn't read as Markdown at all); rules (`---`) are dropped, and a
/// table becomes one line per row, its header row bold.
String markdownToDeltaJson(String md, {String? skipTitle}) {
  final ops = <Map<String, Object?>>[];
  final lines = const LineSplitter().convert(md);
  var skippedTitle = false;
  String? fence; // the open code fence's marker, inside a fenced block
  final indents = <int>[]; // the list's indentation widths, outermost first
  var blankPending = false;

  void emit(List<Map<String, Object?>> runs, Map<String, Object?>? attrs) {
    if (blankPending && ops.isNotEmpty) ops.add({'insert': '\n'});
    blankPending = false;
    ops.addAll(runs);
    ops.add(attrs == null
        ? {'insert': '\n'}
        : {'insert': '\n', 'attributes': attrs});
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    // Drop the one title line we lifted into the note title.
    if (!skippedTitle && skipTitle != null && skipTitle.isNotEmpty) {
      final m = RegExp(r'^#\s+(.*)$').firstMatch(line.trim());
      if (m != null && m.group(1)!.trim() == skipTitle) {
        skippedTitle = true;
        continue;
      }
    }

    // Fenced code: its lines go in as they are, Markdown and all.
    final fenceMark = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (fence != null) {
      if (fenceMark != null && fenceMark.group(1)!.startsWith(fence)) {
        fence = null;
      } else {
        emit([{'insert': line}], null);
      }
      continue;
    }
    if (fenceMark != null) {
      fence = fenceMark.group(1)!.substring(0, 3);
      indents.clear();
      continue;
    }

    if (line.trim().isEmpty) {
      // A blank line between two items of one list (a "loose" list) isn't
      // a break in it; any other run of blank lines is one empty line.
      final next = lines.skip(i + 1).firstWhere((l) => l.trim().isNotEmpty,
          orElse: () => '');
      if (indents.isEmpty || !_isListItem(next)) {
        blankPending = true;
        indents.clear();
      }
      continue;
    }

    // A rule: nothing to show but the gap.
    if (RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      blankPending = true;
      indents.clear();
      continue;
    }

    // A table: one line per row, cells joined; the separator row goes.
    if (RegExp(r'^\s*\|.*\|\s*$').hasMatch(line)) {
      if (RegExp(r'^\s*\|[\s:|-]+\|\s*$').hasMatch(line)) continue;
      final cells = line.trim().substring(1, line.trim().length - 1)
          .split('|')
          .map((c) => c.trim())
          .toList();
      final isHeader = i + 1 < lines.length &&
          RegExp(r'^\s*\|[\s:|-]+\|\s*$').hasMatch(lines[i + 1]);
      emit(
          _inlineRuns(
              cells.join('  ·  '), isHeader ? {'bold': true} : const {}),
          null);
      continue;
    }

    Map<String, Object?>? lineAttr;
    final heading =
        RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$').firstMatch(line);
    final item = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    final quote = RegExp(r'^\s{0,3}>\s?(.*)$').firstMatch(line);
    var runAttrs = const <String, Object?>{};

    if (heading != null) {
      indents.clear();
      final level = heading.group(1)!.length;
      line = heading.group(2)!;
      if (level == 1) {
        lineAttr = {'header': 1};
      } else if (level <= 3) {
        lineAttr = {'header': 2};
      } else {
        runAttrs = const {'bold': true};
      }
    } else if (item != null) {
      final width = item.group(1)!.replaceAll('\t', '    ').length;
      // Nesting follows the indentation, however many spaces a level is.
      while (indents.isNotEmpty && width < indents.last) {
        indents.removeLast();
      }
      if (indents.isEmpty || width > indents.last) indents.add(width);
      final depth = (indents.length - 1).clamp(0, 4);
      final marker = item.group(2)!;
      var rest = item.group(3)!;
      final box = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(rest);
      String kind;
      if (box != null && !RegExp(r'\d').hasMatch(marker)) {
        kind = box.group(1) == ' ' ? 'unchecked' : 'checked';
        rest = box.group(2)!;
      } else {
        kind = RegExp(r'\d').hasMatch(marker) ? 'ordered' : 'bullet';
      }
      line = rest;
      lineAttr = {'list': kind, if (depth > 0) 'indent': depth};
    } else if (quote != null) {
      indents.clear();
      line = quote.group(1)!.replaceFirst(RegExp(r'^(>\s?)+'), '');
      lineAttr = {'blockquote': true};
    } else {
      indents.clear();
    }

    emit(_inlineRuns(line.trim(), runAttrs), lineAttr);
  }
  if (ops.isEmpty) ops.add({'insert': '\n'});
  return jsonEncode(ops);
}

bool _isListItem(String line) =>
    RegExp(r'^\s*([-*+]|\d+[.)])\s+\S').hasMatch(line);

/// Whether pasted [text] is Markdown (as an AI chat's Copy button gives it)
/// rather than plain words: a heading, a list, a quote or a fence, or bold,
/// strikethrough, code or a link written out in Markdown.
bool looksLikeMarkdown(String text) {
  if (text.trim().isEmpty) return false;
  final block = RegExp(
      r'^\s{0,3}(#{1,6}\s+\S|[-*+]\s+\S|\d+[.)]\s+\S|>\s?\S|```|~~~)',
      multiLine: true);
  final inline = RegExp(r'\*\*[^*\n]+\*\*|__[^_\n]+__|~~[^~\n]+~~|'
      r'`[^`\n]+`|\[[^\]\n]+\]\([^)\s]+\)');
  return block.hasMatch(text) || inline.hasMatch(text);
}

/// Splits one line's inline Markdown into Quill insert ops carrying [attrs]
/// plus their own: `***both***`, `**bold**`/`__bold__`, `*italic*`,
/// `~~strike~~`, `[text](url)` and `<url>` links. Code spans keep their text
/// (a note has no code style) and nothing inside them is read; `\*` and its
/// like are the character itself.
List<Map<String, Object?>> _inlineRuns(String line,
    [Map<String, Object?> attrs = const {}]) {
  final out = <Map<String, Object?>>[];
  void text(String s) {
    if (s.isEmpty) return;
    out.add(attrs.isEmpty ? {'insert': s} : {'insert': s, 'attributes': attrs});
  }

  final pattern = RegExp(r'(\\(?<esc>[\\`*_{}\[\]()#+\-.!~>|]))'
      r'|(`(?<code>[^`]+)`)'
      r'|(\*\*\*(?<bi>\S(?:.*?\S)?)\*\*\*)'
      r'|(\*\*(?<b>\S(?:.*?\S)?)\*\*)'
      r'|(__(?<b2>\S(?:.*?\S)?)__)'
      r'|(\*(?<i>[^\s*](?:[^*]*?[^\s*])?)\*)'
      r'|(~~(?<s>\S(?:.*?\S)?)~~)'
      r'|(\[(?<lt>[^\]]+)\]\((?<lu>[^)\s]+)(?:\s+"[^"]*")?\))'
      r'|(<(?<au>https?://[^>\s]+)>)');
  var idx = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > idx) text(line.substring(idx, m.start));
    String? g(String name) => m.namedGroup(name);
    if (g('esc') != null) {
      text(g('esc')!);
    } else if (g('code') != null) {
      text(g('code')!);
    } else if (g('bi') != null) {
      out.addAll(
          _inlineRuns(g('bi')!, {...attrs, 'bold': true, 'italic': true}));
    } else if ((g('b') ?? g('b2')) != null) {
      out.addAll(_inlineRuns((g('b') ?? g('b2'))!, {...attrs, 'bold': true}));
    } else if (g('i') != null) {
      out.addAll(_inlineRuns(g('i')!, {...attrs, 'italic': true}));
    } else if (g('s') != null) {
      out.addAll(_inlineRuns(g('s')!, {...attrs, 'strike': true}));
    } else if (g('lt') != null) {
      out.addAll(_inlineRuns(g('lt')!, {...attrs, 'link': g('lu')}));
    } else if (g('au') != null) {
      out.add({'insert': g('au'), 'attributes': {...attrs, 'link': g('au')}});
    }
    idx = m.end;
  }
  if (idx < line.length) text(line.substring(idx));
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
