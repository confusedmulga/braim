import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/models/note.dart';
import 'package:braim/services/db/db_snapshot.dart';
import 'package:braim/services/phone_server/paired_devices.dart';
import 'package:braim/services/phone_server/phone_server.dart';
import 'package:braim/services/phone_server/web_bundle.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/services/store/library_delta.dart';
import 'package:braim/state/app_state.dart';

import 'library_store_test.dart' show MemoryLibraryStore;

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// One browser tab on the live channel.
class _Tab {
  _Tab(this.ws) {
    ws.listen((d) => _frames.add(jsonDecode(d as String) as Map<String, dynamic>));
  }

  final WebSocket ws;
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> seen = [];
  late final _sub = _frames.stream.listen(seen.add);

  static Future<_Tab> open(int port, String token) async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/api/live');
    final tab = _Tab(ws);
    tab._sub; // start recording
    ws.add(jsonEncode({'op': 'auth', 'token': token}));
    await tab.next('snapshot');
    return tab;
  }

  Future<Map<String, dynamic>> next(String op) async {
    for (final f in seen) {
      if (f['op'] == op) {
        seen.remove(f);
        return f;
      }
    }
    final f = await _frames.stream
        .firstWhere((f) => f['op'] == op)
        .timeout(const Duration(seconds: 5));
    seen.remove(f);
    return f;
  }

  void send(Map<String, Object?> m) => ws.add(jsonEncode(m));

  Future<void> close() async {
    await ws.close();
    await _sub.cancel();
  }
}

void main() {
  late Directory root;
  late AppState state;
  late PhoneServer server;
  late int port;
  var allowPairing = true;
  var allowCrypt = true;
  final plain = Note(title: 'plain note');
  final secret = Note(title: 'secret', spaceId: kCryptSpaceId);

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_server_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    Directory('${root.path}/web').createSync();
    File('${root.path}/web/index.html').writeAsStringSync('<html>braim</html>');
    File('${root.path}/web/version.json').writeAsStringSync('{"version":"1"}');
    File('${root.path}/web/main.dart.js').writeAsStringSync('main();');
    Directory('${root.path}/images').createSync();
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    allowPairing = true;
    allowCrypt = true;
    final store = MemoryLibraryStore(AppData(
      notes: [
        Note.fromJson(plain.toJson()),
        Note.fromJson(secret.toJson()),
      ],
      spaces: [],
      cards: [],
    ));
    state = AppState(store: store);
    await state.init();
    server = PhoneServer(
      state: state,
      bundle: DirectoryWebBundle('${root.path}/web'),
      devices: PairedDevices(null),
      imagesDir: '${root.path}/images',
      approvePairing: (_) async => allowPairing,
      approveCrypt: (_) async => allowCrypt,
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    await server.start();
    port = server.boundPort!;
  });

  tearDown(() async {
    await server.stop();
    await state.flushNow();
    state.dispose();
  });

  final client = HttpClient();

  Future<({int status, String body, HttpHeaders headers})> call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    req.followRedirects = false;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    headers.forEach(req.headers.set);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    if (bytes != null) req.add(bytes);
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    return (status: res.statusCode, body: body, headers: res.headers);
  }

  Future<String> pair() async {
    final code = server.newPairingCode();
    final res = await call('POST', '/api/pair',
        json: {'code': code, 'name': 'Test browser'});
    expect(res.status, 200, reason: res.body);
    return (jsonDecode(res.body) as Map)['token'] as String;
  }

  test('hello answers without auth; the API needs a session', () async {
    final hello = await call('GET', '/api/hello');
    expect(jsonDecode(hello.body), {'app': 'braim', 'proto': 1});
    expect((await call('GET', '/api/session')).status, 401);
    expect((await call('GET', '/api/session', token: 'nope')).status, 401);
  });

  test('requests for another host name are refused (DNS rebinding)', () async {
    final res =
        await call('GET', '/api/hello', headers: {'Host': 'evil.example'});
    expect(res.status, 421);
  });

  test('pairing: single-use code, owner confirms, token opens the API',
      () async {
    expect((await call('POST', '/api/pair', json: {'code': 'x'})).status, 410);
    final code = server.newPairingCode();
    expect(
        (await call('POST', '/api/pair', json: {'code': 'wrong'})).status, 403);
    final ok = await call('POST', '/api/pair', json: {'code': code});
    expect(ok.status, 200);
    final token = (jsonDecode(ok.body) as Map)['token'] as String;
    expect((await call('GET', '/api/session', token: token)).status, 200);
    // Used once, gone.
    expect((await call('POST', '/api/pair', json: {'code': code})).status, 410);

    allowPairing = false;
    final denied = await call('POST', '/api/pair',
        json: {'code': server.newPairingCode()});
    expect(denied.status, 403);
    expect(denied.body, contains('denied'));
  });

  test('a snapshot never carries the Crypt until the phone unlocks it',
      () async {
    final token = await pair();
    final snap = LibraryDelta.fromJson(
        jsonDecode((await call('GET', '/api/snapshot', token: token)).body)
            as Map<String, dynamic>);
    final ids = snap.rows.map((r) => r.id).toSet();
    expect(ids, contains(plain.id));
    expect(ids, isNot(contains(secret.id)));

    final tab = await _Tab.open(port, token);
    allowCrypt = false;
    expect((await call('POST', '/api/crypt/unlock', token: token)).status, 403);
    allowCrypt = true;
    expect((await call('POST', '/api/crypt/unlock', token: token)).status, 200);
    final push = await tab.next('push');
    expect(LibraryDelta.fromJson(push['delta'] as Map<String, dynamic>)
        .rows
        .map((r) => r.id), [secret.id]);

    await call('POST', '/api/crypt/lock', token: token);
    final lock = await tab.next('lock');
    expect(lock['ids'], [secret.id]);
    await tab.close();
  });

  test('a browser edit lands on the phone and reaches the other tabs only',
      () async {
    final token = await pair();
    final a = await _Tab.open(port, token);
    final b = await _Tab.open(port, token);

    final typed = Note(title: 'typed on a laptop');
    a.send({
      'op': 'push',
      'seq': 1,
      'delta': LibraryDelta(rows: [
        (table: 'notes', id: typed.id, row: noteRow(typed)),
      ], settings: {
        'readerFont': jsonEncode('Merriweather'),
        'darkMode': jsonEncode(true), // per-device: must be ignored
      }).toJson(),
    });
    expect((await a.next('ack'))['seq'], 1);
    expect(state.noteById(typed.id)?.title, 'typed on a laptop');
    expect(state.readerFont, 'Merriweather');
    expect(state.darkMode, isFalse);

    final toB = await b.next('push');
    final rows = LibraryDelta.fromJson(toB['delta'] as Map<String, dynamic>).rows;
    expect(rows.map((r) => r.id), [typed.id]);

    // The phone's own save goes to both tabs; the laptop's edit isn't echoed.
    await state.flushNow();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.seen.where((f) => f['op'] == 'push'), isEmpty);
    await state.upsertNote(state.noteById(plain.id)!..title = 'edited on phone');
    await state.flushNow();
    for (final tab in [a, b]) {
      final p = await tab.next('push');
      final d = LibraryDelta.fromJson(p['delta'] as Map<String, dynamic>);
      expect(d.rows.map((r) => r.id), contains(plain.id));
    }
    await a.close();
    await b.close();
  });

  test('a locked browser cannot touch Crypt rows; malformed rows are dropped',
      () async {
    final token = await pair();
    final tab = await _Tab.open(port, token);
    tab.send({
      'op': 'push',
      'seq': 7,
      'delta': LibraryDelta(rows: [
        (table: 'notes', id: secret.id, row: null),
        (table: 'notes', id: 'junk', row: {'id': 'junk', 'body': '{nope'}),
        (table: 'evil', id: 'x', row: null),
      ]).toJson(),
    });
    await tab.next('ack');
    expect(state.noteById(secret.id), isNotNull);
    expect(state.noteById('junk'), isNull);
    await tab.close();
  });

  test('typing time adds up instead of overwriting', () async {
    final token = await pair();
    final tab = await _Tab.open(port, token);
    final before = state.typingTime.inMilliseconds;
    tab.send({'op': 'addTyping', 'ms': 1500});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(state.typingTime.inMilliseconds, before + 1500);
    await tab.close();
  });

  test('images: upload by name, never overwrite, served back', () async {
    final token = await pair();
    expect((await call('PUT', '/api/image/..%2Fx.jpg', token: token, bytes: [1]))
        .status, 400);
    final put = await call('PUT', '/api/image/abc.jpg',
        token: token, bytes: [1, 2, 3]);
    expect(put.status, 200);
    await call('PUT', '/api/image/abc.jpg', token: token, bytes: [9]);
    expect(File('${root.path}/images/abc.jpg').readAsBytesSync(), [1, 2, 3]);
    final get = await call('GET', '/api/image/abc.jpg', token: token);
    expect(get.status, 200);
    expect((await call('GET', '/api/image/abc.jpg')).status, 401);
  });

  test('static bundle: served, revalidated, fonts fall back to Google',
      () async {
    final index = await call('GET', '/');
    expect(index.status, 200);
    expect(index.body, contains('braim'));
    final etag = index.headers.value('etag')!;
    expect((await call('GET', '/', headers: {'If-None-Match': etag})).status,
        304);
    final font = await call('GET', '/fonts/gstatic/notosans/v1/x.woff2');
    expect(font.status, 302);
    expect(font.headers.value('location'),
        'https://fonts.gstatic.com/s/notosans/v1/x.woff2');
    expect((await call('GET', '/missing.js')).status, 404);
    expect((await call('GET', '/..%2Fsecret')).status, 400);
  });

  test('fetch proxy: only for a session, only http(s)', () async {
    final site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    site.listen((r) {
      r.response.headers.contentType = ContentType.html;
      r.response.write('<title>Hi</title>');
      r.response.close();
    });
    final token = await pair();
    final url = 'http://127.0.0.1:${site.port}/page';
    expect((await call('POST', '/api/fetch', json: {'url': url})).status, 401);
    expect((await call('POST', '/api/fetch',
            token: token, json: {'url': 'file:///etc/passwd'}))
        .status, 400);
    final res =
        await call('POST', '/api/fetch', token: token, json: {'url': url});
    final j = jsonDecode(res.body) as Map;
    expect(j['status'], 200);
    expect(utf8.decode(base64.decode(j['body'] as String)), '<title>Hi</title>');
    await site.close(force: true);
  });

  test('a revoked computer is disconnected and refused', () async {
    final token = await pair();
    final tab = await _Tab.open(port, token);
    await server.revoke(hashToken(token));
    expect((await tab.next('bye'))['reason'], 'revoked');
    expect((await call('GET', '/api/session', token: token)).status, 401);
  });
}
