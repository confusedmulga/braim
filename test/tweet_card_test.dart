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

  group('isTweet', () {
    test('matches X and Twitter hosts', () {
      for (final u in [
        'https://x.com/jack/status/20',
        'https://twitter.com/jack/status/20',
        'https://mobile.twitter.com/jack/status/20',
        'https://mobile.x.com/jack/status/20',
      ]) {
        expect(TweetCard.isTweetUrl(u), isTrue, reason: u);
      }
    });

    test('no longer matches sites that merely contain "x.com"', () {
      for (final u in [
        'https://www.netflix.com/title/80057281',
        'https://www.dropbox.com/s/abc/file.pdf',
        'https://redux.com/',
        'https://example.org/?ref=x.com',
      ]) {
        expect(TweetCard.isTweetUrl(u), isFalse, reason: u);
      }
    });
  });

  group('tweet images', () {
    const tweet = 'https://x.com/jack/status/20';
    const photo = 'https://pbs.twimg.com/media/GXyz123AbCd?format=jpg&name=large';
    const avatar =
        'https://pbs.twimg.com/profile_images/1683325380441128960/yRsRRjGO_400x400.jpg';
    const defaultAvatar =
        'https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png';

    test('a posted photo counts as the tweet image', () {
      expect(TweetCard.isPostedTweetImage(photo), isTrue);
    });

    test('video and GIF posters count as the tweet image', () {
      for (final u in [
        'https://pbs.twimg.com/ext_tw_video_thumb/1800/pu/img/AbCdEf.jpg',
        'https://pbs.twimg.com/amplify_video_thumb/1800/img/AbCdEf.jpg',
        'https://pbs.twimg.com/tweet_video_thumb/AbCdEf.jpg',
      ]) {
        expect(TweetCard.isPostedTweetImage(u), isTrue, reason: u);
      }
    });

    test('the author\'s profile picture is not a posted image', () {
      expect(TweetCard.isPostedTweetImage(avatar), isFalse);
      expect(TweetCard.isPostedTweetImage(defaultAvatar), isFalse);
    });

    test('a tweet with one photo still shows it (must not regress)', () {
      expect(TweetCard(url: tweet, imageUrl: photo).coverImageUrl, photo);
    });

    test('a spark saved with the profile picture no longer shows it', () {
      // Older builds stored the og:image fallback as the tweet's image.
      expect(TweetCard(url: tweet, imageUrl: avatar).coverImageUrl, isEmpty);
    });

    test('non-tweet sparks keep their image whatever it is', () {
      const og = 'https://assets.nflxext.com/profile_images/og.jpg';
      expect(
          TweetCard(url: 'https://www.netflix.com/title/1', imageUrl: og)
              .coverImageUrl,
          og);
    });
  });
}
