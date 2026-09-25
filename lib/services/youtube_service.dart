import 'dart:convert';

import '../platform/fetcher.dart';

/// A YouTube video's scraped metadata: title, channel, description, and caption
/// transcript. Any field may be empty when unavailable.
typedef YouTubeData = ({
  String title,
  String author,
  String description,
  String transcript,
});

/// Best-effort scraper for a YouTube video's description and transcript — no
/// API key, reading the public watch page the way youtube.com serves it. Both
/// fields come back empty when unavailable (private/age-gated video, captions
/// disabled, or YouTube changed its page), which the UI handles gracefully.
class YouTubeService {
  const YouTubeService._();

  // A desktop-browser UA + English/consent so the watch page returns the full
  // player payload rather than a consent interstitial.
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
  static const _headers = {
    'User-Agent': _ua,
    'Accept-Language': 'en-US,en;q=0.9',
    'Cookie': 'CONSENT=YES+1',
  };

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

  /// A always-available thumbnail for a video id — derived directly from the id
  /// (no fetch, no scraping), so a YouTube spark always has a cover image.
  static String thumbnailUrl(String id) =>
      'https://i.ytimg.com/vi/$id/hqdefault.jpg';

  /// Fetches [id]'s description and transcript. Never throws — failures yield
  /// empty strings. YouTube occasionally serves a stub page (or a 429) on the
  /// first hit, so a single short-delayed retry covers that transient case; a
  /// sustained rate-limit still just returns empty (handled gracefully upstream)
  /// rather than hammering.
  static Future<YouTubeData> fetch(String id) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await Fetcher.instance
            .get(Uri.parse('https://www.youtube.com/watch?v=$id&hl=en'),
                headers: _headers)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final parsed = parseWatchPage(res.body);
          if (parsed.title.isNotEmpty ||
              parsed.description.isNotEmpty ||
              parsed.captionUrl != null) {
            final transcript = parsed.captionUrl != null
                ? await _fetchTranscript(parsed.captionUrl!)
                : '';
            return (
              title: parsed.title,
              author: parsed.author,
              description: parsed.description,
              transcript: transcript,
            );
          }
        }
      } catch (_) {
        // Fall through to the retry / empty result.
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return (title: '', author: '', description: '', transcript: '');
  }

  // ---- Watch-page parsing (pure; unit-testable) ----------------------------

  /// Parses a watch page's inline player payload into the video title, channel,
  /// description and best caption-track URL. Pure (no network) so it can be
  /// tested against a captured page without hitting YouTube.
  static ({String title, String author, String description, String? captionUrl})
      parseWatchPage(String html) {
    final player = _extractJson(html, 'ytInitialPlayerResponse');
    if (player == null) {
      return (title: '', author: '', description: '', captionUrl: null);
    }
    final vd = player['videoDetails'];
    String field(String key) =>
        (vd is Map && vd[key] is String) ? (vd[key] as String).trim() : '';
    return (
      title: field('title'),
      author: field('author'),
      description: field('shortDescription'),
      captionUrl: _captionUrl(player),
    );
  }

  /// Pulls the balanced `{...}` object assigned to [name] out of the page's
  /// inline script — matching the `name = {` assignment specifically so an
  /// earlier stray mention of [name] can't send the scanner to the wrong brace.
  static Map<String, dynamic>? _extractJson(String html, String name) {
    final m = RegExp('$name\\s*=\\s*\\{').firstMatch(html);
    if (m == null) return null;
    final open = m.end - 1; // the '{' the regex matched
    final block = _scanBalanced(html, open);
    if (block == null) return null;
    try {
      final decoded = jsonDecode(block);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _captionUrl(Map<String, dynamic> player) {
    final captions = player['captions'];
    final renderer =
        captions is Map ? captions['playerCaptionsTracklistRenderer'] : null;
    final tracks = renderer is Map ? renderer['captionTracks'] : null;
    if (tracks is! List || tracks.isEmpty) return null;
    Map<String, dynamic>? track;
    for (final t in tracks) {
      if (t is Map<String, dynamic> &&
          (t['languageCode'] as String?)?.toLowerCase().startsWith('en') ==
              true) {
        track = t;
        break;
      }
    }
    track ??= tracks.first is Map<String, dynamic>
        ? tracks.first as Map<String, dynamic>
        : null;
    return track?['baseUrl'] as String?;
  }

  static Future<String> _fetchTranscript(String baseUrl) async {
    // Ask for json3 first; some tracks only return content as the legacy XML
    // (or auto-caption) format, so fall back to the bare track URL.
    final urls = <String>[
      baseUrl.contains('fmt=') ? baseUrl : '$baseUrl&fmt=json3',
      baseUrl,
    ];
    for (final url in urls) {
      try {
        final res = await Fetcher.instance
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final text = parseTranscript(res.body);
        if (text.isNotEmpty) return text;
      } catch (_) {
        // Try the next format.
      }
    }
    return '';
  }

  /// Reads a brace-balanced substring starting at [start], honouring strings
  /// and escapes so braces inside JSON string values don't end it early.
  static String? _scanBalanced(String s, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5C) {
          esc = true; // backslash
        } else if (c == 0x22) {
          inStr = false; // closing quote
        }
      } else if (c == 0x22) {
        inStr = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }

  /// Flattens a timedtext caption response (json3, or legacy XML) to plain
  /// text. Public so it can be unit-tested without a network round-trip.
  static String parseTranscript(String body) {
    final head = body.trimLeft();
    if (head.startsWith('{')) {
      // json3: { events: [ { segs: [ { utf8: "..." } ] } ] }
      try {
        final j = jsonDecode(body);
        final events = j is Map ? j['events'] : null;
        if (events is List) {
          final sb = StringBuffer();
          for (final e in events) {
            final segs = e is Map ? e['segs'] : null;
            if (segs is List) {
              for (final seg in segs) {
                if (seg is Map && seg['utf8'] is String) sb.write(seg['utf8']);
              }
            }
          }
          return _clean(sb.toString());
        }
      } catch (_) {}
      return '';
    }
    // Legacy XML: <text start=.. dur=..>caption</text>
    final sb = StringBuffer();
    for (final m
        in RegExp(r'<text[^>]*>(.*?)</text>', dotAll: true).allMatches(body)) {
      sb.write(_decodeEntities(m.group(1) ?? ''));
      sb.write(' ');
    }
    return _clean(sb.toString());
  }

  static String _clean(String s) => s
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String _decodeEntities(String s) => s
      .replaceAll('&amp;#39;', "'")
      .replaceAll('&amp;quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
