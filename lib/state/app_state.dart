import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';
import '../services/link_preview_service.dart';
import '../services/storage_service.dart';

/// Reserved space id for the locked Crypt folder.
const String kCryptSpaceId = '__crypt__';

/// How long deleted notes stay in Recently Deleted before being purged.
const Duration kTrashRetention = Duration(days: 30);

class AppState extends ChangeNotifier {
  AppState();

  final _storage = StorageService.instance;
  final _linkPreview = LinkPreviewService();

  final List<Note> _notes = [];
  final List<Space> _spaces = [];
  final List<TweetCard> _cards = [];

  bool _loaded = false;
  bool get loaded => _loaded;

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
    await _purgeExpiredTrash();
    _loaded = true;
    notifyListeners();

    // Cards saved by the share popup arrive without a preview; enrich them in
    // the background now.
    for (final c in _cards.where((c) => !c.fetched).toList()) {
      _linkPreview.enrich(c).then((_) => _persist());
    }
  }

  // ---- Reads -------------------------------------------------------------

  /// A note is on the "home feed" when it isn't archived, deleted, or in Crypt.
  bool _isFeedNote(Note n) =>
      !n.archived && n.deletedAt == null && n.spaceId != kCryptSpaceId;

  List<Note> get notes => _notes.where(_isFeedNote).toList()..sort(_byCreatedDesc);

  List<Note> get archivedNotes => _notes
      .where((n) =>
          n.archived && n.deletedAt == null && n.spaceId != kCryptSpaceId)
      .toList()
    ..sort(_byCreatedDesc);

  List<Note> get deletedNotes => _notes.where((n) => n.deletedAt != null).toList()
    ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  List<Note> notesForSpace(String spaceId) => _notes
      .where((n) => n.spaceId == spaceId && !n.archived && n.deletedAt == null)
      .toList()
    ..sort(_byCreatedDesc);

  int noteCountForSpace(String spaceId) => _notes
      .where((n) => n.spaceId == spaceId && !n.archived && n.deletedAt == null)
      .length;

  List<Space> get spaces =>
      List.unmodifiable(_spaces..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  List<TweetCard> get cards => _cards
      .where((c) => c.spaceId != kCryptSpaceId)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<TweetCard> cardsForSpace(String spaceId) =>
      (_cards.where((c) => c.spaceId == spaceId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  /// Notes + cards that live in a space.
  int itemCountForSpace(String spaceId) =>
      _notes
          .where((n) =>
              n.spaceId == spaceId && !n.archived && n.deletedAt == null)
          .length +
      _cards.where((c) => c.spaceId == spaceId).length;

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
    final trashed = _notes.where((n) => n.deletedAt != null).toList();
    for (final n in trashed) {
      _notes.remove(n);
      for (final path in n.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    await _persist();
  }

  Future<void> _purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(kTrashRetention);
    final expired = _notes
        .where((n) => n.deletedAt != null && n.deletedAt!.isBefore(cutoff))
        .toList();
    if (expired.isEmpty) return;
    for (final n in expired) {
      _notes.remove(n);
      for (final path in n.imagePaths) {
        await _storage.deleteImage(path);
      }
    }
    await _storage.save(AppData(notes: _notes, spaces: _spaces, cards: _cards));
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

  Future<void> deleteSpace(String id, {bool deleteNotes = false}) async {
    final idx = _spaces.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final space = _spaces.removeAt(idx);
    if (space.thumbnailPath != null) {
      await _storage.deleteImage(space.thumbnailPath!);
    }
    if (deleteNotes) {
      final toDelete = _notes.where((n) => n.spaceId == id).toList();
      for (final n in toDelete) {
        await deleteNote(n.id);
      }
    } else {
      for (final n in _notes.where((n) => n.spaceId == id)) {
        n.spaceId = null;
      }
    }
    // Cards in the space always fall back to no space.
    for (final c in _cards.where((c) => c.spaceId == id)) {
      c.spaceId = null;
    }
    await _persist();
  }

  // ---- Cards -------------------------------------------------------------

  /// Adds a shared link as a card and enriches it in the background.
  Future<TweetCard> addCardFromUrl(String url) async {
    final cleaned = _extractUrl(url);
    final card = TweetCard(url: cleaned);
    _cards.add(card);
    await _persist();

    // Fetch preview without blocking the UI.
    _linkPreview.enrich(card).then((_) => _persist());
    return card;
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

  Future<void> deleteCard(String id) async {
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

  Future<void> _persist() async {
    await _storage.save(AppData(
      notes: _notes,
      spaces: _spaces,
      cards: _cards,
    ));
    notifyListeners();
  }
}
