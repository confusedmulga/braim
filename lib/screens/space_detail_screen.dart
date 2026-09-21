import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_space_sheet.dart';
import '../widgets/bubble_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import '../widgets/item_actions_sheet.dart';
import '../widgets/note_card.dart';
import '../widgets/sort_button.dart';
import '../widgets/tweet_card_widget.dart';
import 'card_detail_screen.dart';
import 'note_editor_screen.dart';
import 'note_open.dart';

class SpaceDetailScreen extends StatefulWidget {
  const SpaceDetailScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  State<SpaceDetailScreen> createState() => _SpaceDetailScreenState();
}

class _SpaceDetailScreenState extends State<SpaceDetailScreen> {
  String get spaceId => widget.spaceId;

  /// In-folder search: toggled by the magnifier in the bar; filters this
  /// folder's notes and cards live.
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  Future<void> _noteActions(BuildContext context, Note note) async {
    final state = context.read<AppState>();
    await showItemActions(
      context,
      pinned: note.pinned,
      archived: note.archived,
      currentSpaceId: note.spaceId,
      onSetPinned: (p) => state.setNotePinned(note.id, p),
      onSetArchived: (a) => state.setNoteArchived(note.id, a),
      onMove: (spaceId) => state.moveNoteToSpace(note.id, spaceId),
      onDelete: () => state.deleteNote(note.id),
      allowCrypt: !note.inCircuit,
    );
  }

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
    final space = state.spaceById(spaceId);
    if (space == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const AppBackground();
    }
    var notes = state.notesForSpace(spaceId);
    var cards = state.cardsForSpace(spaceId);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      notes = notes
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.textPreview.toLowerCase().contains(q))
          .toList();
      cards = cards
          .where((c) =>
              c.noteTitle.toLowerCase().contains(q) ||
              c.text.toLowerCase().contains(q) ||
              c.authorName.toLowerCase().contains(q) ||
              c.url.toLowerCase().contains(q))
          .toList();
    }

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
                    openBuilder: (_) => noteScreen(n),
                    closedBuilder: (context, open) => NoteCard(
                      note: n,
                      space: space,
                      onTap: open,
                      onLongPress: () => _noteActions(context, n),
                    ),
                  ),
                ),
            ],
          ),
        );

    final cardLeft = <TweetCard>[];
    final cardRight = <TweetCard>[];
    for (var i = 0; i < cards.length; i++) {
      (i.isEven ? cardLeft : cardRight).add(cards[i]);
    }

    Widget cardColumn(List<TweetCard> items) => Expanded(
          child: Column(
            children: [
              for (final c in items)
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: GlassMorph(
                    key: ValueKey(c.id),
                    closedRadius: 18,
                    openBuilder: (_) => CardDetailScreen(card: c),
                    closedBuilder: (context, open) => CompactCardTile(
                      card: c,
                      onTap: open,
                      onLongPress: () => _cardActions(context, c),
                    ),
                  ),
                ),
            ],
          ),
        );

    // The feed content, shared by the plain and cover-header layouts.
    final sections = <Widget>[
      if (_searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppPalette.bubbleGlass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    size: 18, color: AppPalette.inkSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(
                        fontSize: 14, color: AppPalette.inkPrimary),
                    cursorColor: AppPalette.inkPrimary,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.t.searchThisFolder,
                      hintStyle: TextStyle(
                          fontSize: 14, color: AppPalette.inkSecondary),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (q.isNotEmpty && notes.isEmpty && cards.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 26, 6, 0),
          child: Center(
            child: Text(context.t.noMatches,
                style: TextStyle(color: AppPalette.inkSecondary)),
          ),
        ),
      if (notes.isNotEmpty)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [column(left), column(right)],
        ),
      if (cards.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
          child: Text(
            context.t.sectionCards,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: AppPalette.inkSecondary,
            ),
          ),
        ),
        // Cards inside folders always use the compact Blocks style.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [cardColumn(cardLeft), cardColumn(cardRight)],
        ),
      ],
    ];

    // While searching, the sections always render (they hold the search bar
    // and the no-matches note), so the empty-folder placeholder stays out.
    final isEmpty = !_searching && notes.isEmpty && cards.isEmpty;
    final cover = space.thumbnailPath;
    final hasCover = cover != null && cover.isNotEmpty;
    final searchButton = FrostedCircleButton(
      tooltip: context.t.searchThisFolder,
      icon: _searching ? Icons.close_rounded : Icons.search_rounded,
      onTap: _toggleSearch,
      // Press and hold to sort this folder — the same options as the Home feed.
      onLongPress: _searching ? null : () => showSortSheet(context),
    );

    final fab = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BubbleButton(
          icon: Icons.playlist_add_rounded,
          tooltip: context.t.addExisting,
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
          closedBuilder: (context, open) => BubbleButton(
              icon: Icons.edit_rounded,
              tooltip: context.t.newNote,
              onTap: open),
        ),
      ],
    );

    // Without a cover: the plain titled screen with the standard chrome. The
    // feed scrolls *under* the pinned back/title/search row and fades out into
    // it, so the ragged tops of the two columns tuck cleanly under the header
    // instead of butting against it.
    if (!hasCover) {
      final topInset = MediaQuery.of(context).padding.top;
      final chromeHeight = topInset + 16 + FrostedCircleButton.size;
      return FrostedScaffold(
        title: space.name,
        actions: [searchButton],
        floatingActionButton: fab,
        bodyUnderChrome: true,
        body: isEmpty
            ? Padding(
                padding: EdgeInsets.only(top: chromeHeight),
                child: _emptyBody(context),
              )
            : TopFade(
                height: chromeHeight,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(14, chromeHeight + 4, 14, 120),
                  children: sections,
                ),
              ),
      );
    }

    // With a cover photo: the Twitter-style collapsing header, with the same
    // pinned frosted chrome (back + search) floating over it.
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: fab,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                _CoverHeader(name: space.name, imagePath: cover),
                if (isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyBody(context),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(sections),
                    ),
                  ),
              ],
            ),
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
                      const FrostedBackButton(),
                      const Spacer(),
                      searchButton,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 56, color: AppPalette.inkSecondary),
          const SizedBox(height: 12),
          Text(context.t.nothingInFolder,
              style: TextStyle(color: AppPalette.inkSecondary)),
          const SizedBox(height: 4),
          Text(context.t.useButtonsToAdd,
              style: TextStyle(
                  color: AppPalette.inkSecondary, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// A collapsing cover-photo header for a folder that has a thumbnail: the image
/// fills an expanded app bar and tucks up into the toolbar as the feed scrolls.
/// The back and search chrome is a pinned frosted overlay above it, so the bar
/// itself carries neither a leading nor actions.
class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.name, required this.imagePath});

  final String name;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 210,
      pinned: true,
      stretch: true,
      automaticallyImplyLeading: false,
      foregroundColor: Colors.white,
      // The collapsed bar is as tall as the floating back/search bubbles plus an
      // 8px gap top and bottom (SafeArea + 8 above the 50px bubble, matched
      // below), so the dark strip closes symmetrically around them instead of
      // ending mid-button.
      toolbarHeight: FrostedCircleButton.size + 16,
      // Dark bar so that once the photo scrolls away on full collapse, the
      // white title and back arrow stay legible (over both themes).
      backgroundColor: const Color(0xF21A1B22),
      // The header photo is dark-scrimmed, so light status icons over it.
      systemOverlayStyle: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      flexibleSpace: FlexibleSpaceBar(
        // Centre the title and reserve the 50px back/search bubbles' width
        // (14 lead + 50) on both sides, so on collapse it settles between the
        // two buttons instead of sliding up behind the back arrow.
        centerTitle: true,
        titlePadding:
            const EdgeInsetsDirectional.only(start: 64, end: 64, bottom: 20),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
          ),
        ),
        // Pin (not parallax) so the cover photo stays behind the bar as it
        // collapses — the white title + scrim then stay legible instead of
        // landing on the light sheet.
        collapseMode: CollapseMode.pin,
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              cacheWidth: 1080,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: AppPalette.sheet),
            ),
            // Scrim top + bottom so the white title and status bar stay legible
            // whether the header is expanded or collapsed.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x73000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
