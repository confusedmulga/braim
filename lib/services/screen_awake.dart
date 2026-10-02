import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the phone's screen on while Braim Web is on. Its server runs inside
/// the app, and Android pauses an app soon after the screen goes off, so the
/// computer would lose the phone within seconds. This is a window flag, not a
/// background service: it needs no permission and only holds while Braim is
/// the app on screen. Elsewhere (iOS, tests) every call is a no-op.
class ScreenAwake {
  ScreenAwake();

  static const _ch = MethodChannel('braim/screen');

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Keeps the screen on, or lets it time out as usual again. Best-effort:
  /// if it fails, Braim Web still works for as long as the screen is on.
  Future<void> keepOn(bool on) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('keepOn', {'on': on});
    } catch (_) {}
  }
}
