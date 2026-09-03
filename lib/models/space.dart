import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A folder that groups notes together.
class Space {
  Space({
    String? id,
    required this.name,
    this.thumbnailPath,
    this.colorValue,
    this.archived = false,
    this.deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  String name;

  /// Absolute path to an uploaded thumbnail image, or null.
  String? thumbnailPath;

  /// Optional folder colour (ARGB int of a swatch); null = default surface.
  /// Tints the folder card and its chips so folders are visually distinct.
  int? colorValue;

  /// Archived folders are hidden from Cortex and live in the Archive.
  bool archived;

  /// When set, the folder is in Recently Deleted (kept ~30 days, then purged).
  DateTime? deletedAt;

  final DateTime createdAt;

  /// Last mutation time; drives last-write-wins when syncing.
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailPath': thumbnailPath,
        if (colorValue != null) 'colorValue': colorValue,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        id: json['id'] as String?,
        name: (json['name'] as String?) ?? 'Untitled',
        thumbnailPath: json['thumbnailPath'] as String?,
        colorValue: json['colorValue'] as int?,
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}
