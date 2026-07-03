import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'thumbnail_label.dart';

/// A note as it appears in the Home feed: a white liquid-glass card with the
/// first image as a labelled thumbnail, then the title and a text preview.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.space,
    required this.onTap,
    this.onLongPress,
  });

  final Note note;
  final Space? space;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final thumb = note.thumbnailPath;
    final preview = note.textPreview;

    return RepaintBoundary(
      child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassEdge(
        borderRadius: 22,
        blur: 0,
        fill: AppPalette.cardFill,
        padding: EdgeInsets.zero,
        shadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thumb != null)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ThumbnailWithLabel(
                  label: space?.name ?? '',
                  imagePath: thumb,
                  borderRadius: 0,
                  placeholderIcon: Icons.image_outlined,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thumb == null && space != null) ...[
                    _spaceChip(space!.name),
                    const SizedBox(height: 8),
                  ],
                  if (note.title.trim().isNotEmpty)
                    Text(
                      note.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                  if (note.title.trim().isNotEmpty && preview.isNotEmpty)
                    const SizedBox(height: 6),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: thumb != null ? 4 : 8,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  if (preview.isEmpty &&
                      note.title.trim().isEmpty &&
                      thumb == null)
                    const Text(
                      'Empty note',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  if (note.imagePaths.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            size: 15, color: AppPalette.inkSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${note.imagePaths.length} photos',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _spaceChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_rounded,
              size: 13, color: AppPalette.inkSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppPalette.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
