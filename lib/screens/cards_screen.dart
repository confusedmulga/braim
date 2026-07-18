import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_morph.dart';
import '../widgets/item_actions_sheet.dart';
import '../widgets/tweet_card_widget.dart';
import 'card_detail_screen.dart';

/// Shows the add-link dialog (clipboard-prefilled) and returns the URL, or
/// null if dismissed. Used by the universal + button in the shell.
Future<String?> showAddLinkDialog(BuildContext context) async {
  final clip = await Clipboard.getData('text/plain');
  final prefill = (clip?.text ?? '').contains('http') ? clip!.text! : '';
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (_) => _AddLinkDialog(initial: prefill),
  );
}

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key, this.controller});

  /// Owned by the shell so it can scroll this feed back to the top.
  final ScrollController? controller;

  Future<void> _cardActions(BuildContext context, TweetCard card) async {
    final state = context.read<AppState>();
    await showItemActions(
      context,
      pinned: card.pinned,
      archived: card.archived,
      currentSpaceId: card.spaceId,
      onSetPinned: (p) => state.setCardPinned(card.id, p),
      onSetArchived: (a) => state.setCardArchived(card.id, a),
      onMove: (spaceId) => state.moveCardToSpace(card.id, spaceId),
      onDelete: () => state.deleteCard(card.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cards = state.cards;

    if (cards.isEmpty) return const _EmptyCards();

    return RawScrollbar(
      controller: controller,
      scrollbarOrientation: ScrollbarOrientation.left,
      thumbColor: AppPalette.inkSecondary.withValues(alpha: 0.5),
      radius: const Radius.circular(4),
      thickness: 3.4,
      mainAxisMargin: 46,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 150),
            // Lazy masonry: builds only visible tiles and packs each into the
            // shortest column (true height balancing).
            sliver: SliverMasonryGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childCount: cards.length,
              itemBuilder: (context, i) {
                final c = cards[i];
                return GlassMorph(
                  key: ValueKey(c.id),
                  closedRadius: 18,
                  openBuilder: (_) => CardDetailScreen(card: c),
                  closedBuilder: (context, open) => CompactCardTile(
                    card: c,
                    folderName: state.spaceById(c.spaceId)?.name,
                    onTap: open,
                    onLongPress: () => _cardActions(context, c),
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


class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog({required this.initial});
  final String initial;

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.saveALink),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t.pasteTweetOrUrl),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: TextStyle(color: AppPalette.inkPrimary),
            decoration: InputDecoration(
              hintText: context.t.urlHint,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(context.t.save),
        ),
      ],
    );
  }
}

class _EmptyCards extends StatelessWidget {
  const _EmptyCards();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined, size: 64, color: AppPalette.textSecondary),
          const SizedBox(height: 16),
          Text(
            context.t.noCardsYet,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              context.t.shareOrPasteLink,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
