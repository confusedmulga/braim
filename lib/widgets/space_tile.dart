import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/space.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'thumbnail_label.dart';

/// A folder tile for the Cortex grid.
///
/// Folders with a thumbnail are full squares; folders without one render as
/// compact half-height tiles tinted with the theme's secondary container so
/// they read against the plain surface, packing tight like the home feed.
class SpaceTile extends StatelessWidget {
  const SpaceTile({
    super.key,
    required this.space,
    required this.itemCount,
    required this.onTap,
    this.onLongPress,
  });

  final Space space;
  final int itemCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  bool get _hasThumb =>
      space.thumbnailPath != null && space.thumbnailPath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tint = _hasThumb ? null : NoteColors.resolveStrong(space.colorValue);
    return GestureDetector(
      onLongPress: onLongPress,
      child: RepaintBoundary(
        child: GlassPanel(
          borderRadius: 26,
          // The tile is filled by its thumbnail; a live backdrop blur per tile
          // made swiping to Cortex stutter.
          blur: 0,
          color:
              _hasThumb ? null : (tint ?? AppPalette.scheme.secondaryContainer),
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: _hasThumb ? _thumbTile(context) : _compactTile(context),
        ),
      ),
    );
  }

  Widget _thumbTile(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ThumbnailWithLabel(
            label: space.name,
            imagePath: space.thumbnailPath,
            borderRadius: 26,
            labelAlignment: Alignment.topLeft,
            labelStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.t.itemsCount(itemCount),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactTile(BuildContext context) {
    // A colour swatch is light-toned in both themes, so it takes a fixed dark
    // ink; the default tile keeps its secondary-container ink.
    final ink = space.colorValue != null
        ? NoteColors.onSwatch
        : AppPalette.scheme.onSecondaryContainer;
    return AspectRatio(
      aspectRatio: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder_rounded, size: 20, color: ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    space.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t.itemsCount(itemCount),
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
