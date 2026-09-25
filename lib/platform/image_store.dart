import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' show XFile;

import 'image_store_device.dart';

/// Stored images are identified by their file name alone. Models keep a path —
/// an absolute device path (`/data/…/app_flutter/images/<uuid>.jpg`) on the
/// phone, or a relative `images/<uuid>.jpg` for images created elsewhere — and
/// only its basename matters off the phone, so a library restored from a
/// backup (whose zip entries are basenames) renders without rewriting a field.
String imageKey(String path) => path.split(RegExp(r'[\\/]')).last;

/// The path a model stores for an image created off the phone.
String relativeImagePath(String key) => '$kRelativeImagesDir/$key';

const kRelativeImagesDir = 'images';

bool isRelativeImagePath(String path) =>
    path.startsWith('$kRelativeImagesDir/');

/// Where image bytes live: the phone's images folder, the browser's IndexedDB
/// (local mode), or the phone over HTTP (remote mode). Picked once at startup.
abstract class ImageStore {
  /// Saves [bytes] under a fresh name and returns the path to store in the
  /// model.
  Future<String> saveBytes(Uint8List bytes, {String ext = '.png'});

  /// Copies a file the user just picked into the store; returns its path.
  Future<String> savePicked(XFile file);

  /// The bytes behind a stored [path], or null when it's missing.
  Future<Uint8List?> load(String path);

  /// Best-effort removal of a stored image.
  Future<void> delete(String path);

  static ImageStore instance = DeviceImageStore();
}

/// File extension (with the dot) for a picked file, defaulting to `.jpg`.
String extensionOf(String name, {String fallback = '.jpg'}) {
  final base = imageKey(name);
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return fallback;
  final ext = base.substring(dot).toLowerCase();
  return ext.length > 6 ? fallback : ext;
}
