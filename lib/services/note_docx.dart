import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;

/// Builds a Word document (.docx) from a note's Markdown, the same source the
/// .md and PDF shares use, so all three carry the same content: headings,
/// bold/italic/strikethrough, inline and block code, bullet, numbered and
/// task lists, quotes, tables, links and rules. Images are a placeholder, as
/// in the other formats.
///
/// A .docx is a zip of XML parts. Only the parts Word needs are written:
/// the document, its styles, list numbering, link targets and a title.
class NoteDocx {
  NoteDocx._();

  static Uint8List fromMarkdown(String source, {String? title}) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(source);
    final writer = _Writer();
    for (final node in nodes) {
      writer.block(node);
    }

    final archive = Archive();
    void add(String name, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _packageRels);
    add('docProps/core.xml', _core(title ?? ''));
    add('word/document.xml', writer.document());
    add('word/styles.xml', _styles);
    add('word/numbering.xml', writer.numbering());
    add('word/_rels/document.xml.rels', writer.relationships());
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

/// Text as XML: escaped, and without the control characters XML forbids
/// (Word refuses a file that has one).
String _esc(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// How a run of text is formatted.
class _Fmt {
  const _Fmt({
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link = false,
  });

  final bool bold, italic, strike, code, link;

  _Fmt copyWith(
          {bool? bold, bool? italic, bool? strike, bool? code, bool? link}) =>
      _Fmt(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        strike: strike ?? this.strike,
        code: code ?? this.code,
        link: link ?? this.link,
      );

  /// The run's properties, in the order Word's schema requires (it may
  /// call a file with them out of order corrupt).
  String get props {
    final p = StringBuffer();
    if (link) p.write('<w:rStyle w:val="Hyperlink"/>');
    if (code) {
      p.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" '
          'w:cs="Consolas"/>');
    }
    if (bold) p.write('<w:b/>');
    if (italic) p.write('<w:i/>');
    if (strike) p.write('<w:strike/>');
    if (code) p.write('<w:shd w:val="clear" w:color="auto" w:fill="F0F0F0"/>');
    return p.isEmpty ? '' : '<w:rPr>$p</w:rPr>';
  }
}

class _Writer {
  final _body = StringBuffer();

  /// Link targets, by relationship id (rId1 and rId2 are the styles and
  /// the numbering).
  final _links = <String>[];

  /// One numbering instance per list: (bulleted?, start number).
  final _lists = <(bool, int)>[];

  String _run(String text, _Fmt fmt) =>
      '<w:r>${fmt.props}<w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';

  void _para(String runs,
      {String? style, (int, int)? list, int indent = 0, String extra = ''}) {
    final pPr = StringBuffer();
    if (style != null) pPr.write('<w:pStyle w:val="$style"/>');
    if (list != null) {
      pPr.write('<w:numPr><w:ilvl w:val="${list.$2}"/>'
          '<w:numId w:val="${list.$1}"/></w:numPr>');
    } else if (indent > 0) {
      pPr.write('<w:ind w:left="${indent * 360}"/>');
    }
    pPr.write(extra);
    _body.write('<w:p>${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}'
        '$runs</w:p>');
  }

  /// The runs for inline Markdown [nodes].
  String inline(List<md.Node>? nodes, [_Fmt fmt = const _Fmt()]) {
    if (nodes == null) return '';
    final out = StringBuffer();
    for (final node in nodes) {
      if (node is md.Text) {
        // A soft line break inside a paragraph reads as a space, as on GitHub.
        out.write(_run(node.text.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' '),
            fmt));
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'strong':
        case 'b':
          out.write(inline(node.children, fmt.copyWith(bold: true)));
        case 'em':
        case 'i':
          out.write(inline(node.children, fmt.copyWith(italic: true)));
        case 'del':
        case 's':
          out.write(inline(node.children, fmt.copyWith(strike: true)));
        case 'code':
          out.write(_run(node.textContent, fmt.copyWith(code: true)));
        case 'br':
          out.write('<w:r><w:br/></w:r>');
        case 'img':
          final alt = node.attributes['alt'] ?? '';
          out.write(_run(alt.isEmpty ? '[image]' : '[image: $alt]', fmt));
        case 'input':
          // A task list's box.
          final checked = node.attributes.containsKey('checked');
          out.write(_run(checked ? '☑ ' : '☐ ', fmt));
        case 'a':
          final href = node.attributes['href'] ?? '';
          final runs = inline(node.children, fmt.copyWith(link: true));
          if (href.isEmpty) {
            out.write(runs);
          } else {
            _links.add(href);
            out.write('<w:hyperlink r:id="rIdL${_links.length}" '
                'w:history="1">$runs</w:hyperlink>');
          }
        default:
          out.write(inline(node.children, fmt));
      }
    }
    return out.toString();
  }

  /// Writes one block-level node (and what it contains).
  void block(md.Node node, {String? style, int depth = 0}) {
    if (node is md.Text) {
      if (node.text.trim().isNotEmpty) _para(inline([node]), style: style);
      return;
    }
    if (node is! md.Element) return;
    switch (node.tag) {
      case 'h1':
        _para(inline(node.children), style: 'Heading1');
      case 'h2':
        _para(inline(node.children), style: 'Heading2');
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _para(inline(node.children), style: 'Heading3');
      case 'p':
        _para(inline(node.children), style: style);
      case 'blockquote':
        for (final child in node.children ?? const <md.Node>[]) {
          block(child, style: 'Quote', depth: depth);
        }
      case 'pre':
        final code = node.textContent.replaceAll(RegExp(r'\n$'), '');
        for (final line in code.split('\n')) {
          _para(_run(line, const _Fmt()), style: 'CodeBlock');
        }
        // A little air after the block.
        _para('', extra: '<w:spacing w:after="0"/>');
      case 'hr':
        _para('',
            extra: '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" '
                'w:color="AAAAAA"/></w:pBdr>');
      case 'ul':
      case 'ol':
        _list(node, depth);
      case 'table':
        _table(node);
      default:
        // Anything else: its blocks, in order.
        for (final child in node.children ?? const <md.Node>[]) {
          block(child, style: style, depth: depth);
        }
    }
  }

  void _list(md.Element list, int depth) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    _lists.add((!ordered, start));
    final numId = _lists.length;
    final level = depth.clamp(0, 2);
    for (final item in list.children ?? const <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      final children = item.children ?? const <md.Node>[];
      // A task item shows its own box instead of a bullet.
      final task = children.any((c) =>
          c is md.Element &&
          (c.tag == 'input' ||
              (c.tag == 'p' &&
                  (c.children?.any((g) =>
                          g is md.Element && g.tag == 'input') ??
                      false))));
      final inlineParts = <md.Node>[];
      void flush() {
        if (inlineParts.isEmpty) return;
        _para(inline(List.of(inlineParts)),
            style: 'ListParagraph',
            list: task ? null : (numId, level),
            indent: task ? level + 1 : 0);
        inlineParts.clear();
      }

      for (final child in children) {
        if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
          flush();
          _list(child, depth + 1);
        } else if (child is md.Element && child.tag == 'p') {
          inlineParts.addAll(child.children ?? const []);
          flush();
        } else {
          inlineParts.add(child);
        }
      }
      flush();
    }
  }

  void _table(md.Element table) {
    final rows = <(bool, List<md.Element>)>[];
    void collect(md.Element el, bool header) {
      for (final child in el.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          rows.add((
            header,
            [
              for (final c in child.children ?? const <md.Node>[])
                if (c is md.Element) c
            ]
          ));
        } else {
          collect(child, child.tag == 'thead');
        }
      }
    }

    collect(table, false);
    if (rows.isEmpty) return;
    final columns =
        rows.map((r) => r.$2.length).reduce((a, b) => a > b ? a : b);
    final out = StringBuffer('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>');
    for (var i = 0; i < columns; i++) {
      out.write('<w:gridCol w:w="${9000 ~/ columns}"/>');
    }
    out.write('</w:tblGrid>');
    for (final (header, cells) in rows) {
      out.write('<w:tr>');
      for (var i = 0; i < columns; i++) {
        final runs = i < cells.length
            ? inline(cells[i].children, _Fmt(bold: header))
            : '';
        out.write('<w:tc><w:tcPr><w:tcW w:w="${9000 ~/ columns}" '
            'w:type="dxa"/></w:tcPr><w:p>$runs</w:p></w:tc>');
      }
      out.write('</w:tr>');
    }
    out.write('</w:tbl>');
    _body.write(out);
    // Word needs a paragraph between a table and whatever follows.
    _para('');
  }

  String document() => '$_xmlHead<w:document xmlns:w="$_w" xmlns:r="$_r">'
      '<w:body>$_body<w:sectPr><w:pgMar w:top="1440" w:right="1440" '
      'w:bottom="1440" w:left="1440" w:header="708" w:footer="708" '
      'w:gutter="0"/></w:sectPr></w:body></w:document>';

  String relationships() {
    final out = StringBuffer('$_xmlHead<Relationships xmlns="http://schemas.'
        'openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_r/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="$_r/numbering" '
        'Target="numbering.xml"/>');
    for (var i = 0; i < _links.length; i++) {
      out.write('<Relationship Id="rIdL${i + 1}" Type="$_r/hyperlink" '
          'Target="${_esc(_links[i])}" TargetMode="External"/>');
    }
    out.write('</Relationships>');
    return out.toString();
  }

  /// List styles: abstract 0 is bulleted, 1 numbered, three levels each;
  /// then one instance per list, so each numbered list counts from its own
  /// start.
  String numbering() {
    String level(int i, String format, String text, String font) =>
        '<w:lvl w:ilvl="$i"><w:start w:val="1"/><w:numFmt w:val="$format"/>'
        '<w:lvlText w:val="$text"/><w:lvlJc w:val="left"/><w:pPr>'
        '<w:ind w:left="${720 + 360 * i}" w:hanging="360"/></w:pPr>'
        '$font</w:lvl>';
    const symbol = '<w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" '
        'w:hint="default"/></w:rPr>';
    final out = StringBuffer('$_xmlHead<w:numbering xmlns:w="$_w">'
        '<w:abstractNum w:abstractNumId="0"><w:multiLevelType '
        'w:val="hybridMultilevel"/>'
        '${level(0, 'bullet', '\uF0B7', symbol)}'
        '${level(1, 'bullet', 'o', '<w:rPr><w:rFonts w:ascii="Courier New" '
            'w:hAnsi="Courier New" w:hint="default"/></w:rPr>')}'
        '${level(2, 'bullet', '\uF0A7', '<w:rPr><w:rFonts w:ascii="Wingdings" '
            'w:hAnsi="Wingdings" w:hint="default"/></w:rPr>')}'
        '</w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1"><w:multiLevelType '
        'w:val="hybridMultilevel"/>'
        '${level(0, 'decimal', '%1.', '')}'
        '${level(1, 'lowerLetter', '%2.', '')}'
        '${level(2, 'lowerRoman', '%3.', '')}'
        '</w:abstractNum>');
    for (var i = 0; i < _lists.length; i++) {
      final (bulleted, start) = _lists[i];
      out.write('<w:num w:numId="${i + 1}"><w:abstractNumId '
          'w:val="${bulleted ? 0 : 1}"/>');
      if (!bulleted) {
        for (var l = 0; l < 3; l++) {
          out.write('<w:lvlOverride w:ilvl="$l"><w:startOverride '
              'w:val="${l == 0 ? start : 1}"/></w:lvlOverride>');
        }
      }
      out.write('</w:num>');
    }
    out.write('</w:numbering>');
    return out.toString();
  }
}

const _contentTypes = '$_xmlHead<Types xmlns="http://schemas.openxmlformats.'
    'org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-'
    'package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.'
    'openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.'
    'openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/numbering.xml" ContentType="application/vnd.'
    'openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.'
    'openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const _packageRels = '$_xmlHead<Relationships xmlns="http://schemas.'
    'openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_r/officeDocument" '
    'Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/'
    '2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>';

String _core(String title) => '$_xmlHead<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/'
    'core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>${_esc(title)}</dc:title><dc:creator>Braim</dc:creator>'
    '</cp:coreProperties>';

const _styles = '$_xmlHead<w:styles xmlns:w="$_w">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" '
    'w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
    '<w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" '
    'w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name '
    'w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>'
    '<w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" '
    'w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/>'
    '<w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name '
    'w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>'
    '<w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="280" '
    'w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/>'
    '<w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name '
    'w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>'
    '<w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" '
    'w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/>'
    '<w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/>'
    '<w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:pBdr><w:left '
    'w:val="single" w:sz="12" w:space="8" w:color="BBBBBB"/></w:pBdr>'
    '<w:ind w:left="567"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/>'
    '</w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="CodeBlock"><w:name '
    'w:val="Code Block"/><w:basedOn w:val="Normal"/><w:pPr><w:shd '
    'w:val="clear" w:color="auto" w:fill="F6F8FA"/><w:spacing w:after="0" '
    'w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts '
    'w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz '
    'w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name '
    'w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:spacing w:after="60"/><w:contextualSpacing/></w:pPr>'
    '</w:style>'
    '<w:style w:type="character" w:styleId="Hyperlink"><w:name '
    'w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u '
    'w:val="single"/></w:rPr></w:style>'
    '<w:style w:type="table" w:styleId="TableGrid"><w:name '
    'w:val="Table Grid"/><w:tblPr><w:tblBorders>'
    '<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
    '</w:tblBorders></w:tblPr></w:style>'
    '</w:styles>';
