// Braim Web HTML building blocks. Every string that reaches HTML goes through
// [esc] or the Markdown sanitiser; there is no template library. See
// docs/braim-web-plan.md, sections 5.5 and 9.

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import '../models/note.dart';
import '../services/wiki_links.dart';
import 'web_assets.dart';

/// Escapes [s] for HTML text and for quoted attribute values.
String esc(String s) => const HtmlEscape().convert(s);

/// A whole page: the head with the stylesheet, the deferred script and, for a
/// signed-in browser, the CSRF token; then [body]. [body] must already be
/// escaped. [styles] and [scripts] name extra files from [WebAssets.files]
/// that only this page needs (the editor's, say); scripts run in order.
String htmlPage({
  required WebAssets assets,
  required String title,
  required String body,
  String? csrf,
  String bodyClass = '',
  List<String> styles = const [],
  List<String> scripts = const [],
}) {
  final out = StringBuffer()
    ..write('<!doctype html>\n<html lang="en">\n<head>\n')
    ..write('<meta charset="utf-8">\n')
    ..write(
      '<meta name="viewport" '
      'content="width=device-width, initial-scale=1">\n',
    )
    ..write('<meta name="color-scheme" content="light dark">\n');
  if (csrf != null) {
    out.write('<meta name="braim-csrf" content="${esc(csrf)}">\n');
  }
  out
    ..write('<title>${esc(title)}</title>\n')
    ..write('<link rel="stylesheet" href="${esc(assets.url('app.css'))}">\n');
  for (final name in styles) {
    out.write('<link rel="stylesheet" href="${esc(assets.url(name))}">\n');
  }
  out.write('<script src="${esc(assets.url('app.js'))}" defer></script>\n');
  for (final name in scripts) {
    out.write('<script src="${esc(assets.url(name))}" defer></script>\n');
  }
  out
    ..write('</head>\n')
    ..write('<body')
    ..write(bodyClass.isEmpty ? '' : ' class="${esc(bodyClass)}"')
    ..write('>\n')
    ..write(body)
    ..write('\n</body>\n</html>\n');
  return out.toString();
}

// ---- Links ------------------------------------------------------------------

final _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
final _controlOrSpace = RegExp(r'[\x00-\x20\x7f]');

/// [url] if it may be linked from a page: `http:`, `https:` and `mailto:`
/// links, plus (when [allowRelative]) paths inside this site. Null for
/// anything else, `javascript:` and `data:` included. Browsers ignore tabs
/// and newlines inside a URL, so those are removed before the check.
String? safeUrl(String url, {bool allowRelative = false}) {
  final u = url.replaceAll(_controlOrSpace, '');
  if (u.isEmpty) return null;
  final m = _scheme.firstMatch(u);
  if (m != null) {
    final scheme = m.group(1)!.toLowerCase();
    return scheme == 'http' || scheme == 'https' || scheme == 'mailto'
        ? u
        : null;
  }
  if (allowRelative &&
      u.startsWith('/') &&
      !u.startsWith('//') &&
      !u.startsWith('/\\')) {
    return u;
  }
  return null;
}

/// An outside link: opens in a new tab and tells the site nothing.
String externalLink(String href, String innerHtml, {String? cls}) =>
    '<a${cls == null ? '' : ' class="$cls"'} href="${esc(href)}" '
    'rel="noopener noreferrer" target="_blank">$innerHtml</a>';

/// The page a `[[Title]]` link goes to.
String wikiHref(String title) => '/link?to=${Uri.encodeQueryComponent(title)}';

/// [text] with its `[[Title]]` links turned into links to `/link` and its
/// `[[@Name]]` mentions into styled spans (reflexes stay on the phone).
String wikiSpansHtml(String text) {
  if (!text.contains('[[')) return esc(text);
  final out = StringBuffer();
  for (final s in splitWikiSpans(text)) {
    if (s.isMention) {
      out.write('<span class="mention">${esc(s.text)}</span>');
    } else if (s.isLink) {
      out.write(
        '<a class="wiki" href="${esc(wikiHref(s.linkTitle!))}">'
        '${esc(s.text)}</a>',
      );
    } else {
      out.write(esc(s.text));
    }
  }
  return out.toString();
}

/// Scraped text (a spark's description, transcript or article) as escaped
/// paragraphs. It comes from other websites, so it is never read as HTML.
String plainTextHtml(String text) {
  final out = StringBuffer();
  for (final para in text.trim().split(RegExp(r'\n\s*\n'))) {
    final p = para.trim();
    if (p.isEmpty) continue;
    out.write('<p>${esc(p).replaceAll('\n', '<br>')}</p>');
  }
  return out.toString();
}

// ---- Rich text (Quill Delta) ------------------------------------------------

String _runHtml(RichRun r) {
  final link = r.link == null ? null : safeUrl(r.link!);
  // A wiki-link inside a hyperlink would nest one link in another.
  var h = link == null ? wikiSpansHtml(r.text) : esc(r.text);
  if (r.strike) h = '<s>$h</s>';
  if (r.underline) h = '<u>$h</u>';
  if (r.italic) h = '<em>$h</em>';
  if (r.bold) h = '<strong>$h</strong>';
  if (r.highlight) h = '<mark>$h</mark>';
  if (link != null) h = externalLink(link, h);
  return h;
}

String _lineContent(RichLine l) {
  final runs = l.runs.isEmpty ? [RichRun(l.text)] : l.runs;
  return runs.map(_runHtml).join();
}

String _lineClasses(RichLine l, [List<String> extra = const []]) {
  final classes = [
    ...extra,
    if (l.indent > 0) 'indent-${l.indent}',
    if (l.align == 'center' || l.align == 'right' || l.align == 'justify')
      'align-${l.align}',
  ];
  return classes.isEmpty ? '' : ' class="${classes.join(' ')}"';
}

/// One text block (Quill Delta JSON or legacy plain text) as HTML, following
/// the phone's read view: headings become `h2`/`h3` (the page title is the
/// `h1`), list lines are grouped into lists, and checklist boxes carry the
/// block and line indexes that `toggleChecklistLine` counts. With
/// [checkedToBottom], ticked items are shown after the rest, as on the phone.
/// Boxes are [interactive] only where a page may tick them.
String richBlockHtml(
  String raw, {
  required int blockIndex,
  bool checkedToBottom = false,
  bool interactive = false,
}) {
  final lines = richToStyledLines(raw);
  var indexed = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
  if (checkedToBottom) {
    indexed = [
      ...indexed.where((e) => e.$2.kind != RichLineKind.checkedItem),
      ...indexed.where((e) => e.$2.kind == RichLineKind.checkedItem),
    ];
  }
  final out = StringBuffer();
  String? open; // the list element currently open
  void closeList() {
    if (open != null) out.write(open == 'ol' ? '</ol>' : '</ul>');
    open = null;
  }

  void openList(String tag, {String cls = ''}) {
    if (open == tag) return;
    closeList();
    out.write(tag == 'ol' ? '<ol>' : '<ul$cls>');
    open = tag;
  }

  for (final (li, l) in indexed) {
    switch (l.kind) {
      case RichLineKind.bullet:
        openList('ul');
        out.write('<li${_lineClasses(l)}>${_lineContent(l)}</li>');
      case RichLineKind.ordered:
        openList('ol');
        out.write('<li${_lineClasses(l)}>${_lineContent(l)}</li>');
      case RichLineKind.checkedItem:
      case RichLineKind.uncheckedItem:
        openList('check', cls: ' class="checklist"');
        final done = l.kind == RichLineKind.checkedItem;
        out
          ..write('<li${_lineClasses(l, [if (done) 'done'])}>')
          ..write(
            '<input type="checkbox" data-block="$blockIndex" '
            'data-line="$li"${done ? ' checked' : ''}'
            '${interactive ? '' : ' disabled'}> ',
          )
          ..write('<span>${_lineContent(l)}</span></li>');
      case RichLineKind.plain:
        closeList();
        if (l.header == 1) {
          out.write('<h2${_lineClasses(l)}>${_lineContent(l)}</h2>');
        } else if (l.header == 2) {
          out.write('<h3${_lineClasses(l)}>${_lineContent(l)}</h3>');
        } else if (l.quote) {
          out.write(
            '<blockquote${_lineClasses(l)}>${_lineContent(l)}'
            '</blockquote>',
          );
        } else if (l.text.isEmpty) {
          out.write('<p class="blank"><br></p>');
        } else {
          out.write('<p${_lineClasses(l)}>${_lineContent(l)}</p>');
        }
    }
  }
  closeList();
  return out.toString();
}

// ---- Markdown ---------------------------------------------------------------

const _allowedTags = {
  'p', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'em', //
  'del', 's', 'code', 'pre', 'blockquote', 'ul', 'ol', 'li', 'table', 'thead',
  'tbody', 'tr', 'th', 'td', 'a', 'img', 'span', 'input',
};

/// Removed together with everything inside them: their text is code or
/// markup, not prose.
const _droppedWithContent = {
  'script', 'style', 'template', 'noscript', 'iframe', 'object', 'embed', //
  'textarea', 'title', 'svg', 'math', 'select', 'button', 'head',
};

const _voidTags = {'br', 'hr', 'img', 'input'};

/// The only classes kept from Markdown output.
const _allowedClasses = {'task-list-item', 'contains-task-list'};

final _textAlign = RegExp(r'text-align:\s*(left|center|right)');

/// GitHub-flavoured Markdown as safe HTML: rendered with the `markdown`
/// package, then rebuilt from the parsed result keeping only an allowlist of
/// tags, attributes and URLs. Everything else is removed and its text kept,
/// escaped. `[[Title]]` outside code becomes a link to `/link`.
String markdownToSafeHtml(String source) {
  final rendered = md.markdownToHtml(
    source,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  return sanitizeHtml(rendered);
}

/// Rebuilds [html] keeping only the allowlist of section 5.5.
String sanitizeHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  final out = StringBuffer();
  for (final node in fragment.nodes) {
    _emit(node, out, inLink: false, inCode: false);
  }
  return out.toString();
}

void _emitChildren(
  dom.Node node,
  StringBuffer out, {
  required bool inLink,
  required bool inCode,
}) {
  for (final child in node.nodes) {
    _emit(child, out, inLink: inLink, inCode: inCode);
  }
}

void _emit(
  dom.Node node,
  StringBuffer out, {
  required bool inLink,
  required bool inCode,
}) {
  if (node is dom.Text) {
    out.write(inLink || inCode ? esc(node.data) : wikiSpansHtml(node.data));
    return;
  }
  if (node is! dom.Element) return; // comments and the like
  final tag = node.localName ?? '';
  if (_droppedWithContent.contains(tag)) return;
  if (!_allowedTags.contains(tag)) {
    _emitChildren(node, out, inLink: inLink, inCode: inCode);
    return;
  }

  final attrs = StringBuffer();
  var link = inLink;
  var code = inCode || tag == 'code' || tag == 'pre';
  switch (tag) {
    case 'a':
      final href = safeUrl(node.attributes['href'] ?? '', allowRelative: true);
      if (href == null || inLink) {
        _emitChildren(node, out, inLink: inLink, inCode: inCode);
        return;
      }
      attrs.write(' href="${esc(href)}"');
      if (!href.startsWith('/')) {
        attrs.write(' rel="noopener noreferrer" target="_blank"');
      }
      link = true;
    case 'img':
      final src = safeUrl(node.attributes['src'] ?? '', allowRelative: true);
      if (src == null || src.startsWith('mailto:')) return;
      attrs.write(
        ' src="${esc(src)}" alt="${esc(node.attributes['alt'] ?? '')}"'
        ' loading="lazy"',
      );
    case 'input':
      if ((node.attributes['type'] ?? '').toLowerCase() != 'checkbox') return;
      attrs.write(' type="checkbox"');
      if (node.attributes.containsKey('checked')) attrs.write(' checked');
      attrs.write(' disabled');
    case 'th':
    case 'td':
      // Table alignment, from `align` (the markdown package) or a style.
      final align = _textAlign.firstMatch(
        'text-align:${node.attributes['align'] ?? ''};'
        '${node.attributes['style'] ?? ''}',
      );
      if (align != null) attrs.write(' class="align-${align.group(1)}"');
  }
  final classes = (node.attributes['class'] ?? '')
      .split(RegExp(r'\s+'))
      .where(_allowedClasses.contains)
      .toList();
  if (classes.isNotEmpty && tag != 'th' && tag != 'td') {
    attrs.write(' class="${classes.join(' ')}"');
  }

  out.write('<$tag$attrs>');
  if (_voidTags.contains(tag)) return;
  _emitChildren(node, out, inLink: link, inCode: code);
  out.write('</$tag>');
}
