import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A computer allowed to open the library. Only a hash of its session token is
/// kept, so the file alone can't be used to get in.
class PairedDevice {
  PairedDevice({
    required this.tokenHash,
    required this.name,
    required this.remember,
    required this.pairedAt,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? pairedAt;

  final String tokenHash;
  final String name;

  /// Whether the pairing outlives the server session ("remember this computer").
  final bool remember;
  final DateTime pairedAt;
  DateTime lastSeen;

  Map<String, Object?> toJson() => {
        'tokenHash': tokenHash,
        'name': name,
        'remember': remember,
        'pairedAt': pairedAt.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
      };

  static PairedDevice fromJson(Map<String, dynamic> j) => PairedDevice(
        tokenHash: j['tokenHash'] as String,
        name: (j['name'] as String?) ?? 'A computer',
        remember: (j['remember'] as bool?) ?? false,
        pairedAt: DateTime.tryParse(j['pairedAt'] as String? ?? '') ??
            DateTime.now(),
        lastSeen: DateTime.tryParse(j['lastSeen'] as String? ?? ''),
      );
}

String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// The computers paired with this phone. Remembered ones persist in a small
/// file in the app's private storage (never in the library, which browsers
/// see); the rest last until the server stops.
class PairedDevices {
  PairedDevices(this._file);

  /// Null keeps everything in memory (tests).
  final File? _file;
  final List<PairedDevice> _devices = [];
  bool _loaded = false;

  List<PairedDevice> get all => List.unmodifiable(_devices);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final f = _file;
    if (f == null || !await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      _devices.addAll(
          list.map((e) => PairedDevice.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(
          [for (final d in _devices) if (d.remember) d.toJson()]));
    } catch (_) {}
  }

  PairedDevice? byToken(String token) {
    final h = hashToken(token);
    for (final d in _devices) {
      if (d.tokenHash == h) return d;
    }
    return null;
  }

  Future<void> add(PairedDevice d) async {
    _devices.add(d);
    await _save();
  }

  Future<void> revoke(String tokenHash) async {
    _devices.removeWhere((d) => d.tokenHash == tokenHash);
    await _save();
  }

  /// Forgets the computers that weren't remembered (the server stopped).
  Future<void> dropSessionOnly() async {
    _devices.removeWhere((d) => !d.remember);
    await _save();
  }

  Future<void> touch(PairedDevice d) async {
    d.lastSeen = DateTime.now();
    if (d.remember) await _save();
  }
}
