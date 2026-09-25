import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;

import '../services/storage_service.dart';
import 'image_store.dart';

/// The phone's images folder, cached at startup so a relative image path
/// (`images/<uuid>.jpg`, created by the web app) resolves synchronously while
/// building widgets. Null until [DeviceImagePaths.init] runs (unit tests),
/// in which case paths are used as given.
class DeviceImagePaths {
  static String? imagesDir;

  static Future<void> init() async {
    try {
      imagesDir = (await StorageService.instance.imagesDir).path;
    } catch (_) {}
  }

  /// The on-disk path for a stored image path: absolute paths pass through
  /// untouched; relative ones resolve against the images folder.
  static String resolve(String path) {
    final dir = imagesDir;
    if (dir == null || !isRelativeImagePath(path)) return path;
    return '$dir/${imageKey(path)}';
  }
}

/// The phone's image store: files in the app's images folder, exactly as the
/// app has always kept them (absolute paths in the models).
class DeviceImageStore implements ImageStore {
  @override
  Future<String> saveBytes(Uint8List bytes, {String ext = '.png'}) =>
      StorageService.instance.saveImageBytes(bytes, ext: ext);

  @override
  Future<String> savePicked(XFile file) =>
      StorageService.instance.saveImage(file.path);

  @override
  Future<Uint8List?> load(String path) async {
    try {
      return await File(DeviceImagePaths.resolve(path)).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String path) =>
      StorageService.instance.deleteImage(DeviceImagePaths.resolve(path));
}
