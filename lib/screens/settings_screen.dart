import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/drive_backup_service.dart';
import '../services/image_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';

/// Human-readable "last backed up" line for the backup row.
String _lastBackupText(BuildContext context, DateTime? last) {
  if (last == null) return context.t.lastBackupNever;
  return context.t.lastBackupAgo(DateTime.now().difference(last).inDays);
}

/// "2026-09-02 14:03 · 4.2 MB" for a Drive backup row.
String _driveFileSubtitle(DriveBackupFile f) {
  final parts = <String>[];
  final m = f.modifiedTime;
  if (m != null) {
    String two(int n) => n.toString().padLeft(2, '0');
    parts.add('${m.year}-${two(m.month)}-${two(m.day)} '
        '${two(m.hour)}:${two(m.minute)}');
  }
  final size = f.sizeBytes;
  if (size != null) {
    final mb = size / (1024 * 1024);
    parts.add(mb >= 1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(0)} KB');
  }
  return parts.join(' · ');
}

/// Settings opens as a transparent overlay so the screen the user came from
/// stays visible (and blurred) behind it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const SettingsScreen(),
      // Slides in from the right edge; closing slides it back out to the
      // right, landing on the feed.
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          )),
          child: child,
        );
      },
    );
  }

  Future<void> _backup(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final nav = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double?>(null);
    var dialogOpen = true;
    // Progress while the zip streams to disk.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.t.preparingBackup),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: v, minHeight: 6),
          ),
        ),
      ),
    ).then((_) => dialogOpen = false);
    try {
      // Pending coalesced edits must reach disk before we zip it.
      if (context.mounted) await context.read<AppState>().flushNow();
      final file = await BackupService.instance.exportToTempFile(
        onProgress: (done, total) =>
            progress.value = total == 0 ? null : done / total,
      );
      if (dialogOpen) nav.pop();
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Braim backup');
      await appState.markBackedUp();
    } catch (e) {
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.backupFailed(e.toString()))));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null || !context.mounted) return;
      final ok = await _confirmRestore(context);
      if (ok != true) return;
      // Nothing pending may overwrite the restored file afterwards.
      await appState.flushNow();
      await BackupService.instance.restoreFromFile(path);
      await appState.init();
      nav.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(t.backupRestored)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.restoreFailed(e.toString()))));
    }
  }

  // ---- Google Drive backup ------------------------------------------------

  /// Explains that a Web client ID must be compiled in before Drive backup can
  /// be used (shown when [AppState.driveConfigured] is false).
  Future<void> _showDriveSetup(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.driveSetupTitle),
        content: Text(context.t.driveSetupBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t.done)),
        ],
      ),
    );
  }

  Future<void> _connectDrive(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    try {
      final ok = await appState.connectDrive();
      if (!ok) return; // user cancelled the picker / consent
      messenger.showSnackBar(SnackBar(content: Text(t.driveConnected)));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(t.driveConnectFailed(e.toString()))));
    }
  }

  Future<void> _disconnectDrive(BuildContext context) =>
      context.read<AppState>().disconnectDrive();

  Future<void> _driveBackupNow(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final nav = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.t.driveBackingUp),
        content: const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          child: LinearProgressIndicator(minHeight: 6),
        ),
      ),
    ).then((_) => dialogOpen = false);
    try {
      await appState.backupToDrive();
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.driveBackedUp)));
    } catch (e) {
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(t.driveBackupFailed(e.toString()))));
    }
  }

  Future<void> _restoreFromDrive(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final nav = Navigator.of(context);
    List<DriveBackupFile> files;
    try {
      files = await appState.listDriveBackups();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(t.driveBackupFailed(e.toString()))));
      return;
    }
    if (!context.mounted) return;
    if (files.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(t.driveNoBackups)));
      return;
    }
    final picked = await showModalBottomSheet<DriveBackupFile>(
      context: context,
      backgroundColor: AppPalette.sheet,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.drivePickTitle,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppPalette.inkPrimary)),
            ),
            for (final f in files)
              ListTile(
                leading: Icon(Icons.cloud_download_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(f.name,
                    style: TextStyle(color: AppPalette.inkPrimary)),
                subtitle: Text(_driveFileSubtitle(f),
                    style: const TextStyle(color: Color(0xFF5E5F69))),
                onTap: () => Navigator.pop(ctx, f),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final ok = await _confirmRestore(context);
    if (ok != true) return;
    try {
      await appState.restoreFromDrive(picked.id);
      nav.pop(); // leave settings, back to the (reloaded) feed
      messenger.showSnackBar(SnackBar(content: Text(t.backupRestored)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(t.restoreFailed(e.toString()))));
    }
  }

  /// Writes the backup zip somewhere the user picks — the Android save sheet
  /// lists Drive, Files, an SD card and more, so this covers both cloud and
  /// local storage without leaving the app.
  Future<void> _saveToDevice(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final nav = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<double?>(null);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.t.preparingBackup),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: v, minHeight: 6),
          ),
        ),
      ),
    ).then((_) => dialogOpen = false);
    try {
      if (context.mounted) await context.read<AppState>().flushNow();
      final file = await BackupService.instance.exportToTempFile(
        onProgress: (done, total) =>
            progress.value = total == 0 ? null : done / total,
      );
      final bytes = await file.readAsBytes();
      if (dialogOpen) nav.pop();
      final saved = await FilePicker.saveFile(
        dialogTitle: t.saveToDevice,
        fileName: file.path.split(RegExp(r'[\\/]')).last,
        bytes: bytes,
      );
      if (saved == null) return; // user backed out of the save sheet
      await appState.markBackedUp();
      messenger.showSnackBar(SnackBar(content: Text(t.backupSavedToDevice)));
    } catch (e) {
      if (dialogOpen) nav.pop();
      messenger
          .showSnackBar(SnackBar(content: Text(t.backupFailed(e.toString()))));
    }
  }

  /// Fills the library with the bundled demo content so every feature has
  /// something to show. Purely additive — existing notes are untouched.
  Future<void> _loadSample(BuildContext context) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.sampleDataTitle),
        content: Text(context.t.sampleDataBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.load)),
        ],
      ),
    );
    if (ok != true) return;
    await appState.loadSampleData();
    messenger.showSnackBar(SnackBar(content: Text(t.sampleDataLoaded)));
  }

  /// Turns the nightly journal nudge on/off, asking for the notification
  /// permission the first time it's switched on.
  Future<void> _setJournalReminder(BuildContext context, bool on) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    // Flip the switch first so it reflects the change immediately, then ask
    // for the permission (its dialog would otherwise stall the toggle).
    await appState.setJournalReminder(on: on);
    if (on) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(t.notifPermNeeded)));
      }
    }
  }

  Future<void> _pickJournalTime(BuildContext context) async {
    final appState = context.read<AppState>();
    final mins = appState.journalReminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: mins ~/ 60, minute: mins % 60),
    );
    if (picked == null) return;
    await appState.setJournalReminder(
        minutes: picked.hour * 60 + picked.minute);
  }

  Future<bool?> _confirmRestore(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.restoreBackupTitle),
        content: Text(context.t.restoreBackupBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.restore)),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.clearAllDataTitle),
        content: Text(context.t.clearAllDataBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.scheme.error,
              foregroundColor: AppPalette.scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.delete),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      // A near-opaque backdrop instead of a live blur: animating a full-screen
      // BackdropFilter made the overlay stutter as it opened.
      body: Container(
          color: AppPalette.scrimFill,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
                  child: Row(
                    children: [
                      FrostedBackButton(
                          onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 14),
                      Text(context.t.settings,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.inkPrimary)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _SectionLabel(context.t.appearance),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.brightness_6_outlined,
                                    color: AppPalette.inkSecondary),
                                const SizedBox(width: 14),
                                Text(context.t.themeLabel,
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        color: AppPalette.inkPrimary)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                selected: {
                                  state.darkFollowSystem
                                      ? 'system'
                                      : (state.darkMode ? 'dark' : 'light')
                                },
                                segments: [
                                  ButtonSegment(
                                    value: 'system',
                                    label:
                                        Text(context.t.appearanceSystem),
                                    icon: const Icon(
                                        Icons.brightness_auto_outlined),
                                  ),
                                  ButtonSegment(
                                    value: 'light',
                                    label: Text(context.t.appearanceLight),
                                    icon: const Icon(
                                        Icons.light_mode_outlined),
                                  ),
                                  ButtonSegment(
                                    value: 'dark',
                                    label: Text(context.t.appearanceDark),
                                    icon:
                                        const Icon(Icons.dark_mode_outlined),
                                  ),
                                ],
                                onSelectionChanged: (sel) {
                                  final v = sel.first;
                                  context.read<AppState>().setAppearance(
                                        followSystem: v == 'system',
                                        dark: v == 'dark',
                                      );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.fontsSection),
                      GlassPanel(
                        borderRadius: 20,
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.text_fields_rounded,
                                    color: AppPalette.inkSecondary),
                                const SizedBox(width: 14),
                                Text(context.t.bodyFontLabel,
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        color: AppPalette.inkPrimary)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: AppPalette.bubbleGlass,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AppPalette.cardOutline),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: state.noteBodyFont,
                                  dropdownColor: AppPalette.sheet,
                                  borderRadius: BorderRadius.circular(14),
                                  items: [
                                    for (final f in kBodyFontOptions)
                                      DropdownMenuItem(
                                        value: f.family,
                                        child: Text(f.label,
                                            style: TextStyle(
                                                fontFamily: f.family,
                                                fontSize: 16,
                                                color: AppPalette.inkPrimary)),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      context
                                          .read<AppState>()
                                          .setNoteBodyFont(v);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Live preview in the selected font.
                            Text(context.t.bodyFontPreview,
                                style: TextStyle(
                                    fontFamily: state.noteBodyFont,
                                    fontSize: 16,
                                    height: 1.35,
                                    color: AppPalette.inkSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.feedBackgroundSection),
                      GlassPanel(
                        borderRadius: 20,
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                        child: Row(
                          children: [
                            // A small preview of the active theme's background.
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: _feedBgPreview(state),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(context.t.feedBackgroundLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      color: AppPalette.inkPrimary)),
                            ),
                            // Set the light-mode image, the dark-mode image, then
                            // reset (shown only when a custom one is set).
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: context.t.feedBackgroundLightMode,
                              icon: const Icon(Icons.light_mode_outlined),
                              color: state.feedBackgroundLight.isNotEmpty
                                  ? AppPalette.scheme.primary
                                  : AppPalette.inkSecondary,
                              onPressed: () async {
                                final path = await ImageService.pickSingle();
                                if (path != null && context.mounted) {
                                  context
                                      .read<AppState>()
                                      .setFeedBackground(dark: false, path: path);
                                }
                              },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: context.t.feedBackgroundDarkMode,
                              icon: const Icon(Icons.dark_mode_outlined),
                              color: state.feedBackgroundDark.isNotEmpty
                                  ? AppPalette.scheme.primary
                                  : AppPalette.inkSecondary,
                              onPressed: () async {
                                final path = await ImageService.pickSingle();
                                if (path != null && context.mounted) {
                                  context
                                      .read<AppState>()
                                      .setFeedBackground(dark: true, path: path);
                                }
                              },
                            ),
                            if (state.feedBackgroundLight.isNotEmpty ||
                                state.feedBackgroundDark.isNotEmpty)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: context.t.feedBackgroundReset,
                                icon: const Icon(Icons.restart_alt_rounded),
                                color: AppPalette.inkSecondary,
                                onPressed: () => context
                                    .read<AppState>()
                                    .clearFeedBackgrounds(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.journalSection),
                      GlassPanel(
                        borderRadius: 20,
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          secondary: Icon(Icons.auto_stories_outlined,
                              color: AppPalette.inkPrimary),
                          title: Text(context.t.journalReminderTitle,
                              style: TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text(context.t.journalReminderSubtitle,
                              style: TextStyle(color: Color(0xFF5E5F69))),
                          value: state.journalReminderOn,
                          onChanged: (v) => _setJournalReminder(context, v),
                        ),
                      ),
                      if (state.journalReminderOn) ...[
                        const SizedBox(height: 12),
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _pickJournalTime(context),
                          child: ListTile(
                            leading: Icon(Icons.schedule_rounded,
                                color: AppPalette.inkPrimary),
                            title: Text(context.t.journalReminderTime,
                                style:
                                    TextStyle(color: AppPalette.inkPrimary)),
                            trailing: Text(
                              TimeOfDay(
                                      hour: state.journalReminderMinutes ~/ 60,
                                      minute:
                                          state.journalReminderMinutes % 60)
                                  .format(context),
                              style: TextStyle(
                                  color: AppPalette.inkPrimary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.backupSection),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        onTap: () => _backup(context),
                        child: ListTile(
                          leading: Icon(Icons.backup_outlined,
                              color: AppPalette.inkPrimary),
                          title: Text(context.t.backupTitle,
                              style:
                                  TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text(
                              _lastBackupText(context, state.lastBackupAt),
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        onTap: () => _restore(context),
                        child: ListTile(
                          leading: Icon(Icons.settings_backup_restore_rounded,
                              color: AppPalette.inkPrimary),
                          title: Text(context.t.restoreFromBackup,
                              style:
                                  TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text(context.t.restoreSubtitle,
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        onTap: () => _saveToDevice(context),
                        child: ListTile(
                          leading: Icon(Icons.save_alt_rounded,
                              color: AppPalette.inkPrimary),
                          title: Text(context.t.saveToDevice,
                              style:
                                  TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text(context.t.saveToDeviceSubtitle,
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.driveSection),
                      if (!state.driveConfigured)
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _showDriveSetup(context),
                          child: ListTile(
                            leading: Icon(Icons.cloud_off_outlined,
                                color: AppPalette.inkSecondary),
                            title: Text(context.t.driveSetupTitle,
                                style: TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: Text(context.t.driveSetupBody,
                                style:
                                    const TextStyle(color: Color(0xFF5E5F69))),
                          ),
                        )
                      else if (!state.driveConnected)
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _connectDrive(context),
                          child: ListTile(
                            leading: Icon(Icons.cloud_outlined,
                                color: AppPalette.inkPrimary),
                            title: Text(context.t.driveConnect,
                                style: TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: Text(context.t.driveConnectSubtitle,
                                style:
                                    const TextStyle(color: Color(0xFF5E5F69))),
                          ),
                        )
                      else ...[
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            leading: Icon(Icons.account_circle_outlined,
                                color: AppPalette.inkPrimary),
                            title: Text(
                                context.t.driveConnectedAs(
                                    state.driveAccountEmail ?? ''),
                                style: TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: Text(
                                _lastBackupText(
                                    context, state.lastDriveBackupAt),
                                style:
                                    const TextStyle(color: Color(0xFF5E5F69))),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          child: SwitchListTile(
                            secondary: Icon(Icons.sync_rounded,
                                color: AppPalette.inkPrimary),
                            title: Text(context.t.driveAutoTitle,
                                style: TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: Text(context.t.driveAutoSubtitle,
                                style:
                                    const TextStyle(color: Color(0xFF5E5F69))),
                            value: state.driveAutoBackup,
                            onChanged: (v) =>
                                context.read<AppState>().setDriveAutoBackup(v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _driveBackupNow(context),
                          child: ListTile(
                            leading: Icon(Icons.backup_outlined,
                                color: AppPalette.inkPrimary),
                            title: Text(context.t.driveBackupNow,
                                style: TextStyle(color: AppPalette.inkPrimary)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _restoreFromDrive(context),
                          child: ListTile(
                            leading: Icon(
                                Icons.settings_backup_restore_rounded,
                                color: AppPalette.inkPrimary),
                            title: Text(context.t.driveRestoreTitle,
                                style: TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: Text(context.t.driveRestoreSubtitle,
                                style:
                                    const TextStyle(color: Color(0xFF5E5F69))),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GlassPanel(
                          borderRadius: 20,
                          blur: 0,
                          color: AppPalette.surfaceGlass,
                          padding: EdgeInsets.zero,
                          onTap: () => _disconnectDrive(context),
                          child: ListTile(
                            leading: const Icon(Icons.logout_rounded,
                                color: Color(0xFFFF8A9B)),
                            title: Text(context.t.driveDisconnect,
                                style:
                                    const TextStyle(color: Color(0xFFFF8A9B))),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.storageSection),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            _statRow(Icons.lightbulb_outline_rounded,
                                context.t.statNotes,
                                state.noteCount),
                            _statRow(Icons.grid_view_rounded,
                                context.t.statCortex,
                                state.spaceCount),
                            _statRow(Icons.style_outlined, context.t.statCards,
                                state.cardCount),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        onTap: () => _loadSample(context),
                        child: ListTile(
                          leading: Icon(Icons.auto_awesome_rounded,
                              color: AppPalette.inkPrimary),
                          title: Text(context.t.loadSampleData,
                              style: TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text(context.t.loadSampleDataSubtitle,
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: EdgeInsets.zero,
                        onTap: () => _confirmClear(context),
                        child: ListTile(
                          leading: const Icon(Icons.delete_forever_rounded,
                              color: Color(0xFFFF8A9B)),
                          title: Text(context.t.clearAllData,
                              style: TextStyle(color: Color(0xFFFF8A9B))),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel(context.t.aboutSection),
                      GlassPanel(
                        borderRadius: 20,
                        // The backdrop is flat and near-opaque; blurring it
                        // would burn a BackdropFilter per panel for nothing.
                        blur: 0,
                        color: AppPalette.surfaceGlass,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.t.appTitle,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: AppPalette.inkPrimary)),
                            const SizedBox(height: 4),
                            Text(context.t.aboutLine,
                                style: TextStyle(
                                    color: AppPalette.inkSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _statRow(IconData icon, String label, int value) {
    return ListTile(
      leading: Icon(icon, color: AppPalette.inkPrimary),
      title: Text(label, style: TextStyle(color: AppPalette.inkPrimary)),
      trailing: Text('$value',
          style: TextStyle(
              color: AppPalette.inkSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// A thumbnail of the active theme's feed background (custom image or built-in).
Widget _feedBgPreview(AppState state) {
  final custom =
      AppPalette.dark ? state.feedBackgroundDark : state.feedBackgroundLight;
  if (custom.isNotEmpty && File(custom).existsSync()) {
    return Image.file(File(custom), fit: BoxFit.cover, cacheWidth: 140);
  }
  return Image.asset(
    AppPalette.dark
        ? 'assets/wallpapers/bg_dark.jpg'
        : 'assets/wallpapers/bg_light.jpg',
    fit: BoxFit.cover,
    cacheWidth: 140,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: AppPalette.inkSecondary,
        ),
      ),
    );
  }
}

