import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/l10n.dart';
import '../../main.dart' show BraimApp;
import '../../platform/fetcher.dart';
import '../../platform/image_store.dart';
import '../../platform/platform_caps.dart';
import '../../platform/web_bridge.dart';
import '../../screens/root_shell.dart';
import '../../services/crypt_auth.dart';
import '../../services/store/remote_library_store.dart';
import '../../services/store/remote_protocol.dart';
import '../../theme/app_theme.dart';
import '../desktop_frame.dart';
import 'remote_link_frame.dart';
import 'remote_pairing.dart';

const _tokenKey = 'braim.remote.token';

/// Remote mode: this page was served by a phone. Pair with it (once; the phone
/// owner confirms on the phone), then run the app on the phone's library.
Future<void> runRemoteApp(String origin) async {
  PlatformCaps.current = PlatformCaps.webRemote;
  // A pairing code rides in the URL fragment (never sent to any server);
  // read it once and drop it from the address bar.
  final hash = webLocationHash();
  String? code;
  if (hash.startsWith('#p=')) {
    code = Uri.decodeComponent(hash.substring(3));
    webReplaceHash('');
  }

  final token = webStorageGet(_tokenKey, session: true) ?? webStorageGet(_tokenKey);
  if (token != null && await _sessionValid(origin, token)) {
    await _start(origin, token);
    return;
  }
  webStorageSet(_tokenKey, null);
  webStorageSet(_tokenKey, null, session: true);

  runApp(RemotePairingApp(
    origin: origin,
    code: code,
    onPaired: (token, remember) {
      webStorageSet(_tokenKey, token, session: true);
      if (remember) webStorageSet(_tokenKey, token);
      _start(origin, token);
    },
  ));
}

Future<bool> _sessionValid(String origin, String token) async {
  try {
    final res = await http.get(Uri.parse('$origin${RemoteApi.session}'),
        headers: {'Authorization': 'Bearer $token'}).timeout(
        const Duration(seconds: 5));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Forgets this computer's session and returns to pairing.
void disconnectFromPhone(RemoteLibraryStore store) {
  webStorageSet(_tokenKey, null);
  webStorageSet(_tokenKey, null, session: true);
  unawaited(store.close());
  runRemoteApp(store.origin);
}

Future<void> _start(String origin, String token) async {
  final store = RemoteLibraryStore(origin: origin, token: token);
  try {
    await store.preload();
  } catch (e) {
    if (store.status.value == PhoneLinkState.revoked) {
      webStorageSet(_tokenKey, null);
      webStorageSet(_tokenKey, null, session: true);
      runRemoteApp(origin);
      return;
    }
    runApp(_UnreachableApp(onRetry: () => _start(origin, token)));
    return;
  }
  ImageStore.instance = RemoteImageStore(origin: origin, token: token);
  Fetcher.instance = PhoneFetcher(origin: origin, token: token);
  cryptPhoneApproval = store.unlockCrypt;
  runApp(BraimApp(
    store: store,
    frame: (context, child) =>
        RemoteLinkFrame(store: store, child: webFrame(context, child)),
    home: (_) => const RootShell(),
  ));
}

class _UnreachableApp extends StatelessWidget {
  const _UnreachableApp({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RemoteShellApp(
      builder: (context) => RemoteMessageCard(
        icon: Icons.wifi_off_rounded,
        title: context.t.webPhoneSection,
        body: context.t.webOfflineReadOnly,
        action: FilledButton(
            onPressed: onRetry, child: Text(context.t.retry)),
      ),
    );
  }
}

/// A minimal themed app for the screens shown before the library loads.
class RemoteShellApp extends StatelessWidget {
  const RemoteShellApp({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    AppPalette.dark = dark;
    return MaterialApp(
      title: 'Braim',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: AppPalette.scheme.surface,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decodes a JSON error body's `error` field ('' when there is none).
String errorOf(http.Response res) {
  try {
    return '${(jsonDecode(res.body) as Map)['error'] ?? ''}';
  } catch (_) {
    return '';
  }
}
