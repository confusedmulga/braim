import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/book.dart';
import '../../models/impulse.dart';
import '../../models/note.dart';
import '../../models/space.dart';
import '../../models/tweet_card.dart';
import '../../state/app_state.dart';
import '../db/db_snapshot.dart';
import '../storage_service.dart' show AppData;
import '../store/library_delta.dart';
import '../store/library_zip.dart';
import '../store/remote_protocol.dart';
import '../store/settings_scope.dart';
import 'paired_devices.dart';
import 'web_bundle.dart';

/// Serves the web app and the phone's own library to browsers on the same
/// Wi-Fi or hotspot (remote mode). It runs inside the app and works on the
/// live [AppState], so the phone's screens and every connected browser share
/// one in-memory library: no second database handle, nothing to merge.
///
/// The phone is the single writer of record. A browser's change is applied
/// here through [AppState.applyIncoming] (and so saved like any local edit),
/// then passed on to the other browsers; the phone's own saves are diffed and
/// pushed to every browser. The Crypt stays behind the phone's lock: its rows
/// only reach a browser whose owner unlocked it on the phone, for a while.
class PhoneServer extends ChangeNotifier {
  PhoneServer({
    required this.state,
    required this.bundle,
    required this.devices,
    required this.imagesDir,
    required this.approvePairing,
    required this.approveCrypt,
    this.port = kPhoneServerPort,
    this.bindAddress,
    this.idleStop = const Duration(minutes: 15),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final AppState state;
  final WebBundle bundle;
  final PairedDevices devices;

  /// The phone's images folder (images are served and stored by file name).
  final String imagesDir;

  /// Asks the phone's owner whether [deviceName] may open the library.
  final Future<bool> Function(String deviceName) approvePairing;

  /// Asks the phone's owner (biometrics) to open the Crypt in [deviceName].
  final Future<bool> Function(String deviceName) approveCrypt;

  final int port;
  final InternetAddress? bindAddress;

  /// Stops by itself after this long with no browser connected.
  final Duration idleStop;

  final http.Client _http;

  HttpServer? _server;
  final Set<_Client> _clients = {};

  /// What the browsers hold (the whole library as last sent), so each save
  /// on the phone pushes only what changed.
  final _differ = SnapshotDiffer();

  /// Crypt open until, per paired device (by token hash).
  final Map<String, DateTime> _cryptUntil = {};

  String? _pairingCode;
  DateTime? _pairingExpires;
  int _pairingFailures = 0;
  bool _pairingBusy = false;

  Timer? _tick;
  DateTime _lastClientSeen = DateTime.now();
  String? _bundleTag;

  static final _random = Random.secure();

  bool get running => _server != null;
  int? get boundPort => _server?.port;

  /// Names of the computers connected right now.
  List<String> get connectedDevices => {
        for (final c in _clients)
          if (c.device != null) c.device!.name,
      }.toList();

  String? get pairingCode {
    final exp = _pairingExpires;
    if (_pairingCode == null || exp == null || DateTime.now().isAfter(exp)) {
      return null;
    }
    return _pairingCode;
  }

  // ---- lifecycle ------------------------------------------------------------

  Future<void> start() async {
    if (_server != null) return;
    await devices.load();
    _differ.reseed(snapshotFromAppData(state.currentSnapshot()));
    state.addFlushListener(_onFlush);
    final address = bindAddress ?? InternetAddress.anyIPv4;
    HttpServer server;
    try {
      server = await HttpServer.bind(address, port);
    } on SocketException {
      server = await HttpServer.bind(address, 0);
    }
    server.autoCompress = true;
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    server.listen(_handle, onError: (_) {});
    _lastClientSeen = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => _onTick());
    notifyListeners();
  }

  Future<void> stop({String reason = 'stopped'}) async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _tick?.cancel();
    _tick = null;
    state.removeFlushListener(_onFlush);
    for (final c in _clients.toList()) {
      c.send({'op': 'bye', 'reason': reason});
      await c.close();
    }
    _clients.clear();
    _cryptUntil.clear();
    _pairingCode = null;
    await server.close(force: true);
    await devices.dropSessionOnly();
    bundle.release();
    notifyListeners();
  }

  void _onTick() {
    final now = DateTime.now();
    // Re-lock the Crypt in browsers that went idle.
    for (final hash in _cryptUntil.keys.toList()) {
      if (now.isAfter(_cryptUntil[hash]!)) _lockCrypt(hash);
    }
    if (_clients.isNotEmpty) {
      _lastClientSeen = now;
    } else if (now.difference(_lastClientSeen) > idleStop) {
      unawaited(stop(reason: 'idle'));
    }
    if (_pairingCode != null && pairingCode == null) {
      _pairingCode = null;
      notifyListeners();
    }
  }

  // ---- pairing --------------------------------------------------------------

  /// A fresh single-use code for the address the phone shows (valid a few
  /// minutes). It travels only in the URL fragment, which browsers never send
  /// in a request.
  String newPairingCode() {
    _pairingCode = _randomToken(16);
    _pairingExpires = DateTime.now().add(kPairingCodeLifetime);
    _pairingFailures = 0;
    notifyListeners();
    return _pairingCode!;
  }

  Future<void> revoke(String tokenHash) async {
    await devices.revoke(tokenHash);
    for (final c in _clients.toList()) {
      if (c.device?.tokenHash == tokenHash) {
        c.send({'op': 'bye', 'reason': 'revoked'});
        await c.close();
      }
    }
    notifyListeners();
  }

  static String _randomToken(int bytes) {
    final b = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      b[i] = _random.nextInt(256);
    }
    return base64Url.encode(b).replaceAll('=', '');
  }

  static bool _sameSecret(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// This phone's LAN addresses, best first (Wi-Fi and hotspot interfaces).
  static Future<List<String>> lanAddresses() async {
    final List<NetworkInterface> list;
    try {
      list = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
    } catch (_) {
      return const [];
    }
    int rank(NetworkInterface i) {
      final n = i.name.toLowerCase();
      if (n.startsWith('wlan') || n.startsWith('swlan') || n.startsWith('ap')) {
        return 0;
      }
      if (n.startsWith('rndis') || n.startsWith('eth')) return 1;
      if (n.startsWith('rmnet') || n.startsWith('ccmni')) return 3;
      return 2;
    }

    final sorted = [...list]..sort((a, b) => rank(a).compareTo(rank(b)));
    return [
      for (final i in sorted)
        if (rank(i) < 3)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
  }

  // ---- HTTP -----------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');
    try {
      // Only answer requests addressed to an IP (or localhost): a page on some
      // other domain that re-points its name at this phone gets nothing.
      final host = req.headers.host ?? '';
      if (host != 'localhost' && InternetAddress.tryParse(host) == null) {
        return _send(res, 421, {'error': 'wrong-host'});
      }
      final path = req.uri.path;
      if (path.startsWith('/api/')) {
        res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        return await _api(req, path);
      }
      if (req.method != 'GET' && req.method != 'HEAD') {
        return _send(res, 405, {'error': 'method'});
      }
      return await _static(req, path);
    } catch (e) {
      try {
        await _send(res, 500, {'error': 'server'});
      } catch (_) {}
    }
  }

  Future<void> _send(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Map<String, dynamic>> _jsonBody(HttpRequest req,
      {int max = 1024 * 1024}) async {
    final bytes = await _readBody(req, max);
    final v = jsonDecode(utf8.decode(bytes));
    if (v is! Map<String, dynamic>) throw const FormatException('object');
    return v;
  }

  static Future<Uint8List> _readBody(HttpRequest req, int max) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in req) {
      out.add(chunk);
      if (out.length > max) throw const FormatException('too large');
    }
    return out.takeBytes();
  }

  PairedDevice? _authed(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!h.startsWith('Bearer ')) return null;
    return devices.byToken(h.substring(7).trim());
  }

  Future<void> _api(HttpRequest req, String path) async {
    final res = req.response;
    if (path == RemoteApi.hello) {
      return _send(res, 200, {'app': 'braim', 'proto': kRemoteProto});
    }
    if (path == RemoteApi.pair && req.method == 'POST') return _pair(req);
    if (path == RemoteApi.live) return _live(req);

    final device = _authed(req);
    if (device == null) return _send(res, 401, {'error': 'unauthorized'});
    unawaited(devices.touch(device));

    if (path == RemoteApi.session) {
      return _send(res, 200, {'name': device.name});
    }
    if (path == RemoteApi.snapshot && req.method == 'GET') {
      return _send(res, 200, _snapshotFor(device).toJson());
    }
    if (path.startsWith(RemoteApi.imagePrefix)) {
      final key = Uri.decodeComponent(path.substring(RemoteApi.imagePrefix.length));
      if (!isSafeImageKey(key)) return _send(res, 400, {'error': 'key'});
      if (req.method == 'GET' || req.method == 'HEAD') return _getImage(res, key);
      if (req.method == 'PUT') return _putImage(req, key);
      return _send(res, 405, {'error': 'method'});
    }
    if (req.method != 'POST') return _send(res, 405, {'error': 'method'});
    if (path == RemoteApi.search) return _search(req, device);
    if (path == RemoteApi.fetch) return _fetch(req);
    if (path == RemoteApi.cryptUnlock) return _unlockCrypt(req, device);
    if (path == RemoteApi.cryptLock) {
      _lockCrypt(device.tokenHash);
      return _send(res, 200, {'ok': true});
    }
    return _send(res, 404, {'error': 'not-found'});
  }

  Future<void> _pair(HttpRequest req) async {
    final res = req.response;
    final Map<String, dynamic> body;
    try {
      body = await _jsonBody(req, max: 4096);
    } catch (_) {
      return _send(res, 400, {'error': 'bad-request'});
    }
    final code = pairingCode;
    if (code == null) return _send(res, 410, {'error': 'expired'});
    if (!_sameSecret('${body['code']}', code)) {
      // A handful of wrong guesses burns the code.
      if (++_pairingFailures >= 5) {
        _pairingCode = null;
        notifyListeners();
      }
      return _send(res, 403, {'error': 'bad-code'});
    }
    if (_pairingBusy) return _send(res, 409, {'error': 'busy'});
    _pairingBusy = true;
    _pairingCode = null; // single use
    notifyListeners();
    final rawName = '${body['name'] ?? ''}'.trim();
    final name = rawName.isEmpty
        ? 'A computer'
        : rawName.substring(0, min(rawName.length, 60));
    bool ok;
    try {
      ok = await approvePairing(name)
          .timeout(const Duration(minutes: 2), onTimeout: () => false);
    } catch (_) {
      ok = false;
    } finally {
      _pairingBusy = false;
    }
    if (!ok) return _send(res, 403, {'error': 'denied'});
    final token = _randomToken(32);
    await devices.add(PairedDevice(
      tokenHash: hashToken(token),
      name: name,
      remember: body['remember'] == true,
      pairedAt: DateTime.now(),
    ));
    notifyListeners();
    return _send(res, 200, {'token': token, 'name': name});
  }

  Future<void> _getImage(HttpResponse res, String key) async {
    final file = File('$imagesDir/$key');
    if (!await file.exists()) return _send(res, 404, {'error': 'missing'});
    res.headers
      ..contentType = ContentType.parse(contentTypeFor(key))
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=31536000, immutable');
    await res.addStream(file.openRead());
    await res.close();
  }

  Future<void> _putImage(HttpRequest req, String key) async {
    final res = req.response;
    final Uint8List bytes;
    try {
      bytes = await _readBody(req, kMaxImageUploadBytes);
    } catch (_) {
      return _send(res, 413, {'error': 'too-large'});
    }
    final file = File('$imagesDir/$key');
    // Names are fresh UUIDs; never let an upload replace an existing picture.
    if (!await file.exists()) {
      await Directory(imagesDir).create(recursive: true);
      final part = File('$imagesDir/.$key.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    }
    return _send(res, 200, {'ok': true});
  }

  Future<void> _search(HttpRequest req, PairedDevice device) async {
    final res = req.response;
    final q = '${(await _jsonBody(req, max: 8192))['q'] ?? ''}';
    final hits = await state.searchIndex(q);
    if (hits == null) return _send(res, 200, {'hits': null});
    final hidden = _cryptOpen(device.tokenHash)
        ? const <String>{}
        : cryptEntityIds(state.currentSnapshot());
    return _send(res, 200, {
      'hits': [
        for (final h in hits)
          if (!hidden.contains(h.id)) {'id': h.id, 'kind': h.kind},
      ],
    });
  }

  /// Fetches a page for a browser's link preview (browsers can't read other
  /// sites). Authenticated sessions only, http(s) only, size- and time-capped
  /// — otherwise it would be an open proxy on the network.
  Future<void> _fetch(HttpRequest req) async {
    final res = req.response;
    final body = await _jsonBody(req, max: 16 * 1024);
    final uri = Uri.tryParse('${body['url'] ?? ''}');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return _send(res, 400, {'error': 'url'});
    }
    final headers = <String, String>{
      for (final e in ((body['headers'] as Map?) ?? const {}).entries)
        if ('${e.key}'.toLowerCase() == 'user-agent') '${e.key}': '${e.value}',
    };
    try {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final streamed =
          await _http.send(request).timeout(const Duration(seconds: 10));
      final out = BytesBuilder(copy: false);
      await for (final chunk
          in streamed.stream.timeout(const Duration(seconds: 10))) {
        out.add(chunk);
        if (out.length > kMaxFetchBytes) break;
      }
      return _send(res, 200, {
        'status': streamed.statusCode,
        'contentType': streamed.headers['content-type'] ?? '',
        'body': base64.encode(out.takeBytes()),
      });
    } catch (_) {
      return _send(res, 200, {'status': 599, 'contentType': '', 'body': ''});
    }
  }

  // ---- static bundle --------------------------------------------------------

  /// A tag for this bundle's files, so a browser revalidates cheaply and
  /// refetches after the app (and its bundle) updates.
  Future<String> _tag() async {
    final cached = _bundleTag;
    if (cached != null) return cached;
    final v = await bundle.read('version.json') ?? Uint8List(0);
    final js = await bundle.read('main.dart.js');
    return _bundleTag = sha1
        .convert([...v, ...utf8.encode('${js?.length ?? 0}')])
        .toString()
        .substring(0, 16);
  }

  Future<void> _static(HttpRequest req, String path) async {
    final res = req.response;
    var rel = path == '/' ? 'index.html' : path.substring(1);
    rel = Uri.decodeComponent(rel);
    if (rel.contains('..') || rel.contains('\\')) {
      return _send(res, 400, {'error': 'path'});
    }
    final etag = '"${await _tag()}-${rel.hashCode.toRadixString(16)}"';
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      res.statusCode = HttpStatus.notModified;
      return res.close();
    }
    final bytes = await bundle.read(rel);
    if (bytes == null) {
      if (rel.startsWith('fonts/gstatic/')) {
        // A fallback font this build doesn't carry: fetch it from Google when
        // the computer is online (off-grid, that script stays as boxes).
        res.statusCode = HttpStatus.found;
        res.headers.set(HttpHeaders.locationHeader,
            'https://fonts.gstatic.com/s/${rel.substring('fonts/gstatic/'.length)}');
        return res.close();
      }
      if (rel == 'index.html') {
        res.headers.contentType = ContentType.html;
        res.write(_noBundlePage);
        return res.close();
      }
      return _send(res, 404, {'error': 'not-found'});
    }
    res.headers
      ..set(HttpHeaders.contentTypeHeader, contentTypeFor(rel))
      ..set(HttpHeaders.etagHeader, etag)
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (req.method == 'HEAD') {
      res.contentLength = bytes.length;
      return res.close();
    }
    res.add(bytes);
    await res.close();
  }

  static const _noBundlePage = '<!doctype html><meta charset="utf-8">'
      '<title>Braim</title><body style="font-family:sans-serif;padding:2em">'
      '<h2>This build of Braim has no web app inside.</h2>'
      '<p>Build the app with <code>tool/build_web_bundle.sh</code> first.</p>';

  // ---- live channel ---------------------------------------------------------

  Future<void> _live(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      return _send(req.response, 400, {'error': 'upgrade'});
    }
    // Browsers let any page open a WebSocket anywhere; only our own page may.
    final origin = req.headers.value('origin');
    final host = req.headers.value(HttpHeaders.hostHeader);
    if (origin != null && host != null && Uri.tryParse(origin)?.authority != host) {
      return _send(req.response, 403, {'error': 'origin'});
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 20);
    final client = _Client(ws);
    _clients.add(client);
    final authTimer = Timer(const Duration(seconds: 10), () {
      if (client.device == null) client.close();
    });
    ws.listen(
      (data) {
        if (data is String) _onFrame(client, data);
      },
      onDone: () {
        authTimer.cancel();
        _clients.remove(client);
        notifyListeners();
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  void _onFrame(_Client c, String data) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final op = msg['op'];
    if (c.device == null) {
      final d = op == 'auth' ? devices.byToken('${msg['token']}') : null;
      if (d == null) {
        c.send({'op': 'bye', 'reason': 'unauthorized'});
        c.close();
        return;
      }
      c.device = d;
      unawaited(devices.touch(d));
      c.send({
        'op': 'snapshot',
        'delta': _snapshotFor(d).toJson(),
        'crypt': _cryptOpen(d.tokenHash),
      });
      notifyListeners();
      return;
    }
    final hash = c.device!.tokenHash;
    switch (op) {
      case 'push':
        _applyFromClient(c, msg['delta'], msg['seq']);
      case 'addTyping':
        final ms = msg['ms'];
        if (ms is int) state.addTypingMillis(ms);
      case 'ping':
        if (msg['active'] == true && _cryptOpen(hash)) {
          _cryptUntil[hash] = DateTime.now().add(kCryptIdleLock);
        }
        c.send({'op': 'pong'});
    }
  }

  /// The library as [device] may see it: everything but the Crypt, unless its
  /// owner unlocked the Crypt there.
  LibraryDelta _snapshotFor(PairedDevice device) {
    final data = state.currentSnapshot();
    final visible = _cryptOpen(device.tokenHash) ? data : withoutCrypt(data);
    return LibraryDelta.ofSnapshot(snapshotFromAppData(visible));
  }

  bool _cryptOpen(String tokenHash) =>
      _cryptUntil[tokenHash]?.isAfter(DateTime.now()) ?? false;

  /// A change for [c]: rows of the Crypt become removals while it's locked
  /// there (a row that just moved into the Crypt must vanish from the page).
  LibraryDelta _forClient(_Client c, LibraryDelta d, Set<String> crypt) {
    if (_cryptOpen(c.device!.tokenHash) || crypt.isEmpty) return d;
    return LibraryDelta(
      rows: [
        for (final r in d.rows)
          crypt.contains(r.id) ? (table: r.table, id: r.id, row: null) : r,
      ],
      settings: d.settings,
    );
  }

  void _broadcast(LibraryDelta d, {_Client? except}) {
    if (d.isEmpty) return;
    final crypt = cryptEntityIds(state.currentSnapshot());
    for (final c in _clients) {
      if (identical(c, except) || c.device == null) continue;
      c.send({'op': 'push', 'delta': _forClient(c, d, crypt).toJson()});
    }
  }

  /// The phone saved: push what changed to every browser.
  void _onFlush(AppData snapshot) {
    final delta = _differ.diff(snapshotFromAppData(snapshot));
    if (delta.isEmpty) return;
    _differ.commit(delta);
    _broadcast(delta);
  }

  static Object? _decodeRow(String table, Map<String, Object?> row) {
    final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    return switch (table) {
      'notes' => Note.fromJson(body),
      'cards' => TweetCard.fromJson(body),
      'books' => Book.fromJson(body),
      'impulses' => Impulse.fromJson(body),
      'spaces' => Space.fromJson(body),
      _ => null,
    };
  }

  void _applyFromClient(_Client c, Object? rawDelta, Object? seq) {
    LibraryDelta delta;
    try {
      delta = LibraryDelta.fromJson(rawDelta as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    final crypt = cryptEntityIds(state.currentSnapshot());
    final open = _cryptOpen(c.device!.tokenHash);
    final rows = <RowChange>[];
    for (final r in delta.rows) {
      if (!SnapshotDiffer.tables.contains(r.table)) continue;
      // A browser without the Crypt can't touch what's in it.
      if (!open && crypt.contains(r.id)) continue;
      final row = r.row;
      if (row != null) {
        try {
          if (row['id'] != r.id || _decodeRow(r.table, row) == null) continue;
        } catch (_) {
          continue; // malformed: drop the row, keep the rest
        }
      }
      rows.add(r);
    }
    final settings = {
      for (final e in delta.settings.entries)
        if (isSharedSetting(e.key)) e.key: e.value,
    };
    final applied = state.applyIncoming(
        LibraryDelta(rows: rows, settings: settings),
        persist: true);
    _differ.commit(applied);
    _broadcast(applied, except: c);
    if (seq != null) c.send({'op': 'ack', 'seq': seq});
  }

  // ---- Crypt ----------------------------------------------------------------

  Future<void> _unlockCrypt(HttpRequest req, PairedDevice device) async {
    final res = req.response;
    bool ok;
    try {
      ok = await approveCrypt(device.name)
          .timeout(const Duration(minutes: 2), onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    if (!ok) return _send(res, 403, {'error': 'denied'});
    _cryptUntil[device.tokenHash] = DateTime.now().add(kCryptIdleLock);
    // Hand the Crypt to that computer's open tabs.
    final data = state.currentSnapshot();
    final crypt = cryptEntityIds(data);
    final rows = LibraryDelta.ofSnapshot(snapshotFromAppData(data))
        .rows
        .where((r) => crypt.contains(r.id))
        .toList();
    for (final c in _clients) {
      if (c.device?.tokenHash == device.tokenHash) {
        c.send({'op': 'push', 'delta': LibraryDelta(rows: rows).toJson()});
      }
    }
    return _send(res, 200, {'ok': true});
  }

  void _lockCrypt(String tokenHash) {
    if (_cryptUntil.remove(tokenHash) == null) return;
    final ids = cryptEntityIds(state.currentSnapshot()).toList();
    for (final c in _clients) {
      if (c.device?.tokenHash == tokenHash) {
        c.send({'op': 'lock', 'ids': ids});
      }
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    _http.close();
    super.dispose();
  }
}

class _Client {
  _Client(this.ws);

  final WebSocket ws;
  PairedDevice? device;

  void send(Map<String, Object?> msg) {
    if (ws.readyState == WebSocket.open) ws.add(jsonEncode(msg));
  }

  Future<void> close() async {
    try {
      await ws.close();
    } catch (_) {}
  }
}
