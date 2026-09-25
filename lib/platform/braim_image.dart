import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'image_store.dart';
import 'image_store_device.dart';
import 'platform_caps.dart';

/// The image provider for a stored image path: the file itself on the phone,
/// or the bytes from the active [ImageStore] in a browser.
ImageProvider braimImageProvider(String path) {
  if (PlatformCaps.current.isWeb) return StoredImageProvider(imageKey(path));
  return FileImage(File(DeviceImagePaths.resolve(path)));
}

/// Whether a stored image path can be shown. On the phone this checks the file
/// is there (callers use it to fall back to a built-in picture); in a browser
/// the check is deferred to the load, which falls back through errorBuilder.
bool storedImageExists(String path) {
  if (path.isEmpty) return false;
  if (PlatformCaps.current.isWeb) return true;
  try {
    return File(DeviceImagePaths.resolve(path)).existsSync();
  } catch (_) {
    return false;
  }
}

/// `Image.file` for stored image paths, on every platform. Takes the same
/// knobs the app used on `Image.file`, passed straight through.
class BraimImage extends StatelessWidget {
  const BraimImage(
    this.path, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.gaplessPlayback = false,
  });

  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ResizeImage.resizeIfNeeded(
          cacheWidth, cacheHeight, braimImageProvider(path)),
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      errorBuilder: errorBuilder,
      gaplessPlayback: gaplessPlayback,
    );
  }
}

/// Decodes an image whose bytes live in the active [ImageStore] (IndexedDB in
/// local mode, the phone in remote mode). Keyed by the image's file name, so
/// the image cache shares one decode per picture.
@immutable
class StoredImageProvider extends ImageProvider<StoredImageProvider> {
  const StoredImageProvider(this.key);

  final String key;

  @override
  Future<StoredImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StoredImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      StoredImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.key,
    );
  }

  Future<ui.Codec> _load(
      StoredImageProvider key, ImageDecoderCallback decode) async {
    final bytes = await ImageStore.instance.load(key.key);
    if (bytes == null || bytes.isEmpty) {
      // Don't cache the miss: the image may arrive later (a sync, a retry).
      scheduleMicrotask(
          () => PaintingBinding.instance.imageCache.evict(key));
      throw StateError('Stored image ${key.key} is unavailable.');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is StoredImageProvider && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'StoredImageProvider("$key")';
}
