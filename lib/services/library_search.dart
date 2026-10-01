import '../models/note.dart';
import '../models/tweet_card.dart';
import '../state/app_state.dart';
import 'db/db_store.dart';

/// What a library search found, in the order to show it.
typedef LibraryMatches = ({
  List<Note> notes,
  List<TweetCard> cards,
  List<Note> archivedNotes,
  List<TweetCard> archivedCards,
});

/// Searches the library for [query]: full-text index hits first, in rank
/// order, then substring matches the index didn't return. Only searchable
/// items can surface, so the Crypt and deleted content stay hidden. Shared by
/// the phone's universal search and Braim Web, so both list the same results.
Future<({List<Note> notes, List<TweetCard> cards})> searchLibrary(
  AppState state,
  String query,
) async {
  final q = query.toLowerCase().trim();
  final hits = q.isEmpty ? null : await state.searchIndex(q);
  final m = matchLibrary(state, q, hits);
  return (notes: m.notes, cards: m.cards);
}

/// The synchronous half of [searchLibrary]: merges [hits] (null when the
/// index is unavailable) with the substring filter for the lower-cased,
/// trimmed query [q]. Archived matches are for the phone only.
LibraryMatches matchLibrary(AppState state, String q, List<SearchHit>? hits) {
  // A "#tag" query matches on tags too (with or without the leading #).
  final qTag = q.replaceAll('#', '');

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
  List<T> merge<T>(
    List<T> visible,
    String kind,
    bool Function(T) matches,
    String Function(T) idOf,
  ) {
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
  return (
    notes: merge(state.searchableNotes, 'note', noteMatches, (n) => n.id),
    cards: merge(state.searchableCards, 'card', cardMatches, (c) => c.id),
    archivedNotes: merge(state.archivedNotes, 'note', noteMatches, (n) => n.id),
    archivedCards: merge(state.archivedCards, 'card', cardMatches, (c) => c.id),
  );
}
