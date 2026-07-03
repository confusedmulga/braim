import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/morph_open.dart';
import '../widgets/move_to_space_sheet.dart';
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
  const CardsScreen({super.key});

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
    final cards = context.watch<AppState>().cards;

    if (cards.isEmpty) return const _EmptyCards();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          // Top padding clears the header fade band (see home_screen).
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 150),
          sliver: SliverList.separated(
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final card = cards[i];
              return MorphOpen(
                openColor: Colors.white,
                openBuilder: (_) => CardDetailScreen(card: card),
                closedBuilder: (context, open) => TweetCardWidget(
                  card: card,
                  onTap: open,
                  onLongPress: () => _moveCard(context, card),
                  onDelete: () =>
                      context.read<AppState>().deleteCard(card.id),
                ),
              );
            },
          ),
        ),
      ],
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
            const Text(
              'Save a link',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Paste a tweet or any URL.',
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                hintText: 'https://x.com/…',
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
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _ctrl.text),
                  child: const Text('Save'),
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
            'No cards yet',
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
              'Share a link to Braim, or tap + to paste one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
