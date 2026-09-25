import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'web_bridge.dart';

/// Hands a generated file to the user: the share sheet on the phone (a temp
/// file, as the app always did), a download in a browser.
class FileSaver {
  FileSaver._();

  static Future<void> saveText(
    String text,
    String filename, {
    String mime = 'text/markdown',
    String? title,
  }) =>
      saveBytes(Uint8List.fromList(utf8.encode(text)), filename,
          mime: mime, title: title);

  static Future<void> saveBytes(
    Uint8List bytes,
    String filename, {
    required String mime,
    String? title,
  }) async {
    if (kIsWeb) {
      webDownload(bytes, filename, mime);
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], title: title));
  }
}
