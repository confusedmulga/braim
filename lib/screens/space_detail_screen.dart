import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_space_sheet.dart';
import '../widgets/bubble_button.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import '../widgets/morph_open.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_card.dart';
import '../widgets/tweet_card_widget.dart';
import 'card_detail_screen.dart';
import 'note_editor_screen.dart';

class SpaceDetailScreen extends StatelessWidget {
  const SpaceDetailScreen({super.key, required this.spaceId});

  final String spaceId;

  Future<void> _moveNote(BuildContext context, Note note) async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: note.spaceId);
    if (selected == null || !context.mounted) return;
    await context
        .read<AppState>()
        .moveNoteToSpace(note.id, selected == '__none__' ? null : selected);
  }

  Future<void> _moveCard(BuildContext context, TweetCard card) async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: card.spaceId);
    if (selected == null || !context.mounted) return;
    await context
        .read<AppState>()
        .moveCardToSpace(card.id, selected == '__none__' ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final space = state.spaceById(spaceId);
    if (space == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const AppBackground();
    }
    final notes = state.notesForSpace(spaceId);
    final cards = state.cardsForSpace(spaceId);

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
                      space: space,
                      onTap: open,
                      onLongPress: () => _moveNote(context, n),
                    ),
                  ),
                ),
            ],
          ),
        );

    final isEmpty = notes.isEmpty && cards.isEmpty;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          foregroundColor: AppPalette.inkPrimary,
          title: Text(space.name,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BubbleButton(
              icon: Icons.playlist_add_rounded,
              tooltip: 'Add existing',
              size: 52,
              iconSize: 24,
              onTap: () => showAddToSpaceSheet(context,
                  spaceId: spaceId, spaceName: space.name),
            ),
            const SizedBox(height: 14),
            GlassMorph(
              closedRadius: 34,
              openBuilder: (_) =>
                  NoteEditorScreen(note: Note(spaceId: spaceId), isNew: true),
              closedBuilder: (context, open) =>
                  BubbleButton(icon: Icons.edit_rounded, onTap: open),
            ),
          ],
        ),
        body: isEmpty
            ? _emptyBody()
            : TopFade(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 38, 14, 120),
                  children: [
                    if (notes.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [column(left), column(right)],
                      ),
                    if (cards.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
                        child: Text(
                          'CARDS',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary,
                          ),
                        ),
                      ),
                      for (final c in cards)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 7),
                          child: MorphOpen(
                            openColor: Colors.white,
                            openBuilder: (_) => CardDetailScreen(card: c),
                            closedBuilder: (context, open) => TweetCardWidget(
                              card: c,
                              onTap: open,
                              onLongPress: () => _moveCard(context, c),
                              onDelete: () =>
                                  context.read<AppState>().deleteCard(c.id),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _emptyBody() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 56, color: AppPalette.inkSecondary),
          const SizedBox(height: 12),
          const Text('Nothing in this folder yet',
              style: TextStyle(color: AppPalette.inkSecondary)),
          const SizedBox(height: 4),
          const Text('Use the + buttons to add a note or existing items.',
              style: TextStyle(
                  color: AppPalette.inkSecondary, fontSize: 12.5)),
        ],
      ),
    );
  }
}
