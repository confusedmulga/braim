import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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

/// One paragraph or image in the reader's flow, tagged with the chapter it came
/// from so highlights and bookmarks can be anchored to it.
class _Flow {
  _Flow.paragraph({
    required this.runs,
    required this.style,
    required this.align,
    required this.indent,
    required this.topGap,
    required this.pageId,
  })  : isImage = false,
        imagePath = null;

  _Flow.image({
    required this.imagePath,
    required this.topGap,
    required this.pageId,
  })  : isImage = true,
        runs = const [],
        style = null,
        align = TextAlign.start,
        indent = 0;

  final bool isImage;
  final List<RichRun> runs;
  final TextStyle? style;
  final TextAlign align;
  final double indent;
  final double topGap;
  final String? imagePath;
  final String pageId;
}

/// A [TextSpan] for [runs] with each run's inline marks over [base]. Highlighted
/// runs get a fixed dark ink so they stay legible on the light highlight.
TextSpan _runsToSpan(List<RichRun> runs, TextStyle base) => TextSpan(children: [
      for (final r in runs) TextSpan(text: r.text, style: _runStyle(r, base)),
    ]);

TextStyle _runStyle(RichRun r, TextStyle base) {
  var s = base;
  if (r.bold) s = s.copyWith(fontWeight: FontWeight.w700);
  if (r.italic) s = s.copyWith(fontStyle: FontStyle.italic);
  final d = <TextDecoration>[];
  if (r.underline) d.add(TextDecoration.underline);
  if (r.strike) d.add(TextDecoration.lineThrough);
  if (d.isNotEmpty) s = s.copyWith(decoration: TextDecoration.combine(d));
  if (r.highlight) {
    s = s.copyWith(
        backgroundColor: const Color(0xFFFFE082),
        color: const Color(0xFF202124));
  }
  return s;
}

/// The book read chapter-by-chapter in one continuous, scrollable flow, with
/// reading themes, type controls, a contents jump, per-paragraph bookmarks, and
/// highlights & margin notes.
class BookReadScreen extends StatefulWidget {
  const BookReadScreen({super.key, required this.bookId});

  final String bookId;

  @override
  State<BookReadScreen> createState() => _BookReadScreenState();
}

class _BookReadScreenState extends State<BookReadScreen> {
  final ItemScrollController _isc = ItemScrollController();
  final ItemPositionsListener _ipl = ItemPositionsListener.create();

  // (topmost paragraph index, total paragraphs) — only the counter / hint
  // rebuild on scroll, not the whole reader.
  final ValueNotifier<(int index, int total)> _prog = ValueNotifier((0, 1));

  String _selectedText = '';
  List<Note> _readerPages = const [];

  // The flow (paragraphs + images), rebuilt only when something visible
  // changes (type scale, theme, face, or content).
  String _flowsKey = '';
  List<_Flow> _flows = const [];

  // Per chapter: its paragraphs' text joined the way SelectionArea joins a
  // selection (no separator), and where each paragraph starts in that string,
  // so a passage picked across a paragraph break is still found and painted.
  final Map<String, String> _joinedByPage = {};
  final Map<String, List<(int flowIndex, int start)>> _flowStartsByPage = {};
  Map<int, List<({int start, int end, int color})>> _marksByFlow = const {};
  String _marksKey = '';

  Offset _downPos = Offset.zero;
  int _downMs = 0;

  bool _chrome = true;

  late AppState _state;
  bool _restored = false;
  int _restoreIndex = 0;

  /// The last read position as a paragraph fraction (topmost paragraph ÷ total)
  /// — a stable, per-paragraph anchor that survives font/theme changes.
  double _lastFraction = 0;

  @override
  void initState() {
    super.initState();
    _ipl.itemPositions.addListener(_onPositions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = context.read<AppState>();
  }

  @override
  void dispose() {
    _ipl.itemPositions.removeListener(_onPositions);
    _state.setReaderPosition(widget.bookId, _lastFraction);
    _prog.dispose();
    super.dispose();
  }

  void _onPositions() {
    final positions = _ipl.itemPositions.value;
    if (positions.isEmpty || _flows.isEmpty) return;
    // The first paragraph still (partly) on screen is "where we are".
    final visible = positions.where((p) => p.itemTrailingEdge > 0);
    if (visible.isEmpty) return;
    final idx = visible.map((p) => p.index).reduce(math.min);
    _lastFraction = idx / _flows.length;
    final v = (idx, _flows.length);
    if (_prog.value != v) _prog.value = v;
  }

  static double _progressOf((int, int) v) =>
      v.$2 <= 1 ? 1 : (v.$1 / (v.$2 - 1)).clamp(0.0, 1.0);

  int _indexForFraction(double f) =>
      (f.clamp(0.0, 1.0) * (_flows.isEmpty ? 0 : _flows.length))
          .round()
          .clamp(0, _flows.isEmpty ? 0 : _flows.length - 1);

  // ---- Flow building -------------------------------------------------------

  void _ensureFlows(Book book, List<Note> pages, ReaderTheme theme,
      double scale, String family) {
    final rev = pages.fold<int>(
        0,
        (a, p) =>
            a ^ p.id.hashCode ^ p.updatedAt.microsecondsSinceEpoch.hashCode);
    final key = '${book.id}|$scale|${theme.id}|$family|$rev';
    if (key == _flowsKey && _flows.isNotEmpty) return;
    _flows = _buildFlows(book, pages, theme, scale, family);
    _flowsKey = key;
    _joinedByPage.clear();
    _flowStartsByPage.clear();
    final bufs = <String, StringBuffer>{};
    for (var i = 0; i < _flows.length; i++) {
      final f = _flows[i];
      if (f.isImage) continue;
      final buf = bufs.putIfAbsent(f.pageId, StringBuffer.new);
      _flowStartsByPage.putIfAbsent(f.pageId, () => []).add((i, buf.length));
      buf.write(f.runs.map((r) => r.text).join());
    }
    bufs.forEach((id, b) => _joinedByPage[id] = b.toString());
    _marksKey = '';
    if (!_restored) {
      _restored = true;
      _restoreIndex = _indexForFraction(_state.readerPosition(widget.bookId));
    }
  }

  /// A selection's text with any line breaks dropped, so it compares against
  /// the joined chapter text whether or not the platform inserted them.
  static String _selKey(String s) => s.replaceAll('\n', '').replaceAll('\r', '');

  /// Highlight ranges per paragraph, recomputed only when the flow or the
  /// annotations change. An annotation is located in the chapter's joined
  /// text and then cut at paragraph boundaries, so one that spans a break
  /// paints on both paragraphs.
  void _ensureMarks(List<Note> pages) {
    final key = '$_flowsKey|'
        '${pages.map((p) => '${p.id}:${p.annotations.length}').join(',')}';
    if (key == _marksKey) return;
    _marksKey = key;
    final marks = <int, List<({int start, int end, int color})>>{};
    for (final page in pages) {
      final joined = _joinedByPage[page.id];
      final starts = _flowStartsByPage[page.id];
      if (joined == null || starts == null) continue;
      for (final a in page.annotations) {
        final needle = _selKey(a.text);
        if (needle.isEmpty) continue;
        final at = joined.indexOf(needle);
        if (at < 0) continue;
        final end = at + needle.length;
        for (var k = 0; k < starts.length; k++) {
          final (flowIndex, ps) = starts[k];
          final pe = k + 1 < starts.length ? starts[k + 1].$2 : joined.length;
          final s = math.max(at, ps);
          final e = math.min(end, pe);
          if (s < e) {
            (marks[flowIndex] ??= [])
                .add((start: s - ps, end: e - ps, color: a.colorValue));
          }
        }
      }
    }
    for (final l in marks.values) {
      l.sort((x, y) => x.start.compareTo(y.start));
    }
    _marksByFlow = marks;
  }

  List<_Flow> _buildFlows(Book book, List<Note> pages, ReaderTheme theme,
      double scale, String family) {
    final flows = <_Flow>[];
    final baseSize = (family == 'Caveat' ? 22.0 : 17.0) * scale;
    final gap = baseSize * 0.95;

    TextStyle body([Color? color]) => TextStyle(
          fontFamily: family,
          fontSize: baseSize,
          height: 1.65,
          fontWeight: theme.bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? theme.ink,
        );
    TextStyle heading(double factor) => TextStyle(
          fontFamily: family,
          fontSize: baseSize * factor,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: theme.ink,
        );

    for (final page in pages) {
      final quiet = BookPageKind.isQuietMatter(page.bookPageKind);
      if (!quiet) {
        final title = page.title.trim();
        if (title.isNotEmpty) {
          flows.add(_Flow.paragraph(
            runs: [RichRun(title)],
            style: heading(1.4),
            align: TextAlign.center,
            indent: 0,
            topGap: gap * 2.4,
            pageId: page.id,
          ));
        }
      }
      for (final b in page.blocks) {
        if (b.isImage && b.imagePath.isNotEmpty) {
          flows.add(_Flow.image(
              imagePath: b.imagePath, topGap: gap, pageId: page.id));
          continue;
        }
        if (b.isLink && b.url.isNotEmpty) {
          final label = b.linkTitle.isNotEmpty ? b.linkTitle : b.url;
          flows.add(_Flow.paragraph(
            runs: [RichRun(label)],
            style: body(theme.ink.withValues(alpha: 0.85)),
            align: TextAlign.left,
            indent: 0,
            topGap: gap,
            pageId: page.id,
          ));
          continue;
        }
        if (!b.isText) continue;

        final lines = richToStyledLines(b.text);
        var ordinal = 0;
        for (final l in lines) {
          if (l.kind == RichLineKind.ordered) {
            ordinal++;
          } else {
            ordinal = 0;
          }
          final runs = <RichRun>[];
          final marker = _markerFor(l, ordinal);
          if (marker.isNotEmpty) runs.add(RichRun(marker));
          runs.addAll(l.runs.isEmpty ? [RichRun(l.text)] : l.runs);

          TextStyle st;
          var topGap = gap;
          if (l.header == 1) {
            st = heading(1.5);
            topGap = gap * 1.6;
          } else if (l.header == 2) {
            st = heading(1.25);
            topGap = gap * 1.3;
          } else if (l.quote) {
            st = body(theme.ink.withValues(alpha: 0.75))
                .copyWith(fontStyle: FontStyle.italic);
          } else if (quiet) {
            st = body(theme.ink.withValues(alpha: 0.82))
                .copyWith(fontStyle: FontStyle.italic);
          } else if (l.kind == RichLineKind.checkedItem) {
            st = body(theme.ink.withValues(alpha: 0.6))
                .copyWith(decoration: TextDecoration.lineThrough);
          } else {
            st = body();
          }

          final align = _alignFor(l.align) ??
              (quiet
                  ? TextAlign.center
                  : (l.header > 0 ? TextAlign.left : TextAlign.justify));

          flows.add(_Flow.paragraph(
            runs: runs,
            style: st,
            align: align,
            indent: l.indent * 16.0,
            topGap: topGap,
            pageId: page.id,
          ));
        }
      }
    }
    return flows;
  }

  String _markerFor(RichLine l, int ordinal) {
    switch (l.kind) {
      case RichLineKind.bullet:
        return '•   ';
      case RichLineKind.ordered:
        return '$ordinal.   ';
      case RichLineKind.checkedItem:
        return '☑   ';
      case RichLineKind.uncheckedItem:
        return '☐   ';
      default:
        return '';
    }
  }

  TextAlign? _alignFor(String? a) {
    switch (a) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      default:
        return null;
    }
  }

  // ---- Rendering -----------------------------------------------------------

  Widget _element(int index, _Flow f, double maxImageHeight) {
    if (f.isImage) {
      return Padding(
        padding: EdgeInsets.only(top: f.topGap),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxImageHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(f.imagePath!),
              width: double.infinity,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              cacheWidth: 1440,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: f.topGap, left: f.indent),
      child: Text.rich(_spanFor(index, f), textAlign: f.align, style: f.style),
    );
  }

  /// The paragraph's rich text, with any reader annotations painted over the
  /// matching passages (see [_ensureMarks]).
  InlineSpan _spanFor(int index, _Flow f) {
    final marks = _marksByFlow[index];
    if (marks == null || marks.isEmpty) return _runsToSpan(f.runs, f.style!);
    return _highlightedSpan(f.runs, f.style!, marks);
  }

  InlineSpan _highlightedSpan(List<RichRun> runs, TextStyle base,
      List<({int start, int end, int color})> marks) {
    final children = <InlineSpan>[];
    var pos = 0;
    for (final r in runs) {
      final rStart = pos;
      final rEnd = pos + r.text.length;
      pos = rEnd;
      var cur = rStart;
      final runStyle = _runStyle(r, base);
      while (cur < rEnd) {
        ({int start, int end, int color})? cover;
        var nextStart = rEnd;
        for (final m in marks) {
          if (m.start <= cur && cur < m.end) {
            cover = m;
            break;
          }
          if (m.start > cur && m.start < nextStart) nextStart = m.start;
        }
        if (cover != null) {
          final end = math.min(rEnd, cover.end);
          children.add(TextSpan(
            text: r.text.substring(cur - rStart, end - rStart),
            style: runStyle.copyWith(
                backgroundColor: Color(cover.color).withValues(alpha: 0.5)),
          ));
          cur = end;
        } else {
          children.add(TextSpan(
            text: r.text.substring(cur - rStart, nextStart - rStart),
            style: runStyle,
          ));
          cur = nextStart;
        }
      }
    }
    return TextSpan(children: children);
  }

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
    final family = book.fontFamily;
    _ensureFlows(book, pages, theme, scale, family);
    _ensureMarks(pages);

    final maxImageHeight = MediaQuery.of(context).size.height * 0.66;

    return Scaffold(
      backgroundColor: theme.paper,
      body: SafeArea(
        child: Stack(
          children: [
            // The book, chapter after chapter in one scroll.
            Positioned.fill(
              child: Listener(
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
                  contextMenuBuilder: (context, regionState) =>
                      _selectionMenu(context, regionState),
                  child: _flows.isEmpty
                      ? const SizedBox.shrink()
                      : ScrollablePositionedList.builder(
                          itemScrollController: _isc,
                          itemPositionsListener: _ipl,
                          initialScrollIndex: _restoreIndex,
                          padding:
                              const EdgeInsets.fromLTRB(26, 44, 26, 96),
                          itemCount: _flows.length,
                          itemBuilder: (ctx, i) =>
                              _element(i, _flows[i], maxImageHeight),
                        ),
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
                            '${(_progressOf(v) * 100).round()}%',
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

            // Bottom bar: share, themes & settings, bookmark, contents.
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

            // Progress readout, printed-book style.
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
                      '${(_progressOf(v) * 100).round()}%',
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

  // ---- Selection menu ------------------------------------------------------

  /// The manuscript page a selected passage belongs to (first match wins).
  /// Matched against the chapter's paragraphs joined the way SelectionArea
  /// joins a selection, so a passage picked across a paragraph break resolves.
  Note? _pageForText(String text) {
    final needle = _selKey(text);
    if (needle.isEmpty) return null;
    for (final p in _readerPages) {
      final joined = _joinedByPage[p.id];
      if (joined != null && joined.contains(needle)) return p;
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
        if (page != null) ...[
          ContextMenuButtonItem(
            label: t.annotateNote,
            onPressed: () {
              // Drop the live selection first so its overlay stops competing
              // with the sheet for taps.
              regionState.clearSelection();
              _annotate(page, text, withNote: true);
            },
          ),
          ContextMenuButtonItem(
            label: t.annotateHighlight,
            onPressed: () {
              regionState.clearSelection();
              _annotate(page, text, withNote: false);
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
      // Nothing else to do.
    }
  }

  /// Attaches a highlight (and optionally a note) to whichever page contains
  /// the selected passage. Uses the reader's own (stable) context rather than
  /// the transient selection-menu one, so the pickers stay mounted and tappable.
  Future<void> _annotate(Note page, String text,
      {required bool withNote}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !mounted) return;
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
    } else {
      final picked = await showModalBottomSheet<int>(
        context: context,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: AppPalette.scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in Annotation.palette)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(sheetCtx).pop(c),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
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
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
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
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.inkPrimary)),
                          const Spacer(),
                          Text('${(_progressOf(_prog.value) * 100).round()}%',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppPalette.inkSecondary)),
                        ],
                      ),
                    ),
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

  /// Scrolls to the first paragraph of chapter [pageId].
  void _jumpTo(String pageId) {
    final idx = _flows.indexWhere((f) => f.pageId == pageId);
    if (idx >= 0 && _isc.isAttached) {
      _isc.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
    }
  }

  void _jumpToFraction(double f) {
    if (!_isc.isAttached) return;
    _isc.scrollTo(
        index: _indexForFraction(f),
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
                    // A bounded box, not Flexible: Flexible only works inside a
                    // Flex, and inside this Container it rendered nothing (blank
                    // sheet). ConstrainedBox lets the list size to its content
                    // and scroll if it grows past ~60% of the screen.
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(sheetContext).size.height * 0.6),
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
                // Bounded box, not Flexible (which is invalid inside a Container
                // and rendered a blank sheet).
                : ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(sheetContext).size.height * 0.6),
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
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 16),
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
                                      ? FontWeight.w700
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
