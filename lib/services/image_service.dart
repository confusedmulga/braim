import 'package:image_picker/image_picker.dart';

import 'storage_service.dart';

/// Thin wrapper over image_picker that immediately copies picks into app
/// storage and returns the persistent paths.
///
/// Picks are downscaled at the source: modern phones shoot 50–64MP photos and
/// decoding those full-res for feed tiles caused multi-second jank and GPU
/// out-of-memory crashes on device.
class ImageService {
  static final _picker = ImagePicker();

  /// Note/card body images: capped well above screen width so they stay sharp.
  static const double _maxContentSide = 1920;

  /// Folder thumbnails: rendered ~180dp, so a small crop is plenty.
  static const double _maxThumbSide = 800;

  static Future<List<String>> pickMultiple() async {
    final files = await _picker.pickMultiImage(
      maxWidth: _maxContentSide,
      maxHeight: _maxContentSide,
      imageQuality: 88,
    );
    final paths = <String>[];
    for (final f in files) {
      paths.add(await StorageService.instance.saveImage(f.path));
    }
    return paths;
  }

  static Future<String?> pickSingle({bool camera = false}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: _maxContentSide,
      maxHeight: _maxContentSide,
      imageQuality: 88,
    );
    if (file == null) return null;
    return StorageService.instance.saveImage(file.path);
  }

  /// Picks a small image for folder thumbnails.
  static Future<String?> pickThumbnail() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxThumbSide,
      maxHeight: _maxThumbSide,
      imageQuality: 82,
    );
    if (file == null) return null;
    return StorageService.instance.saveImage(file.path);
  }
}
