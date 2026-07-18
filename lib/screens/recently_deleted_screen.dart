import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/space.dart';
import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/note_card.dart';
import '../widgets/space_tile.dart';
import '../widgets/tweet_card_widget.dart';

/// Recently Deleted — notes, cards and folders are kept for 30 days, then
/// purged. Tap an item to restore it or delete it permanently.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key});

  Future<String?> _ask(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassEdge(
            borderRadius: 26,
            fill: AppPalette.whiteFill,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.restore_rounded,
                      color: AppPalette.inkPrimary),
                  title: Text(context.t.restore,
                      style: TextStyle(color: AppPalette.inkPrimary)),
                  onTap: () => Navigator.pop(context, 'restore'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Color(0xFFE5557A)),
                  title: Text(context.t.deletePermanently,
                      style: TextStyle(color: Color(0xFFE5557A))),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _noteActions(BuildContext context, Note note) async {
    final state = context.read<AppState>();
    final action = await _ask(context);
    if (action == 'restore') {
      await state.restoreNote(note.id);
    } else if (action == 'delete') {
      await state.permanentlyDeleteNote(note.id);
    }
  }

  Future<void> _cardActions(BuildContext context, TweetCard card) async {
    final state = context.read<AppState>();
    final action = await _ask(context);
    if (action == 'restore') {
      await state.restoreCard(card.id);
    } else if (action == 'delete') {
      await state.permanentlyDeleteCard(card.id);
    }
  }

  Future<void> _spaceActions(BuildContext context, Space space) async {
    final state = context.read<AppState>();
    final action = await _ask(context);
    if (action == 'restore') {
      await state.restoreSpace(space.id);
    } else if (action == 'delete') {
      await state.permanentlyDeleteSpace(space.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.deletedNotes;
    final cards = state.deletedCards;
    final spaces = state.deletedSpaces;

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
                  child: NoteCard(
                    note: n,
                    space: state.spaceById(n.spaceId),
                    onTap: () => _noteActions(context, n),
                    onLongPress: () => _noteActions(context, n),
                  ),
                ),
            ],
          ),
        );

    final isEmpty = notes.isEmpty && cards.isEmpty && spaces.isEmpty;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppPalette.inkPrimary,
          title: Text(context.t.recentlyDeleted,
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (!isEmpty)
              TextButton(
                onPressed: () async {
                  final ok = await _confirmEmpty(context);
                  if (ok == true && context.mounted) {
                    await context.read<AppState>().emptyTrash();
                  }
                },
                child: Text(context.t.empty,
                    style: TextStyle(color: Color(0xFFE5557A))),
              ),
          ],
        ),
        body: isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 56, color: AppPalette.inkSecondary),
                    const SizedBox(height: 12),
                    Text(context.t.nothingHere,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                    const SizedBox(height: 4),
                    Text(context.t.deletedKept30,
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
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                      child: Text(
                          context.t.trashHint,
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
                          child: TweetCardWidget(
                            card: c,
                            folderName: state.spaceById(c.spaceId)?.name,
                            onTap: () => _cardActions(context, c),
                            onLongPress: () => _cardActions(context, c),
                            onDelete: () => _cardActions(context, c),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _spaceTile(BuildContext context, AppState state, Space space) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SpaceTile(
        space: space,
        itemCount: state.itemCountForSpace(space.id),
        onTap: () => _spaceActions(context, space),
        onLongPress: () => _spaceActions(context, space),
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

  Future<bool?> _confirmEmpty(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.emptyTrashTitle),
        content: Text(context.t.emptyTrashBody),
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
            child: Text(context.t.empty),
          ),
        ],
      ),
    );
  }
}
