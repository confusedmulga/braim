import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/impulse.dart';
import 'package:braim/services/db/db_snapshot.dart';
import 'package:braim/services/seed_data.dart';
import 'package:braim/services/storage_service.dart';

/// A full library: the demo seed (spaces/notes/cards/books) plus a nested
/// impulse and a spread of non-default settings, so the round-trip touches
/// every entity type and every settings field.
AppData _fullLibrary() {
  final bundle = SeedData.build();
  final impulse = Impulse(
    title: 'Ship the app',
    goal: 'Reach the store',
    mode: ImpulseMode.longTerm,
    category: 'Work',
    days: {1, 3, 5},
    threads: [
      Thread(title: 'Daily reminder', once: false, days: {1, 2}),
      Thread(title: 'One-off', once: true, doneDays: {'2026-01-01'}),
    ],
    sections: [
      Section(title: 'Year 1', subsections: [
        Subsection(title: 'Math', threads: [Thread(title: 'Calculus')]),
      ]),
    ],
    paused: true,
  );
  return AppData(
    notes: bundle.notes,
    spaces: bundle.spaces,
    cards: bundle.cards,
    books: bundle.books,
    impulses: [impulse],
    darkMode: true,
    darkFollowSystem: false,
    noteBodyFont: 'Lora',
    typingMillis: 123456,
    readerTheme: 'calm',
    readerBookmarks: {
      'book-1': [0.1, 0.5, 0.9]
    },
    readerPositions: {'book-1': 0.42},
    journalMonthCovers: {'2026-01': '/img/jan.jpg'},
    journalOrder: ['card', 'tasks', 'entries'],
    feedBackgroundDark: '/img/dark.jpg',
  );
}

void main() {
  group('AppData <-> AppSnapshot', () {
    test('round-trips a full library without losing anything', () {
      final data = _fullLibrary();
      final snap = snapshotFromAppData(data);
      final back = appDataFromSnapshot(snap);

      // Deep equality via the canonical JSON of the whole library.
      expect(jsonEncode(back.toJson()), jsonEncode(data.toJson()));
    });

    test('preserves every entity and setting (count check passes)', () {
      final data = _fullLibrary();
      final snap = snapshotFromAppData(data);
      final v = verifySnapshot(data, snap);
      expect(v.ok, isTrue, reason: v.summary);
      expect(snap.notes.length, data.notes.length);
      expect(snap.impulses.length, 1);
      expect(snap.settings.length, data.settingsToJson().length);
    });

    test('is idempotent: re-snapshotting the decoded data is identical', () {
      final data = _fullLibrary();
      final once = snapshotFromAppData(data);
      final twice = snapshotFromAppData(appDataFromSnapshot(once));
      expect(jsonEncode(twice.notes), jsonEncode(once.notes));
      expect(jsonEncode(twice.settings), jsonEncode(once.settings));
    });

    test('a dropped row fails verification (guards partial imports)', () {
      final data = _fullLibrary();
      final snap = snapshotFromAppData(data);
      final short = AppSnapshot(
        notes: snap.notes.sublist(0, snap.notes.length - 1),
        cards: snap.cards,
        books: snap.books,
        impulses: snap.impulses,
        spaces: snap.spaces,
        settings: snap.settings,
      );
      expect(verifySnapshot(data, short).ok, isFalse);
    });

    test('entity rows carry queryable columns alongside the body', () {
      final data = _fullLibrary();
      final snap = snapshotFromAppData(data);
      final row = snap.notes.first;
      expect(row['id'], isNotNull);
      expect(row['updated_at'], isA<int>());
      expect(row['body'], isA<String>());
      // A book page note carries its book_id column for filtering.
      final page = snap.notes.firstWhere((r) => r['book_id'] != null,
          orElse: () => const {});
      if (page.isNotEmpty) {
        expect(page['book_page_kind'], isNotNull);
      }
    });
  });
}
