/// The plain file name an archive entry may be written as inside [folder]
/// (for example `images/`), or null when the entry isn't one to write.
///
/// Zips get passed between people — a backup someone sent, a shared circuit —
/// so an entry's name is untrusted input. A name like `images/../data.json`
/// would otherwise land outside the folder and overwrite app files (a "zip
/// slip"). Only a single path segment is accepted: no separators, not `.` or
/// `..`, no control characters, and a sane length.
String? safeEntryFileName(String entryName, {required String folder}) {
  if (!entryName.startsWith(folder)) return null;
  final name = entryName.substring(folder.length);
  if (name.isEmpty || name.length > 255) return null;
  if (name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\\')) return null;
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) return null;
  return name;
}
