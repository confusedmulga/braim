import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/wiki_links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// An item's place in the graph: the `[[links]]` it points at (each resolved to
/// a note or card, or offered to create), and a "Mentioned in" list of notes,
/// journal entries and cards that point back. Shared by the note editor and
/// the card detail screen.
class NoteLinksSection extends StatelessWidget {
  const NoteLinksSection({
    super.key,
    required this.selfId,
    required this.title,
    required this.scanText,
    required this.onOpen,
    required this.onCreateOpen,
  });

  /// This item's id, so it never lists itself as a backlink.
  final String selfId;

  /// This item's title, looked up in others' text for backlinks.
  final String title;

  /// This item's own text, scanned for the outgoing `[[links]]`.
  final String scanText;

  /// Open a resolved target (note or card).
  final void Function(LinkRef ref) onOpen;

  /// Create a note for an unresolved `[[title]]`, then open it.
  final void Function(String title) onCreateOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final linkTitles = state.wikiTitlesIn(scanText);
    final backlinks = state.backlinksToTitle(title, excludeId: selfId);
    if (linkTitles.isEmpty && backlinks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (linkTitles.isNotEmpty) ...[
            _Header(icon: Icons.hub_outlined, label: context.t.linksSection),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in linkTitles)
                  _LinkChip(
                    title: t,
                    target: state.resolveLink(t),
                    onOpen: onOpen,
                    onCreateOpen: onCreateOpen,
                  ),
              ],
            ),
          ],
          if (backlinks.isNotEmpty) ...[
            if (linkTitles.isNotEmpty) const SizedBox(height: 18),
            _Header(
                icon: Icons.forum_outlined,
                label: context.t.mentionedIn(backlinks.length)),
            const SizedBox(height: 8),
            for (final ref in backlinks)
              _BacklinkTile(ref: ref, onTap: () => onOpen(ref)),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppPalette.inkSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: AppPalette.inkSecondary,
          ),
        ),
      ],
    );
  }
}

IconData _kindIcon(LinkKind kind) =>
    kind == LinkKind.card ? Icons.link_rounded : Icons.description_outlined;

/// One outgoing `[[link]]`: a solid chip when it resolves (to a note or card),
/// a dashed "create" chip when no item has that title yet.
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.title,
    required this.target,
    required this.onOpen,
    required this.onCreateOpen,
  });

  final String title;
  final LinkRef? target;
  final void Function(LinkRef ref) onOpen;
  final void Function(String title) onCreateOpen;

  @override
  Widget build(BuildContext context) {
    final resolved = target != null;
    final scheme = AppPalette.scheme;
    return Material(
      color: resolved
          ? scheme.secondaryContainer
          : AppPalette.chipFill.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: resolved
            ? BorderSide.none
            : BorderSide(
                color: AppPalette.inkSecondary.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: resolved ? () => onOpen(target!) : () => onCreateOpen(title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                resolved ? _kindIcon(target!.kind) : Icons.add_rounded,
                size: 14,
                color: resolved
                    ? scheme.onSecondaryContainer
                    : AppPalette.inkSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: resolved
                        ? scheme.onSecondaryContainer
                        : AppPalette.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An item that mentions this one — its title over a one-line preview, with a
/// note/card icon.
class _BacklinkTile extends StatelessWidget {
  const _BacklinkTile({required this.ref, required this.onTap});
  final LinkRef ref;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = ref.title.trim().isNotEmpty
        ? ref.title.trim()
        : context.t.untitledNote;
    final preview = ref.preview.replaceAll('\n', ' ').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.bubbleGlass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppPalette.cardOutline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(_kindIcon(ref.kind),
                    size: 18, color: AppPalette.inkSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppPalette.inkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
