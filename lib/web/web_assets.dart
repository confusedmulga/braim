// Braim Web static files: the site's CSS and scripts from assets/web/, and the
// bundled fonts. Loaded from the Flutter bundle and kept in memory.

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';

/// Reads one bundle asset; [rootBundle.load] in the app, the file system in
/// tests.
typedef WebAssetLoader = Future<ByteData> Function(String key);

class WebAssets {
  WebAssets({WebAssetLoader? load}) : _load = load ?? rootBundle.load;

  final WebAssetLoader _load;

  /// Served at `/assets/<name>` from `assets/web/<name>`, with their types.
  static const files = <String, String>{
    'app.css': 'text/css; charset=utf-8',
    'app.js': 'text/javascript; charset=utf-8',
    // The Braim logo (assets/logos/braim.svg, cropped to the drawing).
    'logo.svg': 'image/svg+xml',
    // Edit pages only.
    'editor.css': 'text/css; charset=utf-8',
    'editor.js': 'text/javascript; charset=utf-8',
    'vendor/quill.core.css': 'text/css; charset=utf-8',
    'vendor/quill.js': 'text/javascript; charset=utf-8',
    // Circuit maps only.
    'map.css': 'text/css; charset=utf-8',
    'map.js': 'text/javascript; charset=utf-8',
  };

  /// Served at `/fonts/<name>` from `assets/fonts/<name>`.
  static const fonts = <String>{
    'Caveat-Bold.ttf',
    'Caveat-Regular.ttf',
    'Caveat-SemiBold.ttf',
    'EBGaramond-Bold.ttf',
    'EBGaramond-Regular.ttf',
    'Inter-Regular.ttf',
    'JetBrainsMono-Regular.ttf',
    'Lora-Bold.ttf',
    'Lora-Regular.ttf',
    'Lora-SemiBold.ttf',
    'Merriweather-Bold.ttf',
    'Merriweather-Regular.ttf',
    'Nunito-Regular.ttf',
    'SpaceGrotesk-Bold.ttf',
    'SpaceGrotesk-Medium.ttf',
    'SpaceGrotesk-Regular.ttf',
  };

  static const _immutable = 'private, max-age=31536000, immutable';
  static const _fontCache = 'private, max-age=604800';

  final Map<String, ({Uint8List bytes, String version})> _files = {};
  final Map<String, Uint8List> _fonts = {};

  /// Loads every file in [files], so pages can name them with a version.
  Future<void> preload() async {
    for (final name in files.keys) {
      if (_files.containsKey(name)) continue;
      final bytes = _bytes(await _load('assets/web/$name'));
      final version = sha256.convert(bytes).toString().substring(0, 10);
      _files[name] = (bytes: bytes, version: version);
    }
  }

  /// The versioned URL of [name], for a page to link. [preload] first.
  String url(String name) {
    final file = _files[name];
    if (file == null) throw StateError('$name is not loaded');
    return '/assets/$name?v=${file.version}';
  }

  /// `/assets/<name>`, or null for a name not in [files]. A request carrying
  /// the current version may be cached for good.
  Response? asset(String name, {String? version}) {
    final file = _files[name];
    final type = files[name];
    if (file == null || type == null) return null;
    return Response.ok(
      file.bytes,
      headers: {
        'content-type': type,
        'cache-control': version == file.version ? _immutable : 'no-cache',
      },
    );
  }

  /// `/fonts/<name>`, or null for a name not in [fonts].
  Future<Response?> font(String name) async {
    if (!fonts.contains(name)) return null;
    final bytes = _fonts[name] ??= _bytes(await _load('assets/fonts/$name'));
    return Response.ok(
      bytes,
      headers: {'content-type': 'font/ttf', 'cache-control': _fontCache},
    );
  }

  static Uint8List _bytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
