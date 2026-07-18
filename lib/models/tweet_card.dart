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
    this.articleText = '',
    this.fetched = false,
    this.enrichAttempts = 0,
    this.spaceId,
    this.pinned = false,
    this.archived = false,
    this.deletedAt,
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

  /// Reader-mode capture: the page's full article text, extracted when the
  /// link was saved, so the card reads offline without a browser.
  String articleText;

  /// Id of the space (folder) this card belongs to, or null.
  String? spaceId;

  /// Whether a preview was successfully fetched.
  bool fetched;

  /// How many launch-time preview fetches have been attempted (capped so a
  /// permanently-failing link doesn't refetch forever).
  int enrichAttempts;

  /// Pinned cards sort to the top of the feed (max 10).
  bool pinned;

  /// Archived cards are hidden from the feed and live in the Archive.
  bool archived;

  /// When set, the card is in Recently Deleted (kept ~30 days, then purged).
  DateTime? deletedAt;

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
        'articleText': articleText,
        'fetched': fetched,
        'enrichAttempts': enrichAttempts,
        'spaceId': spaceId,
        'pinned': pinned,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
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
        articleText: (json['articleText'] as String?) ?? '',
        fetched: (json['fetched'] as bool?) ?? false,
        enrichAttempts: (json['enrichAttempts'] as int?) ?? 0,
        spaceId: json['spaceId'] as String?,
        pinned: (json['pinned'] as bool?) ?? false,
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        noteTitle: (json['noteTitle'] as String?) ?? '',
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
