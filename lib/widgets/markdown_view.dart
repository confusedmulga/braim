import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/wiki_links.dart';
import '../theme/app_theme.dart';

/// Renders GitHub-flavored Markdown the way it reads on GitHub after a commit:
/// headings with rules, bold/italic, task lists, tables, fenced code with
/// syntax colours, blockquotes, links and rules. Used by [MarkdownNoteScreen]
/// (the new Markdown node type) — deliberately a clean document look, distinct
/// from the handwriting-style rich notes.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data,
      {super.key, this.selectable = true, this.onWikiTap});

  final String data;
  final bool selectable;

  /// Called with the target title when a `[[wiki-link]]` is tapped. When null,
  /// wiki-links render as plain text (no rewrite).
  final void Function(String title)? onWikiTap;

  static const _wikiScheme = 'wiki:';

  @override
  Widget build(BuildContext context) {
    return MarkdownBlock(
      data: onWikiTap == null ? data : _linkifyWiki(data),
      selectable: selectable,
      config: _githubConfig(onWikiTap),
      generator: MarkdownGenerator(textGenerator: _flowSoftBreaks),
    );
  }

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
      final flowed = node.text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ');
      return TextNode(text: flowed, style: config.p.textStyle);
    }
    return null;
  }

  /// Rewrites `[[Title]]` note links into tappable Markdown links carrying a
  /// `wiki:` scheme, so the GitHub renderer shows them as links and taps route
  /// back into the note graph. `[[@mentions]]` are left as plain text.
  static String _linkifyWiki(String src) =>
      src.replaceAllMapped(wikiLinkPattern, (m) {
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
    ]);
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A malformed or unsupported link is a no-op rather than a crash.
    }
  }
}
