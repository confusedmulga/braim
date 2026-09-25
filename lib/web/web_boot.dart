import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show BraimApp;
import '../platform/image_store.dart';
import '../platform/platform_caps.dart';
import '../services/store/web_local_library_store.dart';
import 'desktop_frame.dart';
import 'remote/remote_boot.dart';
import 'web_home.dart';

/// Starts the app in a browser. A phone serving this page answers
/// `/api/hello` on the page's own origin (remote mode: the phone's library,
/// live); anywhere else the browser keeps its own library (local mode).
/// `?mode=local` forces local mode.
Future<void> runWebApp() async {
  // The app's own long-press / right-click menus replace the browser's.
  unawaited(BrowserContextMenu.disableContextMenu());
  final forceLocal = Uri.base.queryParameters['mode'] == 'local';
  final origin = Uri.base.origin;
  if (!forceLocal && await _servedByPhone(origin)) {
    await runRemoteApp(origin);
    return;
  }
  runLocalApp();
}

Future<bool> _servedByPhone(String origin) async {
  try {
    final res = await http
        .get(Uri.parse('$origin/api/hello'))
        .timeout(const Duration(milliseconds: 1500));
    if (res.statusCode != 200) return false;
    final body = jsonDecode(res.body);
    return body is Map && body['app'] == 'braim';
  } catch (_) {
    return false;
  }
}

/// Local mode: this browser's own library in IndexedDB.
void runLocalApp() {
  PlatformCaps.current = PlatformCaps.webLocal;
  ImageStore.instance = WebLocalImageStore();
  runApp(BraimApp(
    store: WebLocalLibraryStore(),
    frame: webFrame,
    home: (_) => const WebLocalHome(),
  ));
}
