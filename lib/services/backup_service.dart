import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_service.dart';

/// One backup zip sitting in the on-device Backups folder.
class DeviceBackupFile {
  DeviceBackupFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedTime,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedTime;
}

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

  /// Writes a backup zip into a stable "Backups" folder the app can reach
  /// without a save dialog — used by the scheduled on-device auto-backup. Prefers
  /// the app-specific external directory (visible to a file manager, no
  /// permission needed), falling back to the documents directory.
  ///
  /// The zip is streamed to a temp file, copied onto the destination volume
  /// under a hidden staging name, then renamed into place: a rename is atomic on
  /// the same volume, so a process kill mid-write can never leave a truncated
  /// zip where a reader would find it (a plain copy could). Afterwards the
  /// folder is pruned to the newest [keep] Braim backups — each zip carries the
  /// whole image library, so a daily schedule would otherwise grow without
  /// bound. Only files this app itself named are ever removed.
  Future<File> exportToBackupsDir({int keep = 5}) async {
    final tmp = await exportToTempFile();
    try {
      return await placeInBackupsDir(tmp, keep: keep);
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  /// The on-device Backups folder: the app-specific external directory (visible
  /// to a file manager, no permission needed) when available, else the documents
  /// directory. This storage is app-private — Android clears it on uninstall and
  /// it is lost with the device — so it guards against a bad write, not loss.
  Future<Directory> _resolveBackupsDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory('${base.path}/Backups');
  }

  /// The absolute path of the on-device Backups folder, for display in Settings.
  Future<String> backupsDirPath() async => (await _resolveBackupsDir()).path;

  /// The Braim backups sitting in the on-device Backups folder, newest first.
  /// Only files this app named (`braim-backup-*.zip`) are listed.
  Future<List<DeviceBackupFile>> listDeviceBackups() async {
    final dir = await _resolveBackupsDir();
    if (!await dir.exists()) return const [];
    final out = <DeviceBackupFile>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = _base(f.path);
      if (!name.startsWith('braim-backup-') || !name.endsWith('.zip')) continue;
      final stat = f.statSync();
      out.add(DeviceBackupFile(
        path: f.path,
        name: name,
        sizeBytes: stat.size,
        modifiedTime: stat.modified,
      ));
    }
    out.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return out;
  }

  /// Places an already-built backup [tmp] into the app's Backups folder
  /// atomically and prunes to the newest [keep] (see [exportToBackupsDir]).
  /// Does not delete [tmp] — the caller owns it, so one zip can feed both the
  /// Drive upload and the on-device copy on a single pause.
  Future<File> placeInBackupsDir(File tmp, {int keep = 5}) async {
    final dir = await _resolveBackupsDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    // Sweep any leftover staging files first: if a previous run was killed
    // between the copy and the rename below, its `.part` survives, and the prune
    // never collects it (that only matches `braim-backup-*.zip`). Each one is a
    // full-library-sized orphan, so drop them before writing a new one. These
    // are always this app's own temporaries.
    await _sweepStagingFiles(dir);
    final destName = _base(tmp.path);
    final dest = File('${dir.path}/$destName');
    // A hidden ".part" sibling on the destination volume; renamed over the final
    // name once fully written. Its name is filtered out of the prune below.
    final staging = File('${dir.path}/.$destName.part');
    await tmp.copy(staging.path);
    try {
      await staging.rename(dest.path);
    } catch (_) {
      // Rare fallback (destination momentarily locked): copy straight over,
      // then drop the staging file.
      await staging.copy(dest.path);
      try {
        await staging.delete();
      } catch (_) {}
    }
    await _pruneBackupsDir(dir, keep: keep);
    return dest;
  }

  /// Deletes leftover staging files (`.braim-backup-*.part`) from a run that
  /// died mid-write. Only this app's own hidden temporaries match. Best effort.
  Future<void> _sweepStagingFiles(Directory dir) async {
    try {
      for (final f in dir.listSync().whereType<File>()) {
        final name = _base(f.path);
        if (name.startsWith('.braim-backup-') && name.endsWith('.part')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Keeps only the newest [keep] Braim backups in [dir], deleting older ones.
  /// Only files this app named (`braim-backup-*.zip`) are touched, so anything
  /// else the user dropped in the folder is left alone. Best effort.
  Future<void> _pruneBackupsDir(Directory dir, {required int keep}) async {
    try {
      final backups = dir.listSync().whereType<File>().where((f) {
        final name = _base(f.path);
        return name.startsWith('braim-backup-') && name.endsWith('.zip');
      }).toList()
        ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in backups.skip(keep)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {
      // A failed prune isn't worth surfacing; retried on the next backup.
    }
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
    // Land it through the normal atomic save (temp file, flush, rename) so a
    // crash mid-restore can never leave a torn data file behind; the library
    // being replaced rotates into .bak as usual. Parsing it first also means a
    // malformed backup fails here, loudly, instead of after it overwrote the
    // store.
    await StorageService.instance.save(AppData.fromJson(map));
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
