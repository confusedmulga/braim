import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Decides whether a folder/thumbnail label should be black or white so it
/// stays legible on top of whatever image sits behind it.
class ContrastService {
  static final Map<String, Color> _cache = {};

  /// Returns black or white for the given image. [key] uniquely identifies the
  /// image (path or url) so results are cached across rebuilds.
  static Future<Color> labelColorFor(ImageProvider provider, String key) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 8,
      );
      final color = palette.dominantColor?.color ??
          (palette.colors.isNotEmpty ? palette.colors.first : Colors.black);
      // Bright background -> black text, dark background -> white text.
      final result =
          color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      _cache[key] = result;
      return result;
    } catch (_) {
      return Colors.white;
    }
  }
}
