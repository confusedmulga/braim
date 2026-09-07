import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'annotation.dart';
import 'book.dart';
import 'note_block.dart';

const _uuid = Uuid();

/// Text blocks may store either plain text (legacy) or a Quill Delta JSON
/// string. This converts either form to plain text for previews.
String richToPlain(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (final op in decoded) {
          if (op is Map && op['insert'] is String) {
            buffer.write(op['insert']);
          }
        }
        return buffer.toString().trim();
      }
    } catch (_) {
      // Fall through and treat as plain text.
    }
  }
  return trimmed;
}

/// The block-level kind of a single rendered line, recovered from a Quill
/// Delta. [richToPlain] flattens these away; [richToLines] keeps them so a
/// read-only view can still draw checkboxes and list bullets.
enum RichLineKind { plain, checkedItem, uncheckedItem, bullet, ordered }

class RichLine {
  const RichLine(
    this.text,
    this.kind, {
    this.runs = const [],
    this.header = 0,
    this.quote = false,
    this.indent = 0,
    this.align,
  });
  final String text;
  final RichLineKind kind;

  /// The inline runs (styled fragments) making up this line. Empty for the
  /// plain-only [richToLines] output; filled by [richToStyledLines] so a
  /// read-only view can reproduce bold/italic/etc.
  final List<RichRun> runs;

  /// Heading level: 0 = body, 1 = H1, 2 = H2.
  final int header;

  /// A block quote line (indented, italic, with a left rule).
  final bool quote;

  /// Indent depth, 0–3.
  final int indent;

  /// Paragraph alignment: 'center' | 'right' | 'justify', or null for the
  /// default left flow.
  final String? align;

  bool get isCheckItem =>
      kind == RichLineKind.checkedItem || kind == RichLineKind.uncheckedItem;
}

/// One inline fragment of a [RichLine], carrying the inline marks Quill stores
/// (bold, italic, …). [richToStyledLines] fills these so a saved note renders
/// with the same formatting the editor showed.
class RichRun {
  const RichRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.highlight = false,
    this.link,
  });
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool highlight;

  /// An inline hyperlink URL (Quill's `link` attribute), if any.
  final String? link;
}

RichLineKind _kindFromListValue(Object? v) {
  switch (v) {
    case 'checked':
      return RichLineKind.checkedItem;
    case 'unchecked':
      return RichLineKind.uncheckedItem;
    case 'bullet':
      return RichLineKind.bullet;
    case 'ordered':
      return RichLineKind.ordered;
    default:
      return RichLineKind.plain;
  }
}

/// Splits a text block (plain string or Quill Delta JSON) into display lines,
/// preserving each line's checkbox/list marker. Inline formatting (bold,
/// italic, links) is dropped — only block-level structure is recovered, which
/// is what a read-only view needs to render checklists that would otherwise
/// vanish when the note is saved and re-opened.
List<RichLine> richToLines(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final lines = <RichLine>[];
        final cur = StringBuffer();
        for (final op in decoded) {
          if (op is! Map || op['insert'] is! String) continue;
          final s = op['insert'] as String;
          final attrs = op['attributes'];
          // A Quill line's block attribute (list/checkbox) lives on the op
          // carrying the newline that ends the line.
          final listVal = attrs is Map ? attrs['list'] : null;
          final segments = s.split('\n');
          for (var i = 0; i < segments.length; i++) {
            cur.write(segments[i]);
            if (i < segments.length - 1) {
              lines.add(RichLine(cur.toString(), _kindFromListValue(listVal)));
              cur.clear();
            }
          }
        }
        if (cur.toString().isNotEmpty) {
          lines.add(RichLine(cur.toString(), RichLineKind.plain));
        }
        // Quill documents always end in a newline, which finalises a trailing
        // empty paragraph — drop it so the read view doesn't gain a blank line.
        if (lines.isNotEmpty &&
            lines.last.kind == RichLineKind.plain &&
            lines.last.text.isEmpty) {
          lines.removeLast();
        }
        return lines;
      }
    } catch (_) {
      // Fall through and treat the whole thing as plain text.
    }
  }
  return [
    for (final l in trimmed.split('\n')) RichLine(l, RichLineKind.plain),
  ];
}

RichRun _runFromAttrs(Map a, String text) => RichRun(
      text,
      bold: a['bold'] == true,
      italic: a['italic'] == true,
      underline: a['underline'] == true,
      strike: a['strike'] == true,
      highlight: a['background'] != null,
      link: a['link'] is String ? a['link'] as String : null,
    );

/// Splits a text block (plain string or Quill Delta JSON) into styled display
/// lines. Unlike [richToLines], this keeps each line's inline runs (bold,
/// italic, underline, strikethrough, highlight, links) and its block-level
/// formatting (heading, quote, indent, alignment) so a read-only view can
/// reproduce exactly what the editor showed. The line order/count matches
/// [richToLines] so checkbox [lineIndex]es stay in sync.
List<RichLine> richToStyledLines(String raw) {
  final trimmed = raw.trim();
  List<RichLine> plainFallback() => [
        for (final l in trimmed.split('\n'))
          RichLine(l, RichLineKind.plain, runs: [RichRun(l)]),
      ];
  if (trimmed.isEmpty) return const [];
  if (!trimmed.startsWith('[')) return plainFallback();
  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return plainFallback();
  }
  if (decoded is! List) return plainFallback();

  final lines = <RichLine>[];
  var runs = <RichRun>[];
  for (final op in decoded) {
    if (op is! Map || op['insert'] is! String) continue;
    final s = op['insert'] as String;
    final a = op['attributes'] is Map ? op['attributes'] as Map : const {};
    // Inline marks ride on the text op; block marks ride on the op carrying
    // the newline that ends the line.
    final kind = _kindFromListValue(a['list']);
    final header = a['header'] is num ? (a['header'] as num).toInt() : 0;
    final quote = a['blockquote'] == true;
    var indent = a['indent'] is num ? (a['indent'] as num).toInt() : 0;
    indent = indent < 0 ? 0 : (indent > 3 ? 3 : indent);
    final align = a['align'] is String ? a['align'] as String : null;
    final parts = s.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) runs.add(_runFromAttrs(a, parts[i]));
      if (i < parts.length - 1) {
        lines.add(RichLine(
          runs.map((r) => r.text).join(),
          kind,
          runs: List.of(runs),
          header: header,
          quote: quote,
          indent: indent,
          align: align,
        ));
        runs = <RichRun>[];
      }
    }
  }
  if (runs.isNotEmpty) {
    lines.add(RichLine(runs.map((r) => r.text).join(), RichLineKind.plain,
        runs: List.of(runs)));
  }
  // Drop the trailing empty paragraph Quill always terminates on (mirrors
  // richToLines so line indexes line up).
  if (lines.isNotEmpty &&
      lines.last.kind == RichLineKind.plain &&
      lines.last.text.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Flips the checkbox state of the [lineIndex]-th line of a Quill Delta text
/// block, where [lineIndex] matches the enumeration produced by [richToLines].
/// Returns the block's new text, or the original unchanged when the line isn't
/// a checkbox (or the block isn't a delta). Used to tick items straight from
/// the read view without entering the full editor.
String toggleChecklistLine(String raw, int lineIndex) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('[')) return raw;
  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return raw;
  }
  if (decoded is! List) return raw;

  // Denormalise so every newline is its own op; then the L-th newline op is
  // exactly the terminator of the L-th line (matching richToLines' order),
  // and we can flip just that one line without disturbing the rest.
  final ops = <Map<String, dynamic>>[];
  for (final op in decoded) {
    if (op is! Map) continue;
    if (op['insert'] is! String) {
      ops.add(Map<String, dynamic>.from(op));
      continue;
    }
    final s = op['insert'] as String;
    final attrs = op['attributes'];
    final segments = s.split('\n');
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].isNotEmpty) {
        ops.add({
          'insert': segments[i],
          if (attrs is Map) 'attributes': Map<String, dynamic>.from(attrs),
        });
      }
      if (i < segments.length - 1) {
        ops.add({
          'insert': '\n',
          if (attrs is Map) 'attributes': Map<String, dynamic>.from(attrs),
        });
      }
    }
  }

  var line = 0;
  for (final op in ops) {
    if (op['insert'] == '\n') {
      if (line == lineIndex) {
        final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final v = attrs['list'];
        if (v == 'checked') {
          attrs['list'] = 'unchecked';
        } else if (v == 'unchecked') {
          attrs['list'] = 'checked';
        } else {
          return raw; // Not a checkbox line — leave it alone.
        }
        op['attributes'] = attrs;
        return jsonEncode(ops);
      }
      line++;
    }
  }
  return raw;
}

class Note {
  Note({
    String? id,
    this.title = '',
    List<NoteBlock>? blocks,
    this.spaceId,
    this.backgroundAsset,
    this.colorValue,
    this.journalDate,
    this.bookId,
    this.bookPageKind = '',
    this.bookOrder = 0,
    this.bookStatus = '',
    this.targetWords = 0,
    this.linkedPageId,
    List<String>? tags,
    this.reminderAt,
    List<Annotation>? annotations,
    List<NoteSnapshot>? history,
    this.fontScale = 1.0,
    this.checkedToBottom = false,
    this.markdown = false,
    this.archived = false,
    this.pinned = false,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        blocks = blocks ?? [],
        tags = tags ?? [],
        annotations = annotations ?? [],
        history = history ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  List<NoteBlock> blocks;

  /// Id of the space (folder) this note belongs to, or null for the inbox.
  String? spaceId;

  /// Optional per-note background image asset (one of the BACK## assets).
  String? backgroundAsset;

  /// Optional Keep-style colour tag (ARGB int of the light swatch); null =
  /// default surface.
  int? colorValue;

  /// The journal day this note belongs to as 'yyyy-MM-dd', or null for a
  /// regular note. Journal entries never appear in the Home feed or search.
  String? journalDate;

  /// When set, this note is a page of that book rather than a feed note;
  /// [bookPageKind] is one of [BookPageKind] and [bookOrder] fixes its
  /// place in the book. Book pages never show in Home, search or journal.
  String? bookId;
  String bookPageKind;
  int bookOrder;

  /// A chapter's word goal (0 = none). Drives the progress bar on the page.
  int targetWords;

  /// For a workshop note: the id of the manuscript page it's tied to (a
  /// character sheet linked to the chapter they appear in), or null. Purely an
  /// authoring aid — linked notes never appear in the reader or an export.
  String? linkedPageId;

  /// Free-form tags (without the leading '#'), a lightweight cross-cutting
  /// alternative to folders. A note can carry several.
  List<String> tags;

  /// When set, a local notification fires at this time — turns the note into
  /// a lightweight reminder/task.
  DateTime? reminderAt;

  /// Highlights and margin notes made while reading this page.
  List<Annotation> annotations;

  /// Saved version snapshots (book chapters): point-in-time copies of the
  /// title + body so a heavy revise stays reversible. Oldest first.
  List<NoteSnapshot> history;

  /// Draft / revised / final, or empty for untagged (see [BookPageStatus]).
  String bookStatus;

  bool get isBookPage => bookId != null;

  /// A workshop note attached to a book (character/plot note) rather than a
  /// page of the manuscript.
  bool get isBookNote =>
      bookId != null && bookPageKind == BookPageKind.note;

  /// A page that forms part of the manuscript (Contents / Introduction /
  /// chapter) — everything a book holds except its workshop notes.
  bool get isManuscriptPage => bookId != null && !isBookNote;

  /// Words in the page body, for the per-chapter and whole-book counts.
  int get wordCount {
    final text = textPreview.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  int get charCount => textPreview.length;

  /// A per-note text-size multiplier applied to the whole body (0.8–1.6), so a
  /// single note can be set larger or smaller without changing the app default.
  double fontScale;

  /// When set, ticked checklist items sink to the bottom of their list in the
  /// saved read view, keeping the unfinished ones on top.
  bool checkedToBottom;

  /// A GitHub-flavored Markdown node: its single text block holds raw markdown
  /// (not a Quill Delta), edited as source and rendered with a GFM engine
  /// rather than the handwriting-style rich view. Regular notes leave this off.
  bool markdown;

  /// The raw markdown source of a [markdown] node (its first text block), or ''.
  String get markdownSource {
    for (final b in blocks) {
      if (b.isText) return b.text;
    }
    return '';
  }

  /// Archived notes are hidden from the feed and live in the Archive.
  bool archived;

  /// Pinned notes sort to the top of the feed (max 10).
  bool pinned;

  /// When set, the note is in Recently Deleted (kept ~30 days, then purged).
  DateTime? deletedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Path of the first image in the note, used as the feed thumbnail.
  String? get thumbnailPath {
    for (final b in blocks) {
      if (b.isImage && b.imagePath.isNotEmpty) return b.imagePath;
    }
    return null;
  }

  /// Concatenated plain text preview for the feed (and search): text blocks
  /// plus the titles of inline link cards.
  String get textPreview {
    final buffer = StringBuffer();
    for (final b in blocks) {
      if (b.isText) {
        final plain = richToPlain(b.text);
        if (plain.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(plain);
        }
      } else if (b.isLink) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(b.linkTitle.isNotEmpty ? b.linkTitle : b.url);
      }
    }
    return buffer.toString();
  }

  bool get isEmpty =>
      title.trim().isEmpty &&
      blocks.every((b) => b.isText && richToPlain(b.text).isEmpty);

  List<String> get imagePaths => blocks
      .where((b) => b.isImage && b.imagePath.isNotEmpty)
      .map((b) => b.imagePath)
      .toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'spaceId': spaceId,
        'backgroundAsset': backgroundAsset,
        'colorValue': colorValue,
        'journalDate': journalDate,
        if (bookId != null) 'bookId': bookId,
        if (bookPageKind.isNotEmpty) 'bookPageKind': bookPageKind,
        if (bookId != null) 'bookOrder': bookOrder,
        if (bookStatus.isNotEmpty) 'bookStatus': bookStatus,
        if (targetWords > 0) 'targetWords': targetWords,
        if (linkedPageId != null) 'linkedPageId': linkedPageId,
        if (tags.isNotEmpty) 'tags': tags,
        if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
        if (annotations.isNotEmpty)
          'annotations': annotations.map((a) => a.toJson()).toList(),
        if (history.isNotEmpty)
          'history': history.map((s) => s.toJson()).toList(),
        if (fontScale != 1.0) 'fontScale': fontScale,
        if (checkedToBottom) 'checkedToBottom': checkedToBottom,
        if (markdown) 'markdown': true,
        'archived': archived,
        'pinned': pinned,
        'deletedAt': deletedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        spaceId: json['spaceId'] as String?,
        backgroundAsset: json['backgroundAsset'] as String?,
        colorValue: json['colorValue'] as int?,
        journalDate: json['journalDate'] as String?,
        bookId: json['bookId'] as String?,
        bookPageKind: (json['bookPageKind'] as String?) ?? '',
        bookOrder: (json['bookOrder'] as num?)?.toInt() ?? 0,
        bookStatus: (json['bookStatus'] as String?) ?? '',
        targetWords: (json['targetWords'] as num?)?.toInt() ?? 0,
        linkedPageId: json['linkedPageId'] as String?,
        tags: ((json['tags'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
        annotations: ((json['annotations'] as List?) ?? [])
            .map((e) => Annotation.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: ((json['history'] as List?) ?? [])
            .map((e) => NoteSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        checkedToBottom: (json['checkedToBottom'] as bool?) ?? false,
        markdown: (json['markdown'] as bool?) ?? false,
        archived: (json['archived'] as bool?) ?? false,
        pinned: (json['pinned'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}

/// A point-in-time copy of a note's title and body — one entry in a chapter's
/// version history. Immutable once captured.
class NoteSnapshot {
  NoteSnapshot({
    String? id,
    DateTime? createdAt,
    this.title = '',
    List<NoteBlock>? blocks,
    this.auto = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        blocks = blocks ?? [];

  final String id;
  final DateTime createdAt;
  final String title;
  final List<NoteBlock> blocks;

  /// Captured automatically (on open/restore) rather than by an explicit save.
  final bool auto;

  int get wordCount {
    final text = textPreview.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  int get charCount => textPreview.length;

  String get textPreview {
    final buffer = StringBuffer();
    for (final b in blocks) {
      if (!b.isText) continue;
      final plain = richToPlain(b.text);
      if (plain.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(plain);
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        if (title.isNotEmpty) 'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (auto) 'auto': true,
      };

  factory NoteSnapshot.fromJson(Map<String, dynamic> json) => NoteSnapshot(
        id: json['id'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        title: (json['title'] as String?) ?? '',
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        auto: (json['auto'] as bool?) ?? false,
      );
}
