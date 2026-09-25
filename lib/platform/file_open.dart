import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// A file the user picked: its display name and contents.
typedef OpenedFile = ({String name, Uint8List bytes});

/// Lets the user pick one file and returns its bytes. On the phone the file is
/// read from the path the picker hands back; in a browser the picker hands
/// the bytes over directly (there are no paths). Null when cancelled or
/// unreadable.
Future<OpenedFile?> pickOneFile({List<String>? extensions}) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
      withData: kIsWeb,
    );
  } catch (_) {
    return null;
  }
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  try {
    final bytes = f.bytes ??
        (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) return null;
    return (name: f.name, bytes: bytes);
  } catch (_) {
    return null;
  }
}
