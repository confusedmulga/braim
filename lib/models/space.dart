import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A folder that groups notes together.
class Space {
  Space({
    String? id,
    required this.name,
    this.thumbnailPath,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;

  /// Absolute path to an uploaded thumbnail image, or null.
  String? thumbnailPath;

  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailPath': thumbnailPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Space.fromJson(Map<String, dynamic> json) => Space(
        id: json['id'] as String?,
        name: (json['name'] as String?) ?? 'Untitled',
        thumbnailPath: json['thumbnailPath'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
