import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// Settings opens as a transparent overlay so the screen the user came from
/// stays visible (and blurred) behind it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const SettingsScreen(),
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await BackupService.instance.exportToTempFile();
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Braim backup');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restore(BuildContext context) async {
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
      await BackupService.instance.restoreFromFile(path);
      await appState.init();
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Backup restored')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<bool?> _confirmRestore(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassPanel(
          borderRadius: 22,
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restore backup?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 8),
              Text('This replaces your current notes, cards and folders '
                  'with the ones in the backup.',
                  style: TextStyle(color: AppPalette.inkSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassPanel(
          borderRadius: 22,
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Clear all data?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 8),
              Text(
                'This permanently deletes every note, space and card on this device.',
                style: TextStyle(color: AppPalette.inkSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5557A)),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      body: BackdropFilter(
        // Blurs whatever screen is painted behind this transparent route.
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          color: Colors.white.withValues(alpha: 0.60),
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
                      const Text('Settings',
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
                      _SectionLabel('Backup'),
                      GlassPanel(
                        borderRadius: 20,
                        color: const Color(0xB3FFFFFF),
                        padding: EdgeInsets.zero,
                        onTap: () => _backup(context),
                        child: const ListTile(
                          leading: Icon(Icons.backup_outlined,
                              color: AppPalette.inkPrimary),
                          title: Text('Back up (data + images)',
                              style:
                                  TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text('Share to Google Drive, Files, …',
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        color: const Color(0xB3FFFFFF),
                        padding: EdgeInsets.zero,
                        onTap: () => _restore(context),
                        child: const ListTile(
                          leading: Icon(Icons.settings_backup_restore_rounded,
                              color: AppPalette.inkPrimary),
                          title: Text('Restore from backup',
                              style:
                                  TextStyle(color: AppPalette.inkPrimary)),
                          subtitle: Text('Pick a .zip backup file',
                              style: TextStyle(color: Color(0xFF5E5F69))),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('Storage'),
                      GlassPanel(
                        borderRadius: 20,
                        color: const Color(0xB3FFFFFF),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            _statRow(Icons.lightbulb_outline_rounded, 'Notes',
                                state.noteCount),
                            _statRow(Icons.grid_view_rounded, 'Cortex',
                                state.spaceCount),
                            _statRow(Icons.style_outlined, 'Cards',
                                state.cardCount),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GlassPanel(
                        borderRadius: 20,
                        color: const Color(0xB3FFFFFF),
                        padding: EdgeInsets.zero,
                        onTap: () => _confirmClear(context),
                        child: ListTile(
                          leading: const Icon(Icons.delete_forever_rounded,
                              color: Color(0xFFFF8A9B)),
                          title: const Text('Clear all data',
                              style: TextStyle(color: Color(0xFFFF8A9B))),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('About'),
                      GlassPanel(
                        borderRadius: 20,
                        color: const Color(0xB3FFFFFF),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Braim',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: AppPalette.inkPrimary)),
                            const SizedBox(height: 4),
                            Text('A glassy notes app · v1.0 (prototype)',
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
      ),
    );
  }

  Widget _statRow(IconData icon, String label, int value) {
    return ListTile(
      leading: Icon(icon, color: AppPalette.inkPrimary),
      title: Text(label, style: const TextStyle(color: AppPalette.inkPrimary)),
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
