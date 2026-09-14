import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders a Markdown node to a US-Letter PDF that reads like the committed
/// document: an 11pt body (a default Word size) with headings scaled up, plus
/// bold/italic, lists, task boxes, inline + fenced code, tables, quotes, links
/// and rules. Built-in fonts keep it dependency-free; emoji/CJK may not appear.
class NotePdf {
  const NotePdf._();

  static const double _body = 11; // pt — the body size the user asked for.

  /// Builds the PDF bytes for [source] (raw markdown). [title] is used only as
  /// document metadata; the markdown's own headings carry the visible title.
  static Future<Uint8List> fromMarkdown(String source, {String? title}) async {
    final doc = pw.Document(title: title);
    final base = await _theme();

    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(source);

    final widgets = <pw.Widget>[];
    for (final node in nodes) {
      final w = _block(node);
      if (w != null) widgets.add(w);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        theme: base,
        margin: const pw.EdgeInsets.all(54), // ~0.75in like a document.
        build: (_) => widgets,
      ),
    );
    return doc.save();
  }

  /// A theme using the app's bundled SpaceGrotesk (a clean sans with good
  /// Unicode coverage — bullets, curly quotes, dashes). Falls back to the
  /// built-in PDF fonts if the assets can't be loaded (e.g. in a unit test).
  /// The family ships no italic, so emphasis reads upright; emoji won't render.
  static Future<pw.ThemeData> _theme() async {
    try {
      final regular = pw.Font.ttf(
          await rootBundle.load('assets/fonts/SpaceGrotesk-Regular.ttf'));
      final bold = pw.Font.ttf(
          await rootBundle.load('assets/fonts/SpaceGrotesk-Bold.ttf'));
      return pw.ThemeData.withFont(
          base: regular, bold: bold, italic: regular, boldItalic: bold);
    } catch (_) {
      return pw.ThemeData.withFont();
    }
  }

  // ---- Block-level nodes ---------------------------------------------------

  static pw.Widget? _block(md.Node node) {
    if (node is md.Text) {
      final t = node.text.trim();
      return t.isEmpty ? null : pw.Paragraph(text: t);
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
        return _heading(node, 2.0, rule: true);
      case 'h2':
        return _heading(node, 1.5, rule: true);
      case 'h3':
        return _heading(node, 1.25);
      case 'h4':
        return _heading(node, 1.1);
      case 'h5':
      case 'h6':
        return _heading(node, 1.0);
      case 'p':
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.RichText(text: _inline(node.children, _bodyStyle())),
        );
      case 'ul':
        return _list(node, ordered: false);
      case 'ol':
        return _list(node, ordered: true);
      case 'blockquote':
        return _blockquote(node);
      case 'pre':
        return _codeBlock(node);
      case 'hr':
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: _rule, thickness: 0.8, height: 1),
        );
      case 'table':
        return _table(node);
      default:
        // Unknown block (e.g. a bare image): fall back to its text.
        final text = node.textContent.trim();
        return text.isEmpty ? null : pw.Paragraph(text: text);
    }
  }

  static pw.Widget _heading(md.Element node, double scale, {bool rule = false}) {
    final size = _body * scale;
    final text = pw.RichText(
      text: _inline(
        node.children,
        pw.TextStyle(
            fontSize: size,
            fontWeight: pw.FontWeight.bold,
            lineSpacing: 2,
            color: _ink),
      ),
    );
    return pw.Container(
      margin: pw.EdgeInsets.only(top: scale >= 1.25 ? 14 : 10, bottom: 6),
      padding: rule ? const pw.EdgeInsets.only(bottom: 4) : null,
      decoration: rule
          ? const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.7)))
          : null,
      child: text,
    );
  }

  static pw.Widget _list(md.Element node, {required bool ordered}) {
    final items = <pw.Widget>[];
    var index = 1;
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'li') continue;
      // GitHub task lists: the li starts with a checkbox input.
      bool? checkbox;
      final kids = List<md.Node>.from(child.children ?? const []);
      if (kids.isNotEmpty &&
          kids.first is md.Element &&
          (kids.first as md.Element).tag == 'input') {
        final el = kids.removeAt(0) as md.Element;
        checkbox = el.attributes['checked'] == 'true';
      }
      // Separate the item's own inline content from any nested lists, so a
      // sub-list renders as its own indented block below the item instead of
      // being flattened onto the parent line.
      final inlineNodes = <md.Node>[];
      final nestedLists = <md.Element>[];
      for (final k in kids) {
        if (k is md.Element && (k.tag == 'ul' || k.tag == 'ol')) {
          nestedLists.add(k);
        } else {
          inlineNodes.add(k);
        }
      }
      final marker = checkbox != null
          ? (checkbox ? '[x] ' : '[ ] ')
          : (ordered ? '${index++}. ' : '• ');
      items.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3, left: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(marker,
                    style: pw.TextStyle(
                        fontSize: _body,
                        color: _ink,
                        font: checkbox != null ? pw.Font.courier() : null)),
                pw.Expanded(
                    child: pw.RichText(
                        text: _inline(inlineNodes, _bodyStyle()))),
              ],
            ),
            for (final sub in nestedLists)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14),
                child: _list(sub, ordered: sub.tag == 'ol'),
              ),
          ],
        ),
      ));
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start, children: items),
    );
  }

  static pw.Widget _blockquote(md.Element node) {
    final inner = <pw.Widget>[];
    for (final child in node.children ?? const <md.Node>[]) {
      final w = _block(child);
      if (w != null) inner.add(w);
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _rule, width: 3)),
      ),
      child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start, children: inner),
    );
  }

  static pw.Widget _codeBlock(md.Element node) {
    // <pre><code>…</code></pre>
    var text = node.textContent;
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: _codeBg,
        border: pw.Border.all(color: _rule, width: 0.7),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: pw.Font.courier(), fontSize: _body - 1.5, color: _ink)),
    );
  }

  static pw.Widget _table(md.Element node) {
    final rows = <pw.TableRow>[];
    for (final section in node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      final header = section.tag == 'thead';
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <pw.Widget>[];
        for (final td in tr.children ?? const <md.Node>[]) {
          if (td is! md.Element) continue;
          cells.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.RichText(
                text: _inline(
                    td.children,
                    header
                        ? _bodyStyle().copyWith(fontWeight: pw.FontWeight.bold)
                        : _bodyStyle())),
          ));
        }
        rows.add(pw.TableRow(
          decoration:
              header ? const pw.BoxDecoration(color: _codeBg) : null,
          children: cells,
        ));
      }
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Table(
        border: pw.TableBorder.all(color: _rule, width: 0.7),
        children: rows,
      ),
    );
  }

  // ---- Inline spans --------------------------------------------------------

  static pw.TextSpan _inline(List<md.Node>? nodes, pw.TextStyle style) {
    final spans = <pw.InlineSpan>[];
    for (final n in nodes ?? const <md.Node>[]) {
      _appendInline(n, style, spans);
    }
    return pw.TextSpan(style: style, children: spans);
  }

  static void _appendInline(
      md.Node node, pw.TextStyle style, List<pw.InlineSpan> out) {
    if (node is md.Text) {
      out.add(pw.TextSpan(text: _decode(node.text), style: style));
      return;
    }
    if (node is! md.Element) return;
    switch (node.tag) {
      case 'strong':
        _children(node, style.copyWith(fontWeight: pw.FontWeight.bold), out);
      case 'em':
        _children(node, style.copyWith(fontStyle: pw.FontStyle.italic), out);
      case 'del':
        _children(
            node, style.copyWith(decoration: pw.TextDecoration.lineThrough), out);
      case 'a':
        _children(
            node,
            style.copyWith(
                color: _link, decoration: pw.TextDecoration.underline),
            out);
      case 'code':
        out.add(pw.TextSpan(
          text: node.textContent,
          style: style.copyWith(
              font: pw.Font.courier(), fontSize: style.fontSize! - 1),
        ));
      case 'br':
        out.add(pw.TextSpan(text: '\n', style: style));
      case 'img':
        final alt = node.attributes['alt'];
        if (alt != null && alt.isNotEmpty) {
          out.add(pw.TextSpan(text: '[$alt]', style: style));
        }
      default:
        _children(node, style, out);
    }
  }

  static void _children(
      md.Element node, pw.TextStyle style, List<pw.InlineSpan> out) {
    for (final c in node.children ?? const <md.Node>[]) {
      _appendInline(c, style, out);
    }
  }

  /// The markdown parser leaves a few HTML entities; decode the common ones so
  /// they don't show as `&amp;` in the PDF.
  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  static pw.TextStyle _bodyStyle() =>
      pw.TextStyle(fontSize: _body, lineSpacing: 2.5, color: _ink);

  static const _ink = PdfColor.fromInt(0xFF1B1B1F);
  static const _rule = PdfColor.fromInt(0xFFD0D7DE);
  static const _codeBg = PdfColor.fromInt(0xFFF3F4F6);
  static const _link = PdfColor.fromInt(0xFF0969DA);
}
