import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_greeting.dart';
import '../widgets/glass_morph.dart';
import '../widgets/stat_card.dart';
import 'book_screen.dart';

/// The Narrative tab: a shelf of the books you're writing.
class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key, this.controller});

  /// Owned by the shell so it can scroll this feed back to the top.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final books = state.books;

    return CustomScrollView(
      controller: controller,
      slivers: [
        const SliverToBoxAdapter(
          child: FeedGreeting(picker: pickNarrativeGreeting),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: StatCard(stats: [
              Stat('${books.length}', context.t.statTotalBooks),
              Stat('${state.totalBookPages}', context.t.statPagesWritten),
              Stat('${state.totalBookWords}', context.t.statWordsWritten),
            ]),
          ),
        ),
        if (books.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 4),
              child: Column(
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 46, color: AppPalette.inkSecondary),
                  const SizedBox(height: 12),
                  Text(context.t.booksEmptyTitle,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    context.t.booksEmptyBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: AppPalette.inkSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 150),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 2 / 3,
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: books.length,
                (context, i) {
                  final book = books[i];
                  // A cover expands into the book the same way a note card
                  // expands into its editor — the app's container transform.
                  return GlassMorph(
                    key: ValueKey(book.id),
                    closedRadius: 12,
                    openBuilder: (_) => BookScreen(bookId: book.id),
                    closedBuilder: (context, open) =>
                        BookTile(book: book, onTap: open),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
