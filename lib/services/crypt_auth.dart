import 'package:local_auth/local_auth.dart';

/// Prompts biometric / device-credential auth before opening the Crypt.
/// Returns true if unlocked. If the device has no secure lock at all, we let
/// the user in (there is nothing to authenticate against) rather than trapping
/// their notes.
Future<bool> authenticateForCrypt() async {
  final auth = LocalAuthentication();
  try {
    final supported = await auth.isDeviceSupported();
    if (!supported) return true;
    return await auth.authenticate(
      localizedReason: 'Unlock Crypt',
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}
