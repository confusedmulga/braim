import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum NoteBlockType { text, image, link }

/// A single chunk of a note. A note is an ordered list of these, so images
/// and link cards can sit in between text the way the user wants.
class NoteBlock {
  NoteBlock({
    String? id,
    required this.type,
    this.text = '',
    this.imagePath = '',
    this.url = '',
    this.linkTitle = '',
    this.linkImage = '',
    this.linkSite = '',
    this.linkFetched = false,
  }) : id = id ?? _uuid.v4();

  final String id;
  final NoteBlockType type;

  /// Used when [type] is text.
  String text;

  /// Absolute path to a saved image file when [type] is image.
  String imagePath;

  /// The pasted URL when [type] is link, plus its fetched preview.
  String url;
  String linkTitle;
  String linkImage;
  String linkSite;
  bool linkFetched;

  bool get isImage => type == NoteBlockType.image;
  bool get isText => type == NoteBlockType.text;
  bool get isLink => type == NoteBlockType.link;

  NoteBlock copyWith({NoteBlockType? type, String? text, String? imagePath}) {
    return NoteBlock(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      url: url,
      linkTitle: linkTitle,
      linkImage: linkImage,
      linkSite: linkSite,
      linkFetched: linkFetched,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'imagePath': imagePath,
        if (url.isNotEmpty) 'url': url,
        if (linkTitle.isNotEmpty) 'linkTitle': linkTitle,
        if (linkImage.isNotEmpty) 'linkImage': linkImage,
        if (linkSite.isNotEmpty) 'linkSite': linkSite,
        if (linkFetched) 'linkFetched': linkFetched,
      };

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
        id: json['id'] as String?,
        type: NoteBlockType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => NoteBlockType.text,
        ),
        text: (json['text'] as String?) ?? '',
        imagePath: (json['imagePath'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        linkTitle: (json['linkTitle'] as String?) ?? '',
        linkImage: (json['linkImage'] as String?) ?? '',
        linkSite: (json['linkSite'] as String?) ?? '',
        linkFetched: (json['linkFetched'] as bool?) ?? false,
      );
}
