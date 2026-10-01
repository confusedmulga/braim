import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/services/braim_web_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/web/web_assets.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_controller.dart';
import 'package:braim/web/web_security.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// Records what the controller asks of the Android service.
class _FakeService implements BraimWebService {
  final calls = <String>[];
  final started = <Map<String, String>>[];
  Object? failStart;
  void Function()? stopRequested;

  /// Whether the server was already listening when the service was started.
  bool? serverUpWhenStarted;
  bool Function()? serverUp;

  @override
  set onStopRequested(void Function()? callback) => stopRequested = callback;

  @override
  Future<void> start({
    required String url,
    required String title,
    required String turnOff,
    required String channelName,
  }) async {
    calls.add('start');
    serverUpWhenStarted = serverUp?.call();
    final fail = failStart;
    if (fail != null) throw fail;
    started.add({
      'url': url,
      'title': title,
      'turnOff': turnOff,
      'channelName': channelName,
    });
  }

  @override
  Future<void> update({
    required String url,
    required String title,
    required String turnOff,
  }) async {
    calls.add('update $url');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

Future<ByteData> _loadFromDisk(String key) async =>
    ByteData.sublistView(await File(key).readAsBytes());

void main() {
  late Directory root;
  late DateTime now;
  late List<String> ips;
  late _FakeService service;
  late AppState state;
  late BraimWebController web;
  late HttpClient client;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_controller_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  BraimWebController newController({
    List<int>? ports,
    Duration tick = const Duration(seconds: 30),
  }) {
    final c = BraimWebController(
      state,
      openSessions: () async => WebSessionStore(
        File('${root.path}/${WebSessionStore.fileName}'),
        now: () => now,
      ),
      assets: WebAssets(load: _loadFromDisk),
      pairing: WebPairing(now: () => now),
      service: service,
      listAddresses: () async => ips,
      now: () => now,
      tick: tick,
      bindAddress: InternetAddress.loopbackIPv4,
      ports: ports ?? const [0],
    );
    service.serverUp = () => c.debugServer?.running ?? false;
    return c;
  }

  setUp(() {
    now = DateTime(2026, 10, 1, 9);
    ips = ['192.168.1.23'];
    service = _FakeService();
    final f = File('${root.path}/${WebSessionStore.fileName}');
    if (f.existsSync()) f.deleteSync();
    state = AppState();
    web = newController();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    web.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await state.flushNow();
    state.dispose();
  });

  /// A request from the phone itself (loopback), as `adb forward` sends it.
  Future<HttpClientResponse> request(
    String method,
    String path, {
    String? host,
    String? token,
    String? csrf,
    Object? json,
  }) async {
    final port = web.port!;
    final req = await client.open(method, '127.0.0.1', port, path)
      ..followRedirects = false;
    req.headers.host = host ?? '127.0.0.1';
    req.headers.port = port;
    if (token != null) req.headers.add('cookie', 'braim_session=$token');
    if (csrf != null) req.headers.add('x-braim-csrf', csrf);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    return req.close();
  }

  Future<int> status(
    String method,
    String path, {
    String? host,
    String? token,
    String? csrf,
  }) async {
    final res = await request(
      method,
      path,
      host: host,
      token: token,
      csrf: csrf,
    );
    await res.drain<void>();
    return res.statusCode;
  }

  /// Links a browser through the real socket and returns its token.
  Future<String> pair() async {
    final res = await request(
      'POST',
      '/api/pair',
      json: {'code': web.pairingCode},
    );
    expect(res.statusCode, 200);
    await res.drain<void>();
    final cookie = res.cookies.firstWhere((c) => c.name == 'braim_session');
    return cookie.value;
  }

  test('with no Wi-Fi and no hotspot, nothing starts', () async {
    ips = [];
    await web.start();
    expect(web.running, isFalse);
    expect(web.startError, WebStartError.noNetwork);
    expect(web.pairingCode, isNull);
    expect(web.addresses, isEmpty);
    expect(service.calls, isEmpty);
  });

  test(
    'start runs the server first, then the service, with a fresh code',
    () async {
      final changes = <bool>[];
      web.addListener(() => changes.add(web.running));
      await web.start();

      expect(web.running, isTrue);
      expect(web.startError, isNull);
      expect(web.port, isNotNull);
      expect(web.addresses, ['http://192.168.1.23:${web.port}']);
      expect(web.pairingCode, matches(WebPairing.codePattern));
      expect(web.codeTimeLeft, WebPairing.codeLife);
      expect(web.sessions, isEmpty);
      expect(changes.last, isTrue);

      expect(service.serverUpWhenStarted, isTrue);
      expect(service.started.single, {
        'url': 'http://192.168.1.23:${web.port}',
        'title': 'Braim Web is on',
        'turnOff': 'Turn off',
        'channelName': 'Braim Web',
      });

      expect(await status('GET', '/pair'), 200);

      // A second start changes nothing.
      final port = web.port;
      await web.start();
      expect(web.port, port);
      expect(service.calls.where((c) => c == 'start'), hasLength(1));
    },
  );

  test('a port that cannot be bound starts nothing', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      web.dispose();
      web = newController(ports: [busy.port]);
      await web.start();
      expect(web.running, isFalse);
      expect(web.startError, WebStartError.failed);
      expect(service.calls, isEmpty);
    } finally {
      await busy.close();
    }
  });

  test(
    'if Android refuses the service, the server is stopped as well',
    () async {
      service.failStart = PlatformException(code: 'start_failed');
      await web.start();
      expect(web.running, isFalse);
      expect(web.startError, WebStartError.failed);
      expect(web.port, isNull);
      expect(web.debugServer!.running, isFalse);

      // Trying again once Android allows it works.
      service.failStart = null;
      await web.start();
      expect(web.running, isTrue);
      expect(web.startError, isNull);
    },
  );

  test('stop closes the server, every open page and the service', () async {
    await web.start();
    final port = web.port!;
    final token = await pair();

    final events = await request('GET', '/api/events', token: token);
    expect(events.statusCode, 200);
    final ended = Completer<void>();
    void end() {
      if (!ended.isCompleted) ended.complete();
    }

    events.listen((_) {}, onDone: end, onError: (_) => end());

    await web.stop();
    expect(web.running, isFalse);
    expect(web.stopReason, WebStopReason.user);
    expect(web.pairingCode, isNull);
    expect(web.addresses, isEmpty);
    expect(service.calls.last, 'stop');
    await ended.future.timeout(const Duration(seconds: 2));

    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, port),
      throwsA(isA<SocketException>()),
    );
  });

  test('turns off after 30 minutes without a request', () async {
    await web.start();
    now = now.add(const Duration(minutes: 29, seconds: 59));
    await web.debugTick();
    expect(web.running, isTrue);

    now = now.add(const Duration(seconds: 1));
    await web.debugTick();
    expect(web.running, isFalse);
    expect(web.stopReason, WebStopReason.autoOff);
    expect(service.calls.last, 'stop');
  });

  test(
    'requests and visibility pings keep it on; event streams do not',
    () async {
      await web.start();
      final token = await pair(); // minute 0
      final csrf = csrfTokenFor(token);

      now = now.add(const Duration(minutes: 20));
      expect(await status('POST', '/api/ping', token: token, csrf: csrf), 204);

      now = now.add(const Duration(minutes: 20)); // 20 since the ping
      await web.debugTick();
      expect(web.running, isTrue);
      // An open page's event stream, connecting or reconnecting, is not use.
      final events = await request('GET', '/api/events', token: token);
      expect(events.statusCode, 200);
      events.listen((_) {}, onError: (_) {});

      now = now.add(const Duration(minutes: 10)); // 30 since the ping
      await web.debugTick();
      expect(web.running, isFalse);
      expect(web.stopReason, WebStopReason.autoOff);
    },
  );

  test('the checks run on their own every tick', () async {
    web.dispose();
    web = newController(tick: const Duration(milliseconds: 20));
    await web.start();
    now = now.add(const Duration(minutes: 31));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(web.running, isFalse);
    expect(web.stopReason, WebStopReason.autoOff);
  });

  test('follows the phone\'s addresses as the network changes', () async {
    await web.start();
    final port = web.port!;
    expect(await status('GET', '/pair', host: '192.168.1.23'), 200);

    ips = ['10.0.0.5', '192.168.43.1']; // a new Wi-Fi, and the hotspot
    await web.debugTick();
    expect(web.addresses, [
      'http://10.0.0.5:$port',
      'http://192.168.43.1:$port',
    ]);
    expect(service.calls.last, 'update http://10.0.0.5:$port');
    expect(await status('GET', '/pair', host: '192.168.43.1'), 200);
    expect(await status('GET', '/pair', host: '192.168.1.23'), 421);

    // Unchanged addresses don't touch the notification.
    await web.debugTick();
    expect(service.calls.where((c) => c.startsWith('update')), hasLength(1));
  });

  test('Turn off in the notification stops everything', () async {
    await web.start();
    service.stopRequested!();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(web.running, isFalse);
    expect(web.stopReason, WebStopReason.notification);
    expect(service.calls.last, 'stop');
  });

  test('lists linked browsers, logs one out, and logs out all', () async {
    await web.start();
    final a = await pair();
    now = now.add(const Duration(minutes: 5));
    final b = await pair();

    final listed = web.sessions;
    expect(listed, hasLength(2));
    expect(listed.first.lastSeen, now); // most recently used first
    expect(listed.first.label, 'Browser'); // dart:io's agent is no browser

    await web.logOut(listed.last.id);
    expect(web.sessions, hasLength(1));
    expect(await status('GET', '/', token: a), 302);
    expect(await status('GET', '/', token: b), 200);

    await web.logOutAll();
    expect(web.sessions, isEmpty);
    expect(await status('GET', '/', token: b), 302);
  });

  test('is always off at launch; linked browsers are remembered', () async {
    await web.start();
    final token = await pair();
    await web.stop();

    final again = newController();
    try {
      expect(again.running, isFalse);
      await again.start();
      web.dispose();
      web = again;
      expect(await status('GET', '/', token: token), 200);
    } catch (_) {
      again.dispose();
      rethrow;
    }
  });
}
