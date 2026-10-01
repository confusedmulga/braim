import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/note.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/web/web_assets.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_security.dart';
import 'package:braim/web/web_server.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

class _Conn implements HttpConnectionInfo {
  _Conn(String ip) : remoteAddress = InternetAddress(ip);

  @override
  final InternetAddress remoteAddress;

  @override
  int get remotePort => 50123;

  @override
  int get localPort => 8420;
}

/// Reads bundle assets straight from the project folder.
Future<ByteData> _loadFromDisk(String key) async =>
    ByteData.sublistView(await File(key).readAsBytes());

const _phone = '192.168.1.23';
const _laptop = '192.168.1.50';
const _host = '$_phone:8420';

void main() {
  late Directory root;
  late DateTime now;
  late AppState state;
  late WebPairing pairing;
  late WebSessionStore sessions;
  late BraimWebServer server;
  late int activity;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_server_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    now = DateTime(2026, 9, 30, 12);
    final sessionFile = File('${root.path}/${WebSessionStore.fileName}');
    if (sessionFile.existsSync()) sessionFile.deleteSync();
    state = AppState();
    pairing = WebPairing(now: () => now);
    sessions = WebSessionStore(sessionFile, now: () => now);
    activity = 0;
    server =
        BraimWebServer(
            state: state,
            sessions: sessions,
            pairing: pairing,
            assets: WebAssets(load: _loadFromDisk),
            onActivity: () => activity++,
          )
          ..addresses = const [_phone, '10.0.0.7']
          ..debugPort = 8420;
    await server.prepare();
  });

  tearDown(() async {
    await server.stop();
    await state.flushNow();
    state.dispose();
  });

  Future<Response> send(
    String method,
    String path, {
    String? host = _host,
    String? remote = _laptop,
    String? session,
    String? csrf,
    Map<String, String> headers = const {},
    Object? body,
  }) {
    // The server checks the Host header; the URI is only shelf's bookkeeping.
    return Future.sync(
      () => server.handler(
        Request(
          method,
          Uri.parse('http://$_host$path'),
          headers: {
            'host': ?host,
            if (session != null) 'cookie': 'braim_session=$session',
            'x-braim-csrf': ?csrf,
            ...headers,
          },
          body: body,
          context: {if (remote != null) kConnectionInfoKey: _Conn(remote)},
        ),
      ),
    );
  }

  Future<Response> pairWith(String code, {String? userAgent}) => send(
    'POST',
    '/api/pair',
    headers: {'content-type': 'application/json', 'user-agent': ?userAgent},
    body: jsonEncode({'code': code}),
  );

  String tokenFrom(Response r) => RegExp(
    r'braim_session=([^;]*)',
  ).firstMatch(r.headers['set-cookie']!)!.group(1)!;

  /// Pairs a new browser and returns its session token.
  Future<String> pair() async {
    final r = await pairWith(pairing.code);
    expect(r.statusCode, 200, reason: await r.readAsString());
    return tokenFrom(r);
  }

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  /// The escaper writes '/' as '&#47;', which browsers read back as '/'.
  String unescapeSlashes(String html) => html.replaceAll('&#47;', '/');

  String wrongCode() =>
      ((int.parse(pairing.code) + 1) % 1000000).toString().padLeft(6, '0');

  group('network checks', () {
    test(
      'the phone\'s addresses and loopback localhost are accepted',
      () async {
        expect((await send('GET', '/pair')).statusCode, 200);
        expect(
          (await send('GET', '/pair', host: '10.0.0.7:8420')).statusCode,
          200,
        );
        expect(
          (await send(
            'GET',
            '/pair',
            host: 'LOCALHOST:8420',
            remote: '127.0.0.1',
          )).statusCode,
          200,
        );
        expect(
          (await send(
            'GET',
            '/pair',
            host: '127.0.0.1:8420',
            remote: '127.0.0.1',
          )).statusCode,
          200,
        );
      },
    );

    test('any other Host gets 421 (DNS rebinding)', () async {
      for (final host in [
        'evil.example:8420',
        'evil.example',
        '192.168.1.99:8420', // not the phone
        '$_phone:8421', // wrong port
        _phone, // no port
        '$_phone:8420.evil.example',
      ]) {
        expect(
          (await send('GET', '/pair', host: host)).statusCode,
          421,
          reason: host,
        );
      }
      // localhost only from the phone itself (adb forward), never the LAN.
      expect(
        (await send('GET', '/pair', host: 'localhost:8420')).statusCode,
        421,
      );
      expect(
        (await send('GET', '/pair', host: '127.0.0.1:8420')).statusCode,
        421,
      );
      expect((await send('GET', '/pair', host: null)).statusCode, 421);
    });

    test('remote addresses outside private ranges get 403', () async {
      for (final ip in [
        '8.8.8.8',
        '100.64.0.9', // carrier NAT: the mobile-data side
        '172.32.0.1',
        '172.15.255.255',
        '169.254.10.10',
        '192.169.0.1',
        '11.0.0.1',
        '2001:db8::1',
        '::1',
      ]) {
        expect(
          (await send('GET', '/pair', remote: ip)).statusCode,
          403,
          reason: ip,
        );
      }
      for (final ip in [
        '10.1.2.3',
        '172.16.0.5',
        '172.31.255.254',
        '192.168.43.2',
        '127.0.0.1',
      ]) {
        expect(
          (await send('GET', '/pair', remote: ip)).statusCode,
          200,
          reason: ip,
        );
      }
      expect((await send('GET', '/pair', remote: null)).statusCode, 403);
    });

    test('bodies over 2 MB are refused', () async {
      final r = await send(
        'POST',
        '/api/pair',
        headers: {
          'content-type': 'application/json',
          'content-length': '${kWebMaxBodyBytes + 1}',
        },
      );
      expect(r.statusCode, 413);

      // Without a declared length, the reader stops at the cap.
      final big = Stream.fromIterable([
        List.filled(kWebMaxBodyBytes, 0x20),
        utf8.encode('{"code":1}'),
      ]);
      final r2 = await send(
        'POST',
        '/api/pair',
        headers: {'content-type': 'application/json'},
        body: big,
      );
      expect(r2.statusCode, 413);
    });
  });

  group('pairing', () {
    test(
      'the right code links the browser with a strict, HttpOnly cookie',
      () async {
        final r = await pairWith(
          pairing.code,
          userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/140.0 Safari/537.36',
        );
        expect(r.statusCode, 200);
        final cookie = r.headers['set-cookie']!;
        final parts = cookie.split(';').map((p) => p.trim()).toList();
        expect(
          parts.first,
          matches(RegExp(r'^braim_session=[A-Za-z0-9_-]{43}$')),
        );
        expect(parts, contains('HttpOnly'));
        expect(parts, contains('SameSite=Strict'));
        expect(parts, contains('Path=/'));
        expect(
          parts,
          contains('Max-Age=${const Duration(days: 30).inSeconds}'),
        );
        expect(cookie.toLowerCase(), isNot(contains('secure')));
        expect(sessions.sessions.single.label, 'Chrome on Windows');
        expect(activity, 1);
      },
    );

    test('a wrong code is refused, and a code works only once', () async {
      final wrong = await pairWith(wrongCode());
      expect(wrong.statusCode, 403);
      expect((await json(wrong))['error'], 'wrong');
      expect(
        (await json(await pairWith(wrongCode())))['message'],
        "That code didn't match",
      );
      expect(wrong.headers['set-cookie'], isNull);

      final code = pairing.code;
      expect((await pairWith(code)).statusCode, 200);
      final again = await pairWith(code);
      expect(again.statusCode, 403);
      expect((await json(again))['error'], 'wrong');
    });

    test('an expired code says so', () async {
      final old = pairing.code;
      now = now.add(WebPairing.codeLife);
      final r = await pairWith(old);
      expect(r.statusCode, 403);
      expect((await json(r))['error'], 'expired');
    });

    test('five misses lock pairing for 30 seconds', () async {
      for (var i = 0; i < 4; i++) {
        expect((await pairWith(wrongCode())).statusCode, 403);
      }
      final locked = await pairWith(wrongCode());
      expect(locked.statusCode, 429);
      final body = await json(locked);
      expect(body['error'], 'locked');
      expect(body['seconds'], 30);
      expect(body['message'], 'Too many tries. Wait 30 seconds.');

      now = now.add(const Duration(seconds: 12));
      final still = await json(await pairWith(pairing.code));
      expect(still['error'], 'locked');
      expect(still['seconds'], 18);

      now = now.add(const Duration(seconds: 18));
      expect((await pairWith(pairing.code)).statusCode, 200);
    });

    test('at most five browsers', () async {
      final tokens = [for (var i = 0; i < 5; i++) await pair()];
      final sixth = await pairWith(pairing.code);
      expect(sixth.statusCode, 403);
      final body = await json(sixth);
      expect(body['error'], 'full');
      expect(
        body['message'],
        'Too many linked browsers. Log one out on your phone.',
      );

      // Logging one out on the phone makes room.
      await server.logOut(sessions.lookup(tokens.first)!.id);
      expect((await pairWith(pairing.code)).statusCode, 200);
    });

    test('malformed requests are refused without touching the code', () async {
      final code = pairing.code;
      expect(
        (await send(
          'POST',
          '/api/pair',
          headers: {'content-type': 'text/plain'},
          body: jsonEncode({'code': code}),
        )).statusCode,
        415,
      );
      for (final body in [
        '{',
        '[]',
        '{"code": 123456}',
        '{"code":"12345"}',
        '{"code":"1234567"}',
        '{"code":"12a456"}',
      ]) {
        final r = await send(
          'POST',
          '/api/pair',
          headers: {'content-type': 'application/json'},
          body: body,
        );
        expect(r.statusCode, 400, reason: body);
      }
      expect(pairing.code, code);
      expect((await pairWith(code)).statusCode, 200);
    });

    test('the pairing page skips itself for a linked browser', () async {
      final token = await pair();
      final r = await send('GET', '/pair', session: token);
      expect(r.statusCode, 302);
      expect(r.headers['location'], '/');
    });
  });

  group('sessions', () {
    test(
      'without a session, pages go to /pair and the API answers 401',
      () async {
        for (final session in [null, 'x' * 43, 'not-a-token']) {
          final page = await send('GET', '/', session: session);
          expect(page.statusCode, 302);
          expect(page.headers['location'], '/pair');
          expect(
            (await send('GET', '/nowhere', session: session)).statusCode,
            302,
          );

          final events = await send('GET', '/api/events', session: session);
          expect(events.statusCode, 401);
          expect((await json(events))['error'], 'unauthorized');
          expect(
            (await send('POST', '/api/ping', session: session)).statusCode,
            401,
          );
        }
        expect(activity, 0);
      },
    );

    test('a linked browser gets the page, with its CSRF token', () async {
      final token = await pair();
      final r = await send('GET', '/', session: token);
      expect(r.statusCode, 200);
      expect(r.mimeType, 'text/html');
      final html = await r.readAsString();
      expect(
        html,
        contains('<meta name="braim-csrf" content="${csrfTokenFor(token)}">'),
      );
      // The visit renews the cookie.
      expect(r.headers['set-cookie'], contains('braim_session=$token'));
      expect(r.headers['set-cookie'], contains('Max-Age=2592000'));
    });

    test('requests mark the session seen; event streams do not', () async {
      final token = await pair();
      final before = activity;
      now = now.add(const Duration(hours: 1));
      await send('GET', '/', session: token);
      expect(activity, before + 1);
      expect(sessions.lookup(token)!.lastSeen, now);

      now = now.add(const Duration(hours: 1));
      final events = await send('GET', '/api/events', session: token);
      expect(events.statusCode, 200);
      expect(activity, before + 1);
      expect(
        sessions.lookup(token)!.lastSeen,
        now.subtract(const Duration(hours: 1)),
      );
    });

    test('a session idle for 30 days is gone', () async {
      final token = await pair();
      now = now.add(const Duration(days: 29));
      expect((await send('GET', '/', session: token)).statusCode, 200);
      now = now.add(const Duration(days: 30));
      expect((await send('GET', '/', session: token)).statusCode, 302);
    });

    test('sessions survive a restart of the server', () async {
      final token = await pair();
      await server.stop();
      final again =
          BraimWebServer(
              state: state,
              sessions: WebSessionStore(sessions.file, now: () => now),
              pairing: pairing,
              assets: WebAssets(load: _loadFromDisk),
            )
            ..addresses = const [_phone]
            ..debugPort = 8420;
      await again.prepare();
      final r = await again.handler(
        Request(
          'GET',
          Uri.parse('http://$_host/'),
          headers: {'host': _host, 'cookie': 'braim_session=$token'},
          context: {kConnectionInfoKey: _Conn(_laptop)},
        ),
      );
      expect(r.statusCode, 200);
    });

    test(
      'log out from the browser ends the session and clears the cookie',
      () async {
        final token = await pair();
        final csrf = csrfTokenFor(token);
        final r = await send('POST', '/api/logout', session: token, csrf: csrf);
        expect(r.statusCode, 200);
        expect(r.headers['set-cookie'], contains('braim_session=;'));
        expect(r.headers['set-cookie'], contains('Max-Age=0'));
        expect((await send('GET', '/', session: token)).statusCode, 302);
        expect(sessions.sessions, isEmpty);
      },
    );

    test('log out and log out all from the phone', () async {
      final a = await pair();
      final b = await pair();
      final c = await pair();
      await server.logOut(sessions.lookup(b)!.id);
      expect((await send('GET', '/', session: a)).statusCode, 200);
      expect((await send('GET', '/', session: b)).statusCode, 302);

      await server.logOutAll();
      expect((await send('GET', '/', session: a)).statusCode, 302);
      expect((await send('GET', '/', session: c)).statusCode, 302);
    });
  });

  group('CSRF', () {
    test('mutations without the page\'s token get 403', () async {
      final token = await pair();
      final csrf = csrfTokenFor(token);
      for (final given in [null, '', 'wrong', csrfTokenFor(await pair())]) {
        for (final method in ['POST', 'PUT', 'DELETE', 'PATCH']) {
          final r = await send(
            method,
            '/api/ping',
            session: token,
            csrf: given,
          );
          expect(r.statusCode, 403, reason: '$method with $given');
          expect((await json(r))['error'], 'csrf');
        }
      }
      // A refused logout leaves the session alone.
      expect(
        (await send('POST', '/api/logout', session: token)).statusCode,
        403,
      );
      expect(sessions.lookup(token), isNotNull);

      expect(
        (await send(
          'POST',
          '/api/ping',
          session: token,
          csrf: csrf,
        )).statusCode,
        204,
      );
    });

    test('no CORS headers, even for another origin', () async {
      final token = await pair();
      final r = await send(
        'GET',
        '/',
        session: token,
        headers: {'origin': 'http://evil.example'},
      );
      expect(
        r.headers.keys.where((k) => k.startsWith('access-control-')),
        isEmpty,
      );
    });
  });

  group('responses', () {
    Future<List<Response>> htmlResponses() async {
      final token = await pair();
      return [
        await send('GET', '/pair'),
        await send('GET', '/', session: token),
        await send('GET', '/nowhere', session: token),
        await send('GET', '/assets/missing.css'),
      ];
    }

    test('every HTML response carries the CSP and the other headers', () async {
      for (final r in await htmlResponses()) {
        expect(r.mimeType, 'text/html');
        expect(r.headers['content-security-policy'], kWebCsp);
        expect(r.headers['x-content-type-options'], 'nosniff');
        expect(r.headers['referrer-policy'], 'no-referrer');
        expect(r.headers['cache-control'], 'no-store');
      }
      for (final r in [
        await send('GET', '/api/events'),
        await send('GET', '/pair', host: 'evil.example:8420'),
        await send('GET', '/pair', remote: '8.8.8.8'),
      ]) {
        expect(r.headers['content-security-policy'], kWebCsp);
        expect(r.headers['cache-control'], 'no-store');
      }
    });

    test('pages hold no inline scripts or event-handler attributes', () async {
      for (final r in await htmlResponses()) {
        final html = unescapeSlashes(await r.readAsString());
        final scripts = RegExp(
          r'<script\b[^>]*>(.*?)</script>',
          dotAll: true,
        ).allMatches(html).toList();
        expect(scripts, isNotEmpty);
        for (final tag in scripts) {
          expect(tag.group(0), contains('src="/assets/'));
          expect(tag.group(1), isEmpty);
        }
        expect(
          html,
          isNot(matches(RegExp(r'\son[a-z]+\s*=', caseSensitive: false))),
        );
      }
    });

    test('unknown pages get a plain error page, the API gets JSON', () async {
      final token = await pair();
      final page = await send('GET', '/nowhere', session: token);
      expect(page.statusCode, 404);
      expect(await page.readAsString(), contains('Not found'));
      final api = await send('GET', '/api/nowhere', session: token);
      expect(api.statusCode, 404);
      expect(await json(api), {'error': 'not_found'});
    });
  });

  group('static files', () {
    test('CSS and scripts load without a session, versioned', () async {
      final page = unescapeSlashes(
        await (await send('GET', '/pair')).readAsString(),
      );
      final css = RegExp(
        r'href="(/assets/app\.css\?v=[0-9a-f]+)"',
      ).firstMatch(page)!.group(1)!;
      final js = RegExp(
        r'src="(/assets/app\.js\?v=[0-9a-f]+)"',
      ).firstMatch(page)!.group(1)!;

      final r = await send('GET', css);
      expect(r.statusCode, 200);
      expect(r.mimeType, 'text/css');
      expect(r.headers['cache-control'], contains('immutable'));
      expect(await r.readAsString(), contains('--raised'));

      final s = await send('GET', js);
      expect(s.mimeType, 'text/javascript');
      expect(await s.readAsString(), contains('/api/pair'));

      // Without the current version it must be revalidated.
      expect(
        (await send('GET', '/assets/app.css?v=old')).headers['cache-control'],
        'no-cache',
      );
    });

    test('fonts load from the bundle; nothing else does', () async {
      final r = await send('GET', '/fonts/Lora-Regular.ttf');
      expect(r.statusCode, 200);
      expect(r.mimeType, 'font/ttf');
      expect(
        (await r.read().expand((b) => b).toList()).length,
        File('assets/fonts/Lora-Regular.ttf').lengthSync(),
      );

      for (final path in [
        '/fonts/OFL-Lora.txt',
        '/fonts/..%2F..%2Fpubspec.yaml',
        '/fonts/../../pubspec.yaml',
        '/assets/..%2Fpubspec.yaml',
        '/assets/web/app.css',
        '/assets/logo.png',
      ]) {
        final res = await send('GET', path);
        expect(res.statusCode, anyOf(404, 302), reason: path);
        expect(res.mimeType, isNot('font/ttf'), reason: path);
      }
    });
  });

  group('event stream', () {
    test('sends changes to a linked browser and ends at log out', () async {
      final token = await pair();
      final r = await send('GET', '/api/events', session: token);
      expect(r.statusCode, 200);
      expect(r.mimeType, 'text/event-stream');
      expect(r.context['shelf.io.buffer_output'], isFalse);

      final received = <String>[];
      final done = Completer<void>();
      r.read().listen(
        (b) => received.add(utf8.decode(b)),
        onDone: done.complete,
      );
      await pumpEventQueue();
      expect(received.first, startsWith(': hello'));

      await state.upsertNote(Note(title: 'From the phone'));
      await pumpEventQueue();
      expect(
        received.last,
        'event: changed\ndata: {"rev":${state.revision}}\n\n',
      );

      await send(
        'POST',
        '/api/logout',
        session: token,
        csrf: csrfTokenFor(token),
      );
      await done.future.timeout(const Duration(seconds: 2));
      expect(server.events.anyConnected, isFalse);
    });
  });

  test(
    'a real socket: binds the next free port, checks the peer, compresses',
    () async {
      final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        final port = await server.start(
          address: InternetAddress.loopbackIPv4,
          ports: [busy.port, 0],
        );
        expect(port, isNot(busy.port));
        expect(server.port, port);
        expect(server.running, isTrue);

        final client = HttpClient();
        try {
          // Loopback peer with a localhost Host: the adb-forward path.
          final req = await client.get('127.0.0.1', port, '/pair');
          req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
          final res = await req.close();
          expect(res.statusCode, 200);
          expect(
            res.compressionState,
            HttpClientResponseCompressionState.decompressed,
          );
          expect(res.headers.value('x-powered-by'), isNull);
          expect(
            await res.transform(utf8.decoder).join(),
            contains('Link this browser to Braim'),
          );

          // The same peer asking for another name is refused.
          final bad = await client.get('127.0.0.1', port, '/pair');
          bad.headers.host = 'evil.example';
          bad.headers.port = port;
          final badRes = await bad.close();
          expect(badRes.statusCode, 421);
          await badRes.drain<void>();
        } finally {
          client.close(force: true);
        }

        await server.stop();
        expect(server.running, isFalse);
        expect(server.port, isNull);
      } finally {
        await busy.close();
      }
    },
  );
}
