import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

/// Creates and restores full backups (data + images) as a single .zip.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  Future<File> _dataFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/keepy_data.json');
  }

  Future<Directory> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/images');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _base(String path) => path.split(RegExp(r'[\\/]')).last;

  /// Streams a backup zip (data.json + images/) to a temporary file, one
  /// source file at a time — a large image library never sits in RAM at once.
  /// [onProgress] reports (filesDone, filesTotal).
  Future<File> exportToTempFile(
      {void Function(int done, int total)? onProgress}) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/braim-backup-$stamp.zip');

    final dataFile = await _dataFile();
    final imagesDir = await _imagesDir();
    final images = imagesDir.listSync().whereType<File>().toList();
    final total = images.length + 1;
    var done = 0;

    final encoder = ZipFileEncoder();
    encoder.create(out.path);
    try {
      if (await dataFile.exists()) {
        await encoder.addFile(dataFile, 'data.json');
      }
      done++;
      onProgress?.call(done, total);
      for (final f in images) {
        await encoder.addFile(f, 'images/${_base(f.path)}');
        done++;
        onProgress?.call(done, total);
      }
    } finally {
      await encoder.close();
    }
    return out;
  }

  /// Restores from a backup zip: extracts images, rewrites their paths to this
  /// device's images folder, and replaces the data file.
  Future<void> restoreFromZipBytes(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final imagesDir = await _imagesDir();

    String? dataJson;
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name == 'data.json') {
        dataJson = utf8.decode(f.content as List<int>);
      } else if (f.name.startsWith('images/')) {
        final base = f.name.substring('images/'.length);
        if (base.isEmpty) continue;
        await File('${imagesDir.path}/$base')
            .writeAsBytes(f.content as List<int>);
      }
    }

    if (dataJson == null) {
      throw const FormatException('Not a valid Braim backup (no data.json).');
    }

    final map = jsonDecode(dataJson) as Map<String, dynamic>;
    _rewritePaths(map, imagesDir.path);
    await (await _dataFile()).writeAsString(jsonEncode(map));
  }

  Future<void> restoreFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    await restoreFromZipBytes(bytes);
  }

  /// Points every stored image path at this device's images folder using the
  /// original file name, so a backup restores correctly on any install.
  void _rewritePaths(Map<String, dynamic> map, String imagesPath) {
    String fix(String? p) =>
        (p == null || p.isEmpty) ? '' : '$imagesPath/${_base(p)}';

    void fixBlocks(List? blocks) {
      if (blocks == null) return;
      for (final b in blocks) {
        if (b is Map && b['type'] == 'image' && b['imagePath'] is String) {
          final v = b['imagePath'] as String;
          if (v.isNotEmpty) b['imagePath'] = fix(v);
        }
      }
    }

    for (final n in (map['notes'] as List? ?? [])) {
      if (n is Map) fixBlocks(n['blocks'] as List?);
    }
    for (final s in (map['spaces'] as List? ?? [])) {
      if (s is Map && s['thumbnailPath'] is String) {
        final v = s['thumbnailPath'] as String;
        if (v.isNotEmpty) s['thumbnailPath'] = fix(v);
      }
    }
    for (final c in (map['cards'] as List? ?? [])) {
      if (c is Map) fixBlocks(c['blocks'] as List?);
    }
  }
}
