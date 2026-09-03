import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/book.dart';
import '../models/note.dart';
import '../services/book_export.dart';
import '../services/image_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/book_cover_art.dart';
import '../widgets/bouncy_route.dart';
import '../widgets/bubble_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/stat_card.dart';
import '../widgets/text_prompt.dart';
import 'book_find_replace_screen.dart';
import 'book_read_screen.dart';
import 'chapter_history_screen.dart';
import 'note_editor_screen.dart';

/// Prompts for a book title and creates it (with its default pages).
Future<void> showCreateBook(BuildContext context) async {
  final title = await promptForText(
    context,
    title: context.t.newBook,
    hint: context.t.bookTitle,
    capitalization: TextCapitalization.words,
  );
  if (title == null || !context.mounted) return;
  final book = await context.read<AppState>().addBook(title.trim());
  if (!context.mounted) return;
  Navigator.of(context).push(cupertinoRoute(BookScreen(bookId: book.id)));
}

/// A book on the shelf: a rectangular cover with the title along the bottom.
class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title =
        book.title.trim().isEmpty ? context.t.untitledBook : book.title;
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.cardOutline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (book.coverPath != null)
                Image.file(File(book.coverPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, _, _) =>
                        BookCoverArt(book: book, compact: true))
              else
                BookCoverArt(book: book, compact: true),
              // A thin spine down the left edge, book-like.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
              ),
              // A photo cover gets a scrim + title overlay; a generated cover
              // already carries its own title.
              if (book.coverPath != null) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.55, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 12,
                  bottom: 12,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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
}

/// An opened book: the cover standing on a tinted stage, the title and
/// author, Read / Add chapter actions, the description, then the contents.
class BookScreen extends StatelessWidget {
  const BookScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.bookById(bookId);
    if (book == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const AppBackground();
    }
    final pages = state.bookPages(bookId);
    final listed =
        pages.where((p) => p.bookPageKind != BookPageKind.contents).toList();
    final title =
        book.title.trim().isEmpty ? context.t.untitledBook : book.title;
    final author = book.author.trim().isNotEmpty
        ? book.author.trim()
        : (state.accountName ?? state.accountEmail ?? '');
    final words = state.bookWordCount(bookId);
    final noteCount = state.bookNotes(bookId).length;

    // A flat, solid screen — off-white in light mode, black in dark. The only
    // colour is the curved panel behind the cover, and it scrolls away with
    // the cover (no gradient, no fixed backdrop).
    final paper = AppPalette.dark ? Colors.black : const Color(0xFFF5F4EF);
    return Scaffold(
      backgroundColor: paper,
      // The book's create button: a floating + that adds a chapter, matching
      // the create bubble used to make books on the shelf.
      floatingActionButton: BubbleButton(
        icon: Icons.add_rounded,
        tooltip: context.t.addChapter,
        onTap: () async {
          final ch = await context.read<AppState>().addBookChapter(bookId);
          if (context.mounted) {
            Navigator.of(context)
                .push(cupertinoRoute(NoteEditorScreen(note: ch, isNew: true)));
          }
        },
      ),
      body: Stack(
        children: [
          // Android-style stretch overscroll (clamped, not springy): pulling
          // the top just stretches the coloured panel rather than sliding it
          // down and baring the page colour above it.
          ScrollConfiguration(
            behavior: const _StretchScrollBehavior(),
            child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _CoverStage(
                book: book,
                panelColor: AppPalette.scheme.secondaryContainer),
          ),
          DecoratedSliver(
            decoration: BoxDecoration(color: paper),
            sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            sliver: SliverList.list(children: [
              // The author's name comes first, small, then the title — the
              // way a book jacket introduces itself.
              GestureDetector(
                onTap: () => _editAuthor(context, book),
                child: Text(
                  author.isEmpty ? context.t.setAuthor : author,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppPalette.inkSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: book.fontFamily,
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.inkPrimary,
                ),
              ),
              const SizedBox(height: 10),
              // Word/chapter line, the writer's version of a genre label.
              Text(
                '${context.t.chaptersCount(state.bookChapters(bookId).length)}'
                '   ·   ${context.t.wordsCount(words)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: AppPalette.inkSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: listed.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                cupertinoRoute(BookReadScreen(bookId: bookId)),
                              ),
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: Text(context.t.readBook),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Notes sits beside Read; adding a chapter now lives on the
                  // floating + button (the book's create button).
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(cupertinoRoute(BookNotesScreen(bookId: bookId))),
                      icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                      label: Text(noteCount > 0
                          ? '${context.t.bookNotesSection}  ·  $noteCount'
                          : context.t.bookNotesSection),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                        foregroundColor: AppPalette.inkPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              StatCard(stats: [
                Stat('$words', context.t.statWords),
                Stat('${state.bookCharCount(bookId)}',
                    context.t.statCharacters),
                Stat('${state.bookReadingMinutes(bookId)}',
                    context.t.statMinRead),
              ]),
              const SizedBox(height: 26),
              _SectionTitle(context.t.bookDescription),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _editDescription(context, book),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.transparent,
                  child: Text(
                    book.description.trim().isEmpty
                        ? context.t.addDescription
                        : book.description.trim(),
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: book.description.trim().isEmpty
                          ? AppPalette.inkSecondary.withValues(alpha: 0.7)
                          : AppPalette.inkSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              _ContentsSection(bookId: bookId, pages: pages),
            ]),
            ),
          ),
        ],
            ),
          ),
          // The back / share / more chrome stays pinned to the top; it no
          // longer scrolls away with the cover.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    FrostedBackButton(onTap: () => Navigator.pop(context)),
                    const Spacer(),
                    FrostedCircleButton(
                      icon: Icons.ios_share_rounded,
                      tooltip: context.t.export,
                      iconSize: 20,
                      onTap: () => _exportSheet(context, book),
                    ),
                    const SizedBox(width: 10),
                    FrostedCircleButton(
                      icon: Icons.more_vert_rounded,
                      tooltip: context.t.moreOptions,
                      onTap: () => _bookMenu(context, book),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _addNote(BuildContext context, String bookId) async {
    final note = await context.read<AppState>().addBookNote(bookId);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(cupertinoRoute(NoteEditorScreen(note: note, isNew: true)));
  }

  static Future<void> _editAuthor(BuildContext context, Book book) async {
    final name = await promptForText(
      context,
      title: context.t.bookAuthor,
      hint: context.t.authorHint,
      initial: book.author,
      capitalization: TextCapitalization.words,
    );
    if (name == null || !context.mounted) return;
    book.author = name.trim();
    await context.read<AppState>().updateBook(book);
  }

  static Future<void> _editDescription(
      BuildContext context, Book book) async {
    final text = await promptForText(
      context,
      title: context.t.bookDescription,
      hint: context.t.addDescription,
      initial: book.description,
      minLines: 3,
      maxLines: 6,
    );
    if (text == null || !context.mounted) return;
    book.description = text.trim();
    await context.read<AppState>().updateBook(book);
  }
}

/// A book's workshop notes on their own page — characters, places, plot ideas.
/// Opened from the Notes button beside Read / Add chapter, so the manuscript
/// listing stays uncluttered.
class BookNotesScreen extends StatelessWidget {
  const BookNotesScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notes = state.bookNotes(bookId);

    return FrostedScaffold(
      title: context.t.bookNotesSection,
      actions: [
        FrostedCircleButton(
          icon: Icons.add_rounded,
          tooltip: context.t.bookNoteAdd,
          onTap: () => BookScreen._addNote(context, bookId),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          _NotesList(bookId: bookId, notes: notes),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          color: AppPalette.inkPrimary,
        ),
      );
}

/// The cover, standing on a curved panel of solid colour that scrolls away
/// with it. The cover overlaps the panel's curved bottom edge onto the page.
class _CoverStage extends StatelessWidget {
  const _CoverStage({required this.book, required this.panelColor});

  final Book book;
  final Color panelColor;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final width = MediaQuery.of(context).size.width;
    final coverWidth = width * 0.5;
    final coverHeight = coverWidth * 1.5;
    // Clear the pinned back / share / more chrome, then the cover.
    final coverTop = topInset + 80;
    // The panel's convex curve dips to about three-quarters down the cover, so
    // the cover's foot crosses onto the page below it.
    final panelHeight = coverTop + coverHeight * 0.74;

    return SizedBox(
      height: coverTop + coverHeight + 26,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: panelHeight,
            child: ClipPath(
              clipper: _CurvedBottomClipper(),
              child: ColoredBox(color: panelColor),
            ),
          ),
          Positioned(
            top: coverTop,
            left: (width - coverWidth) / 2,
            width: coverWidth,
            height: coverHeight,
            // The cover itself: a standing book with a deep, soft shadow.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 34,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (book.coverPath != null)
                      Image.file(File(book.coverPath!),
                          fit: BoxFit.cover,
                          cacheWidth: 720,
                          errorBuilder: (_, _, _) => BookCoverArt(book: book))
                    else
                      BookCoverArt(book: book),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 7,
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.20)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The book view's scroll behaviour: clamped physics with the Android stretch
/// overscroll, overriding the app's global springy bounce. Bouncing slid the
/// coloured cover panel down and exposed the page colour above it; clamping
/// keeps the panel pinned to the top edge while still giving the stretch pull.
class _StretchScrollBehavior extends MaterialScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// A solid panel with a gently convex (bulging-down) bottom edge — the curved
/// header behind the book cover.
class _CurvedBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const dip = 34.0;
    return Path()
      ..lineTo(0, size.height - dip)
      ..quadraticBezierTo(
          size.width / 2, size.height + dip, size.width, size.height - dip)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// The Contents section: a "Reorder" toggle beside the title, and the page
/// list below. Long-press on a chapter opens its options, so reordering is an
/// explicit mode with drag handles rather than a hidden long-press-drag.
class _ContentsSection extends StatefulWidget {
  const _ContentsSection({required this.bookId, required this.pages});

  final String bookId;
  final List<Note> pages;

  @override
  State<_ContentsSection> createState() => _ContentsSectionState();
}

class _ContentsSectionState extends State<_ContentsSection> {
  bool _reordering = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _SectionTitle(context.t.contentsSection),
            const Spacer(),
            _ReorderToggle(
              active: _reordering,
              onTap: () => setState(() => _reordering = !_reordering),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _PageList(
          bookId: widget.bookId,
          pages: widget.pages,
          reordering: _reordering,
        ),
      ],
    );
  }
}

/// A small pill that toggles reorder mode: "Reorder" → "Done".
class _ReorderToggle extends StatelessWidget {
  const _ReorderToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = AppPalette.scheme;
    return Material(
      color: active ? scheme.primary : AppPalette.bubbleGlass,
      shape: StadiumBorder(
        side: active
            ? BorderSide.none
            : BorderSide(color: AppPalette.cardOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? Icons.check_rounded : Icons.swap_vert_rounded,
                  size: 15,
                  color: active ? scheme.onPrimary : AppPalette.inkPrimary),
              const SizedBox(width: 5),
              Text(
                active ? context.t.done : context.t.reorder,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? scheme.onPrimary : AppPalette.inkPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reorderable list of pages, each with its word count and status tag.
/// In [reordering] mode each row shows an explicit drag handle; otherwise the
/// rows are tappable (open) and long-pressable (options menu).
class _PageList extends StatelessWidget {
  const _PageList({
    required this.bookId,
    required this.pages,
    this.reordering = false,
  });

  final String bookId;
  final List<Note> pages;
  final bool reordering;

  IconData _icon(String kind) => switch (kind) {
        BookPageKind.contents => Icons.toc_rounded,
        BookPageKind.intro => Icons.article_outlined,
        BookPageKind.dedication => Icons.favorite_outline_rounded,
        BookPageKind.epigraph => Icons.format_quote_rounded,
        BookPageKind.acknowledgements => Icons.handshake_outlined,
        _ => Icons.menu_book_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Drag only via the explicit handle shown in reorder mode, so it never
      // fights the long-press options menu.
      buildDefaultDragHandles: false,
      itemCount: pages.length,
      onReorder: (from, to) =>
          context.read<AppState>().reorderBookPages(bookId, from, to),
      itemBuilder: (context, i) {
        final page = pages[i];
        return Padding(
          key: ValueKey(page.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _PageRow(
            icon: _icon(page.bookPageKind),
            title: page.title.trim().isEmpty
                ? context.t.untitledEntry
                : page.title,
            words: page.wordCount,
            target: page.targetWords,
            linkedNotes: state.bookNotesForPage(page.id).length,
            status: page.bookStatus,
            isContents: page.bookPageKind == BookPageKind.contents,
            onTap: reordering
                ? null
                : () {
                    if (page.bookPageKind == BookPageKind.contents) {
                      Navigator.of(context)
                          .push(cupertinoRoute(ContentsScreen(bookId: bookId)));
                    } else {
                      Navigator.of(context).push(cupertinoRoute(
                          NoteEditorScreen(note: page, isNew: false)));
                    }
                  },
            onLongPress:
                reordering || page.bookPageKind == BookPageKind.contents
                    ? null
                    : () => _pageMenu(context, page),
            dragHandle: reordering
                ? ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.drag_handle_rounded,
                          color: AppPalette.inkSecondary),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _pageMenu(BuildContext context, Note page) async {
    final t = context.t;
    final labels = {
      BookPageStatus.none: t.statusNone,
      BookPageStatus.draft: t.statusDraft,
      BookPageStatus.revised: t.statusRevised,
      BookPageStatus.finished: t.statusFinal,
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(t.chapterStatus,
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary)),
                  ),
                ),
                for (final s in BookPageStatus.all)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      s == BookPageStatus.none
                          ? Icons.label_off_outlined
                          : Icons.label_outline_rounded,
                      color: AppPalette.inkSecondary,
                    ),
                    title: Text(labels[s]!),
                    trailing: page.bookStatus == s
                        ? Icon(Icons.check_rounded,
                            color: AppPalette.inkPrimary)
                        : null,
                    onTap: () => Navigator.pop(context, 'status:$s'),
                  ),
                Divider(color: AppPalette.cardOutline, height: 10),
                ListTile(
                  leading: Icon(Icons.flag_outlined,
                      color: AppPalette.inkSecondary),
                  title: Text(t.wordTarget),
                  subtitle: page.targetWords > 0
                      ? Text(t.wordsCount(page.targetWords),
                          style: TextStyle(color: AppPalette.inkSecondary))
                      : null,
                  onTap: () => Navigator.pop(context, 'target'),
                ),
                Divider(color: AppPalette.cardOutline, height: 10),
                ListTile(
                  leading: Icon(Icons.history_rounded,
                      color: AppPalette.inkSecondary),
                  title: Text(t.versionHistory),
                  subtitle: page.history.isNotEmpty
                      ? Text(t.versionsSaved(page.history.length),
                          style: TextStyle(color: AppPalette.inkSecondary))
                      : null,
                  onTap: () => Navigator.pop(context, 'history'),
                ),
                Divider(color: AppPalette.cardOutline, height: 10),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFE0567B)),
                  title: Text(t.deletePage),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final state = context.read<AppState>();
    if (choice == 'delete') {
      await state.deleteBookPage(page.id);
    } else if (choice.startsWith('status:')) {
      await state.setBookPageStatus(page.id, choice.substring(7));
    } else if (choice == 'target') {
      await _editTarget(context, page);
    } else if (choice == 'history') {
      Navigator.of(context)
          .push(cupertinoRoute(ChapterHistoryScreen(noteId: page.id)));
    }
  }

  Future<void> _editTarget(BuildContext context, Note page) async {
    final result = await promptForText(
      context,
      title: context.t.wordTarget,
      hint: context.t.wordTargetHint,
      initial: page.targetWords > 0 ? '${page.targetWords}' : '',
      keyboardType: TextInputType.number,
    );
    if (result == null || !context.mounted) return;
    final n = int.tryParse(result.trim()) ?? 0;
    await context.read<AppState>().setBookPageTarget(page.id, n);
  }
}

/// The book's workshop notes — characters, plot ideas — shown under the
/// contents but kept out of the manuscript.
class _NotesList extends StatelessWidget {
  const _NotesList({required this.bookId, required this.notes});

  final String bookId;
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          context.t.bookNotesEmpty,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppPalette.inkSecondary.withValues(alpha: 0.75),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NoteCard(note: note, bookId: bookId),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.bookId});

  final Note note;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final title = note.title.trim().isEmpty
        ? context.t.bookNoteUntitled
        : note.title.trim();
    final preview = note.textPreview.trim().replaceAll('\n', '  ');
    final linkedPage = note.linkedPageId == null
        ? null
        : context.read<AppState>().bookPageById(bookId, note.linkedPageId!);
    final linkedTitle = linkedPage == null
        ? null
        : (linkedPage.title.trim().isEmpty
            ? context.t.untitledEntry
            : linkedPage.title.trim());
    return Material(
      color: AppPalette.cardSolid,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
            cupertinoRoute(NoteEditorScreen(note: note, isNew: false))),
        onLongPress: () => _noteMenu(context, note),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
          child: Row(
            children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 20, color: AppPalette.inkSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: AppPalette.inkSecondary),
                      ),
                    ],
                    if (linkedTitle != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 13,
                              color: AppPalette.scheme.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              linkedTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _noteMenu(BuildContext context, Note note) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      Icon(Icons.link_rounded, color: AppPalette.inkPrimary),
                  title: Text(context.t.linkToChapter),
                  onTap: () => Navigator.pop(context, 'link'),
                ),
                if (note.linkedPageId != null)
                  ListTile(
                    leading: Icon(Icons.link_off_rounded,
                        color: AppPalette.inkPrimary),
                    title: Text(context.t.unlink),
                    onTap: () => Navigator.pop(context, 'unlink'),
                  ),
                Divider(color: AppPalette.cardOutline, height: 10),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFE0567B)),
                  title: Text(context.t.bookNoteDelete),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    final state = context.read<AppState>();
    switch (choice) {
      case 'delete':
        await state.deleteBookPage(note.id);
      case 'unlink':
        await state.setBookNoteLink(note.id, null);
      case 'link':
        await _pickChapter(context, note);
    }
  }

  Future<void> _pickChapter(BuildContext context, Note note) async {
    final state = context.read<AppState>();
    // Any manuscript page can be a link target except the Contents index.
    final pages = state
        .bookPages(bookId)
        .where((p) => p.bookPageKind != BookPageKind.contents)
        .toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(context.t.linkToChapter,
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary)),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in pages)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.menu_book_outlined,
                              color: AppPalette.inkSecondary),
                          title: Text(p.title.trim().isEmpty
                              ? context.t.untitledEntry
                              : p.title.trim()),
                          trailing: note.linkedPageId == p.id
                              ? Icon(Icons.check_rounded,
                                  color: AppPalette.inkPrimary)
                              : null,
                          onTap: () => Navigator.pop(context, p.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await context.read<AppState>().setBookNoteLink(note.id, choice);
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.icon,
    required this.title,
    required this.words,
    required this.status,
    required this.isContents,
    required this.onTap,
    this.target = 0,
    this.linkedNotes = 0,
    this.onLongPress,
    this.dragHandle,
  });

  final IconData icon;
  final String title;
  final int words;
  final int target;
  final int linkedNotes;
  final String status;
  final bool isContents;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Shown at the trailing edge in reorder mode (replaces the status tag).
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final hasTarget = target > 0 && !isContents;
    final progress = hasTarget ? (words / target).clamp(0.0, 1.0) : 0.0;
    final reached = hasTarget && words >= target;
    final barColor =
        reached ? const Color(0xFF2FA36B) : AppPalette.scheme.primary;
    return Material(
      color: AppPalette.cardSolid,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppPalette.inkSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    if (!isContents) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            hasTarget
                                ? '$words / $target'
                                : context.t.wordsCount(words),
                            style: TextStyle(
                                fontSize: 12, color: AppPalette.inkSecondary),
                          ),
                          if (linkedNotes > 0) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.sticky_note_2_outlined,
                                size: 13, color: AppPalette.inkSecondary),
                            const SizedBox(width: 3),
                            Text('$linkedNotes',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.inkSecondary)),
                          ],
                        ],
                      ),
                      if (hasTarget) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: AppPalette.cardOutline,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (dragHandle != null)
                dragHandle!
              else if (status.isNotEmpty)
                _StatusTag(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BookPageStatus.draft => (context.t.statusDraft, const Color(0xFFEBA23C)),
      BookPageStatus.revised => (
          context.t.statusRevised,
          const Color(0xFF6C8CFF)
        ),
      _ => (context.t.statusFinal, const Color(0xFF2FA36B)),
    };
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ---- Contents page ---------------------------------------------------------

/// The Contents page: an editable, reorderable list of the book's pages whose
/// titles are the real page titles — edit here and the chapter changes too.
class ContentsScreen extends StatelessWidget {
  const ContentsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final all = state.bookPages(bookId);
    // Everything except the Contents page itself.
    final pages =
        all.where((p) => p.bookPageKind != BookPageKind.contents).toList();
    // Offset so reorder indices map back onto the full page list.
    final offset = all.length - pages.length;

    return FrostedScaffold(
      title: context.t.contentsPage,
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        itemCount: pages.length,
        onReorder: (from, to) => context
            .read<AppState>()
            .reorderBookPages(bookId, from + offset, to + offset),
        itemBuilder: (context, i) => Padding(
          key: ValueKey(pages[i].id),
          padding: const EdgeInsets.only(bottom: 12),
          child: _ContentsRow(index: i + 1, page: pages[i]),
        ),
      ),
    );
  }
}

class _ContentsRow extends StatefulWidget {
  const _ContentsRow({required this.index, required this.page});

  final int index;
  final Note page;

  @override
  State<_ContentsRow> createState() => _ContentsRowState();
}

class _ContentsRowState extends State<_ContentsRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.page.title);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _ContentsRow old) {
    super.didUpdateWidget(old);
    // Reflect a rename made from the chapter editor, unless being edited here.
    if (!_focus.hasFocus && _ctrl.text != widget.page.title) {
      _ctrl.text = widget.page.title;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    context.read<AppState>().setBookPageTitle(widget.page.id, _ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${widget.index}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppPalette.inkSecondary,
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) {
              _focus.unfocus();
              _commit();
            },
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppPalette.inkPrimary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: UnderlineInputBorder(),
            ),
          ),
        ),
        Icon(Icons.drag_handle_rounded, color: AppPalette.inkSecondary),
      ],
    );
  }
}

// ---- Book menu + export ----------------------------------------------------

Future<void> _bookMenu(BuildContext context, Book book) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              ListTile(
                leading:
                    Icon(Icons.edit_rounded, color: AppPalette.inkPrimary),
                title: Text(context.t.renameBook),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.person_outline_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.bookAuthor),
                onTap: () => Navigator.pop(context, 'author'),
              ),
              ListTile(
                leading: Icon(Icons.notes_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.editDescription),
                onTap: () => Navigator.pop(context, 'description'),
              ),
              ListTile(
                leading: Icon(Icons.text_fields_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.bookFont),
                subtitle: Text(BookFonts.label(book.fontFamily),
                    style: TextStyle(color: AppPalette.inkSecondary)),
                onTap: () => Navigator.pop(context, 'font'),
              ),
              ListTile(
                leading: Icon(Icons.post_add_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.addFrontBackMatter),
                onTap: () => Navigator.pop(context, 'matter'),
              ),
              ListTile(
                leading: Icon(Icons.find_replace_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.findAndReplace),
                onTap: () => Navigator.pop(context, 'findreplace'),
              ),
              ListTile(
                leading:
                    Icon(Icons.image_outlined, color: AppPalette.inkPrimary),
                title: Text(context.t.changeCover),
                onTap: () => Navigator.pop(context, 'cover'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFE0567B)),
                title: Text(context.t.deleteBook),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  final state = context.read<AppState>();
  switch (choice) {
    case 'rename':
      final name = await promptForText(
        context,
        title: context.t.renameBook,
        initial: book.title,
      );
      if (name != null) {
        book.title = name.trim();
        await state.updateBook(book);
      }
    case 'author':
      if (context.mounted) await BookScreen._editAuthor(context, book);
    case 'description':
      if (context.mounted) await BookScreen._editDescription(context, book);
    case 'font':
      if (context.mounted) await showBookFontSheet(context, book);
    case 'matter':
      if (context.mounted) await _addMatterSheet(context, book.id);
    case 'findreplace':
      if (context.mounted) {
        Navigator.of(context)
            .push(cupertinoRoute(BookFindReplaceScreen(bookId: book.id)));
      }
    case 'cover':
      final path = await ImageService.pickSingle();
      if (path != null) {
        book.coverPath = path;
        await state.updateBook(book);
      }
    case 'delete':
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(context.t.deleteBook),
          content: Text(context.t.confirmDeleteBook),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.scheme.error,
                  foregroundColor: AppPalette.scheme.onError),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.delete),
            ),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        await state.deleteBook(book.id);
        if (context.mounted) Navigator.pop(context);
      }
  }
}

/// The label for a book-page kind (front/back matter), for menus and defaults.
String bookMatterLabel(BuildContext context, String kind) => switch (kind) {
      BookPageKind.dedication => context.t.matterDedication,
      BookPageKind.epigraph => context.t.matterEpigraph,
      BookPageKind.acknowledgements => context.t.matterAcknowledgements,
      _ => context.t.addPage,
    };

/// Offers the front/back-matter kinds; the chosen one is appended to the book
/// and opened for writing. The writer drags it into place from the Contents.
Future<void> _addMatterSheet(BuildContext context, String bookId) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.t.addFrontBackMatter,
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary)),
                ),
              ),
              for (final kind in BookPageKind.matter)
                ListTile(
                  leading: Icon(
                    switch (kind) {
                      BookPageKind.dedication =>
                        Icons.favorite_outline_rounded,
                      BookPageKind.epigraph => Icons.format_quote_rounded,
                      _ => Icons.handshake_outlined,
                    },
                    color: AppPalette.inkPrimary,
                  ),
                  title: Text(bookMatterLabel(context, kind)),
                  onTap: () => Navigator.pop(context, kind),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final page = await context
      .read<AppState>()
      .addBookMatter(bookId, kind, bookMatterLabel(context, kind));
  if (!context.mounted) return;
  Navigator.of(context)
      .push(cupertinoRoute(NoteEditorScreen(note: page, isNew: true)));
}

/// A picker for the book's typeface. Choosing one applies it book-wide — to
/// every chapter's editor and the reader — via [AppState.setBookFont].
Future<void> showBookFontSheet(BuildContext context, Book book) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.t.bookFontTitle,
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary)),
                ),
              ),
              for (final family in BookFonts.all)
                ListTile(
                  title: Text(
                    BookFonts.label(family),
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: 18,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                  subtitle: Text(
                    context.t.bookFontSample,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: 14,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                  trailing: book.fontFamily == family
                      ? Icon(Icons.check_rounded, color: AppPalette.inkPrimary)
                      : null,
                  onTap: () => Navigator.pop(context, family),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await context.read<AppState>().setBookFont(book.id, choice);
}

Future<void> _exportSheet(BuildContext context, Book book) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(context.t.export,
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary)),
                ),
              ),
              ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.exportPdf),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
              ListTile(
                leading: Icon(Icons.menu_book_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.exportEpub),
                onTap: () => Navigator.pop(context, 'epub'),
              ),
              ListTile(
                leading:
                    Icon(Icons.description_outlined,
                        color: AppPalette.inkPrimary),
                title: Text(context.t.exportMarkdown),
                onTap: () => Navigator.pop(context, 'md'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (format == null || !context.mounted) return;

  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final errorText = context.t.somethingWrong;
  final untitled = context.t.untitledBook;
  final contentsLabel = context.t.contentsPage;
  final pages = state.bookPages(book.id);
  final author = book.author.trim().isNotEmpty
      ? book.author.trim()
      : (state.accountName ?? state.accountEmail ?? '');

  try {
    switch (format) {
      case 'pdf':
        await BookExport.sharePdf(
          book: book,
          pages: pages,
          author: author,
          untitledLabel: untitled,
          contentsLabel: contentsLabel,
        );
      case 'epub':
        await BookExport.shareEpub(
          book: book,
          pages: pages,
          author: author,
          untitledLabel: untitled,
          contentsLabel: contentsLabel,
        );
      case 'md':
        await BookExport.shareMarkdown(
          book: book,
          pages: pages,
          author: author,
          untitledLabel: untitled,
        );
    }
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(errorText)));
  }
}
