import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// Human-readable "last backed up" line for the backup row.
String _lastBackupText(BuildContext context, DateTime? last) {
  if (last == null) return context.t.lastBackupNever;
  return context.t.lastBackupAgo(DateTime.now().difference(last).inDays);
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
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
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
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Icon(Icons.wallpaper_rounded,
                                    color: AppPalette.inkSecondary),
                                const SizedBox(width: 14),
                                Text(context.t.wallpaper,
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        color: AppPalette.inkPrimary)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _WallpaperPicker(
                              selected: state.feedWallpaper,
                              onSelect: (i) => context
                                  .read<AppState>()
                                  .setFeedWallpaper(i),
                            ),
                          ],
                        ),
                      ),
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

/// Thumbnails of the four bundled feed wallpapers; the active one carries a
/// primary-colored ring.
class _WallpaperPicker extends StatelessWidget {
  const _WallpaperPicker({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final names = [
      context.t.wallpaperGreen,
      context.t.wallpaperRed,
      context.t.wallpaperBlue,
      context.t.wallpaperBlack,
    ];
    return Row(
      children: [
        for (var i = 0; i < kFeedWallpapers.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              label: names[i],
              child: Tooltip(
                message: names[i],
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: Container(
                    height: 96,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: i == selected
                            ? AppPalette.scheme.primary
                            : AppPalette.cardOutline,
                        width: i == selected ? 2.5 : 1,
                      ),
                    ),
                    child: Image.asset(
                      kFeedWallpapers[i],
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
