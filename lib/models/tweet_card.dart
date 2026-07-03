import 'package:uuid/uuid.dart';

import 'note_block.dart';

const _uuid = Uuid();

/// A saved link card. Optimised for tweets but works for any shared URL.
/// Beyond the fetched preview, a card carries its own note body (text + images)
/// the user can add, just like a note.
class TweetCard {
  TweetCard({
    String? id,
    required this.url,
    this.text = '',
    this.imageUrl = '',
    this.avatarUrl = '',
    this.authorName = '',
    this.authorHandle = '',
    this.siteName = '',
    this.fetched = false,
    this.spaceId,
    this.noteTitle = '',
    List<NoteBlock>? blocks,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        blocks = blocks ?? [],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String url;

  /// Tweet body / link description.
  String text;

  /// Remote image URL (tweet media or OG image).
  String imageUrl;

  /// Remote profile-picture URL of the tweet author.
  String avatarUrl;

  String authorName;
  String authorHandle;
  String siteName;

  /// Id of the space (folder) this card belongs to, or null.
  String? spaceId;

  /// Whether a preview was successfully fetched.
  bool fetched;

  /// User-added note attached to this card.
  String noteTitle;
  List<NoteBlock> blocks;

  final DateTime createdAt;

  bool get isTweet =>
      url.contains('twitter.com') || url.contains('x.com');

  List<String> get imagePaths => blocks
      .where((b) => b.isImage && b.imagePath.isNotEmpty)
      .map((b) => b.imagePath)
      .toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'text': text,
        'imageUrl': imageUrl,
        'avatarUrl': avatarUrl,
        'authorName': authorName,
        'authorHandle': authorHandle,
        'siteName': siteName,
        'fetched': fetched,
        'spaceId': spaceId,
        'noteTitle': noteTitle,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory TweetCard.fromJson(Map<String, dynamic> json) => TweetCard(
        id: json['id'] as String?,
        url: (json['url'] as String?) ?? '',
        text: (json['text'] as String?) ?? '',
        imageUrl: (json['imageUrl'] as String?) ?? '',
        avatarUrl: (json['avatarUrl'] as String?) ?? '',
        authorName: (json['authorName'] as String?) ?? '',
        authorHandle: (json['authorHandle'] as String?) ?? '',
        siteName: (json['siteName'] as String?) ?? '',
        fetched: (json['fetched'] as bool?) ?? false,
        spaceId: json['spaceId'] as String?,
        noteTitle: (json['noteTitle'] as String?) ?? '',
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
