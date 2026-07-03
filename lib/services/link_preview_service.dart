import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/tweet_card.dart';

/// Best-effort link preview. For tweets it tries Twitter/X oEmbed (no API key
/// required); for everything else it falls back to Open Graph meta tags.
class LinkPreviewService {
  static const _userAgent =
      'Mozilla/5.0 (compatible; KeepyBot/1.0; +https://example.com)';

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
    return card;
  }

  String _handleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('twitter.com') || uri.host.contains('x.com')) {
        final segs = uri.pathSegments;
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
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return false;
    final doc = html_parser.parse(res.body);

    String? meta(String prop) {
      final el = doc.querySelector('meta[property="$prop"]') ??
          doc.querySelector('meta[name="$prop"]');
      return el?.attributes['content'];
    }

    final image = meta('og:image') ?? meta('twitter:image');
    if (image != null && image.isNotEmpty) card.imageUrl = image;
    if (imageOnly) return image != null;

    final title = meta('og:title') ?? doc.querySelector('title')?.text;
    final desc = meta('og:description') ?? meta('description');
    final site = meta('og:site_name');
    if (site != null && site.isNotEmpty) card.siteName = site;
    if (card.text.isEmpty) {
      final combined = [title, desc]
          .where((s) => s != null && s.trim().isNotEmpty)
          .join('\n');
      if (combined.isNotEmpty) card.text = combined;
    }
    return card.text.isNotEmpty || card.imageUrl.isNotEmpty;
  }
}
