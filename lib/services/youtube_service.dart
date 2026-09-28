import 'dart:convert';

import 'package:http/http.dart' as http;

/// A YouTube video's public metadata from oEmbed: title, channel and
/// thumbnail. Any field may be empty when unavailable.
typedef YouTubeData = ({
  String title,
  String author,
  String thumbnailUrl,
});

/// YouTube link support through YouTube's official oEmbed endpoint
/// (`youtube.com/oembed`), which serves a video's title, channel and thumbnail
/// with no API key. Braim deliberately does not read the watch page or caption
/// tracks: YouTube's terms forbid automated access to the site outside its
/// published endpoints.
class YouTubeService {
  const YouTubeService._();

  static final _idRe = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The 11-char video id for a YouTube watch/short/embed URL, else null.
  static String? videoId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    if (host == 'youtu.be') {
      final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      return _idRe.hasMatch(id) ? id : null;
    }
    if (host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com') {
      final v = uri.queryParameters['v'];
      if (v != null && _idRe.hasMatch(v)) return v;
      final segs = uri.pathSegments;
      if (segs.length >= 2 &&
          (segs[0] == 'shorts' || segs[0] == 'embed' || segs[0] == 'v')) {
        return _idRe.hasMatch(segs[1]) ? segs[1] : null;
      }
    }
    return null;
  }

  static bool isYouTube(String url) => videoId(url) != null;

  /// The standard thumbnail for a video id, derived from the id with no fetch,
  /// so a YouTube spark always has a cover image. It is the same URL oEmbed
  /// returns as `thumbnail_url`.
  static String thumbnailUrl(String id) =>
      'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  /// Fetches [id]'s oEmbed metadata. Never throws; a failure (network, private
  /// or removed video, which oEmbed answers with 401/404) yields empty fields.
  static Future<YouTubeData> fetch(String id) async {
    const empty = (title: '', author: '', thumbnailUrl: '');
    try {
      final watch = 'https://www.youtube.com/watch?v=$id';
      final res = await http
          .get(Uri.parse('https://www.youtube.com/oembed'
              '?url=${Uri.encodeComponent(watch)}&format=json'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return empty;
      return parseOembed(res.body);
    } catch (_) {
      return empty;
    }
  }

  /// Reads title, channel and thumbnail from an oEmbed JSON body. Pure (no
  /// network) so it can be unit-tested; malformed input yields empty fields.
  static YouTubeData parseOembed(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return (title: '', author: '', thumbnailUrl: '');
      String field(String key) =>
          j[key] is String ? (j[key] as String).trim() : '';
      return (
        title: field('title'),
        author: field('author_name'),
        thumbnailUrl: field('thumbnail_url'),
      );
    } catch (_) {
      return (title: '', author: '', thumbnailUrl: '');
    }
  }
}
