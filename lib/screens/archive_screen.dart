import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import '../widgets/note_card.dart';
import '../widgets/space_tile.dart';
import '../widgets/tweet_card_widget.dart';
import 'card_detail_screen.dart';
import 'note_editor_screen.dart';
import 'space_detail_screen.dart';

/// Archived notes, cards and folders. Tap opens; long-press restores.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  void _restored(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.archivedNotes;
    final cards = state.archivedCards;
    final spaces = state.archivedSpaces;

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
                    key: ValueKey(n.id),
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
                          _restored(context, context.t.noteUnarchived);
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        );

    final isEmpty = notes.isEmpty && cards.isEmpty && spaces.isEmpty;

    return FrostedScaffold(
      title: context.t.archiveTitle,
      body: isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.archive_outlined,
                        size: 56, color: AppPalette.inkSecondary),
                    const SizedBox(height: 12),
                    Text(context.t.nothingArchived,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                    const SizedBox(height: 4),
                    Text(context.t.archiveHint,
                        style: TextStyle(
                            color: AppPalette.inkSecondary, fontSize: 12.5)),
                  ],
                ),
              )
            : TopFade(
                height: 12,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                      child: Text(context.t.longPressToRestore,
                          style: TextStyle(
                              color: AppPalette.inkSecondary,
                              fontSize: 12.5)),
                    ),
                    if (spaces.isNotEmpty) ...[
                      _label(context, context.t.sectionFolders),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(children: [
                              for (var i = 0; i < spaces.length; i += 2)
                                _spaceTile(context, state, spaces[i]),
                            ]),
                          ),
                          Expanded(
                            child: Column(children: [
                              for (var i = 1; i < spaces.length; i += 2)
                                _spaceTile(context, state, spaces[i]),
                            ]),
                          ),
                        ],
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      _label(context, context.t.sectionNotes),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [column(left), column(right)],
                      ),
                    ],
                    if (cards.isNotEmpty) ...[
                      _label(context, context.t.sectionCards),
                      for (final c in cards)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                          child: GlassMorph(
                            key: ValueKey(c.id),
                            openBuilder: (_) => CardDetailScreen(card: c),
                            closedBuilder: (context, open) =>
                                TweetCardWidget(
                              card: c,
                              folderName:
                                  state.spaceById(c.spaceId)?.name,
                              folderColor:
                                  state.spaceById(c.spaceId)?.colorValue,
                              onTap: open,
                              onLongPress: () async {
                                await context
                                    .read<AppState>()
                                    .setCardArchived(c.id, false);
                                if (context.mounted) {
                                  _restored(
                                      context, context.t.cardUnarchived);
                                }
                              },
                              onDelete: () =>
                                  context.read<AppState>().deleteCard(c.id),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
    );
  }

  Widget _spaceTile(BuildContext context, AppState state, space) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SpaceTile(
        space: space,
        itemCount: state.itemCountForSpace(space.id),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SpaceDetailScreen(spaceId: space.id))),
        onLongPress: () async {
          await context.read<AppState>().setSpaceArchived(space.id, false);
          if (context.mounted) {
            _restored(context, context.t.folderUnarchived);
          }
        },
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: AppPalette.inkSecondary,
        ),
      ),
    );
  }
}
