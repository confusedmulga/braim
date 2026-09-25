import 'dart:io';

import 'package:flutter/services.dart';

/// The web app's files as the phone serves them. Paths are relative to the
/// site root, without a leading slash (`index.html`, `canvaskit/canvaskit.wasm`).
abstract class WebBundle {
  Future<Uint8List?> read(String path);

  /// Drops anything cached (the server stopped).
  void release() {}
}

/// The bundle shipped inside the APK: the web build lives in the app's
/// native assets (`android/app/src/main/assets/web/`, written by
/// tool/build_web_bundle.sh), read through the `braim/webbundle` channel. The
/// Flutter assets the web build would otherwise duplicate — wallpapers, fonts
/// (`assets/assets/…`) — come straight from the phone's own asset bundle.
class ApkWebBundle extends WebBundle {
  static const _channel = MethodChannel('braim/webbundle');
  static const _flutterAssets = 'assets/assets/';

  final Map<String, Uint8List?> _cache = {};

  @override
  Future<Uint8List?> read(String path) async {
    if (_cache.containsKey(path)) return _cache[path];
    Uint8List? bytes;
    if (path.startsWith(_flutterAssets)) {
      try {
        final data = await rootBundle.load(path.substring('assets/'.length));
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {}
    } else {
      try {
        bytes = await _channel.invokeMethod<Uint8List>('read', {'path': path});
      } catch (_) {}
    }
    // Keep the engine files and small ones; the wallpapers stream each time.
    if (bytes == null || bytes.length < 16 * 1024 * 1024) _cache[path] = bytes;
    return bytes;
  }

  @override
  void release() => _cache.clear();

  /// Keeps the phone's screen on while the server runs, so the CPU (and the
  /// server with it) doesn't sleep under the computer.
  static Future<void> keepAwake(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepAwake', {'on': on});
    } catch (_) {}
  }
}

/// A web build on disk (`build/web`), for development and tests.
class DirectoryWebBundle extends WebBundle {
  DirectoryWebBundle(this.root);

  final String root;

  @override
  Future<Uint8List?> read(String path) async {
    final base = Directory(root).absolute.path;
    final file = File('$base/$path').absolute;
    if (!file.path.startsWith(base)) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

String contentTypeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'html' => 'text/html; charset=utf-8',
    'js' || 'mjs' => 'text/javascript; charset=utf-8',
    'json' => 'application/json; charset=utf-8',
    'wasm' => 'application/wasm',
    'css' => 'text/css; charset=utf-8',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'svg' => 'image/svg+xml',
    'ico' => 'image/x-icon',
    'ttf' => 'font/ttf',
    'otf' => 'font/otf',
    'woff2' => 'font/woff2',
    'woff' => 'font/woff',
    'txt' => 'text/plain; charset=utf-8',
    _ => 'application/octet-stream',
  };
}
