import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum NoteBlockType { text, image }

/// A single chunk of a note. A note is an ordered list of these, so images can
/// sit in between text the way the user wants.
class NoteBlock {
  NoteBlock({
    String? id,
    required this.type,
    this.text = '',
    this.imagePath = '',
  }) : id = id ?? _uuid.v4();

  final String id;
  final NoteBlockType type;

  /// Used when [type] is text.
  String text;

  /// Absolute path to a saved image file when [type] is image.
  String imagePath;

  bool get isImage => type == NoteBlockType.image;
  bool get isText => type == NoteBlockType.text;

  NoteBlock copyWith({NoteBlockType? type, String? text, String? imagePath}) {
    return NoteBlock(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'imagePath': imagePath,
      };

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
        id: json['id'] as String?,
        type: NoteBlockType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => NoteBlockType.text,
        ),
        text: (json['text'] as String?) ?? '',
        imagePath: (json['imagePath'] as String?) ?? '',
      );
}
