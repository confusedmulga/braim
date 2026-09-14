import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/youtube_service.dart';

void main() {
  test('videoId recognises the common YouTube URL shapes', () {
    const id = 'dQw4w9WgXcQ';
    expect(YouTubeService.videoId('https://www.youtube.com/watch?v=$id'), id);
    expect(YouTubeService.videoId('https://youtube.com/watch?v=$id&t=30s'), id);
    expect(YouTubeService.videoId('https://youtu.be/$id'), id);
    expect(YouTubeService.videoId('https://www.youtube.com/shorts/$id'), id);
    expect(YouTubeService.videoId('https://m.youtube.com/watch?v=$id'), id);
    expect(YouTubeService.isYouTube('https://youtu.be/$id'), isTrue);
  });

  test('videoId rejects non-YouTube and malformed links', () {
    expect(YouTubeService.videoId('https://vimeo.com/12345'), isNull);
    expect(YouTubeService.videoId('https://example.com/watch?v=abcdefghijk'),
        isNull);
    expect(YouTubeService.videoId('https://www.youtube.com/watch?v=short'),
        isNull);
    expect(YouTubeService.isYouTube('not a url'), isFalse);
  });

  test('parseWatchPage extracts the description and prefers the English track',
      () {
    // Mimics the real inline `ytInitialPlayerResponse = {…};` — the description
    // deliberately contains a `}` brace and an escaped quote to exercise the
    // brace scanner's string handling.
    const html = '<html><head><script>var ytInitialPlayerResponse = '
        '{"videoDetails":{"title":"My Video Title","author":"My Channel",'
        '"shortDescription":"A desc with a } brace and a '
        '\\"quote\\".\\nSecond line."},'
        '"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":['
        '{"baseUrl":"https://yt/api/timedtext?lang=es","languageCode":"es"},'
        '{"baseUrl":"https://yt/api/timedtext?lang=en","languageCode":"en"}'
        ']}}};var meta=1;</script></head></html>';

    final parsed = YouTubeService.parseWatchPage(html);
    expect(parsed.title, 'My Video Title');
    expect(parsed.author, 'My Channel');
    expect(parsed.description, 'A desc with a } brace and a "quote".\nSecond line.');
    expect(parsed.captionUrl, 'https://yt/api/timedtext?lang=en');
  });

  test('parseWatchPage is safe on a page without the payload', () {
    final parsed = YouTubeService.parseWatchPage('<html>nothing here</html>');
    expect(parsed.title, '');
    expect(parsed.author, '');
    expect(parsed.description, '');
    expect(parsed.captionUrl, isNull);
  });

  test('parseTranscript flattens json3 captions', () {
    const json3 = '{"events":[{"segs":[{"utf8":"Hello "},{"utf8":"world"}]},'
        '{"segs":[{"utf8":"\\n"}]},{"segs":[{"utf8":"second line"}]}]}';
    expect(YouTubeService.parseTranscript(json3), 'Hello world second line');
  });

  test('parseTranscript flattens legacy XML captions and decodes entities', () {
    const xml = '<?xml version="1.0"?><transcript>'
        '<text start="0" dur="1">first line</text>'
        '<text start="1" dur="1">second &amp; third</text></transcript>';
    expect(YouTubeService.parseTranscript(xml), 'first line second & third');
  });
}
