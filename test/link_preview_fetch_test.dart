import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:braim/services/link_preview_service.dart';

/// A link's preview reads a page, never a whole download.
void main() {
  test('a link to a large file is not downloaded for a preview', () async {
    var sent = 0;
    // 64 MB of video, a megabyte at a time, counting what was taken.
    Stream<List<int>> body() async* {
      for (var i = 0; i < 64; i++) {
        sent += 1 << 20;
        yield List<int>.filled(1 << 20, 0);
      }
    }

    final preview = await http.runWithClient(
      () => LinkPreviewService.fetchBasicPreview('https://example.com/a.mp4'),
      () => MockClient.streaming((request, _) async => http.StreamedResponse(
            body(),
            200,
            headers: {'content-type': 'video/mp4'},
          )),
    );
    expect(preview, isNull);
    expect(sent, lessThan(8 << 20));
  });

  test('a page is still read for its title', () async {
    final preview = await http.runWithClient(
      () => LinkPreviewService.fetchBasicPreview('https://example.com/post'),
      () => MockClient((request) async => http.Response(
            '<html><head><title>Hello</title>'
            '<meta property="og:title" content="Hello there"></head></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          )),
    );
    expect(preview, isNotNull);
    expect(preview!.title, contains('Hello'));
  });

  test('a huge page is cut off rather than read whole', () async {
    var sent = 0;
    Stream<List<int>> body() async* {
      yield '<html><head><title>Big</title></head><body>'.codeUnits;
      for (var i = 0; i < 64; i++) {
        sent += 1 << 20;
        yield List<int>.filled(1 << 20, 0x61);
      }
    }

    final preview = await http.runWithClient(
      () => LinkPreviewService.fetchBasicPreview('https://example.com/big'),
      () => MockClient.streaming((request, _) async => http.StreamedResponse(
            body(),
            200,
            headers: {'content-type': 'text/html'},
          )),
    );
    expect(preview?.title, 'Big');
    expect(sent, lessThan(8 << 20));
  });
}
