import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:uuid/uuid.dart';

import '../../platform/fetcher.dart';
import '../../platform/image_store.dart';
import '../../platform/web_bridge.dart';
import '../db/db_snapshot.dart';
import '../db/db_store.dart' show SearchHit;
import '../storage_service.dart' show AppData;
import 'library_delta.dart';
import 'library_store.dart';
import 'remote_protocol.dart';
import 'settings_scope.dart';

/// Connection to the phone as the UI shows it.
enum PhoneLinkState { connecting, online, reconnecting, offline, revoked }

/// Remote mode: the phone's library, live, over the LAN. The browser holds it
/// in memory only; the phone is the single writer of record. Changes made here
/// go to the phone as row deltas (the same [SnapshotDiffer] output the phone's
/// SQLite store writes); changes made on the phone arrive on [incoming].
///
/// Settings that belong to this computer (theme, wallpaper, sort…) stay in the
/// browser's localStorage and never reach the phone.
class RemoteLibraryStore implements LibraryStore {
  RemoteLibraryStore({required this.origin, required this.token});

  final String origin;
  final String token;

  final _differ = SnapshotDiffer();
  final _incoming = StreamController<LibraryDelta>.broadcast();

  /// Link state for the status pill / offline guard.
  final status = ValueNotifier(PhoneLinkState.connecting);

  /// Whether the phone currently shares its Crypt with this computer.
  final cryptOpen = ValueNotifier(false);

  /// Called when the phone re-locks the Crypt: drop these ids from memory.
  void Function(Set<String> ids)? onCryptLocked;

  WebSocketConn? _ws;
  Completer<AppSnapshot>? _firstSnapshot;
  bool _closed = false;
  int _seq = 0;
  int _retry = 0;
  DateTime? _offlineSince;
  Timer? _pingTimer;
  bool _activeSincePing = false;

  /// Changes made while the phone was out of reach, merged by row (latest
  /// wins), sent as one push on reconnect.
  final Map<String, RowChange> _queuedRows = {};
  final Map<String, String> _queuedSettings = {};
  int _queuedTyping = 0;

  /// Pushes sent but not yet acknowledged, by sequence number.
  final Map<int, Completer<void>> _unacked = {};

  /// The typing total last agreed with the phone.
  int? _typingBaseline;

  static const _perDeviceKey = 'braim.remote.deviceSettings';

  Map<String, String> get _authHeader => {'Authorization': 'Bearer $token'};

  String get _wsUrl {
    final u = Uri.parse(origin);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: RemoteApi.live).toString();
  }

  // ---- load / connect --------------------------------------------------------

  AppData? _preloaded;

  /// Connects and fetches the library before the app starts, so the boot can
  /// show a "can't reach your phone" screen instead of an endless spinner.
  /// Throws when the phone can't be reached or the session was refused.
  Future<void> preload() async => _preloaded ??= _toAppData(await _connect());

  @override
  Future<AppData> load({bool restored = false}) async {
    final pre = _preloaded;
    if (pre != null) {
      _preloaded = null;
      return pre;
    }
    return _toAppData(await _connect());
  }

  AppData _toAppData(AppSnapshot snap) {
    _differ.reseed(snap);
    final settings = Map.of(snap.settings);
    _typingBaseline = _typingOf(settings);
    // This computer's own theme, wallpaper, sort… (the phone's are only a
    // starting point the first time).
    settings.addAll(_loadPerDevice());
    return appDataFromSnapshot(AppSnapshot(
      notes: snap.notes,
      cards: snap.cards,
      books: snap.books,
      impulses: snap.impulses,
      spaces: snap.spaces,
      settings: settings,
    ));
  }

  static int? _typingOf(Map<String, String> settings) {
    final v = settings['typingMillis'];
    return v == null ? null : (jsonDecode(v) as num?)?.toInt();
  }

  Map<String, String> _loadPerDevice() {
    final raw = webStorageGet(_perDeviceKey);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return const {};
    }
  }

  void _savePerDevice(Map<String, String> changed) {
    if (changed.isEmpty) return;
    final all = {..._loadPerDevice(), ...changed};
    webStorageSet(_perDeviceKey, jsonEncode(all));
  }

  Future<AppSnapshot> _connect() {
    final first = _firstSnapshot = Completer<AppSnapshot>();
    _open();
    return first.future;
  }

  void _open() {
    if (_closed) return;
    final ws = WebSocketConn.connect(_wsUrl);
    _ws = ws;
    ws.ready.then((_) {
      ws.send(jsonEncode({'op': 'auth', 'token': token}));
    }, onError: (_) {});
    ws.messages.listen(_onFrame, onDone: () => _onDrop(ws));
  }

  void _onDrop(WebSocketConn ws) {
    if (!identical(ws, _ws) || _closed) return;
    _ws = null;
    _pingTimer?.cancel();
    if (status.value == PhoneLinkState.revoked) return;
    _offlineSince ??= DateTime.now();
    status.value = DateTime.now().difference(_offlineSince!) >
            const Duration(seconds: 60)
        ? PhoneLinkState.offline
        : PhoneLinkState.reconnecting;
    for (final c in _unacked.values) {
      if (!c.isCompleted) c.complete();
    }
    _unacked.clear();
    final first = _firstSnapshot;
    if (first != null && !first.isCompleted && _retry >= 3) {
      first.completeError(StateError('Could not reach the phone.'));
      return;
    }
    // Back off 1, 2, 4… up to 10 s between attempts.
    final wait = Duration(seconds: [1, 2, 4, 8, 10][_retry.clamp(0, 4)]);
    _retry++;
    Timer(wait, _open);
  }

  void _onFrame(String data) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['op']) {
      case 'snapshot':
        _onSnapshot(LibraryDelta.fromJson(msg['delta'] as Map<String, dynamic>),
            crypt: msg['crypt'] == true);
      case 'push':
        final d = _fromPhone(
            LibraryDelta.fromJson(msg['delta'] as Map<String, dynamic>));
        if (!d.isEmpty) _incoming.add(d);
      case 'ack':
        _unacked.remove(msg['seq'])?.complete();
      case 'lock':
        cryptOpen.value = false;
        onCryptLocked?.call({for (final i in (msg['ids'] as List)) '$i'});
      case 'bye':
        if (msg['reason'] == 'revoked' || msg['reason'] == 'unauthorized') {
          status.value = PhoneLinkState.revoked;
          final first = _firstSnapshot;
          if (first != null && !first.isCompleted) {
            first.completeError(StateError('unauthorized'));
          }
        }
    }
  }

  /// Settings this computer keeps for itself never come in from the phone;
  /// the phone's typing total becomes the new agreed baseline.
  LibraryDelta _fromPhone(LibraryDelta d) {
    final settings = <String, String>{};
    d.settings.forEach((k, v) {
      if (kPerDeviceSettings.contains(k)) return;
      if (k == 'typingMillis') {
        _typingBaseline = _typingOf({k: v});
        // Keep what's been typed here but not yet sent on top of it.
        final pending = _queuedTyping;
        if (pending > 0) v = jsonEncode((_typingBaseline ?? 0) + pending);
      }
      settings[k] = v;
    });
    return LibraryDelta(rows: d.rows, settings: settings);
  }

  void _onSnapshot(LibraryDelta full, {required bool crypt}) {
    _retry = 0;
    _offlineSince = null;
    cryptOpen.value = crypt;
    status.value = PhoneLinkState.online;
    _startPings();
    final first = _firstSnapshot;
    if (first != null && !first.isCompleted) {
      _firstSnapshot = null;
      first.complete(full.toSnapshot());
      return;
    }
    // A reconnect: bring memory up to what the phone now holds, except rows
    // changed here meanwhile (they go to the phone next and win).
    // Diffing the phone's library against what this page holds (without
    // committing) is exactly what changed on the phone meanwhile.
    final changed = _differ.diff(full.toSnapshot());
    final rows = [
      for (final r in changed.rows)
        if (!_queuedRows.containsKey('${r.table}:${r.id}')) r,
    ];
    final delta = _fromPhone(LibraryDelta(
      rows: rows,
      settings: {
        for (final e in changed.settings.entries)
          if (!_queuedSettings.containsKey(e.key)) e.key: e.value,
      },
    ));
    if (!delta.isEmpty) _incoming.add(delta);
    _flushQueue();
  }

  void _startPings() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      _ws?.send(jsonEncode({'op': 'ping', 'active': _activeSincePing}));
      _activeSincePing = false;
    });
  }

  /// The user did something (keeps an unlocked Crypt from timing out).
  void markActive() => _activeSincePing = true;

  // ---- saving ----------------------------------------------------------------

  @override
  Future<void> afterLoad(AppData Function() snapshot) async {}

  @override
  void save(AppData snapshot, int rev) {
    final snap = snapshotFromAppData(snapshot);
    final delta = _differ.diff(snap);
    if (delta.isEmpty) return;
    _differ.commit(delta);
    _activeSincePing = true;

    final perDevice = <String, String>{};
    final shared = <String, String>{};
    delta.settings.forEach((k, v) {
      if (kPerDeviceSettings.contains(k)) {
        perDevice[k] = v;
      } else if (k == 'typingMillis') {
        final now = _typingOf({k: v}) ?? 0;
        final base = _typingBaseline ?? now;
        if (now > base) _queuedTyping += now - base;
        _typingBaseline = now;
      } else if (isSharedSetting(k)) {
        shared[k] = v;
      }
    });
    _savePerDevice(perDevice);
    for (final r in delta.rows) {
      _queuedRows['${r.table}:${r.id}'] = r;
    }
    _queuedSettings.addAll(shared);
    _flushQueue();
  }

  void _flushQueue() {
    final ws = _ws;
    if (ws == null || status.value != PhoneLinkState.online) return;
    if (_queuedTyping > 0) {
      ws.send(jsonEncode({'op': 'addTyping', 'ms': _queuedTyping}));
      _queuedTyping = 0;
    }
    if (_queuedRows.isEmpty && _queuedSettings.isEmpty) return;
    final delta = LibraryDelta(
        rows: _queuedRows.values.toList(), settings: Map.of(_queuedSettings));
    _queuedRows.clear();
    _queuedSettings.clear();
    final seq = ++_seq;
    _unacked[seq] = Completer<void>();
    ws.send(jsonEncode({'op': 'push', 'seq': seq, 'delta': delta.toJson()}));
  }

  /// Whether there are edits the phone doesn't have yet.
  bool get hasUnsent =>
      _queuedRows.isNotEmpty || _queuedSettings.isNotEmpty || _unacked.isNotEmpty;

  @override
  Future<void> flushNow({
    required bool loaded,
    required int rev,
    required AppData Function() snapshot,
  }) async {
    _flushQueue();
    if (_unacked.isEmpty) return;
    await Future.wait([for (final c in _unacked.values) c.future])
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
  }

  @override
  void adopt(LibraryDelta applied) => _differ.commit(applied);

  @override
  Stream<LibraryDelta> get incoming => _incoming.stream;

  // ---- HTTP calls ------------------------------------------------------------

  @override
  Future<List<SearchHit>?> search(String query) async {
    try {
      final res = await http
          .post(Uri.parse('$origin${RemoteApi.search}'),
              headers: {..._authHeader, 'Content-Type': 'application/json'},
              body: jsonEncode({'q': query}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final hits = (jsonDecode(res.body) as Map)['hits'];
      if (hits is! List) return null;
      return [
        for (final h in hits)
          (id: '${(h as Map)['id']}', kind: '${h['kind']}'),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Asks the phone to open the Crypt here (its owner confirms on the phone).
  Future<bool> unlockCrypt() async {
    try {
      final res = await http
          .post(Uri.parse('$origin${RemoteApi.cryptUnlock}'),
              headers: _authHeader)
          .timeout(const Duration(minutes: 2));
      final ok = res.statusCode == 200;
      if (ok) {
        cryptOpen.value = true;
        // The Crypt's rows arrive on the live channel; give them a moment.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Ends this computer's session: the phone forgets it.
  Future<void> close() async {
    _closed = true;
    _pingTimer?.cancel();
    _ws?.close();
    _ws = null;
  }
}

/// Images live on the phone: fetched over HTTP (kept in memory once decoded
/// by Flutter's image cache) and uploaded before the row that uses them.
class RemoteImageStore implements ImageStore {
  RemoteImageStore({required this.origin, required this.token});

  final String origin;
  final String token;
  static const _uuid = Uuid();

  final Map<String, Uint8List> _recent = {};

  Map<String, String> get _auth => {'Authorization': 'Bearer $token'};

  @override
  Future<String> saveBytes(Uint8List bytes, {String ext = '.png'}) async {
    final key = '${_uuid.v4()}$ext';
    final res = await http
        .put(Uri.parse('$origin${RemoteApi.imagePrefix}$key'),
            headers: _auth, body: bytes)
        .timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      throw StateError('The phone did not take the image (${res.statusCode}).');
    }
    _remember(key, bytes);
    return relativeImagePath(key);
  }

  @override
  Future<String> savePicked(XFile file) async =>
      saveBytes(await file.readAsBytes(), ext: extensionOf(file.name));

  @override
  Future<Uint8List?> load(String path) async {
    final key = imageKey(path);
    final hit = _recent[key];
    if (hit != null) return hit;
    try {
      final res = await http
          .get(Uri.parse('$origin${RemoteApi.imagePrefix}${Uri.encodeComponent(key)}'),
              headers: _auth)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      _remember(key, res.bodyBytes);
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// A small cache for the crop screen / exports (Flutter caches the decoded
  /// pictures itself).
  void _remember(String key, Uint8List bytes) {
    if (bytes.length > 4 * 1024 * 1024) return;
    _recent[key] = bytes;
    while (_recent.length > 24) {
      _recent.remove(_recent.keys.first);
    }
  }

  /// The phone owns image clean-up (it deletes a picture only once nothing it
  /// holds points at it); a browser never deletes one.
  @override
  Future<void> delete(String path) async {}
}

/// Link previews and YouTube pages, fetched by the phone (browsers can't read
/// other sites).
class PhoneFetcher implements Fetcher {
  PhoneFetcher({required this.origin, required this.token});

  final String origin;
  final String token;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final res = await http.post(Uri.parse('$origin${RemoteApi.fetch}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': url.toString(), 'headers': headers ?? {}}));
    if (res.statusCode != 200) return http.Response('', 599);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final type = '${j['contentType'] ?? ''}';
    return http.Response.bytes(
      base64.decode('${j['body'] ?? ''}'),
      (j['status'] as num?)?.toInt() ?? 599,
      headers: {if (type.isNotEmpty) 'content-type': type},
    );
  }
}
