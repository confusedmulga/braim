import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'note_block.dart';

const _uuid = Uuid();

/// Text blocks may store either plain text (legacy) or a Quill Delta JSON
/// string. This converts either form to plain text for previews.
String richToPlain(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (final op in decoded) {
          if (op is Map && op['insert'] is String) {
            buffer.write(op['insert']);
          }
        }
        return buffer.toString().trim();
      }
    } catch (_) {
      // Fall through and treat as plain text.
    }
  }
  return trimmed;
}

class Note {
  Note({
    String? id,
    this.title = '',
    List<NoteBlock>? blocks,
    this.spaceId,
    this.backgroundAsset,
    this.archived = false,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        blocks = blocks ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  List<NoteBlock> blocks;

  /// Id of the space (folder) this note belongs to, or null for the inbox.
  String? spaceId;

  /// Optional per-note background image asset (one of the BACK## assets).
  String? backgroundAsset;

  /// Archived notes are hidden from the feed and live in the Archive.
  bool archived;

  /// When set, the note is in Recently Deleted (kept ~30 days, then purged).
  DateTime? deletedAt;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Path of the first image in the note, used as the feed thumbnail.
  String? get thumbnailPath {
    for (final b in blocks) {
      if (b.isImage && b.imagePath.isNotEmpty) return b.imagePath;
    }
    return null;
  }

  /// Concatenated plain text preview for the feed.
  String get textPreview {
    final buffer = StringBuffer();
    for (final b in blocks) {
      if (b.isText) {
        final plain = richToPlain(b.text);
        if (plain.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(plain);
        }
      }
    }
    return buffer.toString();
  }

  bool get isEmpty =>
      title.trim().isEmpty &&
      blocks.every((b) => b.isText && richToPlain(b.text).isEmpty);

  List<String> get imagePaths => blocks
      .where((b) => b.isImage && b.imagePath.isNotEmpty)
      .map((b) => b.imagePath)
      .toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'spaceId': spaceId,
        'backgroundAsset': backgroundAsset,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String?,
        title: (json['title'] as String?) ?? '',
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        spaceId: json['spaceId'] as String?,
        backgroundAsset: json['backgroundAsset'] as String?,
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}
