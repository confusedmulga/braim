import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native MediaSession notification for the Pomodoro focus timer.
/// The native side renders the system media UI (with Android 13's squiggly
/// seek-bar) and calls back [onAction] ('play' / 'pause') when the transport
/// button is tapped. iOS / web silently no-op.
class FocusMediaService {
  FocusMediaService._();
  static final FocusMediaService instance = FocusMediaService._();

  static const _ch = MethodChannel('braim/media');
  bool _inited = false;

  /// Fired with 'play' or 'pause' when the media notification's button is used.
  void Function(String action)? onAction;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  void _ensureInit() {
    if (_inited) return;
    _inited = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'mediaAction') {
        onAction?.call(call.arguments as String);
      }
    });
  }

  /// Shows/updates the media notification. [durationMs] and [elapsedMs] drive the
  /// seek-bar; [playing] makes it wiggle (or go straight when paused).
  Future<void> show({
    required String title,
    required String text,
    required int elapsedMs,
    required int durationMs,
    required bool playing,
    required int color,
  }) async {
    if (!_supported) return;
    _ensureInit();
    try {
      await _ch.invokeMethod('show', {
        'title': title,
        'text': text,
        'elapsedMs': elapsedMs,
        'durationMs': durationMs,
        'playing': playing,
        'color': color,
      });
    } catch (_) {}
  }

  Future<void> hide() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('hide');
    } catch (_) {}
  }
}
