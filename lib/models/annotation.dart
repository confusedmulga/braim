import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A passage the reader marked up: a highlight, optionally with a note
/// attached. Stored on the page it belongs to, keyed by the exact text so it
/// survives edits elsewhere in the chapter.
class Annotation {
  Annotation({
    String? id,
    required this.text,
    this.note = '',
    this.colorValue = 0xFFFFE082,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  final String id;

  /// The exact passage that was selected.
  String text;

  /// The reader's note about the passage ('' for a plain highlight).
  String note;

  /// ARGB of the highlight colour.
  int colorValue;

  final DateTime createdAt;

  bool get hasNote => note.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (note.isNotEmpty) 'note': note,
        'colorValue': colorValue,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String?,
        text: (json['text'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFE082,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  /// The highlighter palette offered in the reader.
  static const List<int> palette = [
    0xFFFFE082, // butter
    0xFFA5D6A7, // mint
    0xFF90CAF9, // sky
    0xFFF48FB1, // rose
    0xFFCE93D8, // lilac
  ];
}
