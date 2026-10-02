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
import '../models/book.dart';
import '../services/library_search.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../models/note.dart';
import '../models/tweet_card.dart';
import '../services/wiki_links.dart';
import 'web_api.dart';
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
    Future<Directory> Function()? imagesDir,
    this.onActivity,
  }) : pairing = pairing ?? WebPairing(),
       assets = assets ?? WebAssets(),
       _imagesDir = imagesDir ?? (() => StorageService.instance.imagesDir),
       l10n = lookupAppLocalizations(const Locale('en')) {
    events = WebEventHub(source: state, revision: () => state.revision);
    pages = WebPages(l10n: l10n, assets: this.assets, state: state);
    api = WebApi(state: state, l10n: l10n);
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
  late final WebPages pages;
  late final WebApi api;
  final Future<Directory> Function() _imagesDir;

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
    state.releaseEditLeasesOf(webLeaseHolder(sessionId));
    return saved;
  }

  /// Logs every linked browser out.
  Future<void> logOutAll() {
    for (final s in sessions.sessions) {
      state.releaseEditLeasesOf(webLeaseHolder(s.id));
    }
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
      ..get('/assets/<name|.+>', _asset)
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
    ..get('/', _feed)
    ..get('/notes/new', _newNote)
    ..get('/notes/<id>', _note)
    ..get('/notes/<id>/edit', _editNote)
    ..get('/sparks', _sparks)
    ..get('/sparks/<id>', _spark)
    ..get('/sparks/<id>/edit', _editSpark)
    ..get('/circuits', _circuits)
    ..get('/circuits/<id>', _circuitMap)
    ..get('/books', (Request r) => _view(r, pages.books(), tab: 'books'))
    ..get('/books/<id>', _bookContents)
    ..get('/books/<id>/read', _bookReader)
    ..get('/books/<id>/pages/<pageId>/edit', _editBookPage)
    ..post('/api/notes', (Request r) => api.createNote(r))
    ..put(
      '/api/notes/<id>',
      (Request r, String id) => api.saveNote(r, id, _sid(r)),
    )
    ..delete(
      '/api/notes/<id>',
      (Request r, String id) => api.deleteNote(id, _sid(r)),
    )
    ..post(
      '/api/notes/<id>/check',
      (Request r, String id) => api.checkLine(r, id, _sid(r)),
    )
    ..post('/api/notes/<id>/lease', _takeNoteLease)
    ..delete(
      '/api/notes/<id>/lease',
      (Request r, String id) => api.releaseLease(id, _sid(r)),
    )
    ..post('/api/markdown/preview', (Request r) => api.markdownPreview(r))
    ..post('/api/sparks', (Request r) => api.addSpark(r))
    ..put(
      '/api/sparks/<id>',
      (Request r, String id) => api.saveSpark(r, id, _sid(r)),
    )
    ..delete(
      '/api/sparks/<id>',
      (Request r, String id) => api.deleteSpark(id, _sid(r)),
    )
    ..post(
      '/api/sparks/<id>/check',
      (Request r, String id) => api.checkSparkLine(r, id, _sid(r)),
    )
    ..post('/api/sparks/<id>/lease', _takeSparkLease)
    ..delete(
      '/api/sparks/<id>/lease',
      (Request r, String id) => api.releaseLease(id, _sid(r)),
    )
    ..post('/api/circuits', (Request r) => api.createCircuit(r))
    ..get(
      '/api/circuits/nodes/<id>/menu',
      (Request r, String id) => api.circuitNodeMenu(id),
    )
    ..post(
      '/api/circuits/nodes/<id>/child',
      (Request r, String id) => api.addCircuitNote(r, id, under: true),
    )
    ..post(
      '/api/circuits/nodes/<id>/sibling',
      (Request r, String id) => api.addCircuitNote(r, id, under: false),
    )
    ..post(
      '/api/circuits/nodes/<id>/rename',
      (Request r, String id) => api.renameCircuitNode(r, id, _sid(r)),
    )
    ..post(
      '/api/circuits/nodes/<id>/move',
      (Request r, String id) => api.moveCircuitNode(r, id),
    )
    ..post(
      '/api/circuits/nodes/<id>/delete',
      (Request r, String id) => api.deleteCircuitNode(r, id, _sid(r)),
    )
    ..post(
      '/api/circuits/nodes/<id>/write-placeholder',
      (Request r, String id) => api.writePlaceholder(r, id),
    )
    ..post(
      '/api/circuits/nodes/<id>/remove-placeholder',
      (Request r, String id) => api.removePlaceholder(id),
    )
    ..post(
      '/api/circuits/<id>/layout',
      (Request r, String id) => api.setCircuitLayout(r, id),
    )
    ..post(
      '/api/books/<id>/chapters',
      (Request r, String id) => api.addChapter(id),
    )
    ..post(
      '/api/books/<id>/pages/<pageId>/move',
      (Request r, String id, String pageId) =>
          api.moveBookPage(r, id, pageId, _sid(r)),
    )
    ..get('/search', _search)
    ..get('/link', _link)
    ..get('/img/<name>', _image)
    ..get('/api/notes/<id>/meta', _noteMeta)
    ..get('/api/sparks/<id>/meta', _sparkMeta)
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
  String _sid(Request r) => _session(r).id;
  String _csrf(Request r) => r.context[_csrfKey] as String;

  /// A signed-in page, or just its main area when a list page refreshes
  /// itself (`?partial=1`).
  Response _view(
    Request request,
    WebView view, {
    String tab = '',
    String query = '',
    bool editor = false,
    bool map = false,
  }) {
    if (request.url.queryParameters['partial'] == '1') {
      return _html(view.main);
    }
    return _html(
      pages.page(
        view,
        csrf: _csrf(request),
        tab: tab,
        query: query,
        editor: editor,
        map: map,
      ),
    );
  }

  Response _feed(Request request) => _view(request, pages.feed(), tab: 'notes');

  /// The live note [id] if the web may show it. Anything else, the Crypt
  /// included, is indistinguishable from a note that doesn't exist.
  Note? _visibleNote(String id) => api.visibleNote(id);

  /// The spark [id] if it is in the Sparks feed's population.
  TweetCard? _visibleSpark(String id) => api.visibleSpark(id);

  Response _newNote(Request request) => _view(
    request,
    pages.noteEditor(
      null,
      markdown: request.url.queryParameters['kind'] == 'markdown',
    ),
    tab: 'notes',
    editor: true,
  );

  Response _editNote(Request request, String id) {
    final n = _visibleNote(id);
    if (n == null) return _failure(request, 404);
    final contents = _contentsOf(n);
    if (contents != null) return contents;
    return _view(request, pages.noteEditor(n), tab: _tabOf(n), editor: true);
  }

  /// The menu bar's section for a note.
  static String _tabOf(Note n) =>
      n.bookId != null ? 'books' : (n.inCircuit ? 'circuits' : 'notes');

  /// A book's Contents page is its contents on the web: a redirect there, or
  /// null for any other note.
  Response? _contentsOf(Note n) =>
      n.bookId != null && n.bookPageKind == BookPageKind.contents
      ? Response.found('/books/${Uri.encodeComponent(n.bookId!)}')
      : null;

  Response _editSpark(Request request, String id) {
    final c = _visibleSpark(id);
    if (c == null) return _failure(request, 404);
    return _view(request, pages.sparkEditor(c), tab: 'sparks', editor: true);
  }

  Response _takeNoteLease(Request request, String id) =>
      _visibleNote(id) == null
      ? _failure(request, 404)
      : api.takeLease(id, _sid(request));

  Response _takeSparkLease(Request request, String id) =>
      _visibleSpark(id) == null
      ? _failure(request, 404)
      : api.takeLease(id, _sid(request));

  Response _note(Request request, String id) {
    final n = _visibleNote(id);
    if (n == null) return _failure(request, 404);
    return _contentsOf(n) ?? _view(request, pages.note(n), tab: _tabOf(n));
  }

  Response _circuits(Request request) =>
      _view(request, pages.circuits(), tab: 'circuits');

  /// A circuit's map. Only a first note has one, and only while the web may
  /// show it; a placeholder can be focused but never opened.
  Response _circuitMap(Request request, String id) {
    final root = api.circuitRoot(id);
    if (root == null) return _failure(request, 404);
    final focus = request.url.queryParameters['focus'];
    return _view(
      request,
      pages.circuitMap(
        root,
        focus: focus != null && api.circuitNode(focus)?.circuitId == id
            ? focus
            : null,
      ),
      tab: 'circuits',
      map: true,
    );
  }

  Response _bookContents(Request request, String id) {
    final b = api.visibleBook(id);
    if (b == null) return _failure(request, 404);
    return _view(request, pages.bookContents(b), tab: 'books');
  }

  Response _bookReader(Request request, String id) {
    final b = api.visibleBook(id);
    if (b == null) return _failure(request, 404);
    return _view(request, pages.bookReader(b), tab: 'books');
  }

  Response _editBookPage(Request request, String id, String pageId) {
    final page = api.bookPage(id, pageId);
    if (page == null) return _failure(request, 404);
    return _view(request, pages.noteEditor(page), tab: 'books', editor: true);
  }

  Response _sparks(Request request) =>
      _view(request, pages.sparks(), tab: 'sparks');

  Response _spark(Request request, String id) {
    final c = _visibleSpark(id);
    if (c == null) return _failure(request, 404);
    return _view(request, pages.spark(c), tab: 'sparks');
  }

  Future<Response> _search(Request request) async {
    final query = request.url.queryParameters['q'] ?? '';
    if (query.trim().isEmpty) {
      return _view(request, pages.search(query, null), query: query);
    }
    final found = await searchLibrary(state, query);
    // Search reaches journal entries and archived notes on the phone only.
    final visible = (
      notes: found.notes.where(state.isWebVisibleNote).toList(),
      cards: found.cards,
    );
    return _view(request, pages.search(query, visible), query: query);
  }

  /// A `[[Title]]` link: to the note or spark it names, or a page saying it
  /// lives on the phone. A missing item and a hidden one look the same.
  Response _link(Request request) {
    final title = request.url.queryParameters['to'] ?? '';
    final ref = title.trim().isEmpty ? null : state.resolveLink(title);
    if (ref != null) {
      if (ref.kind == LinkKind.note && _visibleNote(ref.id) != null) {
        return Response.found('/notes/${Uri.encodeComponent(ref.id)}');
      }
      if (ref.kind == LinkKind.card && _visibleSpark(ref.id) != null) {
        return Response.found('/sparks/${Uri.encodeComponent(ref.id)}');
      }
    }
    return _view(request, pages.notAvailable(title));
  }

  static final _imageNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

  static const _imageTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'bmp': 'image/bmp',
  };

  /// `/img/<name>`: only a plain file name, only an image a web-visible item
  /// uses, and only from the images folder. A Crypt image stays private even
  /// when its name is known.
  Future<Response> _image(Request request, String name) async {
    if (!_imageNamePattern.hasMatch(name) ||
        name.startsWith('.') ||
        !state.webImageNames.contains(name)) {
      return _failure(request, 404);
    }
    final dir = await _imagesDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (!await file.exists()) return _failure(request, 404);
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': _imageTypes[ext] ?? 'application/octet-stream',
        'content-length': '${await file.length()}',
        // Image names are UUIDs and never change content.
        'cache-control': 'private, max-age=31536000, immutable',
      },
    );
  }

  Response _noteMeta(Request request, String id) {
    final n = _visibleNote(id);
    if (n == null) return _failure(request, 404);
    return _json(200, {
      'updatedAt': n.updatedAt.millisecondsSinceEpoch,
      'leaseHolder': api.leaseHolderFor(id, _sid(request)),
    });
  }

  Response _sparkMeta(Request request, String id) {
    final c = _visibleSpark(id);
    if (c == null) return _failure(request, 404);
    return _json(200, {
      'updatedAt': c.updatedAt.millisecondsSinceEpoch,
      'leaseHolder': api.leaseHolderFor(id, _sid(request)),
    });
  }

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
