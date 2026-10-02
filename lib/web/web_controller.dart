// Braim Web's phone-side switch: starts and stops the server, keeps the screen
// on while it runs, turns itself off when unused, and tells Settings what to
// show. See docs/braim-web-plan.md, section 6.1.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/screen_awake.dart';
import '../state/app_state.dart';
import 'web_assets.dart';
import 'web_auth.dart';
import 'web_server.dart';

/// Why the last start didn't happen.
enum WebStartError {
  /// No Wi-Fi and no hotspot: no private address to serve on.
  noNetwork,

  /// No free port.
  failed,
}

/// Why Braim Web last stopped.
enum WebStopReason { user, autoOff }

/// A linked browser as Settings shows it.
@immutable
class WebSessionInfo {
  const WebSessionInfo({
    required this.id,
    required this.label,
    required this.created,
    required this.lastSeen,
  });

  final String id;
  final String label;
  final DateTime created;
  final DateTime lastSeen;
}

class BraimWebController extends ChangeNotifier {
  BraimWebController(
    this.state, {
    Future<WebSessionStore> Function()? openSessions,
    WebAssets? assets,
    WebPairing? pairing,
    ScreenAwake? screen,
    Future<List<String>> Function()? listAddresses,
    DateTime Function()? now,
    this.autoOffAfter = const Duration(minutes: 30),
    this.tick = const Duration(seconds: 30),
    InternetAddress? bindAddress,
    List<int>? ports,
  }) : _openSessions = openSessions ?? WebSessionStore.inDocuments,
       _assets = assets,
       _pairing = pairing,
       _screen = screen ?? ScreenAwake(),
       _listAddresses = listAddresses ?? BraimWebServer.privateAddresses,
       _now = now ?? DateTime.now,
       _bindAddress = bindAddress,
       _ports = ports;

  final AppState state;

  /// Braim Web turns itself off after this long with no request from any
  /// linked browser.
  final Duration autoOffAfter;

  /// How often the phone's addresses are re-read and auto-off is checked.
  final Duration tick;

  final Future<WebSessionStore> Function() _openSessions;
  final WebAssets? _assets;
  final WebPairing? _pairing;
  final ScreenAwake _screen;
  final Future<List<String>> Function() _listAddresses;
  final DateTime Function() _now;
  final InternetAddress? _bindAddress;
  final List<int>? _ports;

  BraimWebServer? _server;
  Timer? _ticker;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _ips = const [];
  bool _running = false;
  bool _busy = false;
  bool _disposed = false;

  WebStartError? _startError;
  WebStopReason? _stopReason;

  bool get running => _running;

  /// A start or stop is in progress.
  bool get busy => _busy;

  int? get port => _running ? _server?.port : null;

  /// Full URLs to open, such as `http://192.168.1.23:8420`. The scheme is
  /// always written out: some browsers try HTTPS first without it.
  List<String> get addresses {
    final p = port;
    return p == null ? const [] : _urls(p);
  }

  List<String> _urls(int port) => [for (final ip in _ips) 'http://$ip:$port'];

  /// The code to type into the browser, or null when off.
  String? get pairingCode => _running ? _server?.pairing.code : null;

  Duration get codeTimeLeft =>
      _running ? _server!.pairing.timeLeft : Duration.zero;

  /// Linked browsers, most recently used first.
  List<WebSessionInfo> get sessions {
    final server = _server;
    if (!_running || server == null) return const [];
    return [
      for (final s in server.sessions.sessions)
        WebSessionInfo(
          id: s.id,
          label: s.label,
          created: s.created,
          lastSeen: s.lastSeen,
        ),
    ];
  }

  /// Whether a browser has a page open (an event stream is connected).
  bool get anyBrowserConnected =>
      _running && (_server?.events.anyConnected ?? false);

  /// Why the last [start] didn't happen; cleared by the next attempt.
  WebStartError? get startError => _startError;

  /// Why Braim Web last stopped, until it starts again.
  WebStopReason? get stopReason => _stopReason;

  /// The server, for tests.
  @visibleForTesting
  BraimWebServer? get debugServer => _server;

  /// Starts the server, keeps the screen on, and shows a fresh code. If the
  /// server can't start, nothing is left running and [startError] says why.
  Future<void> start() async {
    if (_running || _busy) return;
    _busy = true;
    _startError = null;
    _stopReason = null;
    _notify();
    try {
      final ips = await _listAddresses();
      if (ips.isEmpty) {
        _startError = WebStartError.noNetwork;
        return;
      }
      final server = _server ??= BraimWebServer(
        state: state,
        sessions: await _openSessions(),
        pairing: _pairing,
        assets: _assets,
      );
      server
        ..addresses = ips
        ..onActivity = _onActivity;
      try {
        await server.start(address: _bindAddress, ports: _ports);
      } catch (_) {
        _startError = WebStartError.failed;
        return;
      }
      _ips = ips;
      await _screen.keepOn(true);
      server.pairing.rotate();
      _running = true;
      _lastActivity = _now();
      _ticker = Timer.periodic(tick, (_) => unawaited(_onTick()));
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Stops the server (closing every page's event stream) and lets the screen
  /// time out again.
  Future<void> stop({WebStopReason reason = WebStopReason.user}) async {
    if (!_running) return;
    _running = false;
    _stopReason = reason;
    _ticker?.cancel();
    _ticker = null;
    _ips = const [];
    _notify();
    await _server?.stop();
    await _screen.keepOn(false);
  }

  /// Logs one linked browser out; its open pages go back to pairing.
  Future<void> logOut(String sessionId) async {
    final saved = _server?.logOut(sessionId);
    _notify(); // the browser is already gone; the file catches up
    await saved;
  }

  /// Logs every linked browser out.
  Future<void> logOutAll() async {
    final saved = _server?.logOutAll();
    _notify();
    await saved;
  }

  void _onActivity() => _lastActivity = _now();

  /// Runs every [tick] while on: turns off after [autoOffAfter] unused, and
  /// follows the phone's addresses as Wi-Fi and the hotspot come and go.
  @visibleForTesting
  Future<void> debugTick() => _onTick();

  Future<void> _onTick() async {
    if (!_running) return;
    if (_now().difference(_lastActivity) >= autoOffAfter) {
      await stop(reason: WebStopReason.autoOff);
      return;
    }
    final ips = await _listAddresses();
    if (!_running || listEquals(ips, _ips)) return;
    _ips = ips;
    _server?.addresses = ips;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
