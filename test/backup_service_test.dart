import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:keepy/services/backup_service.dart';
import 'package:keepy/services/storage_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_backup_test');
    Directory('${root.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('restore rewrites image paths to this device and extracts images',
      () async {
    // A backup made on "another device": image blocks point at foreign paths.
    final data = {
      'notes': [
        {
          'id': 'n1',
          'title': 'pic note',
          'blocks': [
            {
              'id': 'b1',
              'type': 'image',
              'text': '',
              'imagePath': '/other/device/images/photo1.jpg',
            },
          ],
        },
      ],
      'spaces': [
        {'id': 's1', 'name': 'folder', 'thumbnailPath': r'C:\old\thumb.jpg'},
      ],
      'cards': <Object>[],
    };
    final archive = Archive()
      ..addFile(ArchiveFile('data.json', 0, utf8.encode(jsonEncode(data))))
      ..addFile(ArchiveFile('images/photo1.jpg', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('images/thumb.jpg', 3, [4, 5, 6]));
    final zipBytes = ZipEncoder().encode(archive);

    await BackupService.instance.restoreFromZipBytes(zipBytes);

    final restored = await StorageService.instance.load();
    final imagesDir = '${root.path}/images'.replaceAll('\\', '/');

    final notePath =
        restored.notes.single.blocks.single.imagePath.replaceAll('\\', '/');
    expect(notePath, '$imagesDir/photo1.jpg');
    expect(File(notePath).existsSync(), isTrue);

    final thumbPath =
        restored.spaces.single.thumbnailPath!.replaceAll('\\', '/');
    expect(thumbPath, '$imagesDir/thumb.jpg');
    expect(File(thumbPath).existsSync(), isTrue);
  });

  test('export streams a zip containing data.json and images', () async {
    // Seed a data file + one image.
    await StorageService.instance.save(AppData.empty());
    final img = File('${root.path}/images/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);

    final progress = <(int, int)>[];
    final out = await BackupService.instance.exportToTempFile(
      onProgress: (done, total) => progress.add((done, total)),
    );

    expect(out.existsSync(), isTrue);
    final names = ZipDecoder()
        .decodeBytes(out.readAsBytesSync())
        .map((f) => f.name)
        .toSet();
    expect(names.contains('data.json'), isTrue);
    expect(names.contains('images/a.jpg'), isTrue);
    expect(progress.last.$1, progress.last.$2,
        reason: 'progress reaches total');
    img.deleteSync();
  });
}
