import 'dart:async';
import 'dart:typed_data';

/// One write in an IndexedDB transaction: [value] is a `String` or a
/// `Uint8List`; null deletes [key].
typedef IdbOp = ({String store, String key, Object? value});

Never _unsupported() =>
    throw UnsupportedError('Browser APIs are only available on the web.');

String webPageOrigin() => _unsupported();
String webLocationHash() => '';
String webLocationSearch() => '';
void webReplaceHash(String hash) {}
String webDeviceLabel() => 'This computer';

String? webStorageGet(String key, {bool session = false}) => null;
void webStorageSet(String key, String? value, {bool session = false}) {}

void webDownload(Uint8List bytes, String filename, String mime) =>
    _unsupported();

Future<bool> webPersistStorage() async => false;

class WebIdb {
  WebIdb._();

  static Future<WebIdb> open(String name, int version, List<String> stores) =>
      _unsupported();

  Future<Map<String, String>> readAllStrings(String store) => _unsupported();
  Future<List<String>> keys(String store) => _unsupported();
  Future<Uint8List?> getBytes(String store, String key) => _unsupported();
  Future<String?> getString(String store, String key) => _unsupported();
  Future<void> commit(List<IdbOp> ops, {List<String> clear = const []}) =>
      _unsupported();
}

class WebSocketConn {
  WebSocketConn._();

  static WebSocketConn connect(String url) => _unsupported();

  Future<void> get ready => _unsupported();
  Stream<String> get messages => _unsupported();
  Future<void> get closed => _unsupported();
  void send(String text) => _unsupported();
  void close() {}
}
