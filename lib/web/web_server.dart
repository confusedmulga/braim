// Braim Web's HTTP server: runs in the app's main isolate next to AppState, so
// a web edit goes through the same methods a phone tap does. See
// docs/braim-web-plan.md, sections 3, 5 and 7.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import 'web_assets.dart';
import 'web_auth.dart';
import 'web_events.dart';
import 'web_pages.dart';
import 'web_security.dart';

class BraimWebServer {
  BraimWebServer({
    required this.state,
    required this.sessions,
    WebPairing? pairing,
    WebAssets? assets,
    this.onActivity,
  }) : pairing = pairing ?? WebPairing(),
       assets = assets ?? WebAssets(),
       l10n = lookupAppLocalizations(const Locale('en')) {
    events = WebEventHub(source: state, revision: () => state.revision);
  }

  /// Tried in order until one is free.
  static const firstPort = 8420;
  static const lastPort = 8429;

  static const sessionCookie = 'braim_session';
  static const sessionMaxAge = Duration(days: 30);

  final AppState state;
  final WebSessionStore sessions;
  final WebPairing pairing;
  final WebAssets assets;
  final AppLocalizations l10n;
  late final WebEventHub events;

  /// Called on every request from a linked browser, and on pairing; the
  /// controller's auto-off timer restarts on it. Event streams don't count:
  /// neither their keep-alives nor a reconnect after a network drop.
  void Function()? onActivity;

  HttpServer? _server;
  int? _port;
  List<String> _addresses = const [];
  bool _prepared = false;

  bool get running => _server != null;

  /// The port in use, or null when stopped.
  int? get port => _port;

  /// The phone's private IPv4 addresses, which are the Host names accepted.
  List<String> get addresses => _addresses;
  set addresses(List<String> ips) => _addresses = List.unmodifiable(ips);

  /// Lets handler tests set the port without binding a socket.
  @visibleForTesting
  set debugPort(int? port) => _port = port;

  /// Loads the linked browsers and the static files. [start] calls it.
  Future<void> prepare() async {
    if (_prepared) return;
    await sessions.load();
    await assets.preload();
    _prepared = true;
  }

  /// Binds the first free port of [ports] (8420 to 8429 by default) on
  /// [address] (every IPv4 interface by default) and returns it.
  Future<int> start({InternetAddress? address, List<int>? ports}) async {
    final running = _server;
    if (running != null) return running.port;
    await prepare();
    SocketException? lastError;
    for (final p in ports ?? [for (var p = firstPort; p <= lastPort; p++) p]) {
      try {
        final server = await shelf_io.serve(
          handler,
          address ?? InternetAddress.anyIPv4,
          p,
          poweredByHeader: null,
        );
        server.autoCompress = true;
        _server = server;
        return _port = server.port;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const SocketException('No free port');
  }

  /// Closes every connection and event stream and stops listening.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    events.closeAll();
    await server?.close(force: true);
    await sessions.flush();
  }

  /// Logs one linked browser out, ending its open event streams. The session
  /// is gone at once; the returned future waits for the file write.
  Future<void> logOut(String sessionId) {
    final saved = sessions.remove(sessionId);
    events.closeSession(sessionId);
    return saved;
  }

  /// Logs every linked browser out.
  Future<void> logOutAll() {
    final saved = sessions.removeAll();
    events.closeAll();
    return saved;
  }

  /// The phone's private, non-loopback IPv4 addresses (Wi-Fi and hotspot can
  /// both be present).
  static Future<List<String>> privateAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (isPrivateIPv4(a) && !a.isLoopback) out.add(a.address);
        }
      }
    } catch (_) {
      // No interfaces readable: nothing to offer.
    }
    return out;
  }

  // ---- Pipeline ------------------------------------------------------------

  /// The whole server as one shelf handler, in the order of section 7.2:
  /// address and host checks, then static files and pairing (no session),
  /// then the session and CSRF checks, then the routes. Security headers and
  /// error pages wrap everything.
  late final Handler handler = _buildHandler();

  Handler _buildHandler() {
    final signedIn = const Pipeline()
        .addMiddleware(_sessionCheck)
        .addMiddleware(_csrfCheck)
        .addHandler(_routes().call);
    final open = Router(notFoundHandler: signedIn)
      ..get('/assets/<name>', _asset)
      ..get('/fonts/<name>', _font)
      ..get('/pair', _pairPage)
      ..post('/api/pair', _pair);
    return const Pipeline()
        .addMiddleware(compressible())
        .addMiddleware(securityHeaders())
        .addMiddleware(_errors)
        .addMiddleware(addressCheck())
        .addMiddleware(
          hostCheck(addresses: () => _addresses, port: () => _port),
        )
        .addMiddleware(bodyLimit())
        .addHandler(open.call);
  }

  Router _routes() => Router(notFoundHandler: (r) => _failure(r, 404))
    ..get('/', _home)
    ..post('/api/logout', _logout)
    ..post('/api/ping', _ping)
    ..get('/api/events', _events);

  static const _sessionKey = 'braim.session';
  static const _csrfKey = 'braim.csrf';

  static bool _isApi(Request r) =>
      r.url.path == 'api' || r.url.path.startsWith('api/');

  Handler _errors(Handler inner) => (request) async {
    try {
      return await inner(request);
    } on HijackException {
      rethrow;
    } on BodyTooLarge {
      return _failure(request, 413);
    } catch (e) {
      if (kDebugMode) debugPrint('Braim Web: ${request.url.path}: $e');
      return _failure(request, 500);
    }
  };

  /// No valid session: pages go to the pairing page, API calls get 401. A
  /// valid session is marked seen and carried to the handlers.
  Handler _sessionCheck(Handler inner) => (request) async {
    WebSession? session;
    String? token;
    for (final t in _cookies(request, sessionCookie)) {
      session = sessions.lookup(t);
      if (session != null) {
        token = t;
        break;
      }
    }
    if (session == null || token == null) {
      return _isApi(request)
          ? _json(401, {'error': 'unauthorized'})
          : Response.found('/pair');
    }
    if (request.url.path != 'api/events') {
      sessions.touch(session);
      onActivity?.call();
    }
    final response = await inner(
      request.change(
        context: {_sessionKey: session, _csrfKey: csrfTokenFor(token)},
      ),
    );
    // A page load renews the cookie, so a browser in use is never asked
    // to pair again; the phone drops it after 30 idle days.
    if (!_isApi(request) &&
        response.statusCode == 200 &&
        response.mimeType == 'text/html') {
      return response.change(
        headers: {'set-cookie': _sessionCookieValue(token)},
      );
    }
    return response;
  };

  /// Mutating requests must echo the page's CSRF token in `X-Braim-CSRF`.
  Handler _csrfCheck(Handler inner) => (request) {
    if (isMutatingMethod(request.method)) {
      final expected = request.context[_csrfKey] as String;
      final given = request.headers[kCsrfHeader];
      if (given == null || !constantTimeEquals(given, expected)) {
        return _json(403, {'error': 'csrf'});
      }
    }
    return inner(request);
  };

  // ---- Open routes ----------------------------------------------------------

  Response _asset(Request request, String name) =>
      assets.asset(name, version: request.url.queryParameters['v']) ??
      _failure(request, 404);

  Future<Response> _font(Request request, String name) async =>
      await assets.font(name) ?? _failure(request, 404);

  Response _pairPage(Request request) {
    final linked = _cookies(
      request,
      sessionCookie,
    ).any((t) => sessions.lookup(t) != null);
    if (linked) return Response.found('/');
    return _html(pairPage(l10n, assets));
  }

  Future<Response> _pair(Request request) async {
    // JSON only: a plain cross-site form can't send it.
    if (request.mimeType != 'application/json') {
      return _json(415, {'error': 'bad_request'});
    }
    Object? body;
    try {
      body = jsonDecode(await readBodyLimited(request));
    } on FormatException {
      return _json(400, {'error': 'bad_request'});
    }
    final code = body is Map ? body['code'] : null;
    if (code is! String || !WebPairing.codePattern.hasMatch(code)) {
      return _json(400, {'error': 'bad_request'});
    }
    if (sessions.isFull) {
      return _json(403, {'error': 'full', 'message': l10n.webPairFull});
    }
    switch (pairing.check(code)) {
      case PairOutcome.paired:
        final created = await sessions.create(
          label: webSessionLabel(request.headers['user-agent'], l10n),
        );
        onActivity?.call();
        return _json(
          200,
          {'ok': true},
          headers: {'set-cookie': _sessionCookieValue(created.token)},
        );
      case PairOutcome.wrong:
        return _json(403, {'error': 'wrong', 'message': l10n.webPairWrong});
      case PairOutcome.expired:
        return _json(403, {'error': 'expired', 'message': l10n.webPairExpired});
      case PairOutcome.locked:
        final ms = pairing.lockLeft.inMilliseconds;
        final seconds = ms <= 0 ? 1 : (ms / 1000).ceil();
        return _json(429, {
          'error': 'locked',
          'seconds': seconds,
          'message': l10n.webPairLocked(seconds),
        });
    }
  }

  // ---- Signed-in routes -----------------------------------------------------

  WebSession _session(Request r) => r.context[_sessionKey] as WebSession;
  String _csrf(Request r) => r.context[_csrfKey] as String;

  Response _home(Request request) =>
      _html(homePlaceholderPage(l10n, assets, _csrf(request)));

  Future<Response> _logout(Request request) async {
    await logOut(_session(request).id);
    return _json(
      200,
      {'ok': true},
      headers: {
        'set-cookie':
            '$sessionCookie=; $_cookieAttributes; '
            'Max-Age=0',
      },
    );
  }

  Response _ping(Request request) => Response(204);

  Response _events(Request request) => Response.ok(
    events.connect(_session(request).id),
    headers: {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
    },
    // Each event must leave at once, not sit in the output buffer.
    context: {'shelf.io.buffer_output': false},
  );

  // ---- Helpers --------------------------------------------------------------

  /// Not `Secure`: the site is plain HTTP on the local network.
  static const _cookieAttributes = 'Path=/; HttpOnly; SameSite=Strict';

  static String _sessionCookieValue(String token) =>
      '$sessionCookie=$token; $_cookieAttributes; '
      'Max-Age=${sessionMaxAge.inSeconds}';

  /// Every value of the cookie [name] the browser sent.
  static Iterable<String> _cookies(Request request, String name) sync* {
    final header = request.headers['cookie'];
    if (header == null) return;
    for (final part in header.split(';')) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      if (part.substring(0, eq).trim() == name) {
        yield part.substring(eq + 1).trim();
      }
    }
  }

  static Response _html(String html, {int status = 200}) => Response(
    status,
    body: html,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );

  static Response _json(
    int status,
    Map<String, Object?> body, {
    Map<String, Object>? headers,
  }) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
  );

  /// An error as the caller expects it: JSON for the API, a plain page
  /// otherwise. Never a stack trace.
  Response _failure(Request request, int status) {
    if (_isApi(request)) {
      final code = switch (status) {
        404 => 'not_found',
        413 => 'too_large',
        _ => 'server',
      };
      return _json(status, {'error': code});
    }
    final message = status == 404 ? l10n.webNotFound : l10n.webError;
    return _html(errorPage(l10n, assets, message), status: status);
  }
}
