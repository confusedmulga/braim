/// How the app is running: on the phone, or in a browser with its own copy of
/// the library, or in a browser talking to the phone over the LAN.
enum RunMode { device, webLocal, webRemote }

/// How the Crypt can be opened in this mode.
enum CryptUnlock {
  /// The device's own biometric / credential prompt (the phone).
  biometric,

  /// The browser asks the phone, which prompts its owner (remote mode).
  phoneApproval,

  /// Crypt isn't available here (a browser-only library never holds it).
  unavailable,
}

/// What this run of the app can offer. Screens hide or disable rows by these
/// flags instead of checking `kIsWeb`, so the remote/local/device differences
/// live in one table.
class PlatformCaps {
  const PlatformCaps._({
    required this.mode,
    required this.canBackupToDevice,
    required this.canScheduleReminders,
    required this.canUseCamera,
    required this.canShareIntent,
    required this.canDnd,
    required this.canFetchPreviews,
    required this.canImportBackupZip,
    required this.canExportBackupZip,
    required this.cryptUnlock,
  });

  final RunMode mode;

  /// On-device backup zips, the auto-backup schedule and restore-from-file.
  final bool canBackupToDevice;

  /// Local notifications (note reminders, journal nudge, reflex reminders).
  final bool canScheduleReminders;
  final bool canUseCamera;
  final bool canShareIntent;
  final bool canDnd;

  /// Whether link previews / YouTube data can be fetched (the browser can't
  /// read arbitrary sites; remote mode asks the phone to fetch instead).
  final bool canFetchPreviews;

  /// Browser-only library: bring a phone backup in, or take one out.
  final bool canImportBackupZip;
  final bool canExportBackupZip;
  final CryptUnlock cryptUnlock;

  bool get isWeb => mode != RunMode.device;
  bool get isRemote => mode == RunMode.webRemote;
  bool get isWebLocal => mode == RunMode.webLocal;

  static const device = PlatformCaps._(
    mode: RunMode.device,
    canBackupToDevice: true,
    canScheduleReminders: true,
    canUseCamera: true,
    canShareIntent: true,
    canDnd: true,
    canFetchPreviews: true,
    canImportBackupZip: false,
    canExportBackupZip: false,
    cryptUnlock: CryptUnlock.biometric,
  );

  static const webLocal = PlatformCaps._(
    mode: RunMode.webLocal,
    canBackupToDevice: false,
    canScheduleReminders: false,
    canUseCamera: false,
    canShareIntent: false,
    canDnd: false,
    canFetchPreviews: false,
    canImportBackupZip: true,
    canExportBackupZip: true,
    cryptUnlock: CryptUnlock.unavailable,
  );

  static const webRemote = PlatformCaps._(
    mode: RunMode.webRemote,
    canBackupToDevice: false,
    canScheduleReminders: false,
    canUseCamera: false,
    canShareIntent: false,
    canDnd: false,
    canFetchPreviews: true,
    canImportBackupZip: false,
    canExportBackupZip: false,
    cryptUnlock: CryptUnlock.phoneApproval,
  );

  /// Set once at startup (the phone keeps the default).
  static PlatformCaps current = device;
}
