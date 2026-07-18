import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_morph.dart';
import '../widgets/item_actions_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  /// Owned by the shell so it can scroll this feed back to the top.
  final ScrollController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _noteActions(Note note) async {
    final state = context.read<AppState>();
    await showItemActions(
      context,
      pinned: note.pinned,
      archived: note.archived,
      currentSpaceId: note.spaceId,
      onSetPinned: (p) => state.setNotePinned(note.id, p),
      onSetArchived: (a) => state.setNoteArchived(note.id, a),
      onMove: (spaceId) => state.moveNoteToSpace(note.id, spaceId),
      onDelete: () => state.deleteNote(note.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.notes;

    if (notes.isEmpty) return const _EmptyState();

    final showBackupBanner = state.showBackupReminder;

    // Left-edge scrollbar: appears while scrolling, hugs the left side so
    // it never fights the right-hand fade/toggle area.
    return RawScrollbar(
      controller: widget.controller,
      scrollbarOrientation: ScrollbarOrientation.left,
      thumbColor: AppPalette.inkSecondary.withValues(alpha: 0.5),
      radius: const Radius.circular(4),
      thickness: 3.4,
      mainAxisMargin: 46,
      child: CustomScrollView(
        controller: widget.controller,
      slivers: [
        if (showBackupBanner)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              child: _BackupBanner(
                onBackup: () {
                  state.dismissBackupReminder();
                  Navigator.of(context).push(SettingsScreen.route());
                },
                onDismiss: state.dismissBackupReminder,
              ),
            ),
          ),
        SliverPadding(
          // Just enough top padding to clear the (short) header fade band.
          padding: EdgeInsets.fromLTRB(14, showBackupBanner ? 8 : 12, 14, 150),
          // Lazy masonry: builds only visible tiles and packs each new tile
          // into the currently-shortest column (true height balancing).
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childCount: notes.length,
            itemBuilder: (context, i) {
              final n = notes[i];
              return GlassMorph(
                key: ValueKey(n.id),
                openBuilder: (_) => NoteEditorScreen(note: n, isNew: false),
                closedBuilder: (context, open) => NoteCard(
                  note: n,
                  space: state.spaceById(n.spaceId),
                  onTap: open,
                  onLongPress: () => _noteActions(n),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

/// A dismissible safety nudge shown atop the feed when the library hasn't been
/// backed up recently. Dismiss is session-only — a real safety net should
/// return next launch if the notes still aren't backed up.
class _BackupBanner extends StatelessWidget {
  const _BackupBanner({required this.onBackup, required this.onDismiss});

  final VoidCallback onBackup;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassEdge(
      borderRadius: 18,
      blur: 0,
      fill: AppPalette.cardSolid,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 22, color: AppPalette.inkPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t.backupReminderTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppPalette.inkPrimary)),
                const SizedBox(height: 2),
                Text(context.t.backupReminderBody,
                    style: TextStyle(
                        fontSize: 12.5, color: AppPalette.inkSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onBackup,
            style: TextButton.styleFrom(
                foregroundColor: AppPalette.inkPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Text(context.t.backupNow,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: context.t.dismiss,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppPalette.inkSecondary),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              size: 64, color: AppPalette.textSecondary),
          const SizedBox(height: 16),
          Text(
            context.t.noNotesYet,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.t.tapPencilToAdd,
            style: TextStyle(color: AppPalette.textSecondary),
          ),
        ],
      ),
    );
  }
}
