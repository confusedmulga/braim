import 'package:local_auth/local_auth.dart';

import '../platform/platform_caps.dart';

/// In a browser served by the phone, the phone does the unlocking: this asks
/// it (its owner confirms with the phone's own biometrics) and loads the Crypt
/// once allowed. Set by the remote-mode boot.
Future<bool> Function()? cryptPhoneApproval;

/// Prompts biometric / device-credential auth before opening the Crypt.
/// Returns true if unlocked. If the device has no secure lock at all, we let
/// the user in (there is nothing to authenticate against) rather than trapping
/// their notes.
Future<bool> authenticateForCrypt({required String reason}) async {
  switch (PlatformCaps.current.cryptUnlock) {
    case CryptUnlock.unavailable:
      return false;
    case CryptUnlock.phoneApproval:
      return await cryptPhoneApproval?.call() ?? false;
    case CryptUnlock.biometric:
      break;
  }
  final auth = LocalAuthentication();
  try {
    final supported = await auth.isDeviceSupported();
    if (!supported) return true;
    return await auth.authenticate(
      localizedReason: reason,
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}
