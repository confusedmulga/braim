import 'package:flutter/material.dart';

import '../models/space.dart';
import 'glass.dart';
import 'thumbnail_label.dart';

/// A square, round-cornered folder tile for the Spaces grid.
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: RepaintBoundary(
        child: GlassPanel(
        borderRadius: 26,
        // The tile is filled by its thumbnail; a live backdrop blur per tile
        // made swiping to Cortex stutter.
        blur: 0,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: AspectRatio(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    itemCount == 1 ? '1 item' : '$itemCount items',
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
        ),
        ),
      ),
    );
  }
}
