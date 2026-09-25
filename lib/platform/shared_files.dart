import 'dart:io';

/// For an item shared into the app: null when [path] isn't a file on disk
/// (it's shared text or a link); otherwise the file's text, or '' when it
/// can't be read as text (a binary file). Android-only in practice: a browser
/// has no share intent.
Future<String?> readSharedFileText(String path) async {
  File file;
  try {
    file = File(path);
    if (!await file.exists()) return null;
  } catch (_) {
    return null;
  }
  try {
    return await file.readAsString();
  } catch (_) {
    return '';
  }
}
