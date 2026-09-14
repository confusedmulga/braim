import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/tweet_card.dart';

void main() {
  const yt = 'https://youtu.be/VTLnDqjfRZQ';

  group('shouldAutoFetchYouTube', () {
    test('a fresh YouTube spark wants an auto-fetch', () {
      expect(TweetCard(url: yt).shouldAutoFetchYouTube, isTrue);
    });

    test('a fetched YouTube spark never refetches', () {
      final card = TweetCard(url: yt, videoFetched: true);
      expect(card.shouldAutoFetchYouTube, isFalse);
    });

    test('auto-fetch stops after the attempt cap, so a blocked video does not '
        'refetch on every open', () {
      final card =
          TweetCard(url: yt, videoFetchAttempts: TweetCard.maxVideoAutoFetchAttempts);
      expect(card.shouldAutoFetchYouTube, isFalse);
      // One attempt below the cap still auto-fetches.
      final almost = TweetCard(
          url: yt,
          videoFetchAttempts: TweetCard.maxVideoAutoFetchAttempts - 1);
      expect(almost.shouldAutoFetchYouTube, isTrue);
    });

    test('a non-YouTube link never auto-fetches', () {
      expect(TweetCard(url: 'https://example.com').shouldAutoFetchYouTube,
          isFalse);
    });

    test('the attempt counter round-trips through JSON only when set', () {
      expect(TweetCard(url: yt).toJson().containsKey('videoFetchAttempts'),
          isFalse);
      final tried = TweetCard(url: yt, videoFetchAttempts: 2);
      expect(TweetCard.fromJson(tried.toJson()).videoFetchAttempts, 2);
    });
  });
}
