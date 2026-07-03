import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';

/// Shows archived notes. Tapping opens the editor (where you can unarchive);
/// long-press restores a note straight back to the feed.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.archivedNotes;

    final left = <Note>[];
    final right = <Note>[];
    for (var i = 0; i < notes.length; i++) {
      (i.isEven ? left : right).add(notes[i]);
    }

    Widget column(List<Note> items) => Expanded(
          child: Column(
            children: [
              for (final n in items)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: GlassMorph(
                    openBuilder: (_) =>
                        NoteEditorScreen(note: n, isNew: false),
                    closedBuilder: (context, open) => NoteCard(
                      note: n,
                      space: state.spaceById(n.spaceId),
                      onTap: open,
                      onLongPress: () async {
                        await context
                            .read<AppState>()
                            .setNoteArchived(n.id, false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Restored to feed')),
                          );
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        );

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppPalette.inkPrimary,
          title: const Text('Archive',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: notes.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.archive_outlined,
                        size: 56, color: AppPalette.inkSecondary),
                    const SizedBox(height: 12),
                    const Text('No archived notes',
                        style: TextStyle(color: AppPalette.inkSecondary)),
                    const SizedBox(height: 4),
                    const Text('Archive a note from its ⋯ menu to hide it here.',
                        style: TextStyle(
                            color: AppPalette.inkSecondary, fontSize: 12.5)),
                  ],
                ),
              )
            : TopFade(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 38, 14, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [column(left), column(right)],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
