import 'package:flutter/material.dart';

import '../services/contrast_service.dart';
import '../theme/app_theme.dart';
import '../platform/braim_image.dart';

/// An image thumbnail with a folder/space name overlaid on top. The label color
/// flips between black and white depending on the image so it stays readable.
class ThumbnailWithLabel extends StatelessWidget {
  const ThumbnailWithLabel({
    super.key,
    required this.label,
    this.imagePath,
    this.imageUrl,
    this.borderRadius = 20,
    this.labelAlignment = Alignment.topLeft,
    this.labelStyle,
    this.fit = BoxFit.cover,
    this.showScrim = true,
    this.placeholderIcon = Icons.folder_rounded,
  });

  final String label;
  final String? imagePath;
  final String? imageUrl;
  final double borderRadius;
  final Alignment labelAlignment;
  final TextStyle? labelStyle;
  final BoxFit fit;
  final bool showScrim;
  final IconData placeholderIcon;

  ImageProvider? get _baseProvider {
    if (imagePath != null && imagePath!.isNotEmpty) {
      return braimImageProvider(imagePath!);
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return NetworkImage(imageUrl!,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback);
    }
    return null;
  }

  /// Decode capped near display size — full-res photos (50MP+) otherwise
  /// allocate enormous textures, janking scrolls and crashing on device.
  ImageProvider? get _provider {
    final base = _baseProvider;
    if (base == null) return null;
    return ResizeImage(base, width: 720);
  }

  String get _key => imagePath ?? imageUrl ?? '';

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (provider != null)
            Image(image: provider, fit: fit, gaplessPlayback: true)
          else
            _placeholder(),
          if (provider != null && showScrim)
            // A gentle scrim near the label corner as a legibility safety net.
            Align(
              alignment: labelAlignment,
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: labelAlignment,
              child: _label(provider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFFFFF), Color(0x11FFFFFF)],
        ),
      ),
      child: Icon(
        placeholderIcon,
        size: 40,
        color: Colors.white.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _label(ImageProvider? provider) {
    final baseStyle = (labelStyle ??
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
        .copyWith(height: 1.1);

    if (provider == null) {
      return Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle.copyWith(color: AppPalette.textPrimary),
      );
    }

    // Contrast sampling only needs a few dozen pixels; a tiny decode keeps
    // the palette work off the critical path.
    final sampler = _baseProvider == null
        ? provider
        : ResizeImage(_baseProvider!, width: 56);

    return FutureBuilder<Color>(
      future: ContrastService.labelColorFor(sampler, _key),
      builder: (context, snap) {
        final color = snap.data ?? Colors.white;
        return Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: baseStyle.copyWith(
            color: color,
            shadows: [
              Shadow(
                color: (color == Colors.white ? Colors.black : Colors.white)
                    .withValues(alpha: 0.25),
                blurRadius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}
