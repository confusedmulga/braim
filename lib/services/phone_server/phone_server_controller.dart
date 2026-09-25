import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/l10n.dart';
import '../../main.dart' show navigatorKey;
import '../../state/app_state.dart';
import '../crypt_auth.dart';
import '../storage_service.dart';
import 'paired_devices.dart';
import 'phone_server.dart';
import 'web_bundle.dart';

/// Owns the phone server for the app: starts it from Settings → "Open on
/// computer", asks the owner (on the phone) before a computer may pair or open
/// the Crypt, and keeps the screen on while it runs.
class PhoneServerController {
  PhoneServerController._();
  static final instance = PhoneServerController._();

  PhoneServer? _server;
  PairedDevices? _devices;

  PhoneServer? get server => _server;

  Future<PhoneServer> start(AppState state) async {
    final existing = _server;
    if (existing != null && existing.running) return existing;
    final docs = await getApplicationDocumentsDirectory();
    final devices =
        _devices ??= PairedDevices(File('${docs.path}/paired_computers.json'));
    final server = PhoneServer(
      state: state,
      bundle: ApkWebBundle(),
      devices: devices,
      imagesDir: (await StorageService.instance.imagesDir).path,
      approvePairing: _confirmPairing,
      approveCrypt: (_) =>
          authenticateForCrypt(reason: _t?.unlockCrypt ?? 'Unlock Crypt'),
    );
    server.addListener(() {
      if (!server.running) ApkWebBundle.keepAwake(false);
    });
    _server = server;
    await server.start();
    await ApkWebBundle.keepAwake(true);
    return server;
  }

  Future<void> stop() async {
    await _server?.stop();
    await ApkWebBundle.keepAwake(false);
  }

  static AppLocalizations? get _t {
    final ctx = navigatorKey.currentContext;
    return ctx == null ? null : AppLocalizations.of(ctx);
  }

  static Future<bool> _confirmPairing(String device) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.computer_rounded),
        title: Text(c.t.pairConfirmTitle),
        content: Text(c.t.pairConfirmBody(device)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.t.pairDeny)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(c.t.pairAllow)),
        ],
      ),
    );
    return ok ?? false;
  }
}
