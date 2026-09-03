// Regenerates the committed demo library file at test_data/braim_demo.json.
//
//   dart run tool/gen_seed.dart
//
// This is the same content the in-app "Load sample data" button adds (both
// come from SeedData.build). The file is a plain data.json — the format the
// app stores on device — so it can be dropped straight into an emulator's app
// storage (adb + run-as) to reseed after a wipe, without any UI steps.
import 'dart:convert';
import 'dart:io';

import 'package:braim/services/seed_data.dart';

void main() {
  final b = SeedData.build();
  final map = <String, dynamic>{
    'notes': b.notes.map((n) => n.toJson()).toList(),
    'spaces': b.spaces.map((s) => s.toJson()).toList(),
    'cards': b.cards.map((c) => c.toJson()).toList(),
    'books': b.books.map((bk) => bk.toJson()).toList(),
    'cardsCompact': false,
    'darkMode': false,
    'darkFollowSystem': true,
    // Pre-seen so a ready-made library doesn't relaunch the first-run tutorial.
    'tutorialSeen': true,
    'lastBackupAt': null,
    'backupReminderDismissedAt': null,
    'sortMode': 'recent',
    'feedWallpaper': 0,
    'readerFontScale': 1.0,
    'readerFont': 'Lora',
    'readerTheme': 'original',
    'journalMonthCovers': <String, String>{},
    'readerPositions': <String, double>{},
    'readerBookmarks': <String, List<double>>{},
  };

  final out = File('test_data/braim_demo.json');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(map));
  stdout.writeln(
      'Wrote ${out.path} — ${b.notes.length} notes, ${b.spaces.length} folders, '
      '${b.cards.length} cards, ${b.books.length} book.');
}
