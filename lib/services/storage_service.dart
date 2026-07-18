import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';

/// Handles all on-device persistence: a single JSON file for metadata plus an
/// images folder for copied note/space pictures.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _uuid = Uuid();

  Directory? _docs;
  Directory? _imagesDir;

  Future<Directory> get _docsDir async {
    return _docs ??= await getApplicationDocumentsDirectory();
  }

  Future<File> get _dataFile async {
    final dir = await _docsDir;
    return File('${dir.path}/keepy_data.json');
  }

  Future<File> get _bakFile async {
    final dir = await _docsDir;
    return File('${dir.path}/keepy_data.bak');
  }

  /// One-file-per-share inbox written by the share popup's engine and drained
  /// by the main app — no two processes ever write the same file.
  Future<Directory> get _inboxDir async {
    final dir = await _docsDir;
    final inbox = Directory('${dir.path}/share_inbox');
    if (!await inbox.exists()) await inbox.create(recursive: true);
    return inbox;
  }

  Future<Directory> get imagesDir async {
    if (_imagesDir != null) return _imagesDir!;
    final dir = await _docsDir;
    final imgs = Directory('${dir.path}/images');
    if (!await imgs.exists()) {
      await imgs.create(recursive: true);
    }
    return _imagesDir = imgs;
  }

  /// Copies a picked image into the app's images folder and returns the new
  /// absolute path so deleting the original source won't break the note.
  Future<String> saveImage(String sourcePath) async {
    final dir = await imagesDir;
    final ext = sourcePath.contains('.')
        ? sourcePath.substring(sourcePath.lastIndexOf('.'))
        : '.jpg';
    final dest = '${dir.path}/${_uuid.v4()}$ext';
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<void> deleteImage(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort; ignore failures.
    }
  }

  Future<AppData> load() async {
    // Try the main file, then the last-good backup: a torn write must never
    // silently erase the library (the next save would overwrite it with
    // nothing).
    final data = await _tryLoad(await _dataFile) ??
        await _tryLoad(await _bakFile);
    return data ?? AppData.empty();
  }

  Future<AppData?> _tryLoad(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      // Decode off the UI isolate: a large library shouldn't stall startup.
      final json =
          await Isolate.run(() => jsonDecode(raw) as Map<String, dynamic>);
      return AppData(
        notes: ((json['notes'] as List?) ?? [])
            .map((e) => Note.fromJson(e as Map<String, dynamic>))
            .toList(),
        spaces: ((json['spaces'] as List?) ?? [])
            .map((e) => Space.fromJson(e as Map<String, dynamic>))
            .toList(),
        cards: ((json['cards'] as List?) ?? [])
            .map((e) => TweetCard.fromJson(e as Map<String, dynamic>))
            .toList(),
        cardsCompact: (json['cardsCompact'] as bool?) ?? false,
        darkMode: (json['darkMode'] as bool?) ?? false,
        darkFollowSystem: (json['darkFollowSystem'] as bool?) ?? true,
        tutorialSeen: (json['tutorialSeen'] as bool?) ?? false,
        lastBackupAt:
            DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
        backupReminderDismissedAt: DateTime.tryParse(
            json['backupReminderDismissedAt'] as String? ?? ''),
        sortMode: (json['sortMode'] as String?) ?? 'recent',
        feedWallpaper: (json['feedWallpaper'] as num?)?.toInt() ?? 0,
        journalMonthCovers:
            ((json['journalMonthCovers'] as Map?) ?? const {})
                .map((k, v) => MapEntry(k.toString(), v.toString())),
      );
    } catch (_) {
      return null;
    }
  }

  /// Atomic save: write to a temp file, demote the current file to .bak, then
  /// rename the temp into place. A crash at any point leaves either the old
  /// file or the .bak intact.
  ///
  /// The expensive part — jsonEncode of the whole library + the write — runs
  /// on a background isolate so keystroke-time saves never touch a UI frame.
  Future<void> save(AppData data) async {
    final file = await _dataFile;
    final bak = await _bakFile;
    // Build the plain map on this isolate (cheap); ship it across.
    final json = {
      'notes': data.notes.map((n) => n.toJson()).toList(),
      'spaces': data.spaces.map((s) => s.toJson()).toList(),
      'cards': data.cards.map((c) => c.toJson()).toList(),
      'cardsCompact': data.cardsCompact,
      'darkMode': data.darkMode,
      'darkFollowSystem': data.darkFollowSystem,
      'tutorialSeen': data.tutorialSeen,
      'lastBackupAt': data.lastBackupAt?.toIso8601String(),
      'backupReminderDismissedAt':
          data.backupReminderDismissedAt?.toIso8601String(),
      'sortMode': data.sortMode,
      'feedWallpaper': data.feedWallpaper,
      'journalMonthCovers': data.journalMonthCovers,
    };
    final filePath = file.path;
    final bakPath = bak.path;
    await Isolate.run(() {
      final tmp = File('$filePath.tmp');
      tmp.writeAsStringSync(jsonEncode(json), flush: true);
      final f = File(filePath);
      if (f.existsSync()) {
        try {
          final b = File(bakPath);
          if (b.existsSync()) b.deleteSync();
          f.renameSync(bakPath);
        } catch (_) {
          // Keeping the .bak fresh is best-effort; the tmp rename below is
          // what guarantees integrity.
        }
      }
      tmp.renameSync(filePath);
    });
  }

  // ---- Share inbox ---------------------------------------------------------

  /// Writes one pending share as its own uniquely-named file (used by the
  /// popup engine, so it never contends with the main app's data file).
  Future<void> saveShareInbox(Map<String, dynamic> record) async {
    final inbox = await _inboxDir;
    final f = File('${inbox.path}/${_uuid.v4()}.json');
    await f.writeAsString(jsonEncode(record), flush: true);
  }

  /// Reads and removes all pending shares.
  Future<List<Map<String, dynamic>>> drainShareInbox() async {
    final inbox = await _inboxDir;
    final records = <Map<String, dynamic>>[];
    for (final entity in inbox.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        records.add(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Unreadable record: drop it rather than blocking the inbox.
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
    return records;
  }
}

class AppData {
  AppData({
    required this.notes,
    required this.spaces,
    required this.cards,
    this.cardsCompact = false,
    this.darkMode = false,
    this.darkFollowSystem = true,
    this.tutorialSeen = false,
    this.lastBackupAt,
    this.backupReminderDismissedAt,
    this.sortMode = 'recent',
    this.feedWallpaper = 0,
    Map<String, String>? journalMonthCovers,
  }) : journalMonthCovers = journalMonthCovers ?? {};
  factory AppData.empty() => AppData(notes: [], spaces: [], cards: []);

  final List<Note> notes;
  final List<Space> spaces;
  final List<TweetCard> cards;

  /// Cards feed view preference: false = Open (full cards), true = Blocks.
  bool cardsCompact;

  /// Dark theme preference (manual override).
  bool darkMode;

  /// When true, dark mode follows the system setting.
  bool darkFollowSystem;

  /// Whether the first-launch tutorial has been shown.
  bool tutorialSeen;

  /// When the user last exported a backup (null = never).
  DateTime? lastBackupAt;

  /// When the backup nudge was last cross-dismissed (snoozes it a week).
  DateTime? backupReminderDismissedAt;

  /// Feed sort order name (see NoteSort).
  String sortMode;

  /// Which bundled feed wallpaper is active (index into kFeedWallpapers).
  int feedWallpaper;

  /// User-chosen cover image per journal month, keyed 'yyyy-MM'.
  Map<String, String> journalMonthCovers;
}
