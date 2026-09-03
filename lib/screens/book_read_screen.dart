import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/annotation.dart';
import '../models/book.dart';
import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/text_prompt.dart';

/// A reading theme: the paper and ink a book is read on.
class ReaderTheme {
  const ReaderTheme(this.id, this.label, this.paper, this.ink, this.bold);

  final String id;
  final String label;
  final Color paper;
  final Color ink;

  /// Whether the body sets in a heavier weight.
  final bool bold;

  static const original =
      ReaderTheme('original', 'Original', Color(0xFFFFFFFF), Color(0xFF16171A), false);
  static const quiet =
      ReaderTheme('quiet', 'Quiet', Color(0xFF15161A), Color(0xFFD7D8DC), false);
  static const paperTheme =
      ReaderTheme('paper', 'Paper', Color(0xFFF3F1EA), Color(0xFF2B2A26), false);
  static const boldTheme =
      ReaderTheme('bold', 'Bold', Color(0xFFFFFFFF), Color(0xFF000000), true);
  static const calm =
      ReaderTheme('calm', 'Calm', Color(0xFFF6E7CE), Color(0xFF4A3A25), false);
  static const focus =
      ReaderTheme('focus', 'Focus', Color(0xFFE8F1E4), Color(0xFF25352A), false);

  static const all = [original, quiet, paperTheme, boldTheme, calm, focus];

  static ReaderTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => original);
}

/// The whole book in one scroll: reading themes, type controls, a contents
/// jump, highlights and margin notes, and a live page counter in the footer.
class BookReadScreen extends StatefulWidget {
  const BookReadScreen({super.key, required this.bookId});

  final String bookId;

  @override
  State<BookReadScreen> createState() => _BookReadScreenState();
}

class _BookReadScreenState extends State<BookReadScreen> {
  final _scroll = ScrollController();

  /// Anchors for the contents jump, one per page.
  final Map<String, GlobalKey> _anchors = {};

  // Current (page, total-pages), tracked without setState: updating a
  // ValueNotifier lets only the tiny page counter and chapter hint rebuild.
  // Calling setState here instead rebuilt the whole non-lazy reader whenever a
  // page boundary was crossed, which interrupted the in-flight scroll — that
  // was the "can't scroll past the first screen" bug.
  final ValueNotifier<(int page, int pages)> _prog = ValueNotifier((1, 1));

  /// The live selection, tracked from the region so the reading menu knows
  /// what was picked. Region-based selection (SelectionArea) is used instead
  /// of per-page SelectableText so a drag scrolls the page rather than being
  /// eaten as a text selection.
  String _selectedText = '';
  List<Note> _readerPages = const [];

  // Raw-pointer tap detection for the chrome toggle: a GestureDetector.onTap
  // loses the arena to SelectionArea, so a Listener watches pointers directly
  // and treats a quick, still press as a tap (a drag scrolls, a long press
  // selects — neither toggles the chrome).
  Offset _downPos = Offset.zero;
  int _downMs = 0;

  /// Chrome hides while reading and returns on a tap.
  bool _chrome = true;

  // Resume: the read position is saved as a 0–1 fraction and restored on open.
  late AppState _state;
  double _lastFraction = 0;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = context.read<AppState>();
  }

  @override
  void dispose() {
    // Remember where the reader left off (fire-and-forget; the write is
    // debounced and the fraction survives font/content changes).
    _state.setReaderPosition(widget.bookId, _lastFraction);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _prog.dispose();
    super.dispose();
  }

  /// Jumps to the saved position once the content is laid out. Retries a few
  /// frames while the extent is still zero (long chapters lay out lazily).
  void _restore([int tries = 0]) {
    if (_restored || !mounted) return;
    if (!_scroll.hasClients) {
      if (tries < 8) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _restore(tries + 1));
      }
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    final frac = _state.readerPosition(widget.bookId);
    if (max <= 0 && frac > 0 && tries < 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore(tries + 1));
      return;
    }
    _restored = true;
    if (frac > 0 && max > 0) _scroll.jumpTo((frac * max).clamp(0.0, max));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    if (view <= 0) return;
    final max = _scroll.position.maxScrollExtent;
    _lastFraction = max > 0 ? (_scroll.offset / max).clamp(0.0, 1.0) : 0;
    final total = max + view;
    final pages = (total / view).ceil().clamp(1, 99999);
    final page = ((_scroll.offset / view).floor() + 1).clamp(1, pages);
    if (_prog.value != (page, pages)) _prog.value = (page, pages);
  }

  static double _progressOf((int, int) v) => v.$2 <= 1 ? 1 : v.$1 / v.$2;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.bookById(widget.bookId);
    if (book == null) return const SizedBox.shrink();
    final pages = state
        .bookPages(widget.bookId)
        .where((p) => p.bookPageKind != BookPageKind.contents)
        .toList();
    _readerPages = pages;
    final theme = ReaderTheme.byId(state.readerTheme);
    final scale = state.readerFontScale;
    // The book is read in its own chosen face, so the type is consistent with
    // how it's written and the choice travels with the book.
    final family = book.fontFamily;

    final bodyStyle = TextStyle(
      fontFamily: family,
      fontSize: (family == 'Caveat' ? 22 : 17) * scale,
      height: 1.65,
      fontWeight: theme.bold ? FontWeight.w600 : FontWeight.w400,
      color: theme.ink,
    );

    return Scaffold(
      backgroundColor: theme.paper,
      body: SafeArea(
        child: Stack(
          children: [
            // The book itself.
            // Region-based selection so a drag scrolls the page instead of
            // being captured as a text selection (per-page SelectableText was
            // eating the scroll gesture). A raw-pointer Listener keeps the
            // tap-to-toggle-chrome working alongside it.
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _downPos = e.position;
                _downMs = DateTime.now().millisecondsSinceEpoch;
              },
              onPointerUp: (e) {
                final moved = (e.position - _downPos).distance;
                final elapsed =
                    DateTime.now().millisecondsSinceEpoch - _downMs;
                if (moved < 12 && elapsed < 250) {
                  setState(() => _chrome = !_chrome);
                }
              },
              child: SelectionArea(
                onSelectionChanged: (content) =>
                    _selectedText = content?.plainText ?? '',
                contextMenuBuilder: (context, selectableRegionState) =>
                    _selectionMenu(context, selectableRegionState),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 96),
                  children: [
                    for (final page in pages) ...[
                      KeyedSubtree(
                        key: _anchors.putIfAbsent(page.id, GlobalKey.new),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // A dedication or epigraph reads centred, with no
                            // chapter heading over it.
                            if (!BookPageKind.isQuietMatter(page.bookPageKind))
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 20, bottom: 18),
                                child: Text(
                                  page.title.trim(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: family,
                                    fontSize: 21 * scale,
                                    fontWeight: FontWeight.w700,
                                    color: theme.ink,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 40),
                            _PageText(
                              page: page,
                              style: BookPageKind.isQuietMatter(
                                      page.bookPageKind)
                                  ? bodyStyle.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.ink.withValues(alpha: 0.8))
                                  : bodyStyle,
                              align: BookPageKind.isQuietMatter(
                                      page.bookPageKind)
                                  ? TextAlign.center
                                  : TextAlign.justify,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                    ],
                  ],
                ),
              ),
            ),

            // Top bar.
            AnimatedOpacity(
              opacity: _chrome ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_chrome,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  color: theme.paper.withValues(alpha: 0.94),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 28),
                        color: theme.ink,
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: ValueListenableBuilder<(int, int)>(
                          valueListenable: _prog,
                          builder: (context, v, _) => Text(
                            _chapterHint(context, v),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.ink.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom bar: share, themes & settings, contents.
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                offset: _chrome ? Offset.zero : const Offset(0, 1.4),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.paper,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: theme.ink.withValues(alpha: 0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.t.shareAsPdf,
                          icon: const Icon(Icons.ios_share_rounded, size: 21),
                          color: theme.ink,
                          onPressed: () => _shareBook(context, book, pages),
                        ),
                        IconButton(
                          tooltip: context.t.readerSettings,
                          icon: const Icon(Icons.text_fields_rounded, size: 22),
                          color: theme.ink,
                          onPressed: () => _showSettings(context),
                        ),
                        IconButton(
                          tooltip: context.t.bookmarkThisSpot,
                          icon: const Icon(
                              Icons.bookmark_add_outlined, size: 21),
                          color: theme.ink,
                          onPressed: _addBookmark,
                        ),
                        IconButton(
                          tooltip: context.t.contentsSection,
                          icon: const Icon(Icons.menu_rounded, size: 21),
                          color: theme.ink,
                          onPressed: () =>
                              _showContents(context, book, pages),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Page counter, printed-book style.
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: _chrome ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ValueListenableBuilder<(int, int)>(
                    valueListenable: _prog,
                    builder: (context, v, _) => Text(
                      '${v.$1}',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: theme.ink.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "4 pages left", the way a reader app counts down.
  String _chapterHint(BuildContext context, (int, int) v) {
    final left = (v.$2 - v.$1).clamp(0, 9999);
    return context.t.pagesLeft(left);
  }

  // ---- Selection menu ------------------------------------------------------

  /// The manuscript page a selected passage belongs to (first match wins).
  Note? _pageForText(String text) {
    if (text.isEmpty) return null;
    for (final p in _readerPages) {
      if (p.textPreview.contains(text)) return p;
    }
    return null;
  }

  Widget _selectionMenu(
      BuildContext context, SelectableRegionState regionState) {
    final t = context.t;
    final text = _selectedText.trim();
    final page = _pageForText(text);
    void close() => regionState.hideToolbar();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: regionState.contextMenuAnchors,
      buttonItems: [
        // Note/Highlight only when the passage sits within one known page.
        if (page != null) ...[
          ContextMenuButtonItem(
            label: t.annotateNote,
            onPressed: () {
              close();
              _annotate(context, page, text, withNote: true);
            },
          ),
          ContextMenuButtonItem(
            label: t.annotateHighlight,
            onPressed: () {
              close();
              _annotate(context, page, text, withNote: false);
            },
          ),
        ],
        ContextMenuButtonItem(
          label: t.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            close();
          },
        ),
        ContextMenuButtonItem(
          label: t.translate,
          onPressed: () {
            close();
            _openUrl('https://translate.google.com/?sl=auto&tl=en&text='
                '${Uri.encodeComponent(text)}&op=translate');
          },
        ),
        ContextMenuButtonItem(
          label: t.dictionary,
          onPressed: () {
            close();
            _openUrl('https://www.google.com/search?q=define+'
                '${Uri.encodeComponent(text)}');
          },
        ),
        ContextMenuButtonItem(
          label: t.share,
          onPressed: () {
            close();
            if (text.trim().isNotEmpty) {
              SharePlus.instance.share(ShareParams(text: text));
            }
          },
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing to do: the reader stays put.
    }
  }

  /// Attaches a highlight (and optionally a note) to whichever page contains
  /// the selected passage.
  Future<void> _annotate(BuildContext context, Note page, String text,
      {required bool withNote}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final state = context.read<AppState>();

    var colour = Annotation.palette.first;
    var note = '';
    if (withNote) {
      final result = await promptForText(
        context,
        title: context.t.annotateNote,
        hint: context.t.noteHint,
        minLines: 2,
        maxLines: 5,
        header: Text('"$trimmed"',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppPalette.inkSecondary)),
      );
      if (result == null) return;
      note = result.trim();
    } else if (context.mounted) {
      final picked = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                color: AppPalette.scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in Annotation.palette)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.black.withValues(alpha: 0.15)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (picked == null) return;
      colour = picked;
    }

    await state.addAnnotation(
      page.id,
      Annotation(text: trimmed, note: note, colorValue: colour),
    );
  }

  // ---- Sheets --------------------------------------------------------------

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReaderSettingsSheet(bookId: widget.bookId),
    );
  }

  void _showContents(BuildContext context, Book book, List<Note> pages) {
    var query = '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (sheetContext, setSheet) {
              final q = query.trim().toLowerCase();
              final shown = q.isEmpty
                  ? pages
                  : pages
                      .where((p) => p.title.toLowerCase().contains(q))
                      .toList();
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                      child: Row(
                        children: [
                          Text(context.t.contentsSection,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.inkPrimary)),
                          const Spacer(),
                          Text('${(_progressOf(_prog.value) * 100).round()}%',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppPalette.inkSecondary)),
                        ],
                      ),
                    ),
                    // Jump-to-chapter search: filter the list by title.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: TextField(
                        onChanged: (v) => setSheet(() => query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: context.t.searchChapters,
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final page in shown)
                            ListTile(
                              dense: true,
                              title: Text(page.title.trim().isEmpty
                                  ? context.t.untitledEntry
                                  : page.title.trim()),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _jumpTo(page.id);
                              },
                            ),
                          if (shown.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(context.t.noChaptersMatch,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppPalette.inkSecondary)),
                            ),
                          if (q.isEmpty) ...[
                            Divider(color: AppPalette.cardOutline),
                            ListTile(
                              leading: Icon(Icons.bookmark_border_rounded,
                                  color: AppPalette.inkPrimary),
                              title: Text(context.t.bookmarks),
                              trailing: Text(
                                '${_state.readerBookmarks(widget.bookId).length}',
                                style:
                                    TextStyle(color: AppPalette.inkSecondary),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _showBookmarks(context);
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.format_quote_rounded,
                                  color: AppPalette.inkPrimary),
                              title: Text(context.t.highlightsAndNotes),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _showAnnotations(context, pages);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _jumpTo(String pageId) {
    final key = _anchors[pageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic);
  }

  void _jumpToFraction(double f) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo((f * max).clamp(0.0, max),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic);
  }

  void _addBookmark() {
    _state.addReaderBookmark(widget.bookId, _lastFraction);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.bookmarkAdded)),
    );
  }

  void _showBookmarks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final marks = _state.readerBookmarks(widget.bookId);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppPalette.scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: marks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(sheetContext.t.noBookmarks,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppPalette.inkSecondary)),
                      )
                    : Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final f in marks)
                              ListTile(
                                leading: Icon(Icons.bookmark_rounded,
                                    color: AppPalette.scheme.primary),
                                title: Text(
                                    sheetContext.t.bookmarkAt(
                                        (f * 100).round())),
                                trailing: IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    await _state.removeReaderBookmark(
                                        widget.bookId, f);
                                    setSheet(() {});
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _jumpToFraction(f);
                                },
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAnnotations(BuildContext context, List<Note> pages) {
    final state = context.read<AppState>();
    final items = state.bookAnnotations(widget.bookId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppPalette.scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(26),
            ),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(sheetContext.t.noHighlightsYet,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: AppPalette.inkSecondary)),
                  )
                : Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in items)
                          ListTile(
                            leading: Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: Color(item.annotation.colorValue),
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(item.annotation.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            subtitle: item.annotation.hasNote
                                ? Text(item.annotation.note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () {
                                state.removeAnnotation(
                                    item.page.id, item.annotation.id);
                                Navigator.pop(sheetContext);
                              },
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _jumpTo(item.page.id);
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareBook(
      BuildContext context, Book book, List<Note> pages) async {
    final buffer = StringBuffer('${book.title}\n\n');
    for (final p in pages) {
      buffer.writeln(p.title.trim());
      buffer.writeln(p.textPreview.trim());
      buffer.writeln();
    }
    await SharePlus.instance
        .share(ShareParams(text: buffer.toString(), title: book.title));
  }
}

/// One page's body: text with the reader's highlights painted behind the
/// marked passages. Selection (and its menu) is handled by the enclosing
/// [SelectionArea] so it never competes with the scroll gesture.
class _PageText extends StatelessWidget {
  const _PageText({
    required this.page,
    required this.style,
    this.align = TextAlign.justify,
  });

  final Note page;
  final TextStyle style;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final text = page.textPreview.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    // Find each highlight's span, then paint the text in order.
    final marks = <({int start, int end, Annotation a})>[];
    for (final a in page.annotations) {
      final i = text.indexOf(a.text);
      if (i >= 0) marks.add((start: i, end: i + a.text.length, a: a));
    }
    marks.sort((x, y) => x.start.compareTo(y.start));

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in marks) {
      if (m.start < cursor) continue; // overlapping marks: keep the first
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(
          backgroundColor: Color(m.a.colorValue).withValues(alpha: 0.55),
        ),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: spans, style: style),
      textAlign: align,
    );
  }
}

/// Themes & Settings: type size, face, and the reading themes. The face is
/// the book's own, so changing it here applies book-wide.
class _ReaderSettingsSheet extends StatelessWidget {
  const _ReaderSettingsSheet({required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final bookFont = state.bookById(bookId)?.fontFamily ?? 'Lora';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
          decoration: BoxDecoration(
            color: AppPalette.scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t.readerSettings,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 16),
              // Type size and face.
              Row(
                children: [
                  _RoundAction(
                    child: Text('A',
                        style: TextStyle(
                            fontSize: 14, color: AppPalette.inkPrimary)),
                    onTap: () => context
                        .read<AppState>()
                        .setReaderFontScale(state.readerFontScale - 0.1),
                  ),
                  const SizedBox(width: 10),
                  _RoundAction(
                    child: Text('A',
                        style: TextStyle(
                            fontSize: 21, color: AppPalette.inkPrimary)),
                    onTap: () => context
                        .read<AppState>()
                        .setReaderFontScale(state.readerFontScale + 0.1),
                  ),
                  const Spacer(),
                  // The book's typeface, book-wide. Scrolls if it overflows
                  // the row on a narrow screen.
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          for (final f in BookFonts.all)
                            GestureDetector(
                              onTap: () =>
                                  context.read<AppState>().setBookFont(bookId, f),
                              child: Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: bookFont == f
                                      ? AppPalette.scheme.secondaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: AppPalette.cardOutline),
                                ),
                                child: Text('Aa',
                                    style: TextStyle(
                                        fontFamily: f,
                                        fontSize: 15,
                                        color: AppPalette.inkPrimary)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Reading themes.
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  for (final t in ReaderTheme.all)
                    GestureDetector(
                      onTap: () =>
                          context.read<AppState>().setReaderTheme(t.id),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: state.readerTheme == t.id
                                ? AppPalette.scheme.primary
                                : AppPalette.cardOutline,
                            width: state.readerTheme == t.id ? 2.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Aa',
                                style: TextStyle(
                                  fontFamily: 'Lora',
                                  fontSize: 20,
                                  fontWeight: t.bold
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: t.ink,
                                )),
                            const SizedBox(height: 4),
                            Text(t.label,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: t.ink.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
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

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          child: child,
        ),
      );
}
