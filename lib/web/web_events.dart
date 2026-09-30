// Braim Web live updates: one event stream per open tab, fed by AppState's
// change notifications. See docs/braim-web-plan.md, section 8.4.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Sends `event: changed` to every open event stream when the library changes,
/// at most once per [throttle], plus a comment line every [keepAlive] so idle
/// connections stay open. It listens to [source] only while a stream is open.
class WebEventHub {
  WebEventHub({
    required this.source,
    required this.revision,
    this.throttle = const Duration(milliseconds: 500),
    this.keepAlive = const Duration(seconds: 25),
  });

  final Listenable source;

  /// The library revision sent with each event (AppState.revision).
  final int Function() revision;

  final Duration throttle;
  final Duration keepAlive;

  final List<_Client> _clients = [];
  Timer? _cooldown;
  Timer? _keepAliveTimer;
  bool _pending = false;
  bool _listening = false;
  int? _lastSentRev;

  /// Whether any browser has an event stream open.
  bool get anyConnected => _clients.isNotEmpty;

  /// Opens a stream for [sessionId]'s tab. It ends when the browser goes away,
  /// the session is logged out, or the server stops.
  Stream<List<int>> connect(String sessionId) {
    late final _Client client;
    final controller = StreamController<List<int>>(
      onCancel: () => _drop(client),
    );
    client = _Client(sessionId, controller);
    _clients.add(client);
    // Sends the headers now, so the browser's EventSource opens at once.
    controller.add(utf8.encode(': hello\n\n'));
    _startListening();
    return controller.stream;
  }

  /// Ends every stream belonging to [sessionId] (a logout).
  void closeSession(String sessionId) {
    for (final c in _clients.where((c) => c.sessionId == sessionId).toList()) {
      _drop(c);
    }
  }

  /// Ends every stream (the server is stopping).
  void closeAll() {
    for (final c in List.of(_clients)) {
      _drop(c);
    }
  }

  void _drop(_Client client) {
    if (!_clients.remove(client)) return;
    unawaited(client.controller.close());
    if (_clients.isEmpty) _stopListening();
  }

  void _startListening() {
    if (_listening) return;
    _listening = true;
    _lastSentRev = revision();
    source.addListener(_onChange);
    _keepAliveTimer = Timer.periodic(keepAlive, (_) {
      _broadcast(': keep-alive\n\n');
    });
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    source.removeListener(_onChange);
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _cooldown?.cancel();
    _cooldown = null;
    _pending = false;
  }

  void _onChange() {
    if (_cooldown != null) {
      _pending = true;
      return;
    }
    _send();
  }

  /// Sends the current revision if it moved, then holds further sends back
  /// for [throttle]; a change during the hold is sent when it ends.
  void _send() {
    _pending = false;
    final rev = revision();
    if (rev == _lastSentRev) return; // a view-only notification
    _lastSentRev = rev;
    _broadcast('event: changed\ndata: ${jsonEncode({'rev': rev})}\n\n');
    _cooldown = Timer(throttle, () {
      _cooldown = null;
      if (_pending) _send();
    });
  }

  void _broadcast(String message) {
    final bytes = utf8.encode(message);
    for (final c in _clients) {
      c.controller.add(bytes);
    }
  }
}

class _Client {
  _Client(this.sessionId, this.controller);
  final String sessionId;
  final StreamController<List<int>> controller;
}
