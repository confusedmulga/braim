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

  /// Lets tests run the Android path off a device.
  @visibleForTesting
  static bool? debugSupportedOverride;

  bool get _supported =>
      debugSupportedOverride ?? (!kIsWeb && Platform.isAndroid);

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

  Future<int?> _getFilter() async {
    try {
      final f = await _ch.invokeMethod<int>('getFilter');
      return f == null || f < 1 ? null : f;
    } catch (_) {
      return null;
    }
  }

  /// Applies [mode]. The first time in a session, the phone's own filter is
  /// written to a marker file, so a killed session's DND is undone on next
  /// launch and ending one puts back exactly what was on before. [DndMode.off]
  /// leaves the phone alone, undoing only what an earlier mode set.
  Future<void> apply(DndMode mode) async {
    if (mode == DndMode.off) {
      await restore();
      return;
    }
    final before = await savedFilter();
    final previous = before ?? await _getFilter() ?? _all;
    final ok =
        await _setFilter(mode == DndMode.silence ? _none : _priority);
    if (ok && before == null) await _writeMarker(previous);
  }

  /// Puts back the filter that was on before the timer changed it, if it did.
  Future<void> restore() async {
    final previous = await savedFilter();
    if (previous == null) return; // the timer didn't touch it
    await _setFilter(previous);
    await _clearMarker();
  }

  /// Called at startup: if a previous run left DND on (the app was killed
  /// mid-session), turn it back to what it was so the phone isn't stuck muted.
  Future<void> restoreIfLeftOn() async {
    if (!_supported) return;
    await restore();
  }

  /// The filter to put back when the session ends, or null when the timer
  /// hasn't changed the phone's DND.
  Future<int?> savedFilter() async {
    if (!_supported) return null;
    try {
      final marker = await _markerFile();
      if (!await marker.exists()) return null;
      final v = int.tryParse((await marker.readAsString()).trim());
      // An older marker held just "1": it means "turn DND off" (all).
      return v == null || v < 1 || v > 4 ? _all : v;
    } catch (_) {
      return null;
    }
  }

  /// Arms an Android alarm for [at], the end of the session: it puts back the
  /// saved filter and clears the timer's notification even if Braim is frozen
  /// or killed in the background by then, so the phone is never left muted.
  Future<void> scheduleEnd(DateTime at) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('scheduleEnd', {
        'atMs': at.millisecondsSinceEpoch,
        'filter': await savedFilter() ?? -1,
        'marker': (await _markerFile()).path,
      });
    } catch (_) {}
  }

  /// Disarms [scheduleEnd] (paused, reset or ended in the app).
  Future<void> cancelScheduledEnd() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('cancelEnd');
    } catch (_) {}
  }

  Future<File> _markerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/focus_dnd.on');
  }

  Future<void> _writeMarker(int previous) async {
    try {
      await (await _markerFile()).writeAsString('$previous', flush: true);
    } catch (_) {}
  }

  Future<void> _clearMarker() async {
    try {
      final m = await _markerFile();
      if (await m.exists()) await m.delete();
    } catch (_) {}
  }
}
