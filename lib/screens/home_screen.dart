import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../widgets/feed_greeting.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_morph.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/glass.dart';
import '../widgets/note_background.dart';
import '../widgets/note_card.dart';
import '../widgets/quick_actions_menu.dart';
import 'markdown_note_screen.dart';
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
  // Multi-select: long-press a note to start, then tap to (de)select.
  bool _selecting = false;
  final Set<String> _selected = {};

  void _enterSelection(Note n) => setState(() {
        _selecting = true;
        _selected.add(n.id);
      });

  void _toggle(Note n) => setState(() {
        if (!_selected.remove(n.id)) _selected.add(n.id);
        if (_selected.isEmpty) _selecting = false;
      });

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  // ---- Long-press quick actions ------------------------------------------

  Future<void> _showActions(Note n) async {
    final action = await showQuickActions(context, pinned: n.pinned);
    if (action == null || !mounted) return;
    switch (action) {
      case QuickAction.move:
        await _moveOne(n);
      case QuickAction.select:
        _enterSelection(n);
      case QuickAction.pin:
        await _pinOne(n);
      case QuickAction.theme:
        await _pickTheme(n);
      case QuickAction.archive:
        await _archiveOne(n);
      case QuickAction.delete:
        if (await confirmDeleteItems(context, 1) && mounted) {
          await _deleteOne(n);
        }
    }
  }

  Future<void> _pinOne(Note n) async {
    final state = context.read<AppState>();
    if (n.pinned) {
      await state.setNotePinned(n.id, false);
      return;
    }
    final ok = await state.setNotePinned(n.id, true);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.pinLimitReached(kMaxPins))),
      );
    }
  }

  Future<void> _pickTheme(Note n) async {
    final state = context.read<AppState>();
    await showNoteStylePicker(
      context,
      currentColor: n.colorValue,
      currentBackground: n.backgroundAsset,
      onColor: (value) {
        n.colorValue = value;
        state.upsertNote(n);
      },
      onBackground: (value) {
        n.backgroundAsset = value;
        state.upsertNote(n);
      },
    );
  }

  Future<void> _moveOne(Note n) async {
    final choice = await showMoveToSpaceSheet(context, currentSpaceId: n.spaceId);
    if (choice == null || !mounted) return;
    await context
        .read<AppState>()
        .bulkMoveNotes({n.id}, choice == '__none__' ? null : choice);
  }

  Future<void> _archiveOne(Note n) =>
      context.read<AppState>().bulkArchiveNotes({n.id}, true);

  Future<void> _deleteOne(Note n) =>
      context.read<AppState>().bulkDeleteNotes({n.id});

  // ---- Multi-select bulk actions -----------------------------------------

  Future<void> _bulkPin() async {
    final state = context.read<AppState>();
    final result = await state.bulkPinNotesLimited(_selected.toSet());
    if (!mounted) return;
    _exitSelection();
    if (result.skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.pinLimitReached(kMaxPins))),
      );
    }
  }

  Future<void> _bulkArchive() async {
    await context.read<AppState>().bulkArchiveNotes(_selected.toSet(), true);
    _exitSelection();
  }

  Future<void> _bulkDelete() async {
    if (!await confirmDeleteItems(context, _selected.length) || !mounted) {
      return;
    }
    await context.read<AppState>().bulkDeleteNotes(_selected.toSet());
    _exitSelection();
  }

  Future<void> _bulkMove() async {
    final choice = await showMoveToSpaceSheet(context, currentSpaceId: null);
    if (choice == null || !mounted) return;
    await context
        .read<AppState>()
        .bulkMoveNotes(_selected.toSet(), choice == '__none__' ? null : choice);
    _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.notes;

    // A brand-new library: open with a subtle first-note greeting (only ever
    // shown while there are zero notes) above the empty-state hint.
    if (notes.isEmpty) {
      return CustomScrollView(
        controller: widget.controller,
        slivers: const [
          SliverToBoxAdapter(
            child: FeedGreeting(picker: pickFirstNoteGreeting),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          ),
        ],
      );
    }

    final showBackupBanner = state.showBackupReminder;

    // Left-edge scrollbar: appears while scrolling, hugs the left side so
    // it never fights the right-hand fade/toggle area.
    final feed = RawScrollbar(
      controller: widget.controller,
      scrollbarOrientation: ScrollbarOrientation.left,
      thumbColor: AppPalette.inkSecondary.withValues(alpha: 0.5),
      radius: const Radius.circular(4),
      thickness: 3.4,
      mainAxisMargin: 46,
      child: CustomScrollView(
        controller: widget.controller,
      slivers: [
        const SliverToBoxAdapter(
          child: FeedGreeting(picker: pickHomeGreeting),
        ),
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
          padding: EdgeInsets.fromLTRB(
              14, showBackupBanner ? 8 : 12, 14, 150),
          // Lazy masonry: builds only visible tiles and packs each new tile
          // into the currently-shortest column (true height balancing).
          // SliverMasonryGrid reuses each realised child's cached column on a
          // reorder, which leaves stale gaps. Re-key only when items actually
          // reorder — a pin/unpin or a sort change — so a fresh layout kicks in
          // there, while add/delete/edit keep their scroll position.
          sliver: SliverMasonryGrid.count(
            key: ValueKey('feed|${state.sortMode.name}|'
                '${notes.where((n) => n.pinned).map((n) => n.id).join(',')}'),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childCount: notes.length,
            itemBuilder: (context, i) {
              final n = notes[i];
              return GlassMorph(
                key: ValueKey(n.id),
                openBuilder: (_) => n.markdown
                    ? MarkdownNoteScreen(note: n)
                    : NoteEditorScreen(note: n, isNew: false),
                closedBuilder: (context, open) => NoteCard(
                  note: n,
                  space: state.spaceById(n.spaceId),
                  selected: _selected.contains(n.id),
                  onTap: _selecting ? () => _toggle(n) : open,
                  onLongPress: _selecting ? null : () => _showActions(n),
                ),
              );
            },
          ),
        ),
      ],
      ),
    );

    // Always a Stack (even when not selecting) so the feed subtree — and its
    // once-per-mount greeting — never re-mounts when selection toggles.
    return Stack(
      children: [
        feed,
        if (_selecting)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 96,
            child: SelectionActionBar(
              count: _selected.length,
              onMove: _bulkMove,
              onPin: _bulkPin,
              onArchive: _bulkArchive,
              onDelete: _bulkDelete,
              onClose: _exitSelection,
            ),
          ),
      ],
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
