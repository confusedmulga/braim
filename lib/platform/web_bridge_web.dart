import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// One write in an IndexedDB transaction: [value] is a `String` or a
/// `Uint8List`; null deletes [key].
typedef IdbOp = ({String store, String key, Object? value});

String webPageOrigin() => web.window.location.origin;
String webLocationHash() => web.window.location.hash;
String webLocationSearch() => web.window.location.search;

/// Replaces the URL fragment without adding a history entry (used to drop a
/// one-time pairing code from the address bar once it has been read).
void webReplaceHash(String hash) {
  final loc = web.window.location;
  final url = '${loc.pathname}${loc.search}${hash.isEmpty ? '' : '#$hash'}';
  web.window.history.replaceState(null, '', url);
}

/// "Chrome on Windows"-style label shown on the phone when pairing.
String webDeviceLabel() {
  final ua = web.window.navigator.userAgent;
  final browser = ua.contains('Edg/')
      ? 'Edge'
      : ua.contains('Firefox/')
          ? 'Firefox'
          : ua.contains('Chrome/')
              ? 'Chrome'
              : ua.contains('Safari/')
                  ? 'Safari'
                  : 'A browser';
  final os = ua.contains('Windows')
      ? 'Windows'
      : ua.contains('Mac OS')
          ? 'Mac'
          : ua.contains('Android')
              ? 'Android'
              : ua.contains('Linux')
                  ? 'Linux'
                  : 'a computer';
  return '$browser on $os';
}

web.Storage _storage(bool session) =>
    session ? web.window.sessionStorage : web.window.localStorage;

String? webStorageGet(String key, {bool session = false}) {
  try {
    return _storage(session).getItem(key);
  } catch (_) {
    return null;
  }
}

void webStorageSet(String key, String? value, {bool session = false}) {
  try {
    if (value == null) {
      _storage(session).removeItem(key);
    } else {
      _storage(session).setItem(key, value);
    }
  } catch (_) {}
}

/// Hands [bytes] to the browser as a file download.
void webDownload(Uint8List bytes, String filename, String mime) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before revoking.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

/// Asks the browser not to evict this site's storage under pressure. Returns
/// whether storage is (now) persistent.
Future<bool> webPersistStorage() async {
  try {
    final storage = web.window.navigator.storage;
    if ((await storage.persisted().toDart).toDart) return true;
    return (await storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<JSAny?> _await(web.IDBRequest req) {
  final done = Completer<JSAny?>();
  req.onsuccess = ((web.Event _) => done.complete(req.result)).toJS;
  req.onerror = ((web.Event _) => done.completeError(
      StateError('IndexedDB request failed: ${req.error?.message}'))).toJS;
  return done.future;
}

/// A minimal IndexedDB wrapper: string-keyed object stores holding either
/// strings or byte arrays.
class WebIdb {
  WebIdb._(this._db);

  final web.IDBDatabase _db;

  static Future<WebIdb> open(
      String name, int version, List<String> stores) async {
    final req = web.window.indexedDB.open(name, version);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result as web.IDBDatabase;
      for (final s in stores) {
        if (!db.objectStoreNames.contains(s)) db.createObjectStore(s);
      }
    }).toJS;
    final db = await _await(req) as web.IDBDatabase;
    return WebIdb._(db);
  }

  Future<Map<String, String>> readAllStrings(String store) async {
    final tx = _db.transaction(store.toJS, 'readonly');
    final os = tx.objectStore(store);
    final keysReq = os.getAllKeys();
    final valuesReq = os.getAll();
    final keys = (await _await(keysReq) as JSArray<JSAny?>).toDart;
    final values = (await _await(valuesReq) as JSArray<JSAny?>).toDart;
    return {
      for (var i = 0; i < keys.length; i++)
        (keys[i] as JSString).toDart: (values[i] as JSString).toDart,
    };
  }

  Future<List<String>> keys(String store) async {
    final tx = _db.transaction(store.toJS, 'readonly');
    final res =
        await _await(tx.objectStore(store).getAllKeys()) as JSArray<JSAny?>;
    return [for (final k in res.toDart) (k as JSString).toDart];
  }

  Future<JSAny?> _get(String store, String key) {
    final tx = _db.transaction(store.toJS, 'readonly');
    return _await(tx.objectStore(store).get(key.toJS));
  }

  Future<Uint8List?> getBytes(String store, String key) async {
    final v = await _get(store, key);
    if (v == null || v.isUndefinedOrNull) return null;
    return (v as JSUint8Array).toDart;
  }

  Future<String?> getString(String store, String key) async {
    final v = await _get(store, key);
    if (v == null || v.isUndefinedOrNull) return null;
    return (v as JSString).toDart;
  }

  /// Applies [ops] (and first empties the [clear] stores) in one transaction:
  /// either all of it lands or none does.
  Future<void> commit(List<IdbOp> ops, {List<String> clear = const []}) {
    final names = {...clear, for (final o in ops) o.store};
    if (names.isEmpty) return Future.value();
    final tx = _db.transaction(
        [for (final n in names) n.toJS].toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onerror = ((web.Event _) => done.isCompleted
        ? null
        : done.completeError(
            StateError('IndexedDB write failed: ${tx.error?.message}'))).toJS;
    tx.onabort = ((web.Event _) => done.isCompleted
        ? null
        : done.completeError(StateError('IndexedDB write aborted'))).toJS;
    for (final s in clear) {
      tx.objectStore(s).clear();
    }
    for (final o in ops) {
      final os = tx.objectStore(o.store);
      final v = o.value;
      if (v == null) {
        os.delete(o.key.toJS);
      } else if (v is String) {
        os.put(v.toJS, o.key.toJS);
      } else if (v is Uint8List) {
        os.put(v.toJS, o.key.toJS);
      } else {
        throw ArgumentError('Unsupported IndexedDB value: ${v.runtimeType}');
      }
    }
    return done.future;
  }
}

/// A text-frame WebSocket.
class WebSocketConn {
  WebSocketConn._(this._ws) {
    _ws.onopen = ((web.Event _) {
      if (!_ready.isCompleted) _ready.complete();
    }).toJS;
    _ws.onmessage = ((web.MessageEvent e) {
      final d = e.data;
      if (d != null && d.isA<JSString>()) {
        _messages.add((d as JSString).toDart);
      }
    }).toJS;
    _ws.onerror = ((web.Event _) {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('WebSocket failed to open'));
      }
    }).toJS;
    _ws.onclose = ((web.CloseEvent _) {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('WebSocket closed before opening'));
      }
      if (!_closed.isCompleted) _closed.complete();
      _messages.close();
    }).toJS;
  }

  static WebSocketConn connect(String url) => WebSocketConn._(web.WebSocket(url));

  final web.WebSocket _ws;
  final _ready = Completer<void>();
  final _closed = Completer<void>();
  final _messages = StreamController<String>.broadcast();

  Future<void> get ready => _ready.future;
  Stream<String> get messages => _messages.stream;
  Future<void> get closed => _closed.future;

  void send(String text) {
    if (_ws.readyState == web.WebSocket.OPEN) _ws.send(text.toJS);
  }

  void close() {
    try {
      _ws.close();
    } catch (_) {}
  }
}
