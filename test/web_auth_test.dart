import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/l10n/l10n.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_security.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('pairing code', () {
    late DateTime now;
    late WebPairing pairing;

    setUp(() {
      now = DateTime(2026, 9, 30, 12);
      pairing = WebPairing(now: () => now);
    });

    String wrongFor(String code) =>
        ((int.parse(code) + 1) % 1000000).toString().padLeft(6, '0');

    test('is six zero-padded digits from a secure source', () {
      for (var i = 0; i < 200; i++) {
        expect(pairing.code, matches(WebPairing.codePattern));
        pairing.rotate();
      }
      // A generator that returns 42 still yields six digits.
      final low = WebPairing(now: () => now, random: _FixedRandom([42, 7]));
      expect(low.code, '000042');
    });

    test('lives for two minutes, then is replaced', () {
      final first = pairing.code;
      now = now.add(const Duration(seconds: 119));
      expect(pairing.code, first);
      expect(pairing.timeLeft, const Duration(seconds: 1));
      now = now.add(const Duration(seconds: 1));
      expect(pairing.code, isNot(first));
      expect(pairing.timeLeft, WebPairing.codeLife);
    });

    test('an expired code is reported as expired, not accepted', () {
      final old = pairing.code;
      now = now.add(WebPairing.codeLife);
      expect(pairing.check(old), PairOutcome.expired);
      expect(pairing.check(pairing.code), PairOutcome.paired);
    });

    test('works once: a used code is replaced at once', () {
      final code = pairing.code;
      expect(pairing.check(code), PairOutcome.paired);
      expect(pairing.code, isNot(code));
      expect(pairing.check(code), PairOutcome.wrong);
    });

    test(
      'five misses replace the code and refuse everything for 30 seconds',
      () {
        final code = pairing.code;
        for (var i = 0; i < 4; i++) {
          expect(pairing.check(wrongFor(code)), PairOutcome.wrong);
        }
        expect(pairing.check(wrongFor(code)), PairOutcome.locked);
        final replacement = pairing.code;
        expect(replacement, isNot(code));
        expect(pairing.lockLeft, WebPairing.lockout);

        // Even the new, correct code is refused while locked, and a refused try
        // doesn't count as a miss.
        now = now.add(const Duration(seconds: 29));
        expect(pairing.check(replacement), PairOutcome.locked);
        expect(pairing.lockLeft, const Duration(seconds: 1));

        now = now.add(const Duration(seconds: 1));
        expect(pairing.lockLeft, Duration.zero);
        expect(pairing.check(replacement), PairOutcome.paired);
      },
    );

    test('misses are counted per code', () {
      var code = pairing.code;
      for (var i = 0; i < 4; i++) {
        pairing.check(wrongFor(code));
      }
      now = now.add(WebPairing.codeLife); // a fresh code, a fresh count
      code = pairing.code;
      for (var i = 0; i < 4; i++) {
        expect(pairing.check(wrongFor(code)), isNot(PairOutcome.locked));
      }
      expect(pairing.check(code), PairOutcome.paired);
    });
  });

  test('constantTimeEquals compares whole strings', () {
    expect(constantTimeEquals('123456', '123456'), isTrue);
    expect(constantTimeEquals('123457', '123456'), isFalse);
    expect(constantTimeEquals('023456', '123456'), isFalse);
    expect(constantTimeEquals('12345', '123456'), isFalse);
    expect(constantTimeEquals('1234567', '123456'), isFalse);
    expect(constantTimeEquals('', '123456'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });

  group('session store', () {
    late Directory dir;
    late File file;
    late DateTime now;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('braim_web_sessions');
      file = File('${dir.path}/${WebSessionStore.fileName}');
      now = DateTime(2026, 9, 30, 12);
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<WebSessionStore> open() async {
      final store = WebSessionStore(file, now: () => now);
      await store.load();
      return store;
    }

    test(
      'tokens are 32 random bytes in base64url; only the hash is stored',
      () async {
        final store = await open();
        final created = await store.create(label: 'Chrome on Windows');
        expect(created.token, matches(WebSessionStore.tokenPattern));
        expect(base64Url.decode('${created.token}='), hasLength(32));
        await store.flush();

        final raw = file.readAsStringSync();
        expect(raw, isNot(contains(created.token)));
        expect(raw, contains(WebSessionStore.hashToken(created.token)));
        expect(created.session.hash, WebSessionStore.hashToken(created.token));
        expect(raw, contains('Chrome on Windows'));
      },
    );

    test('a new store reads the sessions back from the file', () async {
      final store = await open();
      final a = await store.create(label: 'A');
      final b = await store.create(label: 'B');
      await store.flush();

      final reopened = await open();
      expect(reopened.lookup(a.token)?.id, a.session.id);
      expect(reopened.lookup(b.token)?.label, 'B');
      expect(reopened.lookup('x' * 43), isNull);
      expect(reopened.lookup('short'), isNull);
      expect(reopened.lookup(null), isNull);
    });

    test('a session unused for 30 days is dropped; use keeps it', () async {
      final store = await open();
      final idle = await store.create(label: 'idle');
      final busy = await store.create(label: 'busy');

      now = now.add(const Duration(days: 20));
      store.touch(store.lookup(busy.token)!);
      now = now.add(const Duration(days: 10));

      expect(store.lookup(idle.token), isNull);
      expect(store.lookup(busy.token), isNotNull);
      expect(store.sessions.map((s) => s.label), ['busy']);
      await store.flush();
      expect(file.readAsStringSync(), isNot(contains('idle')));
    });

    test('last seen is written in a batch, and on flush', () async {
      final store = await open();
      final created = await store.create(label: 'A');
      await store.flush();
      now = now.add(const Duration(hours: 3));
      store.touch(store.lookup(created.token)!);
      await store.flush();

      final reopened = await open();
      expect(reopened.sessions.single.lastSeen, now);
    });

    test('log out one, and log out all', () async {
      final store = await open();
      final a = await store.create(label: 'A');
      final b = await store.create(label: 'B');
      final c = await store.create(label: 'C');

      expect(await store.remove(b.session.id), isTrue);
      expect(await store.remove(b.session.id), isFalse);
      expect(store.lookup(b.token), isNull);
      expect(store.lookup(a.token), isNotNull);

      await store.removeAll();
      expect(store.lookup(a.token), isNull);
      expect(store.lookup(c.token), isNull);
      expect(store.sessions, isEmpty);
      expect((await open()).sessions, isEmpty);
    });

    test('is full at five browsers', () async {
      final store = await open();
      for (var i = 0; i < WebSessionStore.maxSessions; i++) {
        expect(store.isFull, isFalse);
        await store.create(label: '$i');
      }
      expect(store.isFull, isTrue);
      await store.remove(store.sessions.first.id);
      expect(store.isFull, isFalse);
    });

    test('an unreadable file means no linked browsers, not a crash', () async {
      file.writeAsStringSync('{not json');
      final store = await open();
      expect(store.sessions, isEmpty);
      final created = await store.create(label: 'A');
      expect((await open()).lookup(created.token), isNotNull);
    });
  });

  test('browser labels come from fixed names only', () {
    expect(
      webSessionLabel(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
        l10n,
      ),
      'Chrome on Windows',
    );
    expect(
      webSessionLabel(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/18.0 Safari/605.1.15',
        l10n,
      ),
      'Safari on macOS',
    );
    expect(
      webSessionLabel(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0',
        l10n,
      ),
      'Edge on Windows',
    );
    expect(
      webSessionLabel(
        'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 '
        'Firefox/130.0',
        l10n,
      ),
      'Firefox on Linux',
    );
    expect(webSessionLabel(null, l10n), 'Browser');
    expect(webSessionLabel('<script>alert(1)</script>', l10n), 'Browser');
  });
}

/// A [Random] that replays [values] for nextInt, for predictable codes.
class _FixedRandom implements Random {
  _FixedRandom(this.values);
  final List<int> values;
  int _i = 0;

  @override
  int nextInt(int max) => values[_i++ % values.length] % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
