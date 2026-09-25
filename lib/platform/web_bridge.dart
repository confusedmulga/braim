/// The only door to browser APIs (IndexedDB, storage, downloads, sockets).
/// Everything here is implemented in `web_bridge_web.dart` on the web and
/// throws or no-ops in `web_bridge_stub.dart` everywhere else, so no file
/// outside `lib/platform/` ever imports `package:web` or `dart:js_interop`.
library;

export 'web_bridge_stub.dart'
    if (dart.library.js_interop) 'web_bridge_web.dart';
