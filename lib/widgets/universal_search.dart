import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/tweet_card.dart';
import '../screens/card_detail_screen.dart';
import '../screens/note_open.dart';
import '../screens/space_detail_screen.dart';
import '../services/db/db_store.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Universal search results: notes, cards and cortex folders in one list.
/// Crypt content is intentionally invisible here — it stays secret.
///
/// Notes and cards come from the SQLite full-text index when it's available
/// (ranked best-first; each word matches from its start; accents ignored),
/// merged with the plain substring filter so nothing the index doesn't cover
/// (a folder-name match, a note typed a second ago) is ever missed.
class UniversalSearchResults extends StatefulWidget {
  const UniversalSearchResults({super.key, required this.query});

  final String query;

  @override
  State<UniversalSearchResults> createState() => _UniversalSearchResultsState();
}

class _UniversalSearchResultsState extends State<UniversalSearchResults> {
  /// Ranked index hits for [_hitsFor]; null when the index is unavailable.
  List<SearchHit>? _hits;
  String _hitsFor = '';
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(UniversalSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final q = widget.query.toLowerCase().trim();
    final run = ++_run;
    final hits =
        q.isEmpty ? null : await context.read<AppState>().searchIndex(q);
    if (!mounted || run != _run) return;
    setState(() {
      _hits = hits;
      _hitsFor = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final q = widget.query.toLowerCase().trim();
    // A "#tag" query matches on tags too (with or without the leading #).
    final qTag = q.replaceAll('#', '');
    final hits = _hitsFor == q ? _hits : null;

    final spaces =
        state.spaces.where((s) => s.name.toLowerCase().contains(q)).toList();

    bool noteMatches(Note n) {
      final space = state.spaceById(n.spaceId);
      return n.title.toLowerCase().contains(q) ||
          n.textPreview.toLowerCase().contains(q) ||
          (qTag.isNotEmpty && n.tags.any((t) => t.contains(qTag))) ||
          (space?.name.toLowerCase().contains(q) ?? false);
    }

    bool cardMatches(TweetCard c) {
      return c.text.toLowerCase().contains(q) ||
          c.noteTitle.toLowerCase().contains(q) ||
          c.authorName.toLowerCase().contains(q) ||
          c.authorHandle.toLowerCase().contains(q) ||
          c.url.toLowerCase().contains(q);
    }

    // Index hits first, in rank order, then whatever the substring filter
    // finds that the index didn't. Only items already visible in [visible]
    // can surface, so crypt and deleted content stay hidden.
    List<T> merge<T>(List<T> visible, String kind, bool Function(T) matches,
        String Function(T) idOf) {
      if (hits == null) return visible.where(matches).toList();
      final byId = {for (final v in visible) idOf(v): v};
      final out = <T>[];
      final seen = <String>{};
      for (final h in hits) {
        if (h.kind != kind) continue;
        final v = byId[h.id];
        if (v != null && seen.add(h.id)) out.add(v);
      }
      for (final v in visible) {
        if (matches(v) && seen.add(idOf(v))) out.add(v);
      }
      return out;
    }

    // Search over the *searchable* population, not the Home feed: it reaches
    // into hidden folds (feed lists exclude those) and ignores the transient
    // tag filter, while still keeping Crypt and deleted content out.
    final notes = merge(state.searchableNotes, 'note', noteMatches, (n) => n.id);
    final cards = merge(state.searchableCards, 'card', cardMatches, (c) => c.id);
    final archivedNotes =
        merge(state.archivedNotes, 'note', noteMatches, (n) => n.id);
    final archivedCards =
        merge(state.archivedCards, 'card', cardMatches, (c) => c.id);
    final archivedCount = archivedNotes.length + archivedCards.length;

    if (spaces.isEmpty &&
        notes.isEmpty &&
        cards.isEmpty &&
        archivedCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 56, color: AppPalette.textSecondary),
            const SizedBox(height: 12),
            Text(context.t.noMatches,
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
          _label(context, context.t.sectionCortex),
          for (final s in spaces)
            _ResultTile(
              icon: Icons.folder_rounded,
              title: s.name,
              subtitle: context.t.itemsCount(state.itemCountForSpace(s.id)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SpaceDetailScreen(spaceId: s.id))),
            ),
        ],
        if (notes.isNotEmpty) ...[
          _label(context, context.t.sectionNotes),
          for (final n in notes)
            _ResultTile(
              icon: Icons.lightbulb_outline_rounded,
              title: n.title.trim().isNotEmpty
                  ? n.title.trim()
                  : (n.textPreview.isNotEmpty
                      ? n.textPreview
                      : context.t.emptyNote),
              subtitle: n.title.trim().isNotEmpty && n.textPreview.isNotEmpty
                  ? n.textPreview
                  : null,
              onTap: () => _openNote(context, n),
            ),
        ],
        if (cards.isNotEmpty) ...[
          _label(context, context.t.sectionCards),
          for (final c in cards)
            _ResultTile(
              icon: Icons.link_rounded,
              title: _cardTitle(c),
              subtitle: c.text.isNotEmpty ? c.text : c.url,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CardDetailScreen(card: c))),
            ),
        ],
        if (archivedCount > 0) ...[
          _label(context, context.t.sectionArchived),
          for (final n in archivedNotes)
            _ResultTile(
              icon: Icons.archive_outlined,
              title: n.title.trim().isNotEmpty
                  ? n.title.trim()
                  : (n.textPreview.isNotEmpty
                      ? n.textPreview
                      : context.t.emptyNote),
              subtitle: n.title.trim().isNotEmpty && n.textPreview.isNotEmpty
                  ? n.textPreview
                  : null,
              onTap: () => _openNote(context, n),
            ),
          for (final c in archivedCards)
            _ResultTile(
              icon: Icons.archive_outlined,
              title: _cardTitle(c),
              subtitle: c.text.isNotEmpty ? c.text : c.url,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CardDetailScreen(card: c))),
            ),
        ],
      ],
    );
  }

  String _cardTitle(TweetCard c) {
    if (c.noteTitle.trim().isNotEmpty) return c.noteTitle.trim();
    if (c.authorName.isNotEmpty) return c.authorName;
    if (c.siteName.isNotEmpty) return c.siteName;
    return c.url;
  }

  void _openNote(BuildContext context, Note n) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => noteScreen(n)));
  }

  Widget _label(BuildContext context, String text) {
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
                      style: TextStyle(
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
                        style: TextStyle(
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
