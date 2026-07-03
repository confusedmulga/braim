import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/tweet_card.dart';
import '../screens/card_detail_screen.dart';
import '../screens/note_editor_screen.dart';
import '../screens/space_detail_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Universal search results: notes, cards and cortex folders in one list.
/// Crypt content is intentionally invisible here — it stays secret.
class UniversalSearchResults extends StatelessWidget {
  const UniversalSearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final q = query.toLowerCase().trim();

    final spaces =
        state.spaces.where((s) => s.name.toLowerCase().contains(q)).toList();
    final notes = state.notes.where((n) {
      final space = state.spaceById(n.spaceId);
      return n.title.toLowerCase().contains(q) ||
          n.textPreview.toLowerCase().contains(q) ||
          (space?.name.toLowerCase().contains(q) ?? false);
    }).toList();
    final cards = state.cards.where((c) {
      return c.text.toLowerCase().contains(q) ||
          c.noteTitle.toLowerCase().contains(q) ||
          c.authorName.toLowerCase().contains(q) ||
          c.authorHandle.toLowerCase().contains(q) ||
          c.url.toLowerCase().contains(q);
    }).toList();

    if (spaces.isEmpty && notes.isEmpty && cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 56, color: AppPalette.textSecondary),
            const SizedBox(height: 12),
            Text('No matches',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 150),
      children: [
        if (spaces.isNotEmpty) ...[
          _label('CORTEX'),
          for (final s in spaces)
            _ResultTile(
              icon: Icons.folder_rounded,
              title: s.name,
              subtitle: _countLabel(state.itemCountForSpace(s.id)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SpaceDetailScreen(spaceId: s.id))),
            ),
        ],
        if (notes.isNotEmpty) ...[
          _label('NOTES'),
          for (final n in notes)
            _ResultTile(
              icon: Icons.lightbulb_outline_rounded,
              title: n.title.trim().isNotEmpty
                  ? n.title.trim()
                  : (n.textPreview.isNotEmpty ? n.textPreview : 'Empty note'),
              subtitle: n.title.trim().isNotEmpty && n.textPreview.isNotEmpty
                  ? n.textPreview
                  : null,
              onTap: () => _openNote(context, n),
            ),
        ],
        if (cards.isNotEmpty) ...[
          _label('CARDS'),
          for (final c in cards)
            _ResultTile(
              icon: Icons.link_rounded,
              title: _cardTitle(c),
              subtitle: c.text.isNotEmpty ? c.text : c.url,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CardDetailScreen(card: c))),
            ),
        ],
      ],
    );
  }

  String _countLabel(int n) => n == 1 ? '1 item' : '$n items';

  String _cardTitle(TweetCard c) {
    if (c.noteTitle.trim().isNotEmpty) return c.noteTitle.trim();
    if (c.authorName.isNotEmpty) return c.authorName;
    if (c.siteName.isNotEmpty) return c.siteName;
    return c.url;
  }

  void _openNote(BuildContext context, Note n) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: n, isNew: false)));
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: AppPalette.textSecondary,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: GlassEdge(
          borderRadius: 18,
          blur: 0,
          fill: AppPalette.cardFill,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: AppPalette.inkSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.inkSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
