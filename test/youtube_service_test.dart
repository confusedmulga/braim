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

  test('parseOembed reads title, channel and thumbnail', () {
    const body = '{"title":"My Video Title","author_name":"My Channel",'
        '"thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",'
        '"provider_name":"YouTube","type":"video"}';
    final d = YouTubeService.parseOembed(body);
    expect(d.title, 'My Video Title');
    expect(d.author, 'My Channel');
    expect(d.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
  });

  test('parseOembed is safe on malformed or unexpected bodies', () {
    for (final body in ['Not Found', '', '[]', '{"title":42}']) {
      final d = YouTubeService.parseOembed(body);
      expect(d.title, '');
      expect(d.author, '');
      expect(d.thumbnailUrl, '');
    }
  });
}
