import 'dart:convert';

/// Pure text helpers behind the book-wide find & replace. A note's text block
/// may hold either plain text or a Quill Delta JSON string, so replacements
/// have to reach inside the delta's `insert` runs without disturbing the
/// formatting attributes around them.

/// Replaces every occurrence of [query] in [source] with [replacement],
/// returning the rewritten string and how many replacements were made.
(String, int) replaceCounted(
  String source,
  String query,
  String replacement, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return (source, 0);
  final hay = caseSensitive ? source : source.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final buffer = StringBuffer();
  var count = 0;
  var i = 0;
  while (true) {
    final idx = hay.indexOf(needle, i);
    if (idx < 0) {
      buffer.write(source.substring(i));
      break;
    }
    buffer
      ..write(source.substring(i, idx))
      ..write(replacement);
    i = idx + needle.length;
    count++;
  }
  return (buffer.toString(), count);
}

/// Applies [replaceCounted] to a note text block, keeping any Quill Delta
/// structure intact. Returns the new raw block text and the match count.
(String, int) replaceInBlockText(
  String raw,
  String query,
  String replacement, {
  bool caseSensitive = false,
}) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        var count = 0;
        final out = <dynamic>[];
        for (final op in decoded) {
          if (op is Map && op['insert'] is String) {
            final (s, c) = replaceCounted(
                op['insert'] as String, query, replacement,
                caseSensitive: caseSensitive);
            count += c;
            out.add({...op, 'insert': s});
          } else {
            out.add(op);
          }
        }
        return (jsonEncode(out), count);
      }
    } catch (_) {
      // Malformed delta: fall through and treat it as plain text.
    }
  }
  return replaceCounted(raw, query, replacement, caseSensitive: caseSensitive);
}
