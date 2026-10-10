import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:braim/models/tweet_card.dart';
import 'package:braim/services/link_preview_service.dart';

/// An article page: [head] goes in the page's head, and the body carries
/// enough prose for reader mode to take it as an article.
String page({String head = '', String bodyAttrs = ''}) {
  final para = 'The committee met on Tuesday to weigh the proposal, and after '
      'a long debate about cost and timing it voted to move ahead with a '
      'smaller first phase that can be expanded later. ';
  return '''<!doctype html><html><head>
<meta property="og:title" content="A story">
<meta property="og:description" content="What happened at the meeting.">
$head</head><body $bodyAttrs><article>
${List.filled(8, '<p>${para * 2}</p>').join('\n')}
</article></body></html>''';
}

String ldJson(Object data) =>
    '<script type="application/ld+json">${jsonEncode(data)}</script>';

bool paywalled(String html) =>
    LinkPreviewService.isPaywalled(html_parser.parse(html));

void main() {
  group('isPaywalled', () {
    test('an ordinary free article is not', () {
      expect(paywalled(page()), isFalse);
      expect(
          paywalled(page(
              head: ldJson({
            '@type': 'NewsArticle',
            'isAccessibleForFree': true,
          }))),
          isFalse);
      expect(
          paywalled(page(
              head:
                  '<meta property="article:content_tier" content="free">')),
          isFalse);
    });

    test('schema.org isAccessibleForFree false, as JSON-LD', () {
      expect(
          paywalled(page(
              head: ldJson({
            '@context': 'https://schema.org',
            '@type': 'NewsArticle',
            'isAccessibleForFree': false,
          }))),
          isTrue);
      // Some publishers write it as a string.
      expect(
          paywalled(page(
              head: ldJson({'@type': 'Article', 'isAccessibleForFree': 'False'}))),
          isTrue);
    });

    test('nested in @graph or in a paywalled part', () {
      expect(
          paywalled(page(
              head: ldJson({
            '@graph': [
              {'@type': 'WebSite', 'name': 'Example'},
              {'@type': 'NewsArticle', 'isAccessibleForFree': 'false'},
            ],
          }))),
          isTrue);
      expect(
          paywalled(page(
              head: ldJson({
            '@type': 'NewsArticle',
            'hasPart': [
              {
                '@type': 'WebPageElement',
                'isAccessibleForFree': false,
                'cssSelector': '.paywall',
              }
            ],
          }))),
          isTrue);
    });

    test('microdata and the content-tier tag', () {
      expect(
          paywalled(page(
              head:
                  '<meta itemprop="isAccessibleForFree" content="false">')),
          isTrue);
      for (final tier in ['locked', 'metered', 'Locked']) {
        expect(
            paywalled(page(
                head: '<meta property="article:content_tier" '
                    'content="$tier">')),
            isTrue,
            reason: tier);
      }
    });

    test('a broken JSON-LD block is ignored, not an error', () {
      expect(
          paywalled(page(
              head: '<script type="application/ld+json">{not json'
                  '</script>')),
          isFalse);
    });
  });

  group('saving a link', () {
    Future<TweetCard> save(String html) => http.runWithClient(
          () => LinkPreviewService()
              .enrich(TweetCard(url: 'https://news.example.com/story')),
          () => MockClient((_) async => http.Response(html, 200,
              headers: {'content-type': 'text/html; charset=utf-8'})),
        );

    test('a free article is saved in full for the reader', () async {
      final card = await save(page());
      expect(card.articleText, contains('The committee met on Tuesday'));
      expect(card.articlePaywalled, isFalse);
    });

    test('a subscriber article keeps only its preview', () async {
      // The full text is in the page, hidden by the site's script — exactly
      // the case where extracting it would step around the paywall.
      final card = await save(page(
          head: ldJson({'@type': 'NewsArticle', 'isAccessibleForFree': false})));
      expect(card.articleText, isEmpty);
      expect(card.articlePaywalled, isTrue);
      expect(card.text, contains('A story')); // the preview is still there
      expect(card.fetched, isTrue);
    });

    test('the flag survives saving and loading', () {
      final card = TweetCard(url: 'https://news.example.com/story')
        ..articlePaywalled = true;
      expect(TweetCard.fromJson(card.toJson()).articlePaywalled, isTrue);
      final free = TweetCard(url: 'https://news.example.com/free');
      expect(free.toJson().containsKey('articlePaywalled'), isFalse);
      expect(TweetCard.fromJson(free.toJson()).articlePaywalled, isFalse);
    });
  });
}
