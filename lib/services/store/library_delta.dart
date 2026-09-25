import '../db/db_snapshot.dart';

/// One changed row: the full row map for an insert/update, or null for a hard
/// delete (the row is gone). [table] is one of the entity tables (`notes`,
/// `cards`, `books`, `impulses`, `spaces`).
typedef RowChange = ({String table, String id, Map<String, Object?>? row});

/// The unit of change between two views of the library: changed rows plus
/// changed settings (key -> JSON-encoded value). Written to SQLite by the
/// phone, to IndexedDB by the browser, and sent over the wire in remote mode.
class LibraryDelta {
  const LibraryDelta({this.rows = const [], this.settings = const {}});

  final List<RowChange> rows;
  final Map<String, String> settings;

  bool get isEmpty => rows.isEmpty && settings.isEmpty;

  static const empty = LibraryDelta();

  Map<String, Object?> toJson() => {
        'rows': [
          for (final r in rows) {'t': r.table, 'id': r.id, 'row': r.row},
        ],
        'settings': settings,
      };

  factory LibraryDelta.fromJson(Map<String, dynamic> json) => LibraryDelta(
        rows: [
          for (final r in (json['rows'] as List? ?? const []))
            (
              table: (r as Map)['t'] as String,
              id: r['id'] as String,
              row: (r['row'] as Map?)?.cast<String, Object?>(),
            ),
        ],
        settings: ((json['settings'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
      );

  /// The whole [snap] as a delta (every row an upsert) — a full snapshot on
  /// the wire uses the same shape as an incremental change.
  factory LibraryDelta.ofSnapshot(AppSnapshot snap) => LibraryDelta(
        rows: [
          for (final (table, rows) in SnapshotDiffer.tablesOf(snap))
            for (final row in rows)
              (table: table, id: row['id'] as String, row: row),
        ],
        settings: Map.of(snap.settings),
      );

  /// Rows back into a snapshot (upserts only; deletes are dropped).
  AppSnapshot toSnapshot() {
    final by = <String, List<Map<String, Object?>>>{
      for (final t in SnapshotDiffer.tables) t: [],
    };
    for (final r in rows) {
      final row = r.row;
      if (row != null) by[r.table]?.add(row);
    }
    return AppSnapshot(
      notes: by['notes']!,
      cards: by['cards']!,
      books: by['books']!,
      impulses: by['impulses']!,
      spaces: by['spaces']!,
      settings: Map.of(settings),
    );
  }
}

/// Remembers what a store last held — `"<table>:<id>" -> row body` plus the
/// settings map — so each save can compute only what changed. Pure: no I/O,
/// no engine. The phone's SQLite store, the browser's IndexedDB store and the
/// remote-mode wire all diff through one of these.
class SnapshotDiffer {
  final Map<String, ({String table, String body})> _baseline = {};
  final Map<String, String> _settings = {};

  static const tables = ['notes', 'cards', 'books', 'impulses', 'spaces'];

  static List<(String, List<Map<String, Object?>>)> tablesOf(AppSnapshot s) =>
      [
        ('notes', s.notes),
        ('cards', s.cards),
        ('books', s.books),
        ('impulses', s.impulses),
        ('spaces', s.spaces),
      ];

  static String _key(String table, String id) => '$table:$id';

  /// Forgets everything and takes [snap] as what the store now holds.
  void reseed(AppSnapshot snap) {
    _baseline.clear();
    for (final (table, rows) in tablesOf(snap)) {
      for (final row in rows) {
        _baseline[_key(table, row['id'] as String)] =
            (table: table, body: row['body'] as String);
      }
    }
    _settings
      ..clear()
      ..addAll(snap.settings);
  }

  /// What must change for the store to hold [snap]: rows added or whose body
  /// changed, rows that vanished (hard deletes), and changed settings keys.
  /// Settings keys absent from [snap] are left alone (never deleted).
  LibraryDelta diff(AppSnapshot snap) {
    final rows = <RowChange>[];
    final seen = <String>{};
    for (final (table, list) in tablesOf(snap)) {
      for (final row in list) {
        final id = row['id'] as String;
        final key = _key(table, id);
        seen.add(key);
        final base = _baseline[key];
        if (base == null || base.body != row['body']) {
          rows.add((table: table, id: id, row: row));
        }
      }
    }
    _baseline.forEach((key, v) {
      if (!seen.contains(key)) {
        rows.add(
            (table: v.table, id: key.substring(v.table.length + 1), row: null));
      }
    });
    final settings = <String, String>{};
    snap.settings.forEach((k, v) {
      if (_settings[k] != v) settings[k] = v;
    });
    return LibraryDelta(rows: rows, settings: settings);
  }

  /// Records that [delta] has landed in the store.
  void commit(LibraryDelta delta) {
    for (final r in delta.rows) {
      final key = _key(r.table, r.id);
      final row = r.row;
      if (row == null) {
        _baseline.remove(key);
      } else {
        _baseline[key] = (table: r.table, body: row['body'] as String);
      }
    }
    _settings.addAll(delta.settings);
  }

  bool holds(String table, String id) => _baseline.containsKey(_key(table, id));

  int get rowCount => _baseline.length;
}
