/// A file-name base built from a user's title, for shared and exported files.
///
/// Only the characters file systems reject (`\ / : * ? " < > |` and control
/// characters) are removed, so a title in any script — Hindi, Chinese, emoji —
/// keeps its name. Whitespace runs become [separator], leading and trailing
/// dots/dashes are trimmed (a leading dot would hide the file), and the result
/// is capped at 80 characters. Falls back to [fallback] when nothing is left.
String safeFileBase(
  String title, {
  required String fallback,
  String separator = '-',
}) {
  final sep = RegExp.escape(separator);
  final cleaned = title
      .trim()
      .replaceAll(RegExp(r'\s+'), separator)
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '')
      .replaceAll(RegExp('(?:$sep){2,}'), separator)
      .replaceAll(RegExp(r'^[.\-\s]+|[.\-\s]+$'), '');
  if (cleaned.isEmpty) return fallback;
  final runes = cleaned.runes;
  return runes.length <= 80 ? cleaned : String.fromCharCodes(runes.take(80));
}
