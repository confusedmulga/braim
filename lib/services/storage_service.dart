import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/impulse.dart';
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
        books: ((json['books'] as List?) ?? [])
            .map((e) => Book.fromJson(e as Map<String, dynamic>))
            .toList(),
        impulses: ((json['impulses'] as List?) ?? [])
            .map((e) => Impulse.fromJson(e as Map<String, dynamic>))
            .toList(),
        cardsCompact: (json['cardsCompact'] as bool?) ?? false,
        darkMode: (json['darkMode'] as bool?) ?? false,
        darkFollowSystem: (json['darkFollowSystem'] as bool?) ?? true,
        noteBodyFont: (json['noteBodyFont'] as String?) ?? 'Caveat',
        tutorialSeen: (json['tutorialSeen'] as bool?) ?? false,
        lastBackupAt:
            DateTime.tryParse(json['lastBackupAt'] as String? ?? ''),
        backupReminderDismissedAt: DateTime.tryParse(
            json['backupReminderDismissedAt'] as String? ?? ''),
        driveAutoBackup: (json['driveAutoBackup'] as bool?) ?? false,
        lastDriveBackupAt:
            DateTime.tryParse(json['lastDriveBackupAt'] as String? ?? ''),
        driveAccountEmail: json['driveAccountEmail'] as String?,
        sortMode: (json['sortMode'] as String?) ?? 'recent',
        feedWallpaper: (json['feedWallpaper'] as num?)?.toInt() ?? 0,
        feedBackgroundPath: (json['feedBackgroundPath'] as String?) ?? '',
        feedBackgroundLight: (json['feedBackgroundLight'] as String?) ?? '',
        feedBackgroundDark: (json['feedBackgroundDark'] as String?) ?? '',
        readerFontScale:
            (json['readerFontScale'] as num?)?.toDouble() ?? 1.0,
        readerFont: (json['readerFont'] as String?) ?? 'Lora',
        readerTheme: (json['readerTheme'] as String?) ?? 'original',
        journalMonthCovers:
            ((json['journalMonthCovers'] as Map?) ?? const {})
                .map((k, v) => MapEntry(k.toString(), v.toString())),
        journalReminderOn: (json['journalReminderOn'] as bool?) ?? false,
        journalReminderMinutes:
            (json['journalReminderMinutes'] as num?)?.toInt() ?? 21 * 60,
        pinnedReflexId:
            (json['pinnedReflexId'] as String?) ?? '__daily_day__',
        progressImpulseId:
            (json['progressImpulseId'] as String?) ?? '__daily_day__',
        journalPaneOpen: (json['journalPaneOpen'] as bool?) ?? false,
        cortexPaneOpen: (json['cortexPaneOpen'] as bool?) ?? false,
        progressShowAll: (json['progressShowAll'] as bool?) ?? false,
        typingMillis: (json['typingMillis'] as num?)?.toInt() ?? 0,
        journalOrder: (json['journalOrder'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        readerPositions: ((json['readerPositions'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        readerBookmarks: ((json['readerBookmarks'] as Map?) ?? const {}).map(
            (k, v) => MapEntry(
                k.toString(),
                ((v as List?) ?? const [])
                    .map((e) => (e as num).toDouble())
                    .toList())),
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
  // Serializes saves process-wide: two writers sharing the temp file used to
  // race and corrupt the write (an "access denied" rename on Windows).
  static Future<void> _writeLock = Future.value();

  Future<void> save(AppData data) async {
    final previous = _writeLock;
    final done = Completer<void>();
    _writeLock = done.future;
    await previous.catchError((_) {});
    try {
      await _save(data);
    } finally {
      done.complete();
    }
  }

  Future<void> _save(AppData data) async {
    final file = await _dataFile;
    final bak = await _bakFile;
    // Build the plain map on this isolate (cheap); ship it across.
    final json = {
      'notes': data.notes.map((n) => n.toJson()).toList(),
      'spaces': data.spaces.map((s) => s.toJson()).toList(),
      'cards': data.cards.map((c) => c.toJson()).toList(),
      'books': data.books.map((b) => b.toJson()).toList(),
      'impulses': data.impulses.map((i) => i.toJson()).toList(),
      'cardsCompact': data.cardsCompact,
      'darkMode': data.darkMode,
      'darkFollowSystem': data.darkFollowSystem,
      'noteBodyFont': data.noteBodyFont,
      'tutorialSeen': data.tutorialSeen,
      'lastBackupAt': data.lastBackupAt?.toIso8601String(),
      'backupReminderDismissedAt':
          data.backupReminderDismissedAt?.toIso8601String(),
      'driveAutoBackup': data.driveAutoBackup,
      'lastDriveBackupAt': data.lastDriveBackupAt?.toIso8601String(),
      'driveAccountEmail': data.driveAccountEmail,
      'sortMode': data.sortMode,
      'feedWallpaper': data.feedWallpaper,
      'feedBackgroundPath': data.feedBackgroundPath,
      'feedBackgroundLight': data.feedBackgroundLight,
      'feedBackgroundDark': data.feedBackgroundDark,
      'readerFontScale': data.readerFontScale,
      'readerFont': data.readerFont,
      'readerTheme': data.readerTheme,
      'journalMonthCovers': data.journalMonthCovers,
      'journalReminderOn': data.journalReminderOn,
      'journalReminderMinutes': data.journalReminderMinutes,
      'pinnedReflexId': data.pinnedReflexId,
      'progressImpulseId': data.progressImpulseId,
      'journalPaneOpen': data.journalPaneOpen,
      'cortexPaneOpen': data.cortexPaneOpen,
      'progressShowAll': data.progressShowAll,
      'typingMillis': data.typingMillis,
      'journalOrder': data.journalOrder,
      'readerPositions': data.readerPositions,
      'readerBookmarks': data.readerBookmarks,
    };
    final filePath = file.path;
    final bakPath = bak.path;
    // A unique temp name so overlapping writers can never share a scratch file.
    final tmpPath = '$filePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
    await Isolate.run(() {
      final tmp = File(tmpPath);
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
      // Windows can't rename onto an existing file: clear it first (the .bak
      // above is the safety net), then fall back to copy if rename still trips.
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      try {
        tmp.renameSync(filePath);
      } catch (_) {
        // Rename lost a race (the destination is momentarily locked — happens
        // when a stray reader/writer overlaps, e.g. late timers in tests).
        // Copy as a fallback, and treat even that as best-effort: the .bak
        // written above keeps the library intact if this write can't land.
        try {
          tmp.copySync(filePath);
        } catch (_) {}
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
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
    List<Book>? books,
    List<Impulse>? impulses,
    this.cardsCompact = false,
    this.darkMode = false,
    this.darkFollowSystem = true,
    this.tutorialSeen = false,
    this.lastBackupAt,
    this.backupReminderDismissedAt,
    this.driveAutoBackup = false,
    this.lastDriveBackupAt,
    this.driveAccountEmail,
    this.sortMode = 'recent',
    this.feedWallpaper = 0,
    this.feedBackgroundPath = '',
    this.feedBackgroundLight = '',
    this.feedBackgroundDark = '',
    this.readerFontScale = 1.0,
    this.readerFont = 'Lora',
    this.readerTheme = 'original',
    this.journalReminderOn = false,
    this.journalReminderMinutes = 21 * 60,
    this.noteBodyFont = 'Caveat',
    this.pinnedReflexId = '__daily_day__',
    this.progressImpulseId = '__daily_day__',
    this.journalPaneOpen = false,
    this.cortexPaneOpen = false,
    this.progressShowAll = false,
    this.typingMillis = 0,
    List<String>? journalOrder,
    Map<String, String>? journalMonthCovers,
    Map<String, double>? readerPositions,
    Map<String, List<double>>? readerBookmarks,
  })  : books = books ?? [],
        impulses = impulses ?? [],
        journalOrder = journalOrder ?? const ['tasks', 'card', 'entries'],
        journalMonthCovers = journalMonthCovers ?? {},
        readerPositions = readerPositions ?? {},
        readerBookmarks = readerBookmarks ?? {};
  factory AppData.empty() => AppData(notes: [], spaces: [], cards: []);

  final List<Note> notes;
  final List<Space> spaces;
  final List<TweetCard> cards;
  final List<Book> books;
  final List<Impulse> impulses;

  /// Cards feed view preference: false = Open (full cards), true = Blocks.
  bool cardsCompact;

  /// Dark theme preference (manual override).
  bool darkMode;

  /// When true, dark mode follows the system setting.
  bool darkFollowSystem;

  /// The font family used for node & spark body text.
  String noteBodyFont;

  /// Whether the first-launch tutorial has been shown.
  bool tutorialSeen;

  /// When the user last exported a backup (null = never).
  DateTime? lastBackupAt;

  /// When the backup nudge was last cross-dismissed (snoozes it a week).
  DateTime? backupReminderDismissedAt;

  /// Whether automatic Google Drive backup is enabled.
  bool driveAutoBackup;

  /// When the last successful Google Drive backup completed (null = never).
  DateTime? lastDriveBackupAt;

  /// The connected Google account email for Drive backup (null = not connected).
  String? driveAccountEmail;

  /// Feed sort order name (see NoteSort).
  String sortMode;

  /// Which bundled feed wallpaper is active (index into kFeedWallpapers).
  int feedWallpaper;

  /// A legacy single feed-background image path (migrated into light/dark).
  String feedBackgroundPath;

  /// User-chosen feed backgrounds per theme (empty = built-in wallpaper).
  String feedBackgroundLight;
  String feedBackgroundDark;

  /// Book reader typography and theme.
  double readerFontScale;
  String readerFont;
  String readerTheme;

  /// The nightly "write in your journal" nudge: whether it's on, and the time
  /// of day to fire it, as minutes since midnight (default 21:00).
  bool journalReminderOn;
  int journalReminderMinutes;

  /// The reflex pinned into the journal feed (its threads show below the week
  /// strip). Defaults to the daily day.
  String pinnedReflexId;

  /// The impulse tracked by the green "Today's progress" card. Defaults to the
  /// daily day.
  String progressImpulseId;

  /// Whether the side pane's Journal / Cortex groups are expanded.
  bool journalPaneOpen;
  bool cortexPaneOpen;

  /// Whether the green progress card aggregates all reflexes.
  bool progressShowAll;

  /// Cumulative active-typing time in milliseconds (analytics).
  int typingMillis;

  /// The order of the journal's three movable sections: 'tasks' (daily-day
  /// threads), 'card' (the reflex date card), 'entries' (diary entries).
  List<String> journalOrder;

  /// User-chosen cover image per journal month, keyed 'yyyy-MM'.
  Map<String, String> journalMonthCovers;

  /// Last read position per book, as a 0–1 fraction of the scroll extent.
  Map<String, double> readerPositions;

  /// Reader bookmarks per book, each a 0–1 fraction of the scroll extent.
  Map<String, List<double>> readerBookmarks;
}
