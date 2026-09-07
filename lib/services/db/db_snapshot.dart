import 'dart:convert';

import '../../models/book.dart';
import '../../models/impulse.dart';
import '../../models/note.dart';
import '../../models/space.dart';
import '../../models/tweet_card.dart';
import '../storage_service.dart' show AppData;

/// The library expressed as database rows: one list of column maps per entity
/// table, plus the settings key/value map. This is the pure, engine-independent
/// bridge between [AppData] and the SQLite store — no Drift/sqflite types here,
/// so the data-safety-critical mapping can be unit-tested without a real DB.
///
/// Every entity row carries the full entity as a JSON `body` column (so nothing
/// is ever lost), plus a handful of real columns for the fields the feeds
/// filter and sort on.
class AppSnapshot {
  const AppSnapshot({
    required this.notes,
    required this.cards,
    required this.books,
    required this.impulses,
    required this.spaces,
    required this.settings,
  });

  final List<Map<String, Object?>> notes;
  final List<Map<String, Object?>> cards;
  final List<Map<String, Object?>> books;
  final List<Map<String, Object?>> impulses;
  final List<Map<String, Object?>> spaces;

  /// key -> JSON-encoded value, one per app-level setting.
  final Map<String, String> settings;

  int get entityCount =>
      notes.length +
      cards.length +
      books.length +
      impulses.length +
      spaces.length;
}

int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
int _b(bool v) => v ? 1 : 0;

Map<String, Object?> noteRow(Note n) => {
      'id': n.id,
      'updated_at': n.updatedAt.millisecondsSinceEpoch,
      'created_at': n.createdAt.millisecondsSinceEpoch,
      'archived': _b(n.archived),
      'deleted_at': _ms(n.deletedAt),
      'space_id': n.spaceId,
      'book_id': n.bookId,
      'book_page_kind': n.bookPageKind,
      'book_order': n.bookOrder,
      'journal_date': n.journalDate,
      'pinned': _b(n.pinned),
      'title': n.title,
      'body': jsonEncode(n.toJson()),
    };

Map<String, Object?> cardRow(TweetCard c) => {
      'id': c.id,
      'updated_at': c.updatedAt.millisecondsSinceEpoch,
      'created_at': c.createdAt.millisecondsSinceEpoch,
      'archived': _b(c.archived),
      'deleted_at': _ms(c.deletedAt),
      'space_id': c.spaceId,
      'pinned': _b(c.pinned),
      'url': c.url,
      'body': jsonEncode(c.toJson()),
    };

Map<String, Object?> bookRow(Book b) => {
      'id': b.id,
      'updated_at': b.updatedAt.millisecondsSinceEpoch,
      'created_at': b.createdAt.millisecondsSinceEpoch,
      'archived': _b(b.archived),
      'deleted_at': _ms(b.deletedAt),
      'title': b.title,
      'body': jsonEncode(b.toJson()),
    };

Map<String, Object?> impulseRow(Impulse i) => {
      'id': i.id,
      'updated_at': i.updatedAt.millisecondsSinceEpoch,
      'created_at': i.createdAt.millisecondsSinceEpoch,
      'archived': _b(i.archived),
      'deleted_at': _ms(i.deletedAt),
      'paused': _b(i.paused),
      'category': i.category,
      'body': jsonEncode(i.toJson()),
    };

Map<String, Object?> spaceRow(Space s) => {
      'id': s.id,
      'updated_at': s.updatedAt.millisecondsSinceEpoch,
      'created_at': s.createdAt.millisecondsSinceEpoch,
      'archived': _b(s.archived),
      'deleted_at': _ms(s.deletedAt),
      'name': s.name,
      'body': jsonEncode(s.toJson()),
    };

/// What the full-text index holds for one note or card: a title and a body of
/// plain text, tokenised by SQLite. Tags ride along in the body so a `#tag`
/// query finds them.
typedef SearchDoc = ({String kind, String title, String body});

SearchDoc noteSearchDoc(Note n) => (
      kind: 'note',
      title: n.title,
      body: n.tags.isEmpty
          ? n.textPreview
          : '${n.textPreview}\n${n.tags.join(' ')}',
    );

SearchDoc cardSearchDoc(TweetCard c) => (
      kind: 'card',
      title: '${c.noteTitle} ${c.authorName}'.trim(),
      body: [c.text, c.authorHandle, c.siteName, c.url, c.blocks
            .where((b) => b.isText)
            .map((b) => richToPlain(b.text))
            .join(' ')]
          .where((s) => s.isNotEmpty)
          .join('\n'),
    );

/// Decodes an entity back from its row `body` — the columns are only for
/// querying, never the source of truth for reconstruction.
Map<String, dynamic> _body(Map<String, Object?> row) =>
    jsonDecode(row['body'] as String) as Map<String, dynamic>;

/// [AppData] -> rows. Nothing is dropped: every entity keeps its full JSON in
/// the `body` column.
AppSnapshot snapshotFromAppData(AppData data) => AppSnapshot(
      notes: [for (final n in data.notes) noteRow(n)],
      cards: [for (final c in data.cards) cardRow(c)],
      books: [for (final b in data.books) bookRow(b)],
      impulses: [for (final i in data.impulses) impulseRow(i)],
      spaces: [for (final s in data.spaces) spaceRow(s)],
      settings: data
          .settingsToJson()
          .map((k, v) => MapEntry(k, jsonEncode(v))),
    );

/// rows -> [AppData]. Entities come from each row's `body`; settings from the
/// decoded key/value map.
AppData appDataFromSnapshot(AppSnapshot snap) {
  final settings = <String, dynamic>{
    for (final e in snap.settings.entries) e.key: jsonDecode(e.value),
  };
  return AppData.fromJson(
    settings,
    notesOverride: [for (final r in snap.notes) Note.fromJson(_body(r))],
    cardsOverride: [for (final r in snap.cards) TweetCard.fromJson(_body(r))],
    booksOverride: [for (final r in snap.books) Book.fromJson(_body(r))],
    impulsesOverride: [
      for (final r in snap.impulses) Impulse.fromJson(_body(r))
    ],
    spacesOverride: [for (final r in snap.spaces) Space.fromJson(_body(r))],
  );
}

/// The result of checking an import: whether counts line up, and a summary.
class ImportVerification {
  const ImportVerification(this.ok, this.summary);
  final bool ok;
  final String summary;
}

/// Confirms a snapshot has exactly one row per source entity and one settings
/// key per source setting. Used by the importer to refuse to trust a partial
/// import.
ImportVerification verifySnapshot(AppData source, AppSnapshot snap) {
  final checks = <String, bool>{
    'notes': snap.notes.length == source.notes.length,
    'cards': snap.cards.length == source.cards.length,
    'books': snap.books.length == source.books.length,
    'impulses': snap.impulses.length == source.impulses.length,
    'spaces': snap.spaces.length == source.spaces.length,
    'settings': snap.settings.length == source.settingsToJson().length,
  };
  final ok = checks.values.every((v) => v);
  final summary = checks.entries
      .map((e) => '${e.key}:${e.value ? "ok" : "MISMATCH"}')
      .join(' ');
  return ImportVerification(ok, summary);
}
