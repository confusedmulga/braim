import 'package:uuid/uuid.dart';

import '../services/youtube_service.dart';
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
    this.videoDescription = '',
    this.videoTranscript = '',
    this.videoFetched = false,
    this.videoFetchAttempts = 0,
    this.fetched = false,
    this.enrichAttempts = 0,
    this.spaceId,
    this.pinned = false,
    this.archived = false,
    this.deletedAt,
    this.noteTitle = '',
    this.fontScale = 1.0,
    List<NoteBlock>? blocks,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        blocks = blocks ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

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

  /// For a YouTube spark: the video's full description and caption transcript,
  /// scraped so the card shows both without opening the video. [videoFetched]
  /// records a successful scrape (so an open never refetches once we have it);
  /// [videoFetchAttempts] caps the automatic retries when the scrape keeps
  /// coming back empty (blocked/rate-limited), so a permanently-blocked video
  /// doesn't pay the full scrape cost on every open. The Retry button ignores
  /// the cap.
  String videoDescription;
  String videoTranscript;
  bool videoFetched;
  int videoFetchAttempts;

  /// Automatic YouTube scrape attempts allowed before we wait for a manual
  /// Retry (see [videoFetchAttempts]).
  static const maxVideoAutoFetchAttempts = 3;

  /// Whether an open should still try to scrape this YouTube spark: only when
  /// it's a YouTube link we haven't fetched and haven't exhausted auto-retries.
  bool get shouldAutoFetchYouTube =>
      !videoFetched &&
      videoFetchAttempts < maxVideoAutoFetchAttempts &&
      YouTubeService.videoId(url) != null;

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

  /// A per-card multiplier on the note body's text size.
  double fontScale;

  final DateTime createdAt;

  /// Last mutation time; drives last-write-wins when syncing.
  DateTime updatedAt;

  /// A link to X/Twitter, judged by the host — not a substring of the whole
  /// URL, which also matched netflix.com, dropbox.com and any "…x.com" site.
  bool get isTweet => isTweetUrl(url);

  static bool isTweetUrl(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host == 'x.com' ||
        host.endsWith('.x.com') ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com');
  }

  /// Whether [imageUrl] — the `og:image` X serves for a tweet page — is media
  /// the author actually posted, rather than a stand-in X uses when the tweet
  /// has none (it falls back to the author's profile picture).
  ///
  /// A deny-list, not an allow-list: profile pictures are the stand-in X
  /// serves, so only those are refused. Every media path — photos, video and
  /// GIF posters, link-card images, and any path X adds later — still shows.
  static bool isPostedTweetImage(String imageUrl) {
    final path = Uri.tryParse(imageUrl.trim())?.path ?? '';
    return !path.contains('/profile_images/') &&
        !path.contains('/default_profile_images/');
  }

  /// The image to display for this card: the fetched OG/media image, or — for a
  /// YouTube link with no image yet — a thumbnail derived straight from the
  /// video id (no network, so it always shows even when scraping is blocked).
  /// A tweet only shows media it posted: a stand-in such as the author's
  /// profile picture (saved by older builds) is not shown as the post's image.
  String get coverImageUrl {
    if (imageUrl.isNotEmpty && (!isTweet || isPostedTweetImage(imageUrl))) {
      return imageUrl;
    }
    final vid = YouTubeService.videoId(url);
    return vid != null ? YouTubeService.thumbnailUrl(vid) : '';
  }

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
        if (videoDescription.isNotEmpty) 'videoDescription': videoDescription,
        if (videoTranscript.isNotEmpty) 'videoTranscript': videoTranscript,
        if (videoFetched) 'videoFetched': true,
        if (videoFetchAttempts > 0) 'videoFetchAttempts': videoFetchAttempts,
        'fetched': fetched,
        'enrichAttempts': enrichAttempts,
        'spaceId': spaceId,
        'pinned': pinned,
        'archived': archived,
        'deletedAt': deletedAt?.toIso8601String(),
        'noteTitle': noteTitle,
        if (fontScale != 1.0) 'fontScale': fontScale,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
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
        videoDescription: (json['videoDescription'] as String?) ?? '',
        videoTranscript: (json['videoTranscript'] as String?) ?? '',
        videoFetched: (json['videoFetched'] as bool?) ?? false,
        videoFetchAttempts: (json['videoFetchAttempts'] as int?) ?? 0,
        fetched: (json['fetched'] as bool?) ?? false,
        enrichAttempts: (json['enrichAttempts'] as int?) ?? 0,
        spaceId: json['spaceId'] as String?,
        pinned: (json['pinned'] as bool?) ?? false,
        archived: (json['archived'] as bool?) ?? false,
        deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
        noteTitle: (json['noteTitle'] as String?) ?? '',
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
}
