// Wiki-style links: `[[Title]]` inside an item's text points at another item
// (a note, a journal entry or a card) by its title. This is the parsing half —
// resolution and backlinks live on AppState, which owns the lists.

/// What a resolved `[[link]]` points at.
enum LinkKind { note, card }

/// A resolved reference to a linkable item — enough to render a chip/tile and
/// navigate, without leaking the underlying model.
class LinkRef {
  const LinkRef({
    required this.id,
    required this.kind,
    required this.title,
    required this.preview,
  });

  final String id;
  final LinkKind kind;
  final String title;
  final String preview;
}

/// Matches a `[[target]]` reference. The target may not itself contain
/// brackets, so nested/broken pairs don't swallow half the note.
final RegExp wikiLinkPattern = RegExp(r'\[\[([^\[\]]+)\]\]');

/// The distinct note-link target titles referenced as `[[...]]` in [text],
/// trimmed and de-duplicated case-insensitively (first spelling wins).
/// `[[@Name]]` impulse/thread mentions are skipped — they aren't part of the
/// note graph.
List<String> parseWikiLinkTitles(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in wikiLinkPattern.allMatches(text)) {
    final title = m.group(1)!.trim();
    if (title.isEmpty || title.startsWith('@')) continue;
    if (seen.add(title.toLowerCase())) out.add(title);
  }
  return out;
}

/// A run of text produced by splitting on `[[...]]` markers, tagged so a widget
/// can paint the link runs differently and make them tappable.
class WikiSpan {
  const WikiSpan(this.text, {this.linkTitle, this.isMention = false});

  /// The visible text (for a link, the title without the brackets; for a
  /// mention, the bare name — the `@` and brackets are dropped, colour marks it).
  final String text;

  /// Non-null when this run is a `[[link]]`; carries the target title. For a
  /// mention this is the name *without* the leading `@` (the resolve key).
  final String? linkTitle;

  /// Whether this link is an `[[@Name]]` impulse/thread mention rather than a
  /// note wiki-link.
  final bool isMention;

  bool get isLink => linkTitle != null;
}

/// Splits [text] into ordered runs, turning each `[[target]]` into a link run
/// (with the brackets stripped) and leaving everything else as plain runs.
/// A `[[@Name]]` target is flagged as a mention and shown as `@Name`.
List<WikiSpan> splitWikiSpans(String text) {
  final spans = <WikiSpan>[];
  var cursor = 0;
  for (final m in wikiLinkPattern.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(WikiSpan(text.substring(cursor, m.start)));
    }
    final title = m.group(1)!.trim();
    if (title.isEmpty) {
      spans.add(WikiSpan(m.group(0)!));
    } else if (title.startsWith('@')) {
      final name = title.substring(1).trim();
      spans.add(name.isEmpty
          ? WikiSpan(m.group(0)!)
          : WikiSpan(name, linkTitle: name, isMention: true));
    } else {
      spans.add(WikiSpan(title, linkTitle: title));
    }
    cursor = m.end;
  }
  if (cursor < text.length) spans.add(WikiSpan(text.substring(cursor)));
  return spans;
}
