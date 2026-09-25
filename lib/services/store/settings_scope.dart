/// Which app settings travel with the library and which stay on the device
/// that set them. When a browser works on the phone's library, toggling dark
/// mode on the laptop must not flip the phone.
library;

/// Kept per device: a browser keeps its own copy (in localStorage) and never
/// sends or takes these.
const kPerDeviceSettings = {
  'darkMode',
  'darkFollowSystem',
  'cardsCompact',
  'sortMode',
  'feedWallpaper',
  'feedBackgroundPath',
  'feedBackgroundLight',
  'feedBackgroundDark',
  'journalPaneOpen',
  'cortexPaneOpen',
  'progressShowAll',
  'readerFontScale',
  'tutorialSeen',
};

/// The phone's own bookkeeping (backups): never written from a browser.
const kPhoneOnlySettings = {
  'lastBackupAt',
  'backupReminderDismissedAt',
  'localAutoBackup',
  'localAutoBackupFreq',
  'lastLocalAutoBackupAt',
};

/// Counters both sides add to: a browser sends what it added, never a total.
const kCounterSettings = {'typingMillis'};

/// Whether a settings key may be sent from a browser to the phone as a value.
bool isSharedSetting(String key) =>
    !kPerDeviceSettings.contains(key) &&
    !kPhoneOnlySettings.contains(key) &&
    !kCounterSettings.contains(key);
