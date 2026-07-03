import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/note_card.dart';

/// Recently Deleted — notes are kept here for 30 days, then purged. Tap a note
/// to restore it or delete it permanently.
class RecentlyDeletedScreen extends StatelessWidget {
  const RecentlyDeletedScreen({super.key});

  Future<void> _actions(BuildContext context, Note note) async {
    final action = await showModalBottomSheet<String>(
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
                  leading: const Icon(Icons.restore_rounded,
                      color: AppPalette.inkPrimary),
                  title: const Text('Restore to feed',
                      style: TextStyle(color: AppPalette.inkPrimary)),
                  onTap: () => Navigator.pop(context, 'restore'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Color(0xFFE5557A)),
                  title: const Text('Delete permanently',
                      style: TextStyle(color: Color(0xFFE5557A))),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'restore') {
      await context.read<AppState>().restoreNote(note.id);
    } else if (action == 'delete') {
      await context.read<AppState>().permanentlyDeleteNote(note.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.deletedNotes;

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
                    onTap: () => _actions(context, n),
                    onLongPress: () => _actions(context, n),
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
          title: const Text('Recently deleted',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (notes.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final ok = await _confirmEmpty(context);
                  if (ok == true && context.mounted) {
                    await context.read<AppState>().emptyTrash();
                  }
                },
                child: const Text('Empty',
                    style: TextStyle(color: Color(0xFFE5557A))),
              ),
          ],
        ),
        body: notes.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 56, color: AppPalette.inkSecondary),
                    SizedBox(height: 12),
                    Text('Nothing here',
                        style: TextStyle(color: AppPalette.inkSecondary)),
                    SizedBox(height: 4),
                    Text('Deleted notes are kept for 30 days.',
                        style: TextStyle(
                            color: AppPalette.inkSecondary, fontSize: 12.5)),
                  ],
                ),
              )
            : TopFade(
                child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 34, 14, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                    child: Text('Notes are deleted forever after 30 days.',
                        style: TextStyle(
                            color: AppPalette.inkSecondary, fontSize: 12.5)),
                  ),
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

  Future<bool?> _confirmEmpty(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassEdge(
          borderRadius: 22,
          fill: AppPalette.whiteFill,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Empty recently deleted?',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 8),
              const Text('This permanently deletes all notes in the trash.',
                  style: TextStyle(color: AppPalette.inkSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5557A)),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Empty'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
