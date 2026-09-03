import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The focus timer's Do Not Disturb modes.
enum DndMode {
  /// Leave the phone alone — no DND.
  off,

  /// Silence notifications and the ringer, but calls still surface (no ring).
  /// Maps to Android's PRIORITY interruption filter.
  focus,

  /// Total silence — even calls are suppressed. Android's NONE filter.
  silence,
}

/// Thin bridge to Android's Do Not Disturb (interruption filter). Everything is
/// best-effort: without the one-time "DND access" grant (or on iOS) it no-ops so
/// the timer still works. A marker file lets us restore DND on the next launch
/// if the app was killed mid-session, so we never leave the phone muted.
class DndService {
  DndService._();
  static final DndService instance = DndService._();

  static const _ch = MethodChannel('braim/dnd');

  // Android interruption-filter constants.
  static const int _all = 1;
  static const int _priority = 2;
  static const int _none = 3;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<bool> hasAccess() async {
    if (!_supported) return false;
    try {
      return (await _ch.invokeMethod<bool>('hasAccess')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Do Not Disturb access" screen so the user can grant it.
  Future<void> openSettings() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  Future<bool> _setFilter(int filter) async {
    if (!_supported) return false;
    try {
      return (await _ch.invokeMethod<bool>('setFilter', {'filter': filter})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Applies [mode] and drops a marker so a killed session's DND is restored on
  /// next launch. [DndMode.off] just restores.
  Future<void> apply(DndMode mode) async {
    if (mode == DndMode.off) {
      await restore();
      return;
    }
    final ok =
        await _setFilter(mode == DndMode.silence ? _none : _priority);
    if (ok) await _writeMarker();
  }

  /// Turns DND back to normal and clears the marker.
  Future<void> restore() async {
    await _setFilter(_all);
    await _clearMarker();
  }

  /// Called at startup: if a previous run left DND on (the app was killed
  /// mid-session), turn it back off so the phone isn't stuck muted.
  Future<void> restoreIfLeftOn() async {
    if (!_supported) return;
    try {
      final marker = await _markerFile();
      if (await marker.exists()) {
        await _setFilter(_all);
        await marker.delete();
      }
    } catch (_) {}
  }

  Future<File> _markerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/focus_dnd.on');
  }

  Future<void> _writeMarker() async {
    try {
      await (await _markerFile()).writeAsString('1', flush: true);
    } catch (_) {}
  }

  Future<void> _clearMarker() async {
    try {
      final m = await _markerFile();
      if (await m.exists()) await m.delete();
    } catch (_) {}
  }
}
