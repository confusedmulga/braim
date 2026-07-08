import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
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
    final compact = state.cardsCompact;

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
        // Top padding clears the header fade band + the floating view toggle.
        if (compact)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 44, 14, 150),
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
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 44, 18, 150),
            sliver: SliverList.separated(
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final card = cards[i];
                return GlassMorph(
                  key: ValueKey(card.id),
                  openBuilder: (_) => CardDetailScreen(card: card),
                  closedBuilder: (context, open) => TweetCardWidget(
                    card: card,
                    folderName: state.spaceById(card.spaceId)?.name,
                    onTap: open,
                    onLongPress: () => _cardActions(context, card),
                    onDelete: () =>
                        context.read<AppState>().deleteCard(card.id),
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

/// The Open/Blocks segmented toggle for the cards feed (hosted by the shell
/// so it stays fixed while the feed scrolls).
class CardsViewToggle extends StatelessWidget {
  const CardsViewToggle(
      {super.key, required this.compact, required this.onChanged});

  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassEdge(
      borderRadius: 20,
      blur: 0,
      fill: AppPalette.whiteFill,
      padding: const EdgeInsets.all(3),
      shadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, context.t.viewOpen, Icons.view_agenda_outlined,
              !compact, () => onChanged(false)),
          _segment(context, context.t.viewBlocks, Icons.grid_view_rounded,
              compact, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, IconData icon,
      bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppPalette.selFill : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? AppPalette.inkPrimary
                    : AppPalette.inkSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? AppPalette.inkPrimary
                    : AppPalette.inkSecondary,
              ),
            ),
          ],
        ),
      ),
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: GlassPanel(
        borderRadius: 24,
        strong: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.saveALink,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t.pasteTweetOrUrl,
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                hintText: context.t.urlHint,
                hintStyle: TextStyle(color: AppPalette.textSecondary),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _ctrl.text),
                  child: Text(context.t.save),
                ),
              ],
            ),
          ],
        ),
      ),
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
