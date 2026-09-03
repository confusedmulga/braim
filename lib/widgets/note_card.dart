import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'note_preview.dart';
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
    this.selected = false,
  });

  final Note note;
  final Space? space;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// True when the feed is in multi-select mode and this note is picked.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final thumb = note.thumbnailPath;
    final preview = note.textPreview;

    return RepaintBoundary(
      child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: AppPalette.scheme.primary, width: 2.5))
            : null,
        child: FlatCard(
        borderRadius: 22,
        fill: NoteColors.resolve(note.colorValue),
        child: Stack(
          children: [
            _cardBody(context, thumb, preview),
            if (selected)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPalette.scheme.primary,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
            if (note.pinned)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.22),
                  ),
                  child: const Icon(Icons.push_pin_rounded,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _cardBody(BuildContext context, String? thumb, String preview) {
    return Column(
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
                    _spaceChip(space!),
                    const SizedBox(height: 8),
                  ],
                  // Articles read differently from notes; say so up front.
                  if (note.isArticle) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined,
                            size: 14, color: AppPalette.inkSecondary),
                        const SizedBox(width: 5),
                        Text(
                          note.articleDraft
                              ? context.t.draftLabel
                              : context.t.articleLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (note.title.trim().isNotEmpty)
                    Text(
                      note.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kNoteHeadingFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                  if (note.title.trim().isNotEmpty && preview.isNotEmpty)
                    const SizedBox(height: 6),
                  if (preview.isNotEmpty)
                    NotePreview(
                      note: note,
                      maxLines: thumb != null ? 4 : 7,
                      style: TextStyle(
                        fontFamily: activeBodyFont,
                        fontSize: 18,
                        height: 1.25,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  if (preview.isEmpty &&
                      note.title.trim().isEmpty &&
                      thumb == null)
                    Text(
                      context.t.emptyNote,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  if (note.imagePaths.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 15, color: AppPalette.inkSecondary),
                        const SizedBox(width: 4),
                        Text(
                          context.t.photosCount(note.imagePaths.length),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in note.tags.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppPalette.scheme.secondaryContainer
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('#$tag',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppPalette.inkPrimary)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
    );
  }

  Widget _spaceChip(Space s) {
    final tint = NoteColors.resolveStrong(s.colorValue);
    final fg = tint != null ? NoteColors.onSwatch : AppPalette.inkSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint ?? Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_rounded,
              size: 13, color: fg.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
