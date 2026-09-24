import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/tweet_card.dart';
import 'article_extractor.dart';
import 'youtube_service.dart';

/// Minimal preview for an inline note link card: title, image, site.
class BasicLinkPreview {
  BasicLinkPreview({this.title = '', this.imageUrl = '', this.siteName = ''});
  final String title;
  final String imageUrl;
  final String siteName;
}

/// Everything we pull out of one fetched page, produced off the UI thread.
typedef _PageData = ({
  String title,
  String description,
  String siteName,
  String imageUrl,
  String articleText,
});

/// Best-effort link preview. For tweets it tries Twitter/X oEmbed (no API key
/// required); for everything else it falls back to Open Graph meta tags.
class LinkPreviewService {
  static const _userAgent =
      'Mozilla/5.0 (compatible; BraimBot/1.0; +https://example.com)';

  /// Parses a fetched page and reads its OG tags (and, when [withArticle],
  /// the reader-mode text). Runs inside [Isolate.run]: parsing a large page
  /// takes hundreds of milliseconds and must never block a frame.
  static _PageData _parsePage(Uint8List bytes, {required bool withArticle}) {
    // Decode the raw bytes as UTF-8 (nearly universal today); the http
    // package would otherwise fall back to latin-1 and garble the text.
    final doc =
        html_parser.parse(utf8.decode(bytes, allowMalformed: true));

    String? meta(String prop) {
      final el = doc.querySelector('meta[property="$prop"]') ??
          doc.querySelector('meta[name="$prop"]');
      return el?.attributes['content'];
    }

    final title =
        (meta('og:title') ?? doc.querySelector('title')?.text ?? '').trim();
    final description =
        (meta('og:description') ?? meta('description') ?? '').trim();
    final siteName = (meta('og:site_name') ?? '').trim();
    final imageUrl = (meta('og:image') ?? meta('twitter:image') ?? '').trim();

    // Reader mode last: extraction mutates the DOM the meta reads used.
    var articleText = '';
    if (withArticle) {
      try {
        articleText = ArticleExtractor.extract(doc) ?? '';
      } catch (_) {
        // Best-effort; the preview alone is still a valid card.
      }
    }

    return (
      title: title,
      description: description,
      siteName: siteName,
      imageUrl: imageUrl,
      articleText: articleText,
    );
  }

  /// Fetches just the OG basics for a URL pasted inside a note body.
  /// Returns null when the page can't be fetched (the card shows the bare
  /// domain instead).
  static Future<BasicLinkPreview?> fetchBasicPreview(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      final page =
          await Isolate.run(() => _parsePage(bytes, withArticle: false));
      return BasicLinkPreview(
        title: page.title,
        imageUrl: page.imageUrl,
        siteName: page.siteName.isNotEmpty
            ? page.siteName
            : (Uri.tryParse(url)?.host ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// Mutates and returns the card with whatever preview data we could gather.
  Future<TweetCard> enrich(TweetCard card) async {
    card.authorHandle = _handleFromUrl(card.url);
    if (card.isTweet && card.authorHandle.isNotEmpty) {
      // unavatar resolves a public profile picture from the handle, no API key.
      final h = card.authorHandle.replaceFirst('@', '');
      card.avatarUrl = 'https://unavatar.io/twitter/$h';
    }
    try {
      if (card.isTweet) {
        final ok = await _fetchTweetOembed(card);
        if (ok) {
          card.fetched = true;
          // oEmbed gives no image; try OG for media but don't fail if blocked.
          await _tryOpenGraph(card, imageOnly: true);
          return card;
        }
      }
      final ok = await _tryOpenGraph(card);
      card.fetched = ok || card.text.isNotEmpty;
    } catch (_) {
      // Leave card as-is; the UI shows the raw link.
    }
    // A YouTube link always has a cover derivable from its id, so guarantee one
    // even if the OG image fetch was blocked or missing.
    final vid = YouTubeService.videoId(card.url);
    if (vid != null && card.imageUrl.isEmpty) {
      card.imageUrl = YouTubeService.thumbnailUrl(vid);
    }
    return card;
  }

  String _handleFromUrl(String url) {
    try {
      if (TweetCard.isTweetUrl(url)) {
        final segs = Uri.parse(url.trim()).pathSegments;
        if (segs.isNotEmpty) return '@${segs.first}';
      }
    } catch (_) {}
    return '';
  }

  Future<bool> _fetchTweetOembed(TweetCard card) async {
    final endpoint = Uri.parse(
        'https://publish.twitter.com/oembed?omit_script=true&dnt=true&url=${Uri.encodeComponent(card.url)}');
    final res = await http
        .get(endpoint, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return false;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    card.authorName = (json['author_name'] as String?) ?? card.authorName;
    card.siteName = 'X';
    final htmlBody = json['html'] as String?;
    if (htmlBody != null) {
      // oEmbed snippets are a few hundred bytes; parsing inline is fine.
      final doc = html_parser.parse(htmlBody);
      final p = doc.querySelector('blockquote p');
      var text = (p?.text ?? doc.body?.text ?? '').trim();
      // Strip the trailing "— Author (@handle) date" attribution line.
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) card.text = text;
    }
    return true;
  }

  Future<bool> _tryOpenGraph(TweetCard card, {bool imageOnly = false}) async {
    final res = await http
        .get(Uri.parse(card.url), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return false;
    final bytes = res.bodyBytes;
    final page = await Isolate.run(
        () => _parsePage(bytes, withArticle: !imageOnly));

    // A tweet with no photo still has an og:image — X falls back to the
    // author's profile picture — which must not become the post's image.
    final image = page.imageUrl;
    final keep = image.isNotEmpty &&
        (!card.isTweet || TweetCard.isPostedTweetImage(image));
    if (keep) card.imageUrl = image;
    if (imageOnly) return keep;

    if (page.siteName.isNotEmpty) card.siteName = page.siteName;
    // For a YouTube link, use the video's own title to name the spark (so the
    // feed reads as the video, not "Link") as soon as it's saved.
    if (YouTubeService.videoId(card.url) != null &&
        card.noteTitle.trim().isEmpty &&
        page.title.isNotEmpty) {
      card.noteTitle = page.title;
    }
    if (card.text.isEmpty) {
      final combined = [page.title, page.description]
          .where((s) => s.trim().isNotEmpty)
          .join('\n');
      if (combined.isNotEmpty) card.text = combined;
    }
    card.articleText = page.articleText;
    return card.text.isNotEmpty ||
        card.imageUrl.isNotEmpty ||
        card.articleText.isNotEmpty;
  }
}
