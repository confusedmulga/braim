import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../services/note_markdown.dart';
import '../state/app_state.dart';
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
        // Colour-coded notes read the same vivid way as Cortex folder tiles
        // (light-toned, only slightly darkened in dark mode) instead of the old
        // near-black tint, so a chosen colour is actually visible.
        fill: NoteColors.resolveStrong(note.colorValue),
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
    // On a colour-coded (light-toned) card, ink flips dark so it stays legible;
    // uncoloured cards keep the theme's ink.
    final colored = NoteColors.resolveStrong(note.colorValue) != null;
    final ink = colored ? NoteColors.onSwatch : AppPalette.inkPrimary;
    final ink2 = colored
        ? NoteColors.onSwatch.withValues(alpha: 0.72)
        : AppPalette.inkSecondary;
    // A circuit's first note reads as a "Circuit" tile: a tree badge, the
    // title, a peek of the body, and a footer counting its notes.
    if (note.isCircuitRoot) return _circuitBody(context, ink, ink2);
    // A Markdown node reads as a clean "document" tile (sans face + a badge),
    // distinct from the handwriting-style notes around it.
    if (note.markdown) return _markdownBody(context, ink, ink2);
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
                  if (note.isCircuitNode) ...[
                    _circuitChip(context, ink),
                    const SizedBox(height: 8),
                  ] else if (thumb == null && space != null) ...[
                    _spaceChip(space!, onColor: colored, cardInk: ink),
                    const SizedBox(height: 8),
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
                        color: ink,
                      ),
                    ),
                  if (note.title.trim().isNotEmpty && preview.isNotEmpty)
                    const SizedBox(height: 6),
                  if (preview.isNotEmpty)
                    NotePreview(
                      note: note,
                      maxLines: thumb != null ? 4 : 7,
                      onColor: colored,
                      style: TextStyle(
                        fontFamily: activeBodyFont,
                        fontSize: 18,
                        height: 1.25,
                        color: ink2,
                      ),
                    ),
                  if (preview.isEmpty &&
                      note.title.trim().isEmpty &&
                      thumb == null)
                    Text(
                      context.t.emptyNote,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: ink2,
                      ),
                    ),
                  if (note.imagePaths.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 15, color: ink2),
                        const SizedBox(width: 4),
                        Text(
                          context.t.photosCount(note.imagePaths.length),
                          style: TextStyle(
                            fontSize: 12,
                            color: ink2,
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
                              // On a colour swatch the theme chip goes dark-on-
                              // dark, so tint it from the card's own dark ink.
                              color: colored
                                  ? ink.withValues(alpha: 0.12)
                                  : AppPalette.scheme.secondaryContainer
                                      .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('#$tag',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: ink)),
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

  /// The feed tile for a Markdown node: a small "Markdown" badge, the title in
  /// a clean sans, and a symbol-free preview of the source.
  Widget _markdownBody(BuildContext context, Color ink, Color ink2) {
    final title = note.title.trim();
    final preview = markdownPlainPreview(note.markdownSource,
        skipTitle: title.isEmpty ? null : title);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.data_object_rounded, size: 13, color: ink2),
                const SizedBox(width: 4),
                Text('Markdown',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: ink2)),
              ],
            ),
          ),
          if (note.isCircuitNode) ...[
            const SizedBox(height: 8),
            _circuitChip(context, ink),
          ],
          if (title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: ink)),
          ],
          if (preview.isNotEmpty) ...[
            SizedBox(height: title.isNotEmpty ? 6 : 10),
            Text(preview,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    height: 1.4,
                    color: ink2)),
          ],
          if (title.isEmpty && preview.isEmpty) ...[
            const SizedBox(height: 10),
            Text(context.t.emptyNote,
                style: TextStyle(fontStyle: FontStyle.italic, color: ink2)),
          ],
        ],
      ),
    );
  }

  /// The feed tile for a circuit's first note: a "Circuit" badge, the title, a
  /// couple of lines of the first note's body, and a footer counting the notes
  /// with up to three child titles.
  Widget _circuitBody(BuildContext context, Color ink, Color ink2) {
    final state = context.read<AppState>();
    final title = note.title.trim();
    final preview = note.textPreview;
    final count = state.circuitBranchCount(note.id);
    final children = state
        .circuitChildren(note.id)
        .where((n) => !n.circuitPlaceholder)
        .take(3)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_tree_rounded, size: 13, color: ink2),
                const SizedBox(width: 4),
                Text(context.t.circuitLabel,
                    style: TextStyle(
                        fontFamily: kNoteHeadingFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: ink2)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(title.isEmpty ? context.t.untitledCircuit : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: kNoteHeadingFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ink)),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: activeBodyFont,
                    fontSize: 15,
                    height: 1.25,
                    color: ink2)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree_rounded, size: 13, color: ink2),
              const SizedBox(width: 5),
              Text(context.t.circuitNotesCount(count),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: ink2)),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in children)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      c.title.trim().isEmpty
                          ? context.t.untitledNote
                          : c.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ink),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The "In {circuit}" chip a branch shown in the feed carries where a folder
  /// chip would otherwise sit.
  Widget _circuitChip(BuildContext context, Color ink) {
    final state = context.read<AppState>();
    final root = note.circuitId == null ? null : state.noteById(note.circuitId!);
    final name = (root == null || root.title.trim().isEmpty)
        ? context.t.untitledCircuit
        : root.title.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_rounded,
                size: 13, color: ink.withValues(alpha: 0.85)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(context.t.circuitIn(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: ink)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spaceChip(Space s, {required bool onColor, required Color cardInk}) {
    // On a colour-swatch card (a light-toned tile) the fold chip must borrow the
    // card's own dark ink: a theme-tinted chip goes light-on-light and the fold
    // name vanishes in dark mode. Uncoloured cards keep the fold's own colour.
    final tint = onColor ? null : NoteColors.resolveStrong(s.colorValue);
    final Color bg;
    final Color fg;
    if (onColor) {
      bg = cardInk.withValues(alpha: 0.12);
      fg = cardInk;
    } else if (tint != null) {
      bg = tint;
      fg = NoteColors.onSwatch;
    } else {
      bg = Colors.black.withValues(alpha: 0.06);
      fg = AppPalette.inkSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
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
