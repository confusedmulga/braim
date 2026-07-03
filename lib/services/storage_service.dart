import 'dart:convert';
import 'dart:io';

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
    try {
      final file = await _dataFile;
      if (!await file.exists()) return AppData.empty();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AppData.empty();
      final json = jsonDecode(raw) as Map<String, dynamic>;
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
      );
    } catch (_) {
      return AppData.empty();
    }
  }

  Future<void> save(AppData data) async {
    final file = await _dataFile;
    final json = {
      'notes': data.notes.map((n) => n.toJson()).toList(),
      'spaces': data.spaces.map((s) => s.toJson()).toList(),
      'cards': data.cards.map((c) => c.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(json));
  }
}

class AppData {
  AppData({
    required this.notes,
    required this.spaces,
    required this.cards,
  });
  factory AppData.empty() => AppData(notes: [], spaces: [], cards: []);

  final List<Note> notes;
  final List<Space> spaces;
  final List<TweetCard> cards;
}
