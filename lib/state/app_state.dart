import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/annotation.dart';
import '../models/book.dart';
import '../models/impulse.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';
import '../services/backup_service.dart';
import '../services/book_text_ops.dart';
import '../services/drive_backup_service.dart';
import '../services/link_preview_service.dart';
import '../services/youtube_service.dart';
import '../services/note_markdown.dart';
import '../services/notification_service.dart';
import '../services/seed_data.dart';
import '../services/db/db_store.dart';
import '../services/storage_service.dart';
import '../services/wiki_links.dart';
import '../theme/app_theme.dart';

/// Reserved space id for the locked Crypt folder.
const String kCryptSpaceId = '__crypt__';

/// How long deleted notes stay in Recently Deleted before being purged.
const Duration kTrashRetention = Duration(days: 30);

/// Maximum pinned items per feed (notes and cards each).
const int kMaxPins = 10;

/// Feed sort order chosen by the user; applies to the notes and cards
/// feeds (pinned items always stay on top).
enum NoteSort { recent, oldest, azTitle, zaTitle }

/// A reflex's completion streak: the [current] run of complete days and the
/// [best] ever, counted over its scheduled days.
class ReflexStreak {
  const ReflexStreak(this.current, this.best);
  final int current;
  final int best;
}

/// Today's aggregate task completion across all live reflexes.
class TodayProgress {
  const TodayProgress(this.done, this.total);
  final int done;
  final int total;

  int get pending => (total - done).clamp(0, total);
  double get fraction => total == 0 ? 0 : done / total;
}

/// A target of an `@@@` mention: an impulse (project) or one of its threads.
/// [parent] is the impulse title for a thread (null for an impulse itself).
class MentionTarget {
  const MentionTarget({
    required this.label,
    required this.impulseId,
    required this.threadId,
    this.parent,
  });

  final String label;
  final String impulseId;
  final String? threadId;
  final String? parent;

  bool get isThread => threadId != null;
}

class AppState extends ChangeNotifier {
  /// [dbStore] lets tests hand in a store on an FFI / temp-file database; the
  /// app uses the default (the device's `braim.db`).
  AppState({DbStore? dbStore}) : _dbStore = dbStore ?? DbStore();

  final _storage = StorageService.instance;

  /// SQLite store of the library (migration Phase 2): the app loads from here at
  /// startup and mirrors every save into it, while the JSON file is still
  /// written alongside as a belt-and-suspenders copy and the instant-revert
  /// path. Disabled where sqflite is unavailable (unit tests), where the app
  /// simply stays on the JSON store.
  final DbStore _dbStore;
  final _linkPreview = LinkPreviewService();

  final List<Note> _notes = [];
  final List<Space> _spaces = [];
  final List<TweetCard> _cards = [];
  final List<Book> _books = [];
  final List<Impulse> _impulses = [];
  String _pinnedReflexId = dailyDayId;
  String _progressImpulseId = dailyDayId;
  bool _progressShowAll = false;
  bool _journalPaneOpen = false;
  bool _cortexPaneOpen = false;
  List<String> _journalOrder = const ['tasks', 'card', 'entries'];

  bool _loaded = false;
  bool get loaded => _loaded;

  // ---- Account (local-only build) -----------------------------------------
  //
  // Firebase sync was removed, so the library lives entirely on-device. The
  // account getters stay null for now (article bylines fall back to a plain
  // name); they'll be fed by the connected Google account once automated
  // Google Drive backup lands.

  String? get accountEmail => null;
  String? get accountName => null;
  String? get accountPhotoUrl => null;

  // These were the per-document cloud-write hooks. They're kept as no-ops so
  // the many mutation sites stay untouched — a local build simply persists the
  // whole library through _persist().

  /// Cards feed view: false = Open (full cards), true = Blocks (compact grid).
  bool _cardsCompact = false;
  bool get cardsCompact => _cardsCompact;

  Future<void> setCardsCompact(bool value) async {
    _cardsCompact = value;
    await _persist();
  }

  /// Feed sort order (notes + cards). Pinned items still lead.
  NoteSort _sortMode = NoteSort.recent;
  NoteSort get sortMode => _sortMode;

  Future<void> setSortMode(NoteSort value) async {
    if (value == _sortMode) return;
    _sortMode = value;
    await _persist(); // bumps _rev, so the memoized feeds re-sort
  }

  static NoteSort _sortFromName(String s) => NoteSort.values
      .firstWhere((e) => e.name == s, orElse: () => NoteSort.recent);

  /// The tag the Home feed is filtered to, or null for everything. A transient
  /// view filter (not persisted) set from the sort sheet or the side pane.
  String? _activeTag;
  String? get activeTag => _activeTag;

  void setActiveTag(String? tag) {
    if (_activeTag == tag) return;
    _activeTag = tag;
    _rev++; // invalidate the memoized feed so it re-filters
    notifyListeners();
  }

  /// Every tag in use across the live (non-archived, non-deleted) feed notes,
  /// de-duplicated and sorted alphabetically. Drives the tag pickers.
  List<String> get allTags {
    final set = <String>{};
    for (final n in _notes) {
      if (_isFeedNote(n)) set.addAll(n.tags);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// User-chosen journal month covers, keyed 'yyyy-MM'.
  final Map<String, String> _journalMonthCovers = {};

  /// Which bundled feed wallpaper is active (index into kFeedWallpapers).
  int _feedWallpaper = 0;
  int get feedWallpaper => _feedWallpaper;

  Future<void> setFeedWallpaper(int index) async {
    if (index == _feedWallpaper) return;
    _feedWallpaper = index;
    await _persist();
  }

  /// User-chosen feed backgrounds, one per theme (saved image paths). Empty
  /// means the built-in wallpaper for that mode (what "Reset" restores).
  String _feedBackgroundLight = '';
  String _feedBackgroundDark = '';
  String get feedBackgroundLight => _feedBackgroundLight;
  String get feedBackgroundDark => _feedBackgroundDark;

  /// The custom background for the active theme, or '' to use the built-in one.
  String get feedBackgroundForTheme =>
      AppPalette.dark ? _feedBackgroundDark : _feedBackgroundLight;

  Future<void> setFeedBackground({
    required bool dark,
    required String path,
  }) async {
    if (dark) {
      _feedBackgroundDark = path;
    } else {
      _feedBackgroundLight = path;
    }
    await _persist();
  }

  Future<void> clearFeedBackgrounds() async {
    if (_feedBackgroundLight.isEmpty && _feedBackgroundDark.isEmpty) return;
    _feedBackgroundLight = '';
    _feedBackgroundDark = '';
    await _persist();
  }

  bool _darkMode = false;
  bool get darkMode => _darkMode;

  bool _darkFollowSystem = true;
  bool get darkFollowSystem => _darkFollowSystem;

  bool _systemDark =
      PlatformDispatcher.instance.platformBrightness == Brightness.dark;

  /// The theme actually in effect: system when following, else the manual
  /// switch.
  bool get effectiveDark => _darkFollowSystem ? _systemDark : _darkMode;

  /// Called by the shell when the platform brightness changes.
  void updateSystemBrightness() {
    final dark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    if (dark == _systemDark) return;
    _systemDark = dark;
    if (_darkFollowSystem) {
      AppPalette.dark = effectiveDark;
      notifyListeners();
    }
  }

  Future<void> setDarkFollowSystem(bool value) async {
    _darkFollowSystem = value;
    AppPalette.dark = effectiveDark;
    await _persist();
  }

  /// Sets the whole appearance preference in one persist: follow the system,
  /// or force light/dark manually.
  Future<void> setAppearance({required bool followSystem, bool dark = false}) async {
    _darkFollowSystem = followSystem;
    if (!followSystem) _darkMode = dark;
    AppPalette.dark = effectiveDark;
    await _persist();
  }

  bool _tutorialSeen = false;
  bool get tutorialSeen => _tutorialSeen;

  Future<void> setTutorialSeen() async {
    _tutorialSeen = true;
    await _persist();
  }

  /// When the user last exported a backup (null = never).
  DateTime? _lastBackupAt;
  DateTime? get lastBackupAt => _lastBackupAt;

  /// When the user last dismissed the backup nudge with the cross; the nudge
  /// stays away for a week from then (persisted across launches).
  DateTime? _backupReminderDismissedAt;

  /// Reminder threshold: nudge once a backup is this stale (or never taken).
  static const Duration _backupStaleAfter = Duration(days: 14);

  /// Dismissing the nudge snoozes it for this long.
  static const Duration _backupSnooze = Duration(days: 7);

  /// True when there is something worth losing and it hasn't been backed up
  /// recently.
  bool get backupOverdue {
    if (_notes.isEmpty && _cards.isEmpty && _spaces.isEmpty) return false;
    final last = _lastBackupAt;
    if (last == null) return true;
    return DateTime.now().difference(last) > _backupStaleAfter;
  }

  /// The feed banner: shown when a backup is overdue, at most once a week —
  /// a cross-dismiss keeps it away for the next seven days.
  bool get showBackupReminder {
    if (!backupOverdue) return false;
    final dismissed = _backupReminderDismissedAt;
    if (dismissed == null) return true;
    return DateTime.now().difference(dismissed) >= _backupSnooze;
  }

  Future<void> dismissBackupReminder() async {
    _backupReminderDismissedAt = DateTime.now();
    await _persist();
  }

  /// Records that a backup was just taken; clears the nudge.
  Future<void> markBackedUp() async {
    _lastBackupAt = DateTime.now();
    _backupReminderDismissedAt = null;
    await _persist();
  }

  // ---- On-device automatic backup -----------------------------------------

  bool _localAutoBackup = false;
  String _localAutoBackupFreq = 'weekly'; // 'daily' | 'weekly' | 'monthly'

  /// The [_rev] captured at the last local auto-backup, so a scheduled backup
  /// is skipped when nothing has changed since (in-memory, like Drive's).
  int _revAtLocalBackup = -1;

  bool get localAutoBackup => _localAutoBackup;
  String get localAutoBackupFreq => _localAutoBackupFreq;

  Future<void> setLocalAutoBackup(bool value) async {
    if (_localAutoBackup == value) return;
    _localAutoBackup = value;
    await _persist();
    notifyListeners();
  }

  Future<void> setLocalAutoBackupFreq(String value) async {
    if (_localAutoBackupFreq == value) return;
    _localAutoBackupFreq = value;
    await _persist();
    notifyListeners();
  }

  Duration get _localAutoBackupInterval => switch (_localAutoBackupFreq) {
        'daily' => const Duration(days: 1),
        'monthly' => const Duration(days: 30),
        _ => const Duration(days: 7),
      };

  /// Best-effort scheduled on-device backup, run when the app goes to the
  /// background: only if enabled, there's something to lose, the chosen interval
  /// has elapsed since the last backup, and something changed since the last one.
  /// The .zip lands in the app's Backups folder and is never auto-pruned.
  Future<void> maybeLocalAutoBackup() async {
    if (!_localAutoBackup) return;
    if (_notes.isEmpty && _cards.isEmpty && _spaces.isEmpty) return;
    if (_rev == _revAtLocalBackup) return; // nothing changed since last backup
    final last = _lastBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < _localAutoBackupInterval) {
      return;
    }
    try {
      await flushNow();
      await BackupService.instance.exportToBackupsDir();
      _lastBackupAt = DateTime.now();
      _backupReminderDismissedAt = null;
      await _persist();
      _revAtLocalBackup = _rev;
      notifyListeners();
    } catch (_) {
      // Silent: a failed background backup retries on the next pause.
    }
  }

  // ---- Google Drive backup ------------------------------------------------

  bool _driveAutoBackup = false;
  DateTime? _lastDriveBackupAt;
  String? _driveAccountEmail;
  // Display-only profile for the connected account (name + avatar). Persisted
  // (so the Settings row is populated immediately on launch) and refreshed each
  // launch via a silent auth; both fall back gracefully to the email when
  // unavailable.
  String? _driveAccountName;
  String? _driveAccountPhotoUrl;

  /// The [_rev] captured at the last Drive backup, so a background backup is
  /// skipped when nothing has changed since.
  int _revAtDriveBackup = -1;

  /// Whether a Web client ID is compiled in — i.e. Drive backup is usable.
  bool get driveConfigured => DriveBackupService.instance.isConfigured;

  /// Whether a Google account is currently connected for Drive backup.
  bool get driveConnected => _driveAccountEmail != null;
  String? get driveAccountEmail => _driveAccountEmail;
  String? get driveAccountName => _driveAccountName;
  String? get driveAccountPhotoUrl => _driveAccountPhotoUrl;

  /// Silently refreshes the connected account's name/avatar (called on startup
  /// once the persisted email says an account is connected).
  Future<void> refreshDriveAccount() async {
    if (_driveAccountEmail == null) return;
    final info = await DriveBackupService.instance.currentAccount();
    if (info == null) return;
    // Only take non-null fields: a silent lightweight auth can return a minimal
    // profile, and we must never wipe good persisted values back to null.
    var changed = false;
    if (info.name != null && info.name != _driveAccountName) {
      _driveAccountName = info.name;
      changed = true;
    }
    if (info.photoUrl != null && info.photoUrl != _driveAccountPhotoUrl) {
      _driveAccountPhotoUrl = info.photoUrl;
      changed = true;
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  bool get driveAutoBackup => _driveAutoBackup;
  DateTime? get lastDriveBackupAt => _lastDriveBackupAt;

  /// Connects a Google account (interactive). Returns false if cancelled.
  Future<bool> connectDrive() async {
    final info = await DriveBackupService.instance.connect();
    if (info == null) return false;
    _driveAccountEmail = info.email;
    _driveAccountName = info.name;
    _driveAccountPhotoUrl = info.photoUrl;
    _driveAutoBackup = true; // sensible default once a user opts in
    await _persist();
    return true;
  }

  Future<void> disconnectDrive() async {
    try {
      await DriveBackupService.instance.disconnect();
    } catch (_) {
      // Even if the platform sign-out hiccups, forget the account locally.
    }
    _driveAccountEmail = null;
    _driveAccountName = null;
    _driveAccountPhotoUrl = null;
    _driveAutoBackup = false;
    await _persist();
  }

  Future<void> setDriveAutoBackup(bool value) async {
    if (_driveAutoBackup == value) return;
    _driveAutoBackup = value;
    await _persist();
  }

  /// Zips the library and uploads it to the app's private Drive folder, then
  /// prunes to the newest few. Throws on failure (the caller surfaces it).
  Future<void> backupToDrive() async {
    await flushNow();
    final file = await BackupService.instance.exportToTempFile();
    final filename = file.path.split(RegExp(r'[\\/]')).last;
    await DriveBackupService.instance.uploadBackup(file, filename: filename);
    try {
      await file.delete();
    } catch (_) {}
    try {
      await DriveBackupService.instance.pruneOldBackups(keep: 5);
    } catch (_) {}
    final now = DateTime.now();
    _lastBackupAt = now;
    _lastDriveBackupAt = now;
    _backupReminderDismissedAt = null;
    await _persist();
    _revAtDriveBackup = _rev;
  }

  Future<List<DriveBackupFile>> listDriveBackups() =>
      DriveBackupService.instance.listBackups();

  /// Replaces the whole library with a chosen Drive backup.
  Future<void> restoreFromDrive(String fileId) async {
    await flushNow();
    final bytes = await DriveBackupService.instance.downloadBackup(fileId);
    await BackupService.instance.restoreFromZipBytes(bytes);
    await init(restored: true);
  }

  /// Best-effort silent daily backup when the app goes to the background: only
  /// if auto-backup is on, an account is connected, something changed since the
  /// last upload, and the last one was over a day ago (so it settles into a
  /// roughly daily rhythm, keeping the newest 5 copies via [backupToDrive]).
  Future<void> maybeAutoBackup() async {
    if (!_driveAutoBackup || _driveAccountEmail == null) return;
    if (_rev == _revAtDriveBackup) return; // nothing changed since last upload
    final last = _lastDriveBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 20)) {
      return;
    }
    try {
      await backupToDrive();
    } catch (_) {
      // Silent: a failed background backup retries on the next pause.
    }
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    AppPalette.dark = effectiveDark;
    await _persist();
  }

  // The body font for nodes & sparks (titles/chrome stay on the heading font).
  String _noteBodyFont = kNoteBodyFont;
  String get noteBodyFont => _noteBodyFont;

  Future<void> setNoteBodyFont(String family) async {
    _noteBodyFont = family;
    activeBodyFont = family; // the global that body widgets read
    await _persist();
  }

  /// Loads the library into memory and gets the app running.
  ///
  /// Migration Phase 2: SQLite is the source of truth once it has imported
  /// cleanly and [DbStore.readFromDb] is on; otherwise we fall back to the JSON
  /// store. Pass [restored] after a backup has overwritten the JSON on disk —
  /// then we reload that JSON and fold it back into the DB (which the restore
  /// didn't touch) so the next launch, reading from the DB, sees it.
  Future<void> init({bool restored = false}) async {
    // Lazily load the legacy JSON: it's the one-time import source, the fallback
    // when the DB isn't usable, and the authoritative copy right after a
    // restore. On a normal launch with the DB in charge it isn't read at all.
    AppData? legacyCache;
    // The importer's view of the JSON: null = no legacy store at all (a fresh
    // install), throws = a store exists but can't be read. The importer must
    // not mark done on a throw, or the intact library would sit hidden behind
    // an empty DB.
    Future<AppData?> loadForImport() async =>
        legacyCache ??= await _storage.loadLegacyForImport();
    // The app's own view: always yields a library (empty at worst).
    Future<AppData> loadLegacy() async =>
        legacyCache ??= await _storage.load();

    // Bring up the SQLite store and run the one-time import. Idempotent (a
    // no-op once open), never throws, and disables itself where sqflite is
    // missing (unit tests) so we transparently stay on JSON there.
    await _dbStore.init(loadLegacy: loadForImport);

    // Whether the on-disk JSON is the freshest copy of the library: right after
    // a restore, or when an earlier launch had to save to JSON because the DB
    // wasn't usable then (see StorageService.markJsonAhead). Either way the
    // JSON is read and folded back into the DB below.
    final jsonAhead = restored || await _storage.jsonAhead;

    // Pick this launch's source of truth.
    final AppData data;
    if (!jsonAhead && DbStore.readFromDb && _dbStore.usableForReads) {
      data = (await _dbStore.readAppData()) ?? await loadLegacy();
    } else {
      data = await loadLegacy();
    }

    await _applyData(data);

    if (jsonAhead && _dbStore.enabled) {
      // The JSON is ahead of the DB (a restore, or JSON-only edits from a
      // launch where the DB was down); reconcile the DB from it. The dirty-diff
      // handles both added and removed items, so a smaller restored library
      // correctly drops the extra DB rows. Routed through the same write chain
      // as _flush so it can't overlap a debounced save firing right after, then
      // awaited so the DB is consistent on return. The flag is lowered only
      // once the DB really holds the library.
      final snapshot = _snapshot();
      var synced = false;
      _dbWriteChain = _dbWriteChain.then((_) async {
        synced = await _dbStore.syncFromAppData(snapshot);
      }).catchError((_) {});
      await _dbWriteChain;
      if (synced) {
        await _storage.clearJsonAhead();
        _jsonAheadMarked = false;
      }
    }

    // First launch with full-text search available (or after an index bump):
    // index the library the app just loaded. Chained after any reconcile above
    // and ahead of any later save, so the index never lags a newer row.
    if (_dbStore.enabled) {
      final snapshot = _snapshot();
      _dbWriteChain = _dbWriteChain
          .then((_) => _dbStore.ensureSearchIndex(snapshot))
          .catchError((_) {});
    }

    // Restore the connected account's name/avatar for the Settings display
    // (silent — never prompts; no-op when not connected).
    unawaited(refreshDriveAccount());
  }

  /// The app came back to the foreground. Only the share popup (a separate
  /// engine) can have added to the library meanwhile, and it does so through
  /// the inbox, so just drain that. A full [init] here used to re-read the
  /// whole store, re-sort every feed, reschedule every reminder and swap the
  /// note objects out from under any open editor.
  Future<void> resume() async {
    if (!_loaded) return;
    await _importSharedInbox();
  }

  /// Ranked full-text hits (best first) for [query] from the SQLite index, or
  /// null when the index isn't available, in which case the caller keeps its
  /// in-memory substring search.
  Future<List<SearchHit>?> searchIndex(String query) =>
      _dbStore.search(query);

  /// Populates the in-memory library and settings from [data] and finishes
  /// bringing the app up (trash purge, shared-inbox drain, reminder rescheduling
  /// and the like). Shared by the cold start and the post-restore reload.
  Future<void> _applyData(AppData data) async {
    _notes
      ..clear()
      ..addAll(data.notes);
    _spaces
      ..clear()
      ..addAll(data.spaces);
    _cards
      ..clear()
      ..addAll(data.cards);
    _books
      ..clear()
      ..addAll(data.books);
    _impulses
      ..clear()
      ..addAll(data.impulses);
    // The daily day is now an ordinary grey catch-all rather than a special
    // pinned card. Tint an existing one grey so it reads that way too, unless
    // the user already chose a colour for it.
    final existingDaily = impulseById(dailyDayId);
    if (existingDaily != null && existingDaily.colorValue == null) {
      existingDaily.colorValue = dailyDayColorValue;
    }
    _cardsCompact = data.cardsCompact;
    _darkMode = data.darkMode;
    _darkFollowSystem = data.darkFollowSystem;
    _noteBodyFont = data.noteBodyFont;
    activeBodyFont = _noteBodyFont;
    _tutorialSeen = data.tutorialSeen;
    _lastBackupAt = data.lastBackupAt;
    _backupReminderDismissedAt = data.backupReminderDismissedAt;
    _localAutoBackup = data.localAutoBackup;
    _localAutoBackupFreq = data.localAutoBackupFreq;
    _driveAutoBackup = data.driveAutoBackup;
    _lastDriveBackupAt = data.lastDriveBackupAt;
    _driveAccountEmail = data.driveAccountEmail;
    _driveAccountName = data.driveAccountName;
    _driveAccountPhotoUrl = data.driveAccountPhotoUrl;
    _sortMode = _sortFromName(data.sortMode);
    _feedWallpaper = data.feedWallpaper;
    // Migrate the old single background into both themes when the new
    // per-theme values are unset.
    _feedBackgroundLight = data.feedBackgroundLight.isNotEmpty
        ? data.feedBackgroundLight
        : data.feedBackgroundPath;
    _feedBackgroundDark = data.feedBackgroundDark.isNotEmpty
        ? data.feedBackgroundDark
        : data.feedBackgroundPath;
    _readerFontScale = data.readerFontScale;
    _readerFont = data.readerFont;
    _readerTheme = data.readerTheme;
    _journalReminderOn = data.journalReminderOn;
    _journalReminderMinutes = data.journalReminderMinutes;
    _pinnedReflexId = data.pinnedReflexId;
    _progressImpulseId = data.progressImpulseId;
    _journalPaneOpen = data.journalPaneOpen;
    _cortexPaneOpen = data.cortexPaneOpen;
    _progressShowAll = data.progressShowAll;
    _typingMillis = data.typingMillis;
    _journalOrder = data.journalOrder;
    _journalMonthCovers
      ..clear()
      ..addAll(data.journalMonthCovers);
    _readerPositions
      ..clear()
      ..addAll(data.readerPositions);
    _readerBookmarks
      ..clear()
      ..addAll(data.readerBookmarks);
    _rev++;
    AppPalette.dark = effectiveDark;
    await _purgeExpiredTrash();
    await _importSharedInbox();
    _loaded = true;
    notifyListeners();
    // Make sure any pending reminders are (re)scheduled with the OS.
    for (final n in _notes) {
      if (n.reminderAt != null && n.deletedAt == null) {
        unawaited(NotificationService.instance.syncNote(n));
      }
    }
    // …and the gentle daily-task reminders on live reflexes.
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      for (final t in i.allThreads) {
        final m = t.reminderMinutes;
        if (!t.notify || m == null) continue;
        unawaited(NotificationService.instance.scheduleThreadReminder(
          threadId: t.id,
          title: t.title.trim().isEmpty ? 'Daily day' : t.title.trim(),
          body: 'From your daily day',
          hour: m ~/ 60,
          minute: m % 60,
          weekdays: t.days,
        ));
      }
    }
    unawaited(_syncJournalReminder());

    // Cards saved by the share popup arrive without a preview; enrich them in
    // the background now. Capped so a dead link doesn't refetch every launch.
    for (final c in _cards
        .where((c) => !c.fetched && c.enrichAttempts < 3)
        .toList()) {
      c.enrichAttempts++;
      _linkPreview.enrich(c).then((_) {
        _persist();
      });
    }
  }

  // ---- Reads -------------------------------------------------------------

  /// A note is on the "home feed" when it isn't archived, deleted, in Crypt,
  /// a journal entry, or a book page (those live only in their own places).
  bool _isFeedNote(Note n) =>
      !n.archived &&
      n.deletedAt == null &&
      n.spaceId != kCryptSpaceId &&
      n.journalDate == null &&
      n.bookId == null;

  /// Ids of folds the user has flagged to keep out of the Home and Sparks feeds
  /// (their notes/sparks then show only inside the fold). Recomputed per feed
  /// rebuild, which the [_rev] cache already gates to actual changes.
  Set<String> _hiddenFoldIds() => _spaces
      .where((s) => s.hiddenFromFeed && s.deletedAt == null)
      .map((s) => s.id)
      .toSet();

  // ---- Journal -------------------------------------------------------------

  /// Canonical journal key for a calendar day: 'yyyy-MM-dd'.
  static String journalKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// A journal entry visible in journal lists: not deleted and not hidden
  /// away in Crypt (entries filed there only show inside Crypt itself).
  bool _isLiveJournalEntry(Note n) =>
      n.journalDate != null &&
      n.deletedAt == null &&
      n.spaceId != kCryptSpaceId;

  /// Live journal entries written on [day], newest first.
  List<Note> journalEntriesOn(DateTime day) {
    final key = journalKey(day);
    return _notes
        .where((n) => _isLiveJournalEntry(n) && n.journalDate == key)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static String _monthPrefix(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-';

  /// Days of [month] in [year] that have at least one live journal entry
  /// (used for the calendar's entry dots).
  Set<int> journalDaysIn(int year, int month) {
    final prefix = _monthPrefix(year, month);
    final days = <int>{};
    for (final n in _notes) {
      final d = n.journalDate;
      if (d == null || !_isLiveJournalEntry(n) || !d.startsWith(prefix)) {
        continue;
      }
      final day = int.tryParse(d.substring(prefix.length));
      if (day != null) days.add(day);
    }
    return days;
  }

  /// Entry counts per day for a whole year, keyed 'yyyy-MM-dd' (only days with
  /// entries), for the journal heatmap.
  Map<String, int> journalCountsForYear(int year) {
    final prefix = '${year.toString().padLeft(4, '0')}-';
    final counts = <String, int>{};
    for (final n in _notes) {
      final d = n.journalDate;
      if (d == null || !_isLiveJournalEntry(n) || !d.startsWith(prefix)) {
        continue;
      }
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return counts;
  }

  /// Live journal entries of a whole month, newest day first.
  List<Note> journalEntriesInMonth(int year, int month) {
    final prefix = _monthPrefix(year, month);
    return _notes
        .where((n) =>
            _isLiveJournalEntry(n) && n.journalDate!.startsWith(prefix))
        .toList()
      ..sort((a, b) {
        final byDay = b.journalDate!.compareTo(a.journalDate!);
        return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
      });
  }

  /// Years that have at least one live journal entry, newest first. A year
  /// with nothing written doesn't get a card.
  List<int> journalYears() {
    final years = <int>{};
    for (final n in _notes) {
      final d = n.journalDate;
      if (d == null || !_isLiveJournalEntry(n)) continue;
      final y = int.tryParse(d.substring(0, 4));
      if (y != null) years.add(y);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Entries from earlier years written on today's calendar day ("On this
  /// day"), most recent year first. Empty when this date has no past entries.
  List<Note> journalOnThisDay([DateTime? forDay]) {
    final day = forDay ?? DateTime.now();
    final suffix = '-${day.month.toString().padLeft(2, '0')}'
        '-${day.day.toString().padLeft(2, '0')}';
    final out = <Note>[];
    for (final n in _notes) {
      final d = n.journalDate;
      if (d == null || !_isLiveJournalEntry(n) || !d.endsWith(suffix)) {
        continue;
      }
      final year = int.tryParse(d.substring(0, 4));
      if (year == null || year >= day.year) continue; // earlier years only
      out.add(n);
    }
    out.sort((a, b) => b.journalDate!.compareTo(a.journalDate!));
    return out;
  }

  /// The hour of day (0-23) the user writes entries most often, or null when
  /// nothing has been written yet.
  int? get journalBusiestHour {
    final byHour = <int, int>{};
    for (final n in _notes) {
      if (!_isLiveJournalEntry(n)) continue;
      byHour[n.createdAt.hour] = (byHour[n.createdAt.hour] ?? 0) + 1;
    }
    if (byHour.isEmpty) return null;
    var best = byHour.keys.first;
    for (final e in byHour.entries) {
      if (e.value > byHour[best]!) best = e.key;
    }
    return best;
  }

  int get journalEntryCount =>
      _notes.where(_isLiveJournalEntry).length;

  /// Words in the longest journal entry written so far.
  int get journalLongestEntryWords {
    var longest = 0;
    for (final n in _notes) {
      if (!_isLiveJournalEntry(n)) continue;
      final w = n.wordCount;
      if (w > longest) longest = w;
    }
    return longest;
  }

  /// Pages across every live book (Contents pages and workshop notes excluded
  /// — they're an index and side matter, not the manuscript).
  int get totalBookPages => _notes
      .where((n) =>
          n.bookId != null &&
          n.deletedAt == null &&
          n.bookPageKind != BookPageKind.contents &&
          n.bookPageKind != BookPageKind.note)
      .length;

  int get totalBookWords => _notes
      .where((n) =>
          n.bookId != null &&
          n.deletedAt == null &&
          n.bookPageKind != BookPageKind.note)
      .fold(0, (sum, n) => sum + n.wordCount);

  /// The user-chosen cover for a journal month ('yyyy-MM'), if any.
  String? journalMonthCover(String monthKey) => _journalMonthCovers[monthKey];

  Future<void> setJournalMonthCover(String monthKey, String? path) async {
    if (path == null) {
      _journalMonthCovers.remove(monthKey);
    } else {
      _journalMonthCovers[monthKey] = path;
    }
    await _persist();
  }

  bool _isFeedCard(TweetCard c) =>
      !c.archived && c.deletedAt == null && c.spaceId != kCryptSpaceId;

  bool _isLiveSpace(Space s) => !s.archived && s.deletedAt == null;

  // Feed lists are memoized against a mutation revision so a rebuild of
  // several watching screens doesn't re-filter + re-sort the library each.
  int _rev = 0;
  int _notesRev = -1;
  List<Note>? _notesCache;
  int _cardsRev = -1;
  List<TweetCard>? _cardsCache;

  List<Note> get notes {
    if (_notesRev != _rev || _notesCache == null) {
      final hidden = _hiddenFoldIds();
      final tag = _activeTag;
      _notesCache = _notes
          .where((n) =>
              _isFeedNote(n) &&
              !hidden.contains(n.spaceId) &&
              (tag == null || n.tags.contains(tag)))
          .toList()
        ..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return _compareNotes(a, b);
        });
      _notesRev = _rev;
    }
    return _notesCache!;
  }

  List<Note> get archivedNotes => _notes
      .where((n) =>
          n.archived && n.deletedAt == null && n.spaceId != kCryptSpaceId)
      .toList()
    ..sort(_byCreatedDesc);

  List<Note> get deletedNotes => _notes.where((n) => n.deletedAt != null).toList()
    ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  List<TweetCard> get archivedCards => _cards
      .where((c) =>
          c.archived && c.deletedAt == null && c.spaceId != kCryptSpaceId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<TweetCard> get deletedCards =>
      _cards.where((c) => c.deletedAt != null).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  List<Space> get archivedSpaces =>
      _spaces.where((s) => s.archived && s.deletedAt == null).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Space> get deletedSpaces =>
      _spaces.where((s) => s.deletedAt != null).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  List<Note> notesForSpace(String spaceId) => _notes
      .where((n) => n.spaceId == spaceId && !n.archived && n.deletedAt == null)
      .toList()
    ..sort(_compareNotes);

  int noteCountForSpace(String spaceId) => _notes
      .where((n) => n.spaceId == spaceId && !n.archived && n.deletedAt == null)
      .length;

  List<Space> get spaces =>
      _spaces.where(_isLiveSpace).toList()..sort(_compareSpaces);

  int _compareSpaces(Space a, Space b) {
    switch (_sortMode) {
      case NoteSort.recent:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSort.oldest:
        return a.createdAt.compareTo(b.createdAt);
      case NoteSort.azTitle:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case NoteSort.zaTitle:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
    }
  }

  List<TweetCard> get cards {
    if (_cardsRev != _rev || _cardsCache == null) {
      final hidden = _hiddenFoldIds();
      _cardsCache = _cards
          .where((c) => _isFeedCard(c) && !hidden.contains(c.spaceId))
          .toList()
        ..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return _compareCards(a, b);
        });
      _cardsRev = _rev;
    }
    return _cardsCache!;
  }

  List<TweetCard> cardsForSpace(String spaceId) => (_cards
      .where((c) =>
          c.spaceId == spaceId && !c.archived && c.deletedAt == null)
      .toList()
    ..sort(_compareCards));

  /// Notes + cards that live in a space.
  int itemCountForSpace(String spaceId) =>
      _notes
          .where((n) =>
              n.spaceId == spaceId && !n.archived && n.deletedAt == null)
          .length +
      _cards
          .where((c) =>
              c.spaceId == spaceId && !c.archived && c.deletedAt == null)
          .length;

  Space? spaceById(String? id) {
    if (id == null) return null;
    if (id == kCryptSpaceId) return Space(id: kCryptSpaceId, name: 'Crypt');
    for (final s in _spaces) {
      if (s.id == id) return s;
    }
    return null;
  }

  Note? noteById(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  TweetCard? cardById(String id) {
    for (final c in _cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- Wiki-links & backlinks --------------------------------------------
  //
  // `[[Note title]]` in a note's text points at another note. This is what
  // turns a pile of notes into a connected graph — the most on-brand thing a
  // "second brain" can do. Resolution is by title (case-insensitive); a note
  // shows who links to it as a "Mentioned in" list.

  /// Title + body of a note — the surface scanned for `[[wiki-links]]`.
  static String _linkScanText(Note n) => '${n.title}\n${n.textPreview}';

  /// The distinct `[[titles]]` a note points at.
  List<String> wikiLinkTitlesOf(Note n) =>
      parseWikiLinkTitles(_linkScanText(n));

  /// A note that can be the target of a link (not deleted, not in Crypt, not a
  /// book page — Crypt stays out of the graph so it never leaks through a link).
  bool _isLinkableNote(Note n) =>
      n.deletedAt == null && n.spaceId != kCryptSpaceId && n.bookId == null;

  /// Resolves a `[[title]]` to a note: the most recently edited linkable note
  /// whose title matches (case-insensitively), or null if none exists yet.
  Note? noteByTitle(String title) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return null;
    Note? best;
    for (final n in _notes) {
      if (!_isLinkableNote(n)) continue;
      if (n.title.trim().toLowerCase() != key) continue;
      if (best == null || n.updatedAt.isAfter(best.updatedAt)) best = n;
    }
    return best;
  }

  /// Live notes that link to [target] by its title ("Mentioned in"), most
  /// recently edited first. A note never lists itself.
  List<Note> backlinksTo(Note target) {
    final key = target.title.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final out = <Note>[];
    for (final n in _notes) {
      if (n.id == target.id) continue;
      if (n.deletedAt != null ||
          n.spaceId == kCryptSpaceId ||
          n.bookId != null) {
        continue;
      }
      if (wikiLinkTitlesOf(n).any((t) => t.toLowerCase() == key)) out.add(n);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  // ---- The graph spans cards too, so links and backlinks reach across
  // notes, journal entries and cards.

  /// A card's user-authored text (its title + note body), scanned for links.
  String _cardScanText(TweetCard c) {
    final buffer = StringBuffer(c.noteTitle);
    for (final b in c.blocks) {
      if (!b.isText) continue;
      final plain = richToPlain(b.text);
      if (plain.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(plain);
    }
    return buffer.toString();
  }

  String _cardDisplayTitle(TweetCard c) {
    if (c.noteTitle.trim().isNotEmpty) return c.noteTitle.trim();
    if (c.authorName.trim().isNotEmpty) return c.authorName.trim();
    if (c.siteName.trim().isNotEmpty) return c.siteName.trim();
    return c.url;
  }

  String _cardPreview(TweetCard c) {
    for (final b in c.blocks) {
      if (b.isText) {
        final plain = richToPlain(b.text).trim();
        if (plain.isNotEmpty) return plain;
      }
    }
    return c.text.trim().isNotEmpty ? c.text.trim() : c.url;
  }

  String _noteDisplayTitle(Note n) =>
      n.title.trim().isNotEmpty ? n.title.trim() : n.textPreview;

  LinkRef _noteRef(Note n) => LinkRef(
      id: n.id,
      kind: LinkKind.note,
      title: _noteDisplayTitle(n),
      preview: n.textPreview);

  LinkRef _cardRef(TweetCard c) => LinkRef(
      id: c.id,
      kind: LinkKind.card,
      title: _cardDisplayTitle(c),
      preview: _cardPreview(c));

  /// Distinct `[[titles]]` referenced anywhere in [scanText].
  List<String> wikiTitlesIn(String scanText) => parseWikiLinkTitles(scanText);

  /// Resolves a `[[title]]` to a note or a card (notes win on a tie), or null.
  /// Notes/sparks whose title matches [query] (all when empty) — the `@@`
  /// picker's list, most-recent first, capped for a snappy popup.
  List<Note> searchLinkTargets(String query) {
    final q = query.trim().toLowerCase();
    final all = linkTargets();
    final hits =
        q.isEmpty ? all : all.where((n) => n.title.toLowerCase().contains(q));
    return hits.take(30).toList();
  }

  /// Impulses and their threads whose title matches [query] — the `@@@` mention
  /// picker's list. Impulses (projects) come first, then their threads.
  List<MentionTarget> searchMentionTargets(String query) {
    final q = query.trim().toLowerCase();
    final impulseHits = <MentionTarget>[];
    final threadHits = <MentionTarget>[];
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      final iTitle = i.title.trim();
      if (iTitle.isNotEmpty && (q.isEmpty || iTitle.toLowerCase().contains(q))) {
        impulseHits.add(MentionTarget(
            label: iTitle, impulseId: i.id, threadId: null, parent: null));
      }
      for (final t in i.allThreads) {
        final tt = t.title.trim();
        if (tt.isEmpty) continue;
        if (q.isEmpty || tt.toLowerCase().contains(q)) {
          threadHits.add(MentionTarget(
              label: tt, impulseId: i.id, threadId: t.id, parent: iTitle));
        }
      }
    }
    return [...impulseHits, ...threadHits].take(40).toList();
  }

  /// Resolves a `[[@Name]]` mention to an impulse (and thread, when the name
  /// matched a thread) by exact title. Null when nothing matches.
  MentionTarget? resolveMention(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      if (i.title.trim().toLowerCase() == key) {
        return MentionTarget(
            label: i.title.trim(), impulseId: i.id, threadId: null);
      }
    }
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      for (final t in i.allThreads) {
        if (t.title.trim().toLowerCase() == key) {
          return MentionTarget(
              label: t.title.trim(),
              impulseId: i.id,
              threadId: t.id,
              parent: i.title.trim());
        }
      }
    }
    return null;
  }

  LinkRef? resolveLink(String title) {
    final note = noteByTitle(title);
    if (note != null) return _noteRef(note);
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return null;
    TweetCard? best;
    for (final c in _cards) {
      if (c.deletedAt != null || c.spaceId == kCryptSpaceId) continue;
      if (c.noteTitle.trim().toLowerCase() != key) continue;
      if (best == null || c.updatedAt.isAfter(best.updatedAt)) best = c;
    }
    return best == null ? null : _cardRef(best);
  }

  /// Items (notes, journal entries, cards) that link to [title] — the unified
  /// "Mentioned in" list, most recently edited first, excluding [excludeId].
  List<LinkRef> backlinksToTitle(String title, {required String excludeId}) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final hits = <(DateTime, LinkRef)>[];
    for (final n in _notes) {
      if (n.id == excludeId) continue;
      if (n.deletedAt != null ||
          n.spaceId == kCryptSpaceId ||
          n.bookId != null) {
        continue;
      }
      if (wikiLinkTitlesOf(n).any((t) => t.toLowerCase() == key)) {
        hits.add((n.updatedAt, _noteRef(n)));
      }
    }
    for (final c in _cards) {
      if (c.id == excludeId) continue;
      if (c.deletedAt != null || c.spaceId == kCryptSpaceId) continue;
      if (parseWikiLinkTitles(_cardScanText(c))
          .any((t) => t.toLowerCase() == key)) {
        hits.add((c.updatedAt, _cardRef(c)));
      }
    }
    hits.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final h in hits) h.$2];
  }

  /// Notes that can be linked to (have a title), most recently edited first
  /// and de-duplicated by title — the menu shown by the link picker.
  List<Note> linkTargets() {
    final sorted = _notes
        .where((n) => _isLinkableNote(n) && n.title.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final seen = <String>{};
    final out = <Note>[];
    for (final n in sorted) {
      if (seen.add(n.title.trim().toLowerCase())) out.add(n);
    }
    return out;
  }

  /// Creates a fresh note titled [title] — used when a `[[link]]` points at a
  /// note that doesn't exist yet — persists it, and returns it.
  Future<Note> createLinkedNote(String title) async {
    final note = Note(title: title.trim());
    _notes.add(note);
    await _persist();
    return note;
  }

  // ---- Chapter version history --------------------------------------------
  //
  // Book chapters keep a trail of snapshots so a heavy revise stays reversible.

  static const int _maxChapterVersions = 40;

  String _snapshotKey(String title, List<NoteBlock> blocks) =>
      jsonEncode([title, for (final b in blocks) b.toJson()]);

  List<NoteBlock> _copyBlocks(List<NoteBlock> blocks) =>
      [for (final b in blocks) b.copyWith()];

  void _trimHistory(Note note) {
    if (note.history.length > _maxChapterVersions) {
      note.history.removeRange(0, note.history.length - _maxChapterVersions);
    }
  }

  /// Saves the chapter's current title + body as a version.
  Future<void> saveChapterVersion(String noteId, {bool auto = false}) async {
    final note = noteById(noteId);
    if (note == null) return;
    note.history.add(NoteSnapshot(
      title: note.title,
      blocks: _copyBlocks(note.blocks),
      auto: auto,
    ));
    _trimHistory(note);
    await _persist();
  }

  /// Captures a version (on open) only when the content changed since the last
  /// snapshot and enough time has passed — a light periodic safety net that
  /// grabs the pre-edit state at the start of a writing session.
  Future<void> maybeAutoSnapshotChapter(String noteId) async {
    final note = noteById(noteId);
    if (note == null || !note.isManuscriptPage) return;
    final key = _snapshotKey(note.title, note.blocks);
    if (note.history.isNotEmpty) {
      final last = note.history.last;
      if (_snapshotKey(last.title, last.blocks) == key) return;
      if (DateTime.now().difference(last.createdAt) <
          const Duration(minutes: 10)) {
        return;
      }
    } else if (note.textPreview.trim().isEmpty && note.title.trim().isEmpty) {
      return;
    }
    await saveChapterVersion(noteId, auto: true);
  }

  /// Restores a version, snapshotting the current state first so the restore
  /// itself can be undone.
  Future<void> restoreChapterVersion(String noteId, String snapshotId) async {
    final note = noteById(noteId);
    if (note == null) return;
    NoteSnapshot? snap;
    for (final s in note.history) {
      if (s.id == snapshotId) snap = s;
    }
    if (snap == null) return;
    final currentKey = _snapshotKey(note.title, note.blocks);
    final lastKey = note.history.isEmpty
        ? null
        : _snapshotKey(note.history.last.title, note.history.last.blocks);
    if (currentKey != lastKey) {
      note.history.add(NoteSnapshot(
        title: note.title,
        blocks: _copyBlocks(note.blocks),
        auto: true,
      ));
    }
    note.title = snap.title;
    note.blocks = _copyBlocks(snap.blocks);
    note.updatedAt = DateTime.now();
    _trimHistory(note);
    await _persist();
  }

  Future<void> deleteChapterVersion(String noteId, String snapshotId) async {
    final note = noteById(noteId);
    if (note == null) return;
    note.history.removeWhere((s) => s.id == snapshotId);
    await _persist();
  }

  // Newest-created first, and the position never changes on edit (Keep-style),
  // so a note's slot in the feed stays put — which also keeps the open/close
  // morph aligned to the same card.
  static int _byCreatedDesc(Note a, Note b) =>
      b.createdAt.compareTo(a.createdAt);

  // ---- User-selectable feed sort -----------------------------------------
  int _compareNotes(Note a, Note b) {
    switch (_sortMode) {
      case NoteSort.recent:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSort.oldest:
        return a.createdAt.compareTo(b.createdAt);
      case NoteSort.azTitle:
        return _noteSortKey(a).compareTo(_noteSortKey(b));
      case NoteSort.zaTitle:
        return _noteSortKey(b).compareTo(_noteSortKey(a));
    }
  }

  static String _noteSortKey(Note n) {
    final t = n.title.trim();
    return (t.isNotEmpty ? t : n.textPreview).toLowerCase();
  }

  int _compareCards(TweetCard a, TweetCard b) {
    switch (_sortMode) {
      case NoteSort.recent:
        return b.createdAt.compareTo(a.createdAt);
      case NoteSort.oldest:
        return a.createdAt.compareTo(b.createdAt);
      case NoteSort.azTitle:
        return _cardSortKey(a).compareTo(_cardSortKey(b));
      case NoteSort.zaTitle:
        return _cardSortKey(b).compareTo(_cardSortKey(a));
    }
  }

  static String _cardSortKey(TweetCard c) {
    final t = c.noteTitle.trim();
    if (t.isNotEmpty) return t.toLowerCase();
    if (c.authorName.trim().isNotEmpty) return c.authorName.toLowerCase();
    if (c.siteName.trim().isNotEmpty) return c.siteName.toLowerCase();
    return c.url.toLowerCase();
  }

  // ---- Notes -------------------------------------------------------------

  Future<void> upsertNote(Note note) async {
    note.updatedAt = DateTime.now();
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      _notes[idx] = note;
    } else {
      _notes.add(note);
    }
    await _persist();
  }

  /// Creates a note from shared content (plain text and/or images) and returns
  /// it. Images are already copied into app storage by the caller.
  Future<Note> addSharedNote({
    String? text,
    List<String> imagePaths = const [],
    String? spaceId,
  }) async {
    final blocks = <NoteBlock>[
      for (final p in imagePaths)
        NoteBlock(type: NoteBlockType.image, imagePath: p),
      if (text != null && text.trim().isNotEmpty)
        NoteBlock(type: NoteBlockType.text, text: text.trim()),
    ];
    if (blocks.isEmpty) {
      blocks.add(NoteBlock(type: NoteBlockType.text));
    }
    final note = Note(blocks: blocks, spaceId: spaceId);
    _notes.add(note);
    await _persist();
    return note;
  }

  /// Creates a note from the contents of a shared Markdown/plain-text file and
  /// adds it to the home feed. Returns the new note.
  Future<Note> addSharedMarkdown(String markdown, {String? spaceId}) async {
    final note = noteFromMarkdown(markdown, spaceId: spaceId);
    _notes.add(note);
    await _persist();
    return note;
  }

  /// Creates a GitHub-flavored Markdown node from raw [source] and adds it to
  /// the home feed. Unlike [addSharedMarkdown], the raw markdown is kept as the
  /// source of truth (rendered by a GFM engine) rather than converted to the
  /// rich format. The card title / search text track the first heading.
  Future<Note> addMarkdownNode(String source, {String? spaceId}) async {
    final note = Note(
      markdown: true,
      title: markdownTitle(source),
      blocks: [NoteBlock(type: NoteBlockType.text, text: source)],
      spaceId: spaceId,
    );
    _notes.add(note);
    await _persist();
    return note;
  }

  /// Soft-delete: moves the note to Recently Deleted (kept ~30 days).
  Future<void> deleteNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx]
      ..deletedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    unawaited(NotificationService.instance.cancel(id));
    await _persist();
  }

  Future<void> restoreNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx]
      ..deletedAt = null
      ..updatedAt = DateTime.now();
    await _persist();
  }

  /// Permanently removes a note and its images.
  Future<void> permanentlyDeleteNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    final note = _notes.removeAt(idx);
    for (final path in note.imagePaths) {
      await _storage.deleteImage(path);
    }
    await _persist();
  }

  Future<void> emptyTrash() async {
    for (final n in _notes.where((n) => n.deletedAt != null).toList()) {
      _notes.remove(n);
      for (final path in n.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    for (final c in _cards.where((c) => c.deletedAt != null).toList()) {
      _cards.remove(c);
      for (final path in c.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    for (final sp in _spaces.where((s) => s.deletedAt != null).toList()) {
      await _reallyDeleteSpace(sp);
    }
    await _persist();
  }

  Future<void> _purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(kTrashRetention);
    final expiredNotes = _notes
        .where((n) => n.deletedAt != null && n.deletedAt!.isBefore(cutoff))
        .toList();
    final expiredCards = _cards
        .where((c) => c.deletedAt != null && c.deletedAt!.isBefore(cutoff))
        .toList();
    final expiredSpaces = _spaces
        .where((sp) => sp.deletedAt != null && sp.deletedAt!.isBefore(cutoff))
        .toList();
    if (expiredNotes.isEmpty &&
        expiredCards.isEmpty &&
        expiredSpaces.isEmpty) {
      return;
    }
    for (final n in expiredNotes) {
      _notes.remove(n);
      for (final path in n.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    for (final c in expiredCards) {
      _cards.remove(c);
      for (final path in c.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    for (final sp in expiredSpaces) {
      await _reallyDeleteSpace(sp);
    }
    // Persist the full snapshot — a partial AppData here used to drop impulses,
    // the pinned reflex, journal order and other settings when trash expired.
    await _persist();
  }

  Future<void> moveNoteToSpace(String noteId, String? spaceId) async {
    final note = _notes.firstWhere((n) => n.id == noteId);
    note.spaceId = spaceId;
    note.updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> setNoteArchived(String noteId, bool archived) async {
    final note = _notes.firstWhere((n) => n.id == noteId);
    note.archived = archived;
    note.updatedAt = DateTime.now();
    await _persist();
  }

  /// Pins/unpins a note. Returns false when the pin limit is already reached.
  Future<bool> setNotePinned(String noteId, bool pinned) async {
    if (pinned &&
        _notes.where((n) => _isFeedNote(n) && n.pinned).length >= kMaxPins) {
      return false;
    }
    final note = _notes.firstWhere((n) => n.id == noteId);
    note.pinned = pinned;
    note.updatedAt = DateTime.now();
    await _persist();
    return true;
  }

  // ---- Bulk note actions (multi-select) ---------------------------------
  // Each mutates every matching note, then persists once for the whole batch.

  Future<void> bulkPinNotes(Set<String> ids, bool pinned) async {
    for (final n in _notes) {
      if (!ids.contains(n.id)) continue;
      n
        ..pinned = pinned
        ..updatedAt = DateTime.now();
    }
    await _persist();
  }

  /// Pins as many of [ids] as the pin limit allows (already-pinned ones don't
  /// count against the batch). Returns how many were newly pinned and how many
  /// were skipped because the feed was already at [kMaxPins].
  Future<({int pinned, int skipped})> bulkPinNotesLimited(
      Set<String> ids) async {
    var slots =
        kMaxPins - _notes.where((n) => _isFeedNote(n) && n.pinned).length;
    var pinnedCount = 0;
    var skipped = 0;
    for (final n in _notes) {
      if (!ids.contains(n.id) || n.pinned) continue;
      if (slots > 0) {
        n
          ..pinned = true
          ..updatedAt = DateTime.now();
        slots--;
        pinnedCount++;
      } else {
        skipped++;
      }
    }
    if (pinnedCount > 0) await _persist();
    return (pinned: pinnedCount, skipped: skipped);
  }

  Future<void> bulkArchiveNotes(Set<String> ids, bool archived) async {
    for (final n in _notes) {
      if (!ids.contains(n.id)) continue;
      n
        ..archived = archived
        ..updatedAt = DateTime.now();
    }
    await _persist();
  }

  Future<void> bulkMoveNotes(Set<String> ids, String? spaceId) async {
    for (final n in _notes) {
      if (!ids.contains(n.id)) continue;
      n
        ..spaceId = spaceId
        ..updatedAt = DateTime.now();
    }
    await _persist();
  }

  Future<void> bulkDeleteNotes(Set<String> ids) async {
    final now = DateTime.now();
    for (final n in _notes) {
      if (!ids.contains(n.id)) continue;
      n
        ..deletedAt = now
        ..updatedAt = now;
      unawaited(NotificationService.instance.cancel(n.id));
    }
    await _persist();
  }

  /// Pins/unpins a card. Returns false when the pin limit is already reached.
  Future<bool> setCardPinned(String cardId, bool pinned) async {
    if (pinned &&
        _cards.where((c) => _isFeedCard(c) && c.pinned).length >= kMaxPins) {
      return false;
    }
    final card = _cards.firstWhere((c) => c.id == cardId);
    card.pinned = pinned;
    card.updatedAt = DateTime.now();
    await _persist();
    return true;
  }

  /// Deletes an image file that was removed from a note in the editor.
  Future<void> refreshAfterImageRemoval(String path) async {
    if (path.isEmpty) return;
    await _storage.deleteImage(path);
  }

  // ---- Spaces ------------------------------------------------------------

  Future<Space> addSpace(String name,
      {String? thumbnailPath, int? colorValue}) async {
    final space =
        Space(name: name, thumbnailPath: thumbnailPath, colorValue: colorValue);
    _spaces.add(space);
    await _persist();
    return space;
  }

  Future<void> updateSpace(Space space) async {
    final idx = _spaces.indexWhere((s) => s.id == space.id);
    if (idx >= 0) _spaces[idx] = space;
    space.updatedAt = DateTime.now();
    await _persist();
  }

  /// Soft-delete: the folder moves to Recently Deleted; its notes/cards keep
  /// their association (still visible in the feeds) and come back with it.
  Future<void> deleteSpace(String id) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx]
      ..deletedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> restoreSpace(String id) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx]
      ..deletedAt = null
      ..archived = false
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> setSpaceArchived(String id, bool archived) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx]
      ..archived = archived
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> permanentlyDeleteSpace(String id) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    await _reallyDeleteSpace(_spaces[idx]);
    await _persist();
  }

  /// Removes the folder for good: contents fall back to no folder.
  Future<void> _reallyDeleteSpace(Space space) async {
    _spaces.remove(space);
    if (space.thumbnailPath != null) {
      await _storage.deleteImage(space.thumbnailPath!);
    }
    for (final n in _notes.where((n) => n.spaceId == space.id)) {
      n.spaceId = null;
      n.updatedAt = DateTime.now();
    }
    for (final c in _cards.where((c) => c.spaceId == space.id)) {
      c.spaceId = null;
      c.updatedAt = DateTime.now();
    }
  }

  // ---- Books -------------------------------------------------------------

  /// Live books, newest first.
  List<Book> get books => _books
      .where((b) => !b.archived && b.deletedAt == null)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Book? bookById(String id) {
    for (final b in _books) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// A book's live manuscript pages in reading order (workshop notes excluded
  /// — those live in [bookNotes]).
  List<Note> bookPages(String bookId) => _notes
      .where((n) =>
          n.bookId == bookId &&
          n.deletedAt == null &&
          n.bookPageKind != BookPageKind.note)
      .toList()
    ..sort((a, b) => a.bookOrder.compareTo(b.bookOrder));

  /// A book's workshop notes (characters, plot ideas), most recently edited
  /// first. These sit alongside the manuscript, not inside it.
  List<Note> bookNotes(String bookId) => _notes
      .where((n) =>
          n.bookId == bookId &&
          n.deletedAt == null &&
          n.bookPageKind == BookPageKind.note)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// A book's chapters only (Contents/Introduction excluded), in order.
  List<Note> bookChapters(String bookId) => bookPages(bookId)
      .where((n) => n.bookPageKind == BookPageKind.chapter)
      .toList();

  /// Creates a book with the default Contents, Introduction and Chapter I
  /// pages, and returns it.
  Future<Book> addBook(String title, {String? coverPath}) async {
    final book = Book(title: title, coverPath: coverPath);
    _books.add(book);
    var order = 0;
    Note page(String kind, String pageTitle) {
      final n = Note(
        title: pageTitle,
        bookId: book.id,
        bookPageKind: kind,
        bookOrder: order++,
      );
      _notes.add(n);
      return n;
    }

    page(BookPageKind.contents, 'Contents');
    page(BookPageKind.intro, 'Introduction');
    page(BookPageKind.chapter, 'Chapter I');
    await _persist();
    return book;
  }

  /// Total words across a book's pages.
  int bookWordCount(String bookId) =>
      bookPages(bookId).fold(0, (sum, n) => sum + n.wordCount);

  /// Total characters across a book's manuscript pages.
  int bookCharCount(String bookId) =>
      bookPages(bookId).fold(0, (sum, n) => sum + n.charCount);

  /// Estimated reading time in whole minutes at ~200 words/minute.
  int bookReadingMinutes(String bookId) {
    final words = bookWordCount(bookId);
    return words == 0 ? 0 : (words / 200).ceil();
  }

  /// Looks up one of a book's manuscript pages by id (for a note's link).
  Note? bookPageById(String bookId, String pageId) {
    for (final p in bookPages(bookId)) {
      if (p.id == pageId) return p;
    }
    return null;
  }

  /// Notes linked to a given manuscript page (character sheets, plot notes).
  List<Note> bookNotesForPage(String pageId) => _notes
      .where((n) =>
          n.deletedAt == null &&
          n.bookPageKind == BookPageKind.note &&
          n.linkedPageId == pageId)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Counts how many times [query] appears across a book's manuscript (titles
  /// and body), for the find & replace preview.
  int bookFindMatches(String bookId, String query,
      {bool caseSensitive = false}) {
    if (query.isEmpty) return 0;
    var total = 0;
    for (final page in bookPages(bookId)) {
      total += replaceCounted(page.title, query, query,
              caseSensitive: caseSensitive)
          .$2;
      for (final b in page.blocks) {
        if (!b.isText) continue;
        total += replaceInBlockText(b.text, query, query,
                caseSensitive: caseSensitive)
            .$2;
      }
    }
    return total;
  }

  /// Replaces every occurrence of [query] with [replacement] across a book's
  /// manuscript (titles and body), preserving formatting. Returns the count.
  Future<int> bookReplaceAll(
      String bookId, String query, String replacement,
      {bool caseSensitive = false}) async {
    if (query.isEmpty) return 0;
    var total = 0;
    for (final page in bookPages(bookId)) {
      var changed = false;
      final (newTitle, tc) = replaceCounted(page.title, query, replacement,
          caseSensitive: caseSensitive);
      if (tc > 0) {
        page.title = newTitle;
        total += tc;
        changed = true;
      }
      for (final b in page.blocks) {
        if (!b.isText) continue;
        final (s, c) = replaceInBlockText(b.text, query, replacement,
            caseSensitive: caseSensitive);
        if (c > 0) {
          b.text = s;
          total += c;
          changed = true;
        }
      }
      if (changed) {
        page.updatedAt = DateTime.now();
      }
    }
    if (total > 0) await _persist();
    return total;
  }

  /// Moves a page within the book's reading order and renumbers the rest.
  /// Indices refer to [bookPages] order.
  Future<void> reorderBookPages(String bookId, int oldIndex, int newIndex)
      async {
    final pages = bookPages(bookId);
    if (oldIndex < 0 || oldIndex >= pages.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, pages.length - 1);
    if (newIndex == oldIndex) return;
    final moved = pages.removeAt(oldIndex);
    pages.insert(newIndex, moved);
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].bookOrder == i) continue;
      pages[i]
        ..bookOrder = i
        ..updatedAt = DateTime.now();
    }
    await _persist();
  }

  // ---- Reading ------------------------------------------------------------

  /// Reader typography and theme, shared by every book.
  double _readerFontScale = 1.0;
  String _readerFont = 'Lora';
  String _readerTheme = 'original';

  double get readerFontScale => _readerFontScale;
  String get readerFont => _readerFont;
  String get readerTheme => _readerTheme;

  Future<void> setReaderFontScale(double v) async {
    _readerFontScale = v.clamp(0.8, 1.8);
    await _persist();
  }

  Future<void> setReaderFont(String family) async {
    _readerFont = family;
    await _persist();
  }

  Future<void> setReaderTheme(String theme) async {
    _readerTheme = theme;
    await _persist();
  }

  // ---- Journal daily reminder ---------------------------------------------

  bool _journalReminderOn = false;
  int _journalReminderMinutes = 21 * 60; // 9:00 PM

  bool get journalReminderOn => _journalReminderOn;
  int get journalReminderMinutes => _journalReminderMinutes;

  /// Turns the nightly journal nudge on/off and/or moves its time (minutes
  /// since midnight). Persists, syncs to the cloud, and (re)schedules the OS
  /// notification. Callers request the notification permission first.
  Future<void> setJournalReminder({bool? on, int? minutes}) async {
    if (on != null) _journalReminderOn = on;
    if (minutes != null) {
      _journalReminderMinutes = minutes.clamp(0, 24 * 60 - 1);
    }
    await _persist();
    await _syncJournalReminder();
  }

  Future<void> _syncJournalReminder() async {
    if (_journalReminderOn) {
      await NotificationService.instance.scheduleDailyJournal(
        hour: _journalReminderMinutes ~/ 60,
        minute: _journalReminderMinutes % 60,
        title: 'Time to journal',
        body: 'Take a minute to write about your day.',
      );
    } else {
      await NotificationService.instance.cancelDailyJournal();
    }
  }

  // ---- Reader position + bookmarks (per book, as a 0–1 fraction) ----------

  final Map<String, double> _readerPositions = {};
  final Map<String, List<double>> _readerBookmarks = {};

  /// Where the reader last left off in a book (0 = start).
  double readerPosition(String bookId) => _readerPositions[bookId] ?? 0;

  Future<void> setReaderPosition(String bookId, double fraction) async {
    final f = fraction.clamp(0.0, 1.0);
    if (((_readerPositions[bookId] ?? 0) - f).abs() < 0.001) return;
    _readerPositions[bookId] = f;
    await _persist();
  }

  List<double> readerBookmarks(String bookId) =>
      List.unmodifiable(_readerBookmarks[bookId] ?? const []);

  Future<void> addReaderBookmark(String bookId, double fraction) async {
    final f = fraction.clamp(0.0, 1.0);
    final list = _readerBookmarks.putIfAbsent(bookId, () => []);
    // Ignore a near-duplicate of an existing mark.
    if (list.any((b) => (b - f).abs() < 0.01)) return;
    list
      ..add(f)
      ..sort();
    await _persist();
  }

  Future<void> removeReaderBookmark(String bookId, double fraction) async {
    final list = _readerBookmarks[bookId];
    if (list == null) return;
    list.removeWhere((b) => (b - fraction).abs() < 0.0001);
    if (list.isEmpty) _readerBookmarks.remove(bookId);
    await _persist();
  }

  /// Adds a highlight (optionally with a note) to a book page.
  Future<void> addAnnotation(String noteId, Annotation annotation) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx].annotations.add(annotation);
    _notes[idx].updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> updateAnnotation(
      String noteId, String annotationId, String note) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    for (final a in _notes[idx].annotations) {
      if (a.id == annotationId) a.note = note;
    }
    _notes[idx].updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> removeAnnotation(String noteId, String annotationId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx].annotations.removeWhere((a) => a.id == annotationId);
    _notes[idx].updatedAt = DateTime.now();
    await _persist();
  }

  /// Every annotation in a book, paired with the page it lives on.
  List<({Note page, Annotation annotation})> bookAnnotations(String bookId) => [
        for (final page in bookPages(bookId))
          for (final a in page.annotations) (page: page, annotation: a),
      ];

  /// Tags a chapter draft / revised / final (see [BookPageStatus]).
  Future<void> setBookPageStatus(String noteId, String status) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx]
      ..bookStatus = status
      ..updatedAt = DateTime.now();
    await _persist();
  }

  /// Renames a book page (used by the Contents editor, which links to the
  /// real chapter titles).
  Future<void> setBookPageTitle(String noteId, String title) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx].title = title;
    _notes[idx].updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> updateBook(Book book) async {
    final idx = _books.indexWhere((b) => b.id == book.id);
    if (idx >= 0) _books[idx] = book;
    book.updatedAt = DateTime.now();
    await _persist();
  }

  /// Adds a chapter to a book, auto-named "Chapter N" by chapter count.
  Future<Note> addBookChapter(String bookId) async {
    final chapters = bookChapters(bookId).length;
    final maxOrder = bookPages(bookId)
        .fold<int>(-1, (m, n) => n.bookOrder > m ? n.bookOrder : m);
    final chapter = Note(
      title: 'Chapter ${_roman(chapters + 1)}',
      bookId: bookId,
      bookPageKind: BookPageKind.chapter,
      bookOrder: maxOrder + 1,
    );
    _notes.add(chapter);
    await _persist();
    return chapter;
  }

  /// Adds an extra Introduction-style page (front matter). A book can hold
  /// only one Contents, so that kind isn't offered here.
  Future<Note> addBookPage(String bookId) async {
    final maxOrder = bookPages(bookId)
        .fold<int>(-1, (m, n) => n.bookOrder > m ? n.bookOrder : m);
    final page = Note(
      title: 'Untitled page',
      bookId: bookId,
      bookPageKind: BookPageKind.intro,
      bookOrder: maxOrder + 1,
    );
    _notes.add(page);
    await _persist();
    return page;
  }

  /// Adds a front/back-matter page (dedication, epigraph, acknowledgements) to
  /// a book. Appended to the end; the writer reorders it via the Contents.
  Future<Note> addBookMatter(String bookId, String kind, String title) async {
    final maxOrder = bookPages(bookId)
        .fold<int>(-1, (m, n) => n.bookOrder > m ? n.bookOrder : m);
    final page = Note(
      title: title,
      bookId: bookId,
      bookPageKind: kind,
      bookOrder: maxOrder + 1,
    );
    _notes.add(page);
    await _persist();
    return page;
  }

  /// Sets a chapter's word goal (0 clears it).
  Future<void> setBookPageTarget(String noteId, int target) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx]
      ..targetWords = target < 0 ? 0 : target
      ..updatedAt = DateTime.now();
    await _persist();
  }

  /// Ties a workshop note to a manuscript page (or clears the link with null).
  Future<void> setBookNoteLink(String noteId, String? pageId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    _notes[idx]
      ..linkedPageId = pageId
      ..updatedAt = DateTime.now();
    await _persist();
  }

  /// Adds a blank workshop note to a book (a character sketch, a plot idea).
  /// It's an ordinary note tagged with the book, so it gets the note editor,
  /// autosave and sync — but it stays out of the manuscript.
  Future<Note> addBookNote(String bookId, {String? linkedPageId}) async {
    final note = Note(
      bookId: bookId,
      bookPageKind: BookPageKind.note,
      linkedPageId: linkedPageId,
    );
    _notes.add(note);
    await _persist();
    return note;
  }

  /// Sets a book's typeface, applied everywhere the book is written or read.
  Future<void> setBookFont(String bookId, String family) async {
    final book = bookById(bookId);
    if (book == null || book.fontFamily == family) return;
    book.fontFamily = family;
    await updateBook(book);
  }

  /// Permanently removes a book page and its images.
  Future<void> deleteBookPage(String noteId) async {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx < 0) return;
    final page = _notes.removeAt(idx);
    for (final p in page.imagePaths) {
      await _storage.deleteImage(p);
    }
    await _persist();
  }

  /// Deletes a book for good, along with all its pages and their images.
  Future<void> deleteBook(String bookId) async {
    final idx = _books.indexWhere((b) => b.id == bookId);
    if (idx < 0) return;
    final book = _books.removeAt(idx);
    if (book.coverPath != null) await _storage.deleteImage(book.coverPath!);
    for (final n in _notes.where((n) => n.bookId == bookId).toList()) {
      _notes.remove(n);
      for (final p in n.imagePaths) {
        await _storage.deleteImage(p);
      }
    }
    await _persist();
  }

  static const _romans = [
    'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X',
    'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX',
  ];
  static String _roman(int n) =>
      (n >= 1 && n <= _romans.length) ? _romans[n - 1] : '$n';

  // ---- Cards -------------------------------------------------------------

  /// Adds a shared link as a card and enriches it in the background. If the
  /// same link is already saved (and not deleted), the existing card is
  /// reused instead of creating a duplicate.
  Future<TweetCard> addCardFromUrl(String url, {String? spaceId}) async {
    final cleaned = _extractUrl(url);
    final normalized = _normalizeUrl(cleaned);
    final existing = _cards.where(
        (c) => c.deletedAt == null && _normalizeUrl(c.url) == normalized);
    if (existing.isNotEmpty) {
      final card = existing.first;
      // Merge: adopt the requested folder and surface it again.
      if (spaceId != null) card.spaceId = spaceId;
      card.archived = false;
      card.updatedAt = DateTime.now();
      await _persist();
      return card;
    }
    final card = TweetCard(url: cleaned, spaceId: spaceId);
    _cards.add(card);
    await _persist();

    // Fetch preview without blocking the UI.
    _linkPreview.enrich(card).then((_) {
      card.updatedAt = DateTime.now();
      _persist();
    });
    return card;
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) return u;
    return uri
        .replace(
            scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase())
        .toString();
  }

  /// Imports links saved by the share popup (one inbox file per share, so the
  /// popup never contends with this engine's writes to the data file).
  Future<void> _importSharedInbox() async {
    final records = await _storage.drainShareInbox();
    for (final r in records) {
      final url = r['url'] as String?;
      final noteText = r['noteText'] as String?;
      if ((url == null || url.isEmpty) &&
          (noteText == null || noteText.trim().isEmpty)) {
        continue;
      }
      String? spaceId = r['spaceId'] as String?;
      final newFolderName = (r['newFolderName'] as String?)?.trim();
      if (newFolderName != null && newFolderName.isNotEmpty) {
        final existing = _spaces.where((s) =>
            _isLiveSpace(s) &&
            s.name.toLowerCase() == newFolderName.toLowerCase());
        if (existing.isNotEmpty) {
          spaceId = existing.first.id;
        } else {
          final space = Space(name: newFolderName);
          _spaces.add(space);
          spaceId = space.id;
        }
      }
      if (url != null && url.isNotEmpty) {
        await addCardFromUrl(url, spaceId: spaceId);
      } else {
        // Parse the shared text as Markdown so any formatting (headings,
        // bullets, checkboxes, bold/italic, links) renders instead of showing
        // its raw symbols. Plain text passes through unchanged.
        await addSharedMarkdown(noteText!, spaceId: spaceId);
      }
    }
  }

  Future<void> refreshCard(String id) async {
    final card = _cards.firstWhere((c) => c.id == id);
    await _linkPreview.enrich(card);
    card.updatedAt = DateTime.now();
    await _persist();
  }

  /// Scrapes a YouTube spark's description + transcript (best-effort) and stores
  /// them on the card, so a later open shows the stored copy without refetching.
  /// [force] (the Retry button) refetches regardless of the attempt cap.
  Future<void> fetchYouTubeDetails(String id, {bool force = false}) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final card = _cards[idx];
    final vid = YouTubeService.videoId(card.url);
    if (vid == null) return;
    if (card.videoFetched && !force) return;
    // Stop auto-scraping a persistently-blocked video: after a few empty tries
    // it costs a full (slow) scrape on every open for nothing. Retry ignores it.
    if (!force && card.videoFetchAttempts >= TweetCard.maxVideoAutoFetchAttempts) {
      return;
    }
    // A YouTube spark always gets a thumbnail from its id, even if the scrape
    // below comes back empty.
    if (card.imageUrl.isEmpty) card.imageUrl = YouTubeService.thumbnailUrl(vid);
    final data = await YouTubeService.fetch(vid);
    // Lock the spark as "fetched" once the scrape actually returned the page
    // (an empty transcript alone still counts — auto-captions sit behind
    // YouTube's poToken and genuinely can't be gotten). A wholly-empty result
    // is a block/rate-limit: leave it unfetched but count the attempt so the
    // automatic retries are bounded.
    final gotPage = data.description.isNotEmpty || data.title.isNotEmpty;
    if (!gotPage) card.videoFetchAttempts++;
    card
      ..videoDescription = data.description
      ..videoTranscript = data.transcript
      ..videoFetched = gotPage
      ..updatedAt = DateTime.now();
    // Use the video's own title/channel to identify the spark (unless the user
    // already gave it a title).
    if (card.noteTitle.trim().isEmpty && data.title.isNotEmpty) {
      card.noteTitle = data.title;
    }
    if (card.authorName.trim().isEmpty && data.author.isNotEmpty) {
      card.authorName = data.author;
    }
    await _persist();
  }

  Future<void> updateCard(TweetCard card) async {
    final idx = _cards.indexWhere((c) => c.id == card.id);
    if (idx >= 0) _cards[idx] = card;
    card.updatedAt = DateTime.now();
    await _persist();
  }

  /// Soft-delete: moves the card to Recently Deleted (kept ~30 days).
  Future<void> deleteCard(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx]
      ..deletedAt = DateTime.now()
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> restoreCard(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx]
      ..deletedAt = null
      ..archived = false
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> setCardArchived(String id, bool archived) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx]
      ..archived = archived
      ..updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> permanentlyDeleteCard(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final card = _cards.removeAt(idx);
    for (final path in card.imagePaths) {
      await _storage.deleteImage(path);
    }
    await _persist();
  }

  Future<void> moveCardToSpace(String cardId, String? spaceId) async {
    final card = _cards.firstWhere((c) => c.id == cardId);
    card.spaceId = spaceId;
    card.updatedAt = DateTime.now();
    await _persist();
  }

  String _extractUrl(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text);
    return (match?.group(0) ?? text).trim();
  }

  // ---- Maintenance -------------------------------------------------------

  int get noteCount => _notes.length;
  int get spaceCount => _spaces.length;
  int get cardCount => _cards.length;

  /// Adds the bundled demo library (a spread of notes, cards and a short book)
  /// to whatever is already here — a one-tap way to fill a fresh install so
  /// every feature has something to show. Additive: it never touches existing
  /// content, and each call adds an independent copy.
  Future<void> loadSampleData() async {
    final bundle = SeedData.build();
    for (final s in bundle.spaces) {
      _spaces.add(s);
    }
    for (final n in bundle.notes) {
      _notes.add(n);
    }
    for (final c in bundle.cards) {
      _cards.add(c);
    }
    for (final b in bundle.books) {
      _books.add(b);
    }
    await _persist();
    // Arm any reminders the demo notes carry.
    for (final n in bundle.notes) {
      if (n.reminderAt != null && n.deletedAt == null) {
        unawaited(NotificationService.instance.syncNote(n));
      }
    }
  }

  Future<void> clearAll() async {
    for (final n in _notes) {
      for (final p in n.imagePaths) {
        await _storage.deleteImage(p);
      }
    }
    for (final s in _spaces) {
      if (s.thumbnailPath != null) await _storage.deleteImage(s.thumbnailPath!);
    }
    for (final c in _cards) {
      for (final p in c.imagePaths) {
        await _storage.deleteImage(p);
      }
    }
    _notes.clear();
    _spaces.clear();
    _cards.clear();
    await _persist();
  }

  // ---- Reflexes (Impulse projects with Thread subtasks) -------------------

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Today, as the 'yyyy-MM-dd' key Threads are marked against.
  String get todayKey => _dayKey(DateTime.now());

  /// The 'yyyy-MM-dd' key for any day (used to tick a task on a chosen day).
  static String dayKeyFor(DateTime d) => _dayKey(d);

  /// The fixed id of the "daily day" catch-all reflex: an ordinary daily-mode
  /// Impulse holding loose tasks that don't belong to any project. It's created
  /// only when the user actually adds a loose task (via "add to daily day"), and
  /// from then on behaves like any other reflex — editable, deletable, and shown
  /// in the Reflexes list. New users don't get one by default.
  static const dailyDayId = '__daily_day__';

  /// The grey tint the catch-all daily day wears by default, so it reads as the
  /// "loose tasks" bucket rather than a real project (the "stone" swatch).
  static const int dailyDayColorValue = 0xFFDDDFE4;

  /// The always-present daily-day reflex. Returns a transient (unsaved) one
  /// until the first task is added, so an untouched daily day never persists.
  Impulse get dailyDay =>
      impulseById(dailyDayId) ??
      Impulse(id: dailyDayId, title: 'Daily day', mode: ImpulseMode.daily);

  /// Live Impulses, most recently updated first; finished checklists sink.
  /// The daily day is excluded — it has its own home in the Journal.
  List<Impulse> get impulses {
    final list = _impulses
        .where((i) =>
            i.id != dailyDayId && i.deletedAt == null && !i.archived)
        .toList();
    list.sort((a, b) {
      if (a.isComplete != b.isComplete) return a.isComplete ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  int get impulseCount => _impulses
      .where((i) =>
          i.id != dailyDayId && i.deletedAt == null && !i.archived)
      .length;

  /// All live reflexes, most-recently-updated first (finished checklists sink).
  /// The daily day is no longer force-injected — it appears here only when it
  /// exists as a real impulse (i.e. the user has added loose tasks to it), like
  /// any other reflex.
  List<Impulse> get reflexes {
    final list = _impulses
        .where((i) => i.deletedAt == null && !i.archived)
        .toList();
    list.sort((a, b) {
      if (a.isComplete != b.isComplete) return a.isComplete ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// The distinct, non-empty category labels across the live reflexes, sorted,
  /// for the category tabs above the reflex list.
  List<String> get reflexCategories {
    final set = <String>{};
    for (final i in _impulses) {
      if (i.id == dailyDayId || i.deletedAt != null || i.archived) continue;
      if (i.category.trim().isNotEmpty) set.add(i.category.trim());
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  /// Today's completion across every live, non-paused reflex's threads (the
  /// daily day included) — what the journal's progress ring shows.
  /// Every thread due on [date] across all impulses — the cumulative daily-day
  /// list. A thread is due when its impulse is a daily/long-term goal (checklist
  /// milestones are excluded) and the thread runs on that weekday (its [days]
  /// are empty for "every day", or contain the weekday). The daily-day impulse
  /// comes first, then the projects.
  List<({String impulseId, Thread thread})> dueThreadsOn(DateTime date) {
    final weekday = date.weekday;
    final out = <({String impulseId, Thread thread})>[];
    for (final i in reflexes) {
      if (i.deletedAt != null || i.archived || i.paused) continue;
      if (i.isCompletedManually) continue;
      if (i.mode == ImpulseMode.checklist) continue;
      for (final t in i.allThreads) {
        if (t.days.isEmpty || t.days.contains(weekday)) {
          out.add((impulseId: i.id, thread: t));
        }
      }
    }
    return out;
  }

  /// Completion of the cumulative daily-day list for [date].
  TodayProgress dueProgressOn(DateTime date) {
    final key = dayKeyFor(date);
    var done = 0;
    var total = 0;
    for (final item in dueThreadsOn(date)) {
      total++;
      final imp = impulseById(item.impulseId);
      if (imp != null && imp.threadDone(item.thread, key)) done++;
    }
    return TodayProgress(done, total);
  }

  /// Consecutive days, ending at the most recent completed day, on which the
  /// whole cumulative daily list was cleared. Days with nothing due are neutral
  /// (they neither extend nor break the run). Powers the green card's streak.
  int dueStreak() {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    final todayP = dueProgressOn(day);
    // Today still in progress doesn't count yet — start from yesterday.
    if (!(todayP.total > 0 && todayP.done >= todayP.total)) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    for (var i = 0; i < 180; i++) {
      final p = dueProgressOn(day);
      if (p.total == 0) {
        day = day.subtract(const Duration(days: 1)); // nothing due: neutral
        continue;
      }
      if (p.done >= p.total) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// The last [days] days of the cumulative daily list, oldest first — the data
  /// behind the green card's mini history strip.
  List<TodayProgress> dueHistory(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = days - 1; i >= 0; i--)
        dueProgressOn(today.subtract(Duration(days: i)))
    ];
  }

  /// Today's still-unfinished due threads, earliest-scheduled first, capped at
  /// [limit] — the "next up" hint on the green card.
  List<Thread> pendingDueToday({int limit = 2}) {
    final key = todayKey;
    final pending = <({int? at, Thread thread})>[];
    for (final item in dueThreadsOn(DateTime.now())) {
      final imp = impulseById(item.impulseId);
      if (imp != null && imp.threadDone(item.thread, key)) continue;
      pending.add((at: item.thread.reminderMinutes, thread: item.thread));
    }
    pending.sort((a, b) {
      final aa = a.at, bb = b.at;
      if (aa == null && bb == null) return 0;
      if (aa == null) return 1;
      if (bb == null) return -1;
      return aa.compareTo(bb);
    });
    return [for (final p in pending.take(limit)) p.thread];
  }

  /// The earliest day any live reflex thread was completed — the lower bound for
  /// the cumulative daily-day history calendar. Null when nothing's done yet.
  DateTime? earliestActivityDay() {
    String? min;
    for (final i in _impulses) {
      if (i.deletedAt != null) continue;
      for (final t in i.allThreads) {
        for (final d in t.doneDays) {
          if (min == null || d.compareTo(min) < 0) min = d;
        }
      }
    }
    if (min == null) return null;
    final p = min.split('-');
    if (p.length != 3) return null;
    return DateTime(
        int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  // ---- Analytics: scope tallies -------------------------------------------
  //
  // One tally used everywhere the analytics screen counts a day — the heatmap,
  // the curve and the period stats — so they always agree. It mirrors the
  // per-impulse heatmap/history rules, aggregated over a set of impulses.

  /// (done, scheduled) across [scope] for [day].
  (int done, int scheduled) scopeTallyOn(List<Impulse> scope, DateTime day) {
    final key = dayKeyFor(day);
    var done = 0;
    var scheduled = 0;
    for (final imp in scope) {
      if (imp.deletedAt != null) continue;
      final threads = imp.isLongTerm ? imp.allThreads : imp.threads;
      final onceLike = imp.mode == ImpulseMode.checklist;
      for (final t in threads) {
        if (t.once || onceLike) {
          if (t.doneDays.contains(key)) {
            scheduled++;
            done++;
          }
        } else if (t.days.isEmpty || t.days.contains(day.weekday)) {
          scheduled++;
          if (t.doneDays.contains(key)) done++;
        }
      }
    }
    return (done, scheduled);
  }

  /// (done, scheduled) across [scope] over the trailing [days] ending today.
  (int done, int scheduled) scopeTallyOver(List<Impulse> scope, int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var done = 0;
    var scheduled = 0;
    for (var i = 0; i < days; i++) {
      final (d, s) = scopeTallyOn(scope, today.subtract(Duration(days: i)));
      done += d;
      scheduled += s;
    }
    return (done, scheduled);
  }

  // ---- Past/future edit guard ---------------------------------------------
  //
  // Ticking a thread within +/-2 days of today is free; editing a day further
  // out prompts once (per that day), and the confirmation resets each new
  // calendar day. In-memory only — a lost confirmation just re-prompts.

  final Set<String> _farEditOkDays = {};
  String _farEditOkOn = '';

  void _resetFarEditIfNewDay() {
    final t = todayKey;
    if (_farEditOkOn != t) {
      _farEditOkOn = t;
      _farEditOkDays.clear();
    }
  }

  int _dayOffsetFromToday(String dayKey) {
    final p = dayKey.split('-');
    if (p.length != 3) return 0;
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return d.difference(today).inDays;
  }

  /// Whether ticking a thread on [dayKey] needs the "you're editing the
  /// past/future" confirmation: it's more than 2 days from today and hasn't been
  /// confirmed yet today.
  bool farEditNeedsConfirm(String dayKey) {
    _resetFarEditIfNewDay();
    if (_dayOffsetFromToday(dayKey).abs() <= 2) return false;
    return !_farEditOkDays.contains(dayKey);
  }

  /// True when [dayKey] is in the future (for wording the confirmation).
  bool isFutureDay(String dayKey) => _dayOffsetFromToday(dayKey) > 0;

  /// Records that far-edits on [dayKey] were confirmed for today.
  void confirmFarEdit(String dayKey) {
    _resetFarEditIfNewDay();
    _farEditOkDays.add(dayKey);
  }

  TodayProgress get todayProgress {
    final key = todayKey;
    final weekday = DateTime.now().weekday;
    var done = 0;
    var total = 0;
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived || i.paused) continue;
      if (i.isCompletedManually) continue;
      // Only count reflexes actually scheduled for today.
      if (!i.scheduledOn(weekday)) continue;
      for (final t in i.allThreads) {
        total++;
        if (i.threadDone(t, key)) done++;
      }
    }
    return TodayProgress(done, total);
  }

  /// Today's completion of a single impulse — the count of its threads and how
  /// many are ticked for today. Used by the green progress card (which tracks
  /// one chosen impulse, unlike [todayProgress], which sums every reflex).
  TodayProgress todayProgressFor(Impulse i) {
    final key = todayKey;
    var done = 0;
    var total = 0;
    for (final t in i.allThreads) {
      total++;
      if (i.threadDone(t, key)) done++;
    }
    return TodayProgress(done, total);
  }

  /// The impulse the green "Today's progress" card tracks (default: the daily
  /// day). Chosen by long-pressing that card.
  String get progressImpulseId => _progressImpulseId;
  Impulse get progressImpulse => impulseById(_progressImpulseId) ?? dailyDay;

  Future<void> setProgressImpulse(String id) async {
    _progressImpulseId = id;
    await _persist();
  }

  /// Whether the green progress card aggregates every reflex ("All") rather than
  /// tracking one impulse. Toggled on the card; shared with its analytics view.
  bool get progressShowAll => _progressShowAll;
  Future<void> setProgressShowAll(bool value) async {
    if (_progressShowAll == value) return;
    _progressShowAll = value;
    await _persist();
  }

  /// Total threads across every live impulse (daily-day, checklist and the
  /// long-term curriculum trees) — the analytics "Threads" figure.
  int get totalThreadCount {
    var n = 0;
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      n += i.allThreads.length;
    }
    return n;
  }

  /// A streak of consecutive days (up to today) on which at least one thread in
  /// any impulse was ticked — the "all reflexes" activity streak.
  int activityStreak() {
    final done = <String>{};
    for (final i in _impulses) {
      if (i.deletedAt != null || i.archived) continue;
      for (final t in i.allThreads) {
        done.addAll(t.doneDays);
      }
    }
    if (done.isEmpty) return 0;
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    // Today still in progress: start counting from today if done, else yesterday.
    if (!done.contains(_dayKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (done.contains(_dayKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ---- Time spent writing (analytics) --------------------------------------
  DateTime? _lastTypingAt;
  int _typingMillis = 0;

  /// Cumulative active-typing time across the app. Persisted with the library.
  Duration get typingTime => Duration(milliseconds: _typingMillis);

  /// Called on each editor keystroke; gaps under 8s count as continuous typing,
  /// so idle time between sessions isn't billed. Flushed to disk on the next
  /// [_persist] (e.g. when the note saves) rather than every keystroke.
  void recordTypingActivity() {
    final now = DateTime.now();
    final last = _lastTypingAt;
    _lastTypingAt = now;
    if (last != null) {
      final d = now.difference(last).inMilliseconds;
      if (d > 0 && d < 8000) _typingMillis += d;
    }
  }

  /// Whether the Journal / Cortex groups in the side pane are expanded — kept so
  /// they reopen where the user left them.
  bool get journalPaneOpen => _journalPaneOpen;
  bool get cortexPaneOpen => _cortexPaneOpen;

  Future<void> setJournalPaneOpen(bool value) async {
    if (_journalPaneOpen == value) return;
    _journalPaneOpen = value;
    await _persist();
  }

  Future<void> setCortexPaneOpen(bool value) async {
    if (_cortexPaneOpen == value) return;
    _cortexPaneOpen = value;
    await _persist();
  }

  /// The id of the reflex pinned into the journal feed (default: the daily day).
  String get pinnedReflexId => _pinnedReflexId;

  /// The pinned reflex whose threads show below the week strip; falls back to
  /// the daily day if the pinned one was deleted.
  Impulse get pinnedReflex => impulseById(_pinnedReflexId) ?? dailyDay;

  /// Whether [id] names the daily day (its journal title stays "Your daily day").
  bool isDailyDay(String id) => id == dailyDayId;

  Future<void> setPinnedReflex(String id) async {
    if (_pinnedReflexId == id) return;
    _pinnedReflexId = id;
    await _persist();
  }

  /// The journal's three movable sections. Always normalised to contain each
  /// of 'tasks', 'card' and 'entries' exactly once.
  static const journalSections = ['tasks', 'card', 'entries'];
  List<String> get journalOrder {
    final order = _journalOrder.where(journalSections.contains).toList();
    for (final s in journalSections) {
      if (!order.contains(s)) order.add(s);
    }
    return order;
  }

  Future<void> setJournalOrder(List<String> order) async {
    _journalOrder = order.where(journalSections.contains).toList();
    await _persist();
  }

  /// Adds a task to the daily day, creating (and persisting) the reflex on the
  /// first task so it doesn't exist until it's actually used.
  Future<void> addDailyTask(String title) async {
    if (title.trim().isEmpty) return;
    _dailyDayImpulse().threads.add(Thread(title: title.trim()));
    await _persist();
  }

  /// Adds a blank thread to an impulse and returns its id, so the task sheet
  /// can open on it. The daily day is created on demand if still transient.
  /// Returns null if a non-daily impulse is gone. A thread left blank is
  /// cleaned up when the sheet closes.
  Future<String?> addBlankThread(String impulseId) async {
    var impulse = impulseById(impulseId);
    if (impulse == null) {
      if (impulseId != dailyDayId) return null;
      impulse = _dailyDayImpulse();
    }
    final t = Thread();
    impulse.threads.add(t);
    impulse.updatedAt = DateTime.now();
    await _persist();
    return t.id;
  }

  Impulse _dailyDayImpulse() {
    var d = impulseById(dailyDayId);
    if (d == null) {
      // Born grey so it's visibly the "loose tasks" bucket, not a real project.
      d = Impulse(
        id: dailyDayId,
        title: 'Daily day',
        mode: ImpulseMode.daily,
        colorValue: dailyDayColorValue,
      );
      _impulses.add(d);
    }
    d.updatedAt = DateTime.now();
    return d;
  }

  /// Sets (or clears, when [minutes] is null) a Thread's gentle daily reminder,
  /// keeping the scheduled notification in sync.
  Future<void> setThreadReminder(
      String impulseId, String threadId, int? minutes) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    final thread = impulse.findThread(threadId);
    if (thread == null) return;
    thread.reminderMinutes = minutes;
    impulse.updatedAt = DateTime.now();
    if (minutes != null) {
      unawaited(NotificationService.instance.scheduleThreadReminder(
        threadId: thread.id,
        title: thread.title.trim().isEmpty ? 'Daily day' : thread.title.trim(),
        body: 'From your daily day',
        hour: minutes ~/ 60,
        minute: minutes % 60,
        weekdays: impulse.days,
      ));
    } else {
      unawaited(NotificationService.instance.cancelThreadReminder(thread.id));
    }
    await _persist();
  }

  /// Sets the same time window on every thread of an impulse — a shortcut for
  /// when all its tasks share one slot (e.g. a fixed study hour). [startMinutes]
  /// is minutes past midnight; [endMinutes] is the optional window end (null
  /// clears it). Any thread with notifications on is rescheduled to the new
  /// time. Returns how many threads were moved.
  Future<int> setImpulseThreadsTime(
      String impulseId, int startMinutes, int? endMinutes) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return 0;
    final threads = impulse.allThreads;
    for (final t in threads) {
      t.reminderMinutes = startMinutes;
      t.endMinutes = endMinutes;
      if (t.notify) {
        unawaited(NotificationService.instance.scheduleThreadReminder(
          threadId: t.id,
          title: t.title.trim().isEmpty ? 'Daily day' : t.title.trim(),
          body: 'From your daily day',
          hour: startMinutes ~/ 60,
          minute: startMinutes % 60,
          weekdays: t.days,
        ));
      }
    }
    impulse.updatedAt = DateTime.now();
    await _persist();
    return threads.length;
  }

  Impulse? impulseById(String id) {
    for (final i in _impulses) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<Impulse> addImpulse({
    required String title,
    String goal = '',
    DateTime? startDate,
    DateTime? deadline,
    String mode = ImpulseMode.daily,
    String category = '',
    Set<int> days = const {},
  }) async {
    final impulse = Impulse(
      title: title.trim(),
      goal: goal.trim(),
      startDate: startDate,
      deadline: deadline,
      mode: mode,
      category: category.trim(),
      days: {...days},
    );
    _impulses.add(impulse);
    await _persist();
    return impulse;
  }

  Future<void> updateImpulse(Impulse impulse) async {
    impulse.updatedAt = DateTime.now();
    final idx = _impulses.indexWhere((i) => i.id == impulse.id);
    if (idx >= 0) _impulses[idx] = impulse;
    // Resync thread reminders (each thread carries its own days + opt-in).
    for (final t in impulse.allThreads) {
      final m = t.reminderMinutes;
      if (t.notify && m != null) {
        unawaited(NotificationService.instance.scheduleThreadReminder(
          threadId: t.id,
          title: t.title.trim().isEmpty ? 'Daily day' : t.title.trim(),
          body: 'From your daily day',
          hour: m ~/ 60,
          minute: m % 60,
          weekdays: t.days,
        ));
      }
    }
    await _persist();
  }

  Future<void> deleteImpulse(String id) async {
    _impulses.removeWhere((i) => i.id == id);
    // A deleted reflex can't stay pinned — fall back to the daily day.
    if (_pinnedReflexId == id) _pinnedReflexId = dailyDayId;
    await _persist();
  }

  /// Puts an impulse on hold (or resumes it). Pausing the pinned reflex falls
  /// the journal feed back to the daily day.
  Future<void> setImpulsePaused(String id, bool paused) async {
    final impulse = impulseById(id);
    if (impulse == null) return;
    impulse.paused = paused;
    impulse.updatedAt = DateTime.now();
    if (paused && _pinnedReflexId == id) _pinnedReflexId = dailyDayId;
    await _persist();
  }

  /// Archives an impulse (hidden from the active list) or restores it. An
  /// archived reflex can't stay pinned into the journal.
  Future<void> setImpulseArchived(String id, bool archived) async {
    final impulse = impulseById(id);
    if (impulse == null) return;
    impulse.archived = archived;
    impulse.updatedAt = DateTime.now();
    if (archived && _pinnedReflexId == id) _pinnedReflexId = dailyDayId;
    await _persist();
  }

  /// Archived reflexes, newest first (never the daily day).
  List<Impulse> get archivedReflexes {
    final list = _impulses
        .where((i) =>
            i.id != dailyDayId && i.deletedAt == null && i.archived)
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Drag-reorders a thread within its impulse.
  Future<void> reorderThread(
      String impulseId, int oldIndex, int newIndex) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    if (oldIndex < 0 || oldIndex >= impulse.threads.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final t = impulse.threads.removeAt(oldIndex);
    impulse.threads.insert(newIndex.clamp(0, impulse.threads.length), t);
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  /// Moves a thread to another impulse (e.g. promote a daily task to a project).
  Future<void> moveThread(
      String fromId, String threadId, String toId) async {
    if (fromId == toId) return;
    final from = impulseById(fromId);
    if (from == null) return;
    final idx = from.threads.indexWhere((t) => t.id == threadId);
    if (idx < 0) return;
    var to = impulseById(toId);
    if (to == null) {
      if (toId != dailyDayId) return;
      to = _dailyDayImpulse();
    }
    to.threads.add(from.threads.removeAt(idx));
    from.updatedAt = DateTime.now();
    to.updatedAt = DateTime.now();
    await _persist();
  }

  /// Reorders threads by flag priority (important first), stable within a flag.
  Future<void> sortThreadsByFlag(String impulseId) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    final indexed = [
      for (var i = 0; i < impulse.threads.length; i++)
        MapEntry(i, impulse.threads[i]),
    ];
    indexed.sort((a, b) {
      final r =
          TaskFlag.rank(a.value.flag).compareTo(TaskFlag.rank(b.value.flag));
      return r != 0 ? r : a.key.compareTo(b.key);
    });
    impulse.threads = [for (final e in indexed) e.value];
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  /// Marks an impulse complete by hand (e.g. finished early), or reopens it.
  Future<void> setImpulseCompleted(String id, bool completed) async {
    final impulse = impulseById(id);
    if (impulse == null) return;
    impulse.completedAt = completed ? DateTime.now() : null;
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  /// The current and best run of complete days for an impulse, counted over
  /// its scheduled days only (a missed scheduled day breaks the run; a not-yet-
  /// done today is treated as still in progress, not a break).
  ReflexStreak streakFor(Impulse imp) {
    if (imp.threads.isEmpty) return const ReflexStreak(0, 0);
    String? minDay;
    for (final t in imp.threads) {
      for (final d in t.doneDays) {
        if (minDay == null || d.compareTo(minDay) < 0) minDay = d;
      }
    }
    if (minDay == null) return const ReflexStreak(0, 0);
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final parsed = DateTime.tryParse(minDay);
    var start =
        parsed == null ? end : DateTime(parsed.year, parsed.month, parsed.day);
    if (start.isAfter(end)) return const ReflexStreak(0, 0);
    // Never scan more than ~a year: bounds the cost (and guards bad data). A
    // streak beyond a year isn't worth walking day by day to display.
    final earliest = end.subtract(const Duration(days: 366));
    if (start.isBefore(earliest)) start = earliest;

    var best = 0, run = 0;
    for (var c = start; !c.isAfter(end); c = c.add(const Duration(days: 1))) {
      if (!imp.scheduledOn(c.weekday)) continue;
      if (imp.allDoneOn(_dayKey(c))) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }

    var current = 0;
    for (var c = end; !c.isBefore(start); c = c.subtract(const Duration(days: 1))) {
      if (!imp.scheduledOn(c.weekday)) continue;
      if (imp.allDoneOn(_dayKey(c))) {
        current++;
      } else if (c == end) {
        continue; // today, still in progress
      } else {
        break;
      }
    }
    return ReflexStreak(current, best);
  }

  /// Colour-codes an impulse (a NoteColors swatch int, or null to clear).
  Future<void> setImpulseColor(String id, int? colorValue) async {
    final impulse = impulseById(id);
    if (impulse == null) return;
    impulse.colorValue = colorValue;
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  /// Ticks (or unticks) every thread of an impulse for [dayKey] at once — used
  /// by the daily day's "mark all complete". Never marks a future day.
  Future<void> markAllThreadsDone(
      String impulseId, String dayKey, bool done) async {
    if (done && dayKey.compareTo(todayKey) > 0) return; // no future completion
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    for (final t in impulse.threads) {
      if (done) {
        t.doneDays.add(dayKey);
      } else if (t.once) {
        // One-time tasks are done for good, so clearing means clearing all.
        t.doneDays.clear();
      } else {
        t.doneDays.remove(dayKey);
      }
    }
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> addThread(String impulseId, String title) async {
    final impulse = impulseById(impulseId);
    if (impulse == null || title.trim().isEmpty) return;
    impulse.threads.add(Thread(title: title.trim()));
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> deleteThread(String impulseId, String threadId) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    impulse.removeThread(threadId);
    impulse.updatedAt = DateTime.now();
    // Drop any pending reminder for the removed thread.
    unawaited(NotificationService.instance.cancelThreadReminder(threadId));
    await _persist();
  }

  /// Ticks / unticks a Thread for [dayKey]. Daily threads record that one day
  /// (keeping the per-day history); a checklist thread flips done-for-good.
  Future<void> toggleThreadOn(
      String impulseId, String threadId, String dayKey) async {
    // Past and future days can both be ticked now (the calendar/journal guard
    // any edits more than 2 days out with a confirmation first).
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    final thread = impulse.findThread(threadId);
    if (thread == null) return;
    if (thread.once) {
      // One-time task: done for good, so flip the whole thing on/off.
      if (thread.doneDays.isEmpty) {
        thread.doneDays.add(dayKey);
      } else {
        thread.doneDays.clear();
      }
    } else if (impulse.isDaily || impulse.isLongTerm) {
      if (!thread.doneDays.remove(dayKey)) thread.doneDays.add(dayKey);
    } else if (thread.doneDays.isEmpty) {
      thread.doneDays.add(dayKey);
    } else {
      thread.doneDays.clear();
    }
    impulse.updatedAt = DateTime.now();
    await _persist();
  }

  /// Ticks / unticks a Thread for today.
  Future<void> toggleThread(String impulseId, String threadId) =>
      toggleThreadOn(impulseId, threadId, todayKey);

  /// Persists edits made to a Thread in place (title, description, times,
  /// links, location…) and keeps its reminder notification in sync.
  Future<void> updateThread(String impulseId, Thread thread) async {
    final impulse = impulseById(impulseId);
    if (impulse == null) return;
    if (!impulse.replaceThread(thread)) return;
    impulse.updatedAt = DateTime.now();
    final m = thread.reminderMinutes;
    // A reminder fires only when the thread opts in AND has a start time, on its
    // own chosen weekdays (empty = every day).
    if (thread.notify && m != null) {
      unawaited(NotificationService.instance.scheduleThreadReminder(
        threadId: thread.id,
        title: thread.title.trim().isEmpty ? 'Daily day' : thread.title.trim(),
        body: 'From your daily day',
        hour: m ~/ 60,
        minute: m % 60,
        weekdays: thread.days,
      ));
    } else {
      unawaited(NotificationService.instance.cancelThreadReminder(thread.id));
    }
    await _persist();
  }

  // ---- Long-term impulses: sections & subsections ------------------------

  Section? _section(String impulseId, String sectionId) {
    final imp = impulseById(impulseId);
    if (imp == null) return null;
    for (final s in imp.sections) {
      if (s.id == sectionId) return s;
    }
    return null;
  }

  Subsection? _subsection(String impulseId, String sectionId, String subId) {
    final s = _section(impulseId, sectionId);
    if (s == null) return null;
    for (final sub in s.subsections) {
      if (sub.id == subId) return sub;
    }
    return null;
  }

  void _touchImpulse(String impulseId) {
    final imp = impulseById(impulseId);
    if (imp != null) imp.updatedAt = DateTime.now();
  }

  Future<void> addSection(String impulseId, String title,
      {DateTime? startDate, DateTime? deadline}) async {
    final imp = impulseById(impulseId);
    if (imp == null) return;
    imp.sections.add(
        Section(title: title.trim(), startDate: startDate, deadline: deadline));
    imp.updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> renameSection(
      String impulseId, String sectionId, String title) async {
    final s = _section(impulseId, sectionId);
    if (s == null) return;
    s.title = title.trim();
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> deleteSection(String impulseId, String sectionId) async {
    final imp = impulseById(impulseId);
    if (imp == null) return;
    for (final s in imp.sections.where((s) => s.id == sectionId)) {
      for (final sub in s.subsections) {
        for (final t in sub.threads) {
          unawaited(
              NotificationService.instance.cancelThreadReminder(t.id));
        }
      }
    }
    imp.sections.removeWhere((s) => s.id == sectionId);
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> toggleSectionCollapsed(
      String impulseId, String sectionId) async {
    final s = _section(impulseId, sectionId);
    if (s == null) return;
    s.collapsed = !s.collapsed;
    await _persist();
  }

  /// Sets (or clears, with null) a section's start/deadline dates.
  Future<void> setSectionDates(String impulseId, String sectionId,
      {required DateTime? start, required DateTime? deadline}) async {
    final s = _section(impulseId, sectionId);
    if (s == null) return;
    s.startDate = start;
    s.deadline = deadline;
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> addSubsection(
      String impulseId, String sectionId, String title) async {
    final s = _section(impulseId, sectionId);
    if (s == null) return;
    s.subsections.add(Subsection(title: title.trim()));
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> renameSubsection(String impulseId, String sectionId,
      String subId, String title) async {
    final sub = _subsection(impulseId, sectionId, subId);
    if (sub == null) return;
    sub.title = title.trim();
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> deleteSubsection(
      String impulseId, String sectionId, String subId) async {
    final s = _section(impulseId, sectionId);
    if (s == null) return;
    for (final sub in s.subsections.where((sub) => sub.id == subId)) {
      for (final t in sub.threads) {
        unawaited(NotificationService.instance.cancelThreadReminder(t.id));
      }
    }
    s.subsections.removeWhere((sub) => sub.id == subId);
    _touchImpulse(impulseId);
    await _persist();
  }

  Future<void> toggleSubsectionCollapsed(
      String impulseId, String sectionId, String subId) async {
    final sub = _subsection(impulseId, sectionId, subId);
    if (sub == null) return;
    sub.collapsed = !sub.collapsed;
    await _persist();
  }

  /// Adds a blank thread to a subsection and returns its id, so the task sheet
  /// can open on it (mirrors [addBlankThread] for the flat list).
  Future<String?> addBlankThreadToSubsection(
      String impulseId, String sectionId, String subId) async {
    final sub = _subsection(impulseId, sectionId, subId);
    if (sub == null) return null;
    final t = Thread();
    sub.threads.add(t);
    _touchImpulse(impulseId);
    await _persist();
    return t.id;
  }

  Future<void> reorderThreadInSubsection(String impulseId, String sectionId,
      String subId, int oldIndex, int newIndex) async {
    final sub = _subsection(impulseId, sectionId, subId);
    if (sub == null) return;
    if (oldIndex < 0 || oldIndex >= sub.threads.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final t = sub.threads.removeAt(oldIndex);
    sub.threads.insert(newIndex.clamp(0, sub.threads.length), t);
    _touchImpulse(impulseId);
    await _persist();
  }

  /// Renames a long-term goal's daily-reminder list (its flat threads).
  Future<void> renameDailyReminder(String impulseId, String title) async {
    final imp = impulseById(impulseId);
    if (imp == null) return;
    imp.dailyReminderTitle = title.trim();
    imp.updatedAt = DateTime.now();
    await _persist();
  }

  // ---- Persistence -------------------------------------------------------

  Timer? _flushTimer;
  bool _dirty = false;
  Future<void> _writeChain = Future.value();
  Future<void> _dbWriteChain = Future.value();

  /// The `_rev` captured at the last whole-file JSON checkpoint, so repeated
  /// pauses with no edits in between don't re-write an identical file.
  int _revAtJsonCheckpoint = -1;

  /// Whether this launch has already raised the JSON-ahead flag (it only needs
  /// raising once per stretch of JSON-mode saves).
  bool _jsonAheadMarked = false;

  /// Whether SQLite is the live store this launch: it imported cleanly and the
  /// read flag is on. When false (fallback, or unit tests where sqflite is off)
  /// the app runs on the JSON store exactly as it did before the migration.
  bool get _dbIsPrimary => DbStore.readFromDb && _dbStore.usableForReads;

  /// Marks the library dirty and notifies immediately; the actual disk write
  /// is coalesced (~400ms) and runs on a background isolate. A burst of
  /// mutations becomes a single write.
  Future<void> _persist() async {
    // A late async callback (a link preview finishing, say) may land after
    // dispose; there is nothing left to notify or save for.
    if (_disposed) return;
    _rev++;
    _dirty = true;
    notifyListeners();
    _flushTimer ??= Timer(const Duration(milliseconds: 400), () {
      _flushTimer = null;
      _flush();
    });
  }

  /// The whole in-memory library and settings as an [AppData] — what a save
  /// persists. Kept in one place so the disk write, the DB sync and the
  /// post-restore reconcile all serialize exactly the same state.
  AppData _snapshot() => AppData(
        notes: _notes,
        spaces: _spaces,
        cards: _cards,
        books: _books,
        impulses: _impulses,
        cardsCompact: _cardsCompact,
        darkMode: _darkMode,
        darkFollowSystem: _darkFollowSystem,
        noteBodyFont: _noteBodyFont,
        tutorialSeen: _tutorialSeen,
        lastBackupAt: _lastBackupAt,
        backupReminderDismissedAt: _backupReminderDismissedAt,
        localAutoBackup: _localAutoBackup,
        localAutoBackupFreq: _localAutoBackupFreq,
        driveAutoBackup: _driveAutoBackup,
        lastDriveBackupAt: _lastDriveBackupAt,
        driveAccountEmail: _driveAccountEmail,
        driveAccountName: _driveAccountName,
        driveAccountPhotoUrl: _driveAccountPhotoUrl,
        sortMode: _sortMode.name,
        feedWallpaper: _feedWallpaper,
        feedBackgroundLight: _feedBackgroundLight,
        feedBackgroundDark: _feedBackgroundDark,
        readerFontScale: _readerFontScale,
        readerFont: _readerFont,
        readerTheme: _readerTheme,
        journalReminderOn: _journalReminderOn,
        journalReminderMinutes: _journalReminderMinutes,
        pinnedReflexId: _pinnedReflexId,
        progressImpulseId: _progressImpulseId,
        journalPaneOpen: _journalPaneOpen,
        cortexPaneOpen: _cortexPaneOpen,
        progressShowAll: _progressShowAll,
        typingMillis: _typingMillis,
        journalOrder: _journalOrder,
        journalMonthCovers: Map.of(_journalMonthCovers),
        readerPositions: Map.of(_readerPositions),
        readerBookmarks: {
          for (final e in _readerBookmarks.entries) e.key: List.of(e.value)
        },
      );

  void _flush() {
    if (!_dirty) return;
    _dirty = false;
    final snapshot = _snapshot();
    // Phase 3: SQLite is the sole per-save store — one edit writes one row, not
    // the whole library. Serialized on its own chain; a failed DB write is
    // retried on the next save and never surfaces.
    _dbWriteChain = _dbWriteChain.then((_) async {
      await _dbStore.syncFromAppData(snapshot);
    }).catchError((_) {});
    // The whole-file JSON is written per save only when the DB isn't the live
    // store (fallback / unit tests) or the Phase 2 mirror is kept on; otherwise
    // it's refreshed at checkpoints in flushNow() as a rollback + backup copy.
    if (!_dbIsPrimary || DbStore.writeJsonOnSave) {
      _revAtJsonCheckpoint = _rev;
      // Saving to JSON because the DB isn't the live store: flag the JSON as
      // ahead (once per stretch), so the next launch that does get the DB
      // folds these edits into it instead of reading the stale DB over them.
      final markAhead = !_dbIsPrimary && !_jsonAheadMarked;
      if (markAhead) _jsonAheadMarked = true;
      // catchError: one failed write (disk full, say) must not poison the
      // chain and silently skip every save after it.
      _writeChain = _writeChain.then((_) async {
        if (markAhead) await _storage.markJsonAhead();
        await _storage.save(snapshot);
      }).catchError((_) {});
    }
  }

  /// Forces any pending changes to disk now (app pause, before backup or
  /// restore). Awaits both stores so nothing is left in flight — the DB in
  /// particular, since the next launch reads from it.
  Future<void> flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
    // Phase 3 checkpoint: per-save JSON writes are off, so refresh the on-disk
    // JSON here (pause, before a backup/restore) — it keeps `keepy_data.json`
    // current for the backup zip and as the rollback artifact. Skipped when the
    // library hasn't changed since the last checkpoint, or when _flush already
    // wrote JSON this call.
    if (_loaded &&
        _dbIsPrimary &&
        !DbStore.writeJsonOnSave &&
        _rev != _revAtJsonCheckpoint) {
      _revAtJsonCheckpoint = _rev;
      final snapshot = _snapshot();
      _writeChain = _writeChain
          .then((_) => _storage.save(snapshot))
          .catchError((_) {});
    }
    await _writeChain;
    await _dbWriteChain;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    super.dispose();
  }
}
