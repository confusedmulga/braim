import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to Android's BraimWebService: a foreground service with a "Braim
/// Web is on" notification that keeps the app's process (and so the web
/// server in it) alive while the phone screen is off. The service holds no
/// data and runs no server. Elsewhere (iOS, tests) every call is a no-op.
class BraimWebService {
  BraimWebService();

  static const _ch = MethodChannel('braim/web');

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Called when the notification's Turn off action is tapped.
  set onStopRequested(void Function()? callback) {
    if (!_supported) return;
    _ch.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'stopRequested') callback();
            },
    );
  }

  /// Starts the service, showing [url] in its notification. The strings come
  /// from the app's localizations. Throws a [PlatformException] when Android
  /// refuses the foreground service.
  Future<void> start({
    required String url,
    required String title,
    required String turnOff,
    required String channelName,
  }) async {
    if (!_supported) return;
    await _ch.invokeMethod<bool>('start', {
      'url': url,
      'title': title,
      'turnOff': turnOff,
      'channelName': channelName,
    });
  }

  /// Shows a new address in the running service's notification.
  Future<void> update({
    required String url,
    required String title,
    required String turnOff,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('update', {
        'url': url,
        'title': title,
        'turnOff': turnOff,
      });
    } catch (_) {
      // Only the notification text is stale; the server is unaffected.
    }
  }

  /// Stops the service and removes its notification.
  Future<void> stop() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod<bool>('stop');
    } catch (_) {
      // Nothing running to stop.
    }
  }
}
