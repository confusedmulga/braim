import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';
import '../services/link_preview_service.dart';
import '../services/storage_service.dart';
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

class AppState extends ChangeNotifier {
  AppState();

  final _storage = StorageService.instance;
  final _linkPreview = LinkPreviewService();

  final List<Note> _notes = [];
  final List<Space> _spaces = [];
  final List<TweetCard> _cards = [];

  bool _loaded = false;
  bool get loaded => _loaded;

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

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    AppPalette.dark = effectiveDark;
    await _persist();
  }

  Future<void> init() async {
    final data = await _storage.load();
    _notes
      ..clear()
      ..addAll(data.notes);
    _spaces
      ..clear()
      ..addAll(data.spaces);
    _cards
      ..clear()
      ..addAll(data.cards);
    _cardsCompact = data.cardsCompact;
    _darkMode = data.darkMode;
    _darkFollowSystem = data.darkFollowSystem;
    _tutorialSeen = data.tutorialSeen;
    _lastBackupAt = data.lastBackupAt;
    _backupReminderDismissedAt = data.backupReminderDismissedAt;
    _sortMode = _sortFromName(data.sortMode);
    _feedWallpaper = data.feedWallpaper;
    _journalMonthCovers
      ..clear()
      ..addAll(data.journalMonthCovers);
    _rev++;
    AppPalette.dark = effectiveDark;
    await _purgeExpiredTrash();
    await _importSharedInbox();
    _loaded = true;
    notifyListeners();

    // Cards saved by the share popup arrive without a preview; enrich them in
    // the background now. Capped so a dead link doesn't refetch every launch.
    for (final c in _cards
        .where((c) => !c.fetched && c.enrichAttempts < 3)
        .toList()) {
      c.enrichAttempts++;
      _linkPreview.enrich(c).then((_) => _persist());
    }
  }

  // ---- Reads -------------------------------------------------------------

  /// A note is on the "home feed" when it isn't archived, deleted, in Crypt,
  /// or a journal entry (those live only in the Journal tab).
  bool _isFeedNote(Note n) =>
      !n.archived &&
      n.deletedAt == null &&
      n.spaceId != kCryptSpaceId &&
      n.journalDate == null;

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
      _notesCache = _notes.where(_isFeedNote).toList()
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
    ..sort(_byCreatedDesc);

  int noteCountForSpace(String spaceId) => _notes
      .where((n) => n.spaceId == spaceId && !n.archived && n.deletedAt == null)
      .length;

  List<Space> get spaces => _spaces.where(_isLiveSpace).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<TweetCard> get cards {
    if (_cardsRev != _rev || _cardsCache == null) {
      _cardsCache = _cards.where(_isFeedCard).toList()
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
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

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

  /// Soft-delete: moves the note to Recently Deleted (kept ~30 days).
  Future<void> deleteNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx].deletedAt = DateTime.now();
    await _persist();
  }

  Future<void> restoreNote(String id) async {
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _notes[idx].deletedAt = null;
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
    await _storage.save(AppData(
        notes: _notes,
        spaces: _spaces,
        cards: _cards,
        cardsCompact: _cardsCompact,
        darkMode: _darkMode,
        darkFollowSystem: _darkFollowSystem,
        tutorialSeen: _tutorialSeen,
        lastBackupAt: _lastBackupAt,
        backupReminderDismissedAt: _backupReminderDismissedAt,
        sortMode: _sortMode.name,
        feedWallpaper: _feedWallpaper,
        journalMonthCovers: _journalMonthCovers));
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
    await _persist();
    return true;
  }

  /// Pins/unpins a card. Returns false when the pin limit is already reached.
  Future<bool> setCardPinned(String cardId, bool pinned) async {
    if (pinned &&
        _cards.where((c) => _isFeedCard(c) && c.pinned).length >= kMaxPins) {
      return false;
    }
    final card = _cards.firstWhere((c) => c.id == cardId);
    card.pinned = pinned;
    await _persist();
    return true;
  }

  /// Deletes an image file that was removed from a note in the editor.
  Future<void> refreshAfterImageRemoval(String path) async {
    if (path.isEmpty) return;
    await _storage.deleteImage(path);
  }

  // ---- Spaces ------------------------------------------------------------

  Future<Space> addSpace(String name, {String? thumbnailPath}) async {
    final space = Space(name: name, thumbnailPath: thumbnailPath);
    _spaces.add(space);
    await _persist();
    return space;
  }

  Future<void> updateSpace(Space space) async {
    final idx = _spaces.indexWhere((s) => s.id == space.id);
    if (idx >= 0) _spaces[idx] = space;
    await _persist();
  }

  /// Soft-delete: the folder moves to Recently Deleted; its notes/cards keep
  /// their association (still visible in the feeds) and come back with it.
  Future<void> deleteSpace(String id) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx].deletedAt = DateTime.now();
    await _persist();
  }

  Future<void> restoreSpace(String id) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx]
      ..deletedAt = null
      ..archived = false;
    await _persist();
  }

  Future<void> setSpaceArchived(String id, bool archived) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _spaces[idx].archived = archived;
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
    }
    for (final c in _cards.where((c) => c.spaceId == space.id)) {
      c.spaceId = null;
    }
  }

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
      await _persist();
      return card;
    }
    final card = TweetCard(url: cleaned, spaceId: spaceId);
    _cards.add(card);
    await _persist();

    // Fetch preview without blocking the UI.
    _linkPreview.enrich(card).then((_) => _persist());
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
      if (url == null || url.isEmpty) continue;
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
      await addCardFromUrl(url, spaceId: spaceId);
    }
  }

  Future<void> refreshCard(String id) async {
    final card = _cards.firstWhere((c) => c.id == id);
    await _linkPreview.enrich(card);
    await _persist();
  }

  Future<void> updateCard(TweetCard card) async {
    final idx = _cards.indexWhere((c) => c.id == card.id);
    if (idx >= 0) _cards[idx] = card;
    await _persist();
  }

  /// Soft-delete: moves the card to Recently Deleted (kept ~30 days).
  Future<void> deleteCard(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx].deletedAt = DateTime.now();
    await _persist();
  }

  Future<void> restoreCard(String id) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx]
      ..deletedAt = null
      ..archived = false;
    await _persist();
  }

  Future<void> setCardArchived(String id, bool archived) async {
    final idx = _cards.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    _cards[idx].archived = archived;
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

  // ---- Persistence -------------------------------------------------------

  Timer? _flushTimer;
  bool _dirty = false;
  Future<void> _writeChain = Future.value();

  /// Marks the library dirty and notifies immediately; the actual disk write
  /// is coalesced (~400ms) and runs on a background isolate. A burst of
  /// mutations becomes a single write.
  Future<void> _persist() async {
    _rev++;
    _dirty = true;
    notifyListeners();
    _flushTimer ??= Timer(const Duration(milliseconds: 400), () {
      _flushTimer = null;
      _flush();
    });
  }

  void _flush() {
    if (!_dirty) return;
    _dirty = false;
    final snapshot = AppData(
      notes: _notes,
      spaces: _spaces,
      cards: _cards,
      cardsCompact: _cardsCompact,
      darkMode: _darkMode,
      darkFollowSystem: _darkFollowSystem,
      tutorialSeen: _tutorialSeen,
      lastBackupAt: _lastBackupAt,
      backupReminderDismissedAt: _backupReminderDismissedAt,
      sortMode: _sortMode.name,
      feedWallpaper: _feedWallpaper,
      journalMonthCovers: Map.of(_journalMonthCovers),
    );
    // Chain writes so they never interleave.
    _writeChain = _writeChain.then((_) => _storage.save(snapshot));
  }

  /// Forces any pending changes to disk now (app pause, before backup or
  /// restore).
  Future<void> flushNow() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
    await _writeChain;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}
