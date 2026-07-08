import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Sheet to add existing notes and cards into a space (or remove them). Tapping
/// a row toggles whether that item belongs to [spaceId].
Future<void> showAddToSpaceSheet(
  BuildContext context, {
  required String spaceId,
  required String spaceName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AddToSpaceSheet(spaceId: spaceId, spaceName: spaceName),
  );
}

class _AddToSpaceSheet extends StatelessWidget {
  const _AddToSpaceSheet({required this.spaceId, required this.spaceName});

  final String spaceId;
  final String spaceName;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.notes;
    final cards = state.cards;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: GlassEdge(
        borderRadius: 28,
        fill: AppPalette.whiteFill,
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Text(context.t.addToName(spaceName),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppPalette.inkPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(context.t.addRemoveHint,
                    style: TextStyle(
                        fontSize: 12.5, color: AppPalette.inkSecondary)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (notes.isEmpty && cards.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(context.t.noNotesOrCards,
                            style:
                                TextStyle(color: AppPalette.inkSecondary)),
                      ),
                    if (notes.isNotEmpty) _label('NOTES'),
                    for (final n in notes)
                      _row(
                        icon: Icons.lightbulb_outline_rounded,
                        title: _noteTitle(n),
                        inSpace: n.spaceId == spaceId,
                        onTap: () => context.read<AppState>().moveNoteToSpace(
                            n.id, n.spaceId == spaceId ? null : spaceId),
                      ),
                    if (cards.isNotEmpty) _label('CARDS'),
                    for (final c in cards)
                      _row(
                        icon: c.isTweet
                            ? Icons.alternate_email_rounded
                            : Icons.link_rounded,
                        title: c.authorName.isNotEmpty
                            ? c.authorName
                            : (c.text.isNotEmpty ? c.text : c.url),
                        inSpace: c.spaceId == spaceId,
                        onTap: () => context.read<AppState>().moveCardToSpace(
                            c.id, c.spaceId == spaceId ? null : spaceId),
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

  String _noteTitle(Note n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    final p = n.textPreview.trim();
    if (p.isNotEmpty) return p.split('\n').first;
    return 'Untitled note';
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppPalette.inkSecondary)),
      );

  Widget _row({
    required IconData icon,
    required String title,
    required bool inSpace,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppPalette.inkSecondary, size: 20),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppPalette.inkPrimary)),
      trailing: Icon(
        inSpace ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
        color: inSpace ? const Color(0xFF3BA776) : AppPalette.inkSecondary,
      ),
      onTap: onTap,
    );
  }
}
