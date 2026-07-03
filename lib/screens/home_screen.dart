import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_morph.dart';
import '../widgets/note_card.dart';
import '../widgets/move_to_space_sheet.dart';
import 'note_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _moveNote(Note note) async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: note.spaceId);
    if (selected == null || !mounted) return;
    await context
        .read<AppState>()
        .moveNoteToSpace(note.id, selected == '__none__' ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<AppState>().notes;

    if (notes.isEmpty) return const _EmptyState();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          // Top padding clears the header fade band so resting cards aren't
          // dimmed; they only fade once scrolled up into it.
          padding: const EdgeInsets.fromLTRB(14, 40, 14, 150),
          sliver: SliverToBoxAdapter(
            child: _MasonryFeed(
              notes: notes,
              onLongPress: _moveNote,
            ),
          ),
        ),
      ],
    );
  }
}

class _MasonryFeed extends StatelessWidget {
  const _MasonryFeed({
    required this.notes,
    required this.onLongPress,
  });

  final List<Note> notes;
  final ValueChanged<Note> onLongPress;

  @override
  Widget build(BuildContext context) {
    final left = <Note>[];
    final right = <Note>[];
    for (var i = 0; i < notes.length; i++) {
      (i.isEven ? left : right).add(notes[i]);
    }

    Widget column(List<Note> items) {
      final state = context.read<AppState>();
      return Expanded(
        child: Column(
          children: [
            for (final n in items)
              Padding(
                padding: const EdgeInsets.all(6),
                child: GlassMorph(
                  openBuilder: (_) => NoteEditorScreen(note: n, isNew: false),
                  closedBuilder: (context, open) => NoteCard(
                    note: n,
                    space: state.spaceById(n.spaceId),
                    onTap: open,
                    onLongPress: () => onLongPress(n),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column(left), column(right)],
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
            'No notes yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the pencil to add one.',
            style: TextStyle(color: AppPalette.textSecondary),
          ),
        ],
      ),
    );
  }
}
