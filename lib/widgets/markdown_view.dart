import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/external_links.dart';
import '../services/wiki_links.dart';
import '../theme/app_theme.dart';
import 'dictionary_popup.dart';
import 'find_bar.dart';

/// Renders GitHub-flavored Markdown the way it reads on GitHub after a commit:
/// headings with rules, bold/italic, task lists, tables, fenced code with
/// syntax colours, blockquotes, links and rules. Used by [MarkdownNoteScreen]
/// (the new Markdown node type) — deliberately a clean document look, distinct
/// from the handwriting-style rich notes.
///
/// It scrolls itself, and is built for long documents: the source is parsed
/// once (on a background isolate when it's large) and kept until it changes,
/// and only the blocks on screen are built and laid out. markdown_widget's own
/// MarkdownBlock re-parses the whole document on every rebuild and lays out
/// every block at once, which made a long imported file lag to open, scroll
/// and close.
class MarkdownView extends StatefulWidget {
  const MarkdownView(this.data,
      {super.key,
      this.selectable = true,
      this.onWikiTap,
      this.padding = EdgeInsets.zero,
      this.find,
      this.onFindTotal});

  final String data;
  final bool selectable;

  /// Find in note: the matches to mark, and the current one to scroll to.
  /// Code is shown verbatim and isn't searched.
  final FindHighlight? find;

  /// Told how many matches [find] has, once they're counted.
  final ValueChanged<int>? onFindTotal;

  /// Called with the target title when a `[[wiki-link]]` is tapped. When null,
  /// wiki-links render as plain text (no rewrite).
  final void Function(String title)? onWikiTap;

  /// Space around the document, inside the scrolling area.
  final EdgeInsets padding;

  static const _wikiScheme = 'wiki:';

  /// Sources this long are parsed off the UI thread.
  static const backgroundParseChars = 40000;

  /// How many parses have run on this isolate, so tests can check that a
  /// rebuild with the same source doesn't parse again.
  @visibleForTesting
  static int debugParses = 0;

  /// Splits [data] into its top-level blocks, as markdown_widget's own
  /// generator does (GitHub-flavored, HTML left as written). A plain static
  /// function, so it can run on another isolate.
  static List<m.Node> parse(String data, {required bool wikiLinks}) {
    debugParses++;
    final source = wikiLinks ? _linkifyWiki(data) : data;
    final document = m.Document(
      extensionSet: m.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    return document.parseLines(source.split(WidgetVisitor.defaultSplitRegExp));
  }

  @override
  State<MarkdownView> createState() => _MarkdownViewState();

  /// Rejoins "soft" line breaks so a hard-wrapped document flows as paragraphs,
  /// the way GitHub renders it.
  ///
  /// A single newline inside a paragraph is a soft break: GitHub (like any HTML
  /// renderer) collapses it to a space, so source wrapped at ~72 columns still
  /// reads as one flowing paragraph. Flutter's Text renders a raw `\n` as a hard
  /// line break instead, which is why an imported README broke mid-sentence.
  /// Code blocks and inline code never reach here (they are built straight from
  /// their own textContent), and genuine hard breaks are separate `<br>` nodes,
  /// so both are preserved.
  static SpanNode? _flowSoftBreaks(
      m.Node node, MarkdownConfig config, WidgetVisitor visitor) {
    if (node is m.Text) {
      return TextNode(text: _flow(node.text), style: config.p.textStyle);
    }
    return null;
  }

  static String _flow(String text) =>
      text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ');

  /// The text nodes under [node] that are code: their blocks are built from
  /// the code itself, so these never show as written (or get searched).
  static void _codeTexts(m.Node node, Set<m.Text> out, {bool inCode = false}) {
    if (node is m.Text) {
      if (inCode) out.add(node);
    } else if (node is m.Element) {
      final code = inCode || node.tag == 'code' || node.tag == 'pre';
      for (final child in node.children ?? const <m.Node>[]) {
        _codeTexts(child, out, inCode: code);
      }
    }
  }

  /// How many times [query] shows in [node]'s text (code aside), counted the
  /// way the find highlighter meets it.
  static int _countMatches(m.Node node, String query) {
    final code = Set<m.Text>.identity();
    _codeTexts(node, code);
    var n = 0;
    void walk(m.Node node) {
      if (node is m.Text) {
        if (!code.contains(node)) n += findRanges(_flow(node.text), query).length;
      } else if (node is m.Element) {
        node.children?.forEach(walk);
      }
    }

    walk(node);
    return n;
  }

  /// Rewrites `[[Title]]` note links into tappable Markdown links carrying a
  /// `wiki:` scheme, so the GitHub renderer shows them as links and taps route
  /// back into the note graph. `[[@mentions]]` are left as plain text.
  ///
  /// Fenced code blocks and inline `code` spans are skipped: a `[[x]]` inside
  /// them is source to show verbatim, not a link. (Indented code blocks are rare
  /// in these notes and left untouched.)
  static String _linkifyWiki(String src) {
    final lines = src.split('\n');
    String? fenceChar; // fence character of the open block, or null when outside
    var fenceLen = 0;
    for (var i = 0; i < lines.length; i++) {
      final f = _codeFence(lines[i]);
      if (fenceChar == null) {
        if (f != null) {
          fenceChar = f.$1;
          fenceLen = f.$2;
        } else {
          lines[i] = _linkifyOutsideInlineCode(lines[i]);
        }
      } else if (f != null && f.$1 == fenceChar && f.$2 >= fenceLen && f.$3) {
        // Closing fence: same char, at least as long, nothing but the run.
        fenceChar = null;
        fenceLen = 0;
      }
    }
    return lines.join('\n');
  }

  /// If [line] is a code-fence line, returns (char, runLength, bareClose) where
  /// bareClose is true when only whitespace follows the run (a valid closing
  /// fence). Otherwise null. Up to three leading spaces are allowed.
  static (String, int, bool)? _codeFence(String line) {
    final m = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (m == null) return null;
    final run = m.group(1)!;
    return (run[0], run.length, m.group(2)!.trim().isEmpty);
  }

  /// Rewrites wiki links in [line] but leaves any inline `code` spans untouched.
  static String _linkifyOutsideInlineCode(String line) {
    if (!line.contains('[[')) return line;
    final buf = StringBuffer();
    final n = line.length;
    var i = 0;
    while (i < n) {
      if (line[i] == '`') {
        // Measure the opening backtick run, then find a closing run of equal
        // length; the span between (inclusive) is code, emitted verbatim.
        var j = i;
        while (j < n && line[j] == '`') {
          j++;
        }
        final runLen = j - i;
        var k = j;
        var close = -1;
        while (k < n) {
          if (line[k] == '`') {
            var e = k;
            while (e < n && line[e] == '`') {
              e++;
            }
            if (e - k == runLen) {
              close = e;
              break;
            }
            k = e;
          } else {
            k++;
          }
        }
        if (close != -1) {
          buf.write(line.substring(i, close));
          i = close;
        } else {
          // No matching close: the backticks are literal text, keep scanning.
          buf.write(line.substring(i, j));
          i = j;
        }
      } else {
        var j = i;
        while (j < n && line[j] != '`') {
          j++;
        }
        buf.write(_replaceWikiLinks(line.substring(i, j)));
        i = j;
      }
    }
    return buf.toString();
  }

  static String _replaceWikiLinks(String s) =>
      s.replaceAllMapped(wikiLinkPattern, (m) {
        final title = m.group(1)!.trim();
        if (title.isEmpty || title.startsWith('@')) return m.group(0)!;
        return '[$title]($_wikiScheme${Uri.encodeComponent(title)})';
      });

  /// A GitHub-styled config that follows the app's light/dark mode.
  static MarkdownConfig _githubConfig(void Function(String title)? onWikiTap) {
    final dark = AppPalette.dark;
    final ink = AppPalette.inkPrimary;
    final base =
        dark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;

    // The document face: a clean sans, distinct from the handwriting notes.
    const doc = 'Inter';
    const mono = 'monospace';
    final linkColor = dark ? const Color(0xFF539BF5) : const Color(0xFF0969DA);
    final codeBg = dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final codeBorder = dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);

    TextStyle heading(double size) => TextStyle(
          fontFamily: doc,
          fontSize: size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: ink,
        );

    return base.copy(configs: [
      PConfig(
        textStyle: TextStyle(
            fontFamily: doc, fontSize: 15.5, height: 1.55, color: ink),
      ),
      H1Config(style: heading(26)),
      H2Config(style: heading(21)),
      H3Config(style: heading(17.5)),
      H4Config(style: heading(15.5)),
      LinkConfig(
        style: TextStyle(
            color: linkColor, decoration: TextDecoration.underline),
        onTap: (url) {
          if (onWikiTap != null && url.startsWith(_wikiScheme)) {
            onWikiTap(Uri.decodeComponent(url.substring(_wikiScheme.length)));
            return;
          }
          _open(url);
        },
      ),
      CodeConfig(
        style: TextStyle(
          fontFamily: mono,
          fontSize: 13.5,
          backgroundColor:
              (dark ? Colors.white : Colors.black).withValues(alpha: 0.07),
          color: ink,
        ),
      ),
      PreConfig(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: codeBg,
          border: Border.all(color: codeBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(fontFamily: mono, fontSize: 13.5, height: 1.5),
        styleNotMatched: TextStyle(fontFamily: mono, color: ink),
        theme: dark ? atomOneDarkTheme : githubTheme,
      ),
      BlockquoteConfig(
        sideColor: codeBorder,
        textColor: AppPalette.inkSecondary,
      ),
      // Wide tables would otherwise overflow and clip off-screen. Wrap each in a
      // horizontal scroll view so the full table can be swiped sideways; columns
      // size to their content (markdown_widget's IntrinsicColumnWidth default).
      TableConfig(
        wrapper: (table) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    ]);
  }

  static Future<void> _open(String url) => openExternalUrl(url);
}

class _MarkdownViewState extends State<MarkdownView> {
  /// What [_nodes] were parsed from; a rebuild with the same source reuses
  /// them. (The note hands over the same String until it is edited, so the
  /// check is usually a pointer comparison.)
  String? _source;
  bool? _wikiLinks;

  /// The document's top-level blocks; null while a background parse runs.
  List<m.Node>? _nodes;
  int _parseRun = 0;

  /// Blocks already built, by index — code highlighting in particular is
  /// costly to redo each time a block scrolls back into view. Cleared when
  /// the source, the light/dark look or the find marks change.
  final Map<int, Widget> _built = {};
  bool? _builtDark;
  String _builtFind = '';

  /// Jumps to a block far down a long document (for Find).
  final _items = ItemScrollController();

  /// Find: where each block's matches start in the count of all matches
  /// (one entry more than there are blocks), for the query and parse they
  /// were counted from.
  List<int> _matchStarts = const [];
  String? _countedQuery;
  List<m.Node>? _countedNodes;
  bool _revealPending = false;

  @override
  void didUpdateWidget(MarkdownView old) {
    super.didUpdateWidget(old);
    final f = widget.find;
    final o = old.find;
    if (f != null &&
        (o == null || o.query != f.query || o.current != f.current)) {
      _revealPending = true;
    }
  }

  /// Counts the matches of the find query per block, when the query or the
  /// document changed, and reports the total.
  void _countMatches(List<m.Node> nodes) {
    final query = widget.find?.query;
    if (query == null || query.isEmpty) {
      _matchStarts = const [];
      _countedQuery = null;
      return;
    }
    if (query == _countedQuery && identical(nodes, _countedNodes)) return;
    _countedQuery = query;
    _countedNodes = nodes;
    final starts = <int>[0];
    for (final node in nodes) {
      starts.add(starts.last + MarkdownView._countMatches(node, query));
    }
    _matchStarts = starts;
    _revealPending = true;
    final report = widget.onFindTotal;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report?.call(starts.last);
    });
  }

  /// The block holding match [match], by binary search of [_matchStarts].
  int? _blockOf(int match) {
    final starts = _matchStarts;
    if (starts.isEmpty || match < 0 || match >= starts.last) return null;
    var lo = 0;
    var hi = starts.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= match) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Brings the current match on screen: straight there when its block is
  /// built, else a jump to the block first, then the match within it.
  void _revealCurrent() {
    final f = widget.find;
    final block = f == null ? null : _blockOf(f.current);
    if (f == null || block == null) return;
    if (f.currentKey.currentContext != null) {
      revealKey(f.currentKey);
      return;
    }
    if (!_items.isAttached) return;
    _items.jumpTo(index: block, alignment: 0.25);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealKey(f.currentKey);
    });
  }

  void _ensureParsed() {
    final data = widget.data;
    final wikiLinks = widget.onWikiTap != null;
    if ((identical(data, _source) || data == _source) &&
        wikiLinks == _wikiLinks) {
      return;
    }
    _source = data;
    _wikiLinks = wikiLinks;
    _built.clear();
    final run = ++_parseRun;
    if (data.length < MarkdownView.backgroundParseChars) {
      _nodes = MarkdownView.parse(data, wikiLinks: wikiLinks);
      return;
    }
    _nodes = null;
    Isolate.run(() => MarkdownView.parse(data, wikiLinks: wikiLinks)).then(
      (nodes) {
        if (mounted && run == _parseRun) setState(() => _nodes = nodes);
      },
      // Should the parse not survive the trip between isolates, do it here.
      onError: (Object _) {
        if (mounted && run == _parseRun) {
          setState(() =>
              _nodes = MarkdownView.parse(data, wikiLinks: wikiLinks));
        }
      },
    );
  }

  Widget _block(int index, m.Node node, MarkdownConfig config) {
    final visitor = WidgetVisitor(
        config: config,
        textGenerator: _findGenerator(index, node) ?? MarkdownView._flowSoftBreaks);
    final span = visitor.visit([node]).single;
    // The same spacing markdown_widget's generator puts around each block.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text.rich(span.build()),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureParsed();
    final nodes = _nodes;
    if (nodes == null) {
      return Padding(
        padding: widget.padding + const EdgeInsets.only(top: 40),
        child: const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_builtDark != AppPalette.dark) {
      _built.clear();
      _builtDark = AppPalette.dark;
    }
    _countMatches(nodes);
    final f = widget.find;
    final findKey = f == null ? '' : '${f.query}\u0000${f.current}';
    if (findKey != _builtFind) {
      _built.clear();
      _builtFind = findKey;
    }
    if (_revealPending) {
      _revealPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCurrent();
      });
    }
    final config = MarkdownView._githubConfig(widget.onWikiTap);
    final list = ScrollablePositionedList.builder(
      itemScrollController: _items,
      padding: widget.padding,
      itemCount: nodes.length,
      itemBuilder: (context, i) =>
          _built[i] ??= _block(i, nodes[i], config),
    );
    return widget.selectable ? DefinableSelectionArea(child: list) : list;
  }

  /// The text builder for block [index] while Find has matches in it: plain
  /// text as usual, with each match marked and the current one keyed. Null
  /// when there's nothing to mark there.
  TextNodeGenerator? _findGenerator(int index, m.Node node) {
    final f = widget.find;
    final starts = _matchStarts;
    if (f == null ||
        index + 1 >= starts.length ||
        starts[index + 1] == starts[index]) {
      return null;
    }
    final code = Set<m.Text>.identity();
    MarkdownView._codeTexts(node, code);
    var next = starts[index];
    return (node, config, visitor) {
      if (node is! m.Text) return null;
      final text = MarkdownView._flow(node.text);
      final ranges =
          code.contains(node) ? const <TextRange>[] : findRanges(text, f.query);
      if (ranges.isEmpty) return TextNode(text: text, style: config.p.textStyle);
      final first = next;
      next += ranges.length;
      final current = f.current - first;
      return _FindTextNode(text, config.p.textStyle, ranges,
          current >= 0 && current < ranges.length ? current : null,
          f.currentKey);
    };
  }
}

/// Plain Markdown text with its find matches marked.
class _FindTextNode extends SpanNode {
  _FindTextNode(
      this.text, TextStyle base, this.ranges, this.current, this.currentKey) {
    style = base;
  }

  final String text;
  final List<TextRange> ranges;
  final int? current;
  final GlobalKey currentKey;

  @override
  InlineSpan build() {
    // As a TextNode styles itself: its own style under the parents'.
    final effective = (style ?? const TextStyle()).merge(parentStyle);
    return TextSpan(
      style: effective,
      children: highlightSpans([TextSpan(text: text)], ranges,
          baseStyle: effective, current: current, currentKey: currentKey),
    );
  }
}
