/// What a share from another app holds, judged from its text: a link (saved
/// as a spark) or a note.
///
/// Apps share an article as its link, often with the headline beside it
/// ("Headline\nhttps://…", "Headline - Site https://…"). That is still a
/// link: it becomes a spark, and the headline is offered as its title. Text
/// that only mentions a link — longer writing, or several links — stays a
/// note.
class SharedText {
  const SharedText._({this.url, required this.caption});

  /// The link, when the share is one.
  final String? url;

  /// For a link, the words that came with it (often the headline), or empty.
  /// For a note, the whole text.
  final String caption;

  bool get isLink => url != null;

  /// Captions longer than this, or spread over more lines, are writing in
  /// their own right: the share is a note.
  static const maxCaptionChars = 280;
  static const maxCaptionLines = 4;

  static final _url = RegExp(r'https?://\S+');

  /// Punctuation a link is often written up against ("(see https://x.y).").
  static final _trailing = RegExp(r'''[)\].,;:!?'"]+$''');

  /// Separators left at either end once the link is lifted out (and an
  /// opening bracket the link was written inside).
  static final _edges = RegExp(r'^[\s\-–—|:•·]+|[\s\-–—|:•·(\[]+$');

  factory SharedText.parse(String raw) {
    final text = raw.trim();
    final links = _url.allMatches(text).toList();
    if (links.length != 1) return SharedText._(caption: text);

    final link = links.single;
    var url = link.group(0)!;
    final cut = _trailing.firstMatch(url);
    if (cut != null) url = url.substring(0, cut.start);

    final rest = '${text.substring(0, link.start)}\n${text.substring(link.end)}'
        .split('\n')
        .map((line) => line.replaceAll(_edges, '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final caption = rest.join('\n');
    if (caption.length > maxCaptionChars || rest.length > maxCaptionLines) {
      return SharedText._(caption: text);
    }
    return SharedText._(url: url, caption: caption);
  }
}
