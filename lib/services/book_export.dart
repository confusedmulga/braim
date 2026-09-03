import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/book.dart';
import '../models/note.dart';

/// Turns a book into something shareable: a typeset PDF, a Markdown file, or
/// a real ePub. Everything here is pure data work, so it stays off the UI's
/// critical path and never touches widgets.
class BookExport {
  BookExport._();

  static String _safeName(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    return cleaned.isEmpty ? 'book' : cleaned;
  }

  static String _titleOf(Book book, String fallback) =>
      book.title.trim().isEmpty ? fallback : book.title.trim();

  /// Loads the book's own typeface so exports read in the same face they were
  /// written in. Falls back silently to the PDF default if a face won't load.
  static Future<pw.ThemeData?> _theme(Book book) async {
    try {
      final (reg, bold) = BookFonts.assets(book.fontFamily);
      final base = pw.Font.ttf(await rootBundle.load(reg));
      final boldFont = pw.Font.ttf(await rootBundle.load(bold));
      return pw.ThemeData.withFont(base: base, bold: boldFont);
    } catch (_) {
      return null;
    }
  }

  // ---- PDF -----------------------------------------------------------------

  /// A bound PDF: cover, title page, copyright, contents, then the pages —
  /// each page numbered in the footer.
  static Future<void> sharePdf({
    required Book book,
    required List<Note> pages,
    required String author,
    required String untitledLabel,
    required String contentsLabel,
  }) async {
    final title = _titleOf(book, untitledLabel);
    final theme = await _theme(book);
    final doc = theme == null
        ? pw.Document(title: title, author: author)
        : pw.Document(title: title, author: author, theme: theme);

    // 1. Cover.
    final coverFile =
        book.coverPath != null ? File(book.coverPath!) : null;
    final hasCover = coverFile != null && coverFile.existsSync();
    doc.addPage(pw.Page(
      build: (_) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Stack(fit: pw.StackFit.expand, children: [
          if (hasCover)
            pw.Image(pw.MemoryImage(coverFile.readAsBytesSync()),
                fit: pw.BoxFit.cover)
          else
            pw.Container(color: PdfColor.fromInt(0xFF432B54)),
          pw.Container(
            alignment: pw.Alignment.bottomLeft,
            padding: const pw.EdgeInsets.all(46),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: 34,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white)),
                if (author.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Text(author,
                        style: pw.TextStyle(
                            fontSize: 15, color: PdfColors.white)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    ));

    // 2. Title page + 3. copyright, as quiet front matter.
    doc.addPage(pw.Page(
      build: (_) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 28, fontWeight: pw.FontWeight.bold)),
            if (author.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 12),
                child: pw.Text(author,
                    style: const pw.TextStyle(fontSize: 14)),
              ),
            if (book.description.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(40, 28, 40, 0),
                child: pw.Text(book.description.trim(),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                        fontSize: 11, lineSpacing: 3, color: PdfColors.grey700)),
              ),
          ],
        ),
      ),
    ));
    doc.addPage(pw.Page(
      build: (_) => pw.Align(
        alignment: pw.Alignment.bottomLeft,
        child: pw.Text(
          '$title\n'
          '${author.isEmpty ? '' : '© ${DateTime.now().year} $author\n'}'
          'All rights reserved.',
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
        ),
      ),
    ));

    // 4. Generated contents (the Contents page itself and quiet front matter
    // like a dedication or epigraph are left off the list).
    final listed =
        pages.where((p) => p.bookPageKind != BookPageKind.contents).toList();
    final toc = listed
        .where((p) => !BookPageKind.isQuietMatter(p.bookPageKind))
        .toList();
    if (toc.isNotEmpty) {
      doc.addPage(pw.MultiPage(
        build: (_) => [
          pw.Text(contentsLabel,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          for (var i = 0; i < toc.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Row(children: [
                pw.SizedBox(
                    width: 26, child: pw.Text('${i + 1}.')),
                pw.Expanded(
                    child: pw.Text(toc[i].title.trim().isEmpty
                        ? '-'
                        : toc[i].title.trim())),
              ]),
            ),
        ],
      ));
    }

    // 5. The book itself, numbered from the first real page.
    for (final page in listed) {
      final heading = page.title.trim();
      final body = page.textPreview.trim();
      final quiet = BookPageKind.isQuietMatter(page.bookPageKind);
      doc.addPage(pw.MultiPage(
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('${ctx.pageNumber}',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (_) => quiet
            // A dedication or epigraph: centred, italic, no chapter heading.
            ? [
                pw.SizedBox(height: 60),
                if (body.isNotEmpty)
                  pw.Center(
                    child: pw.Text(body,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 12,
                            lineSpacing: 5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey800)),
                  ),
              ]
            : [
                if (heading.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 18),
                    child: pw.Text(heading,
                        style: pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  ),
                if (body.isNotEmpty)
                  pw.Text(body,
                      textAlign: pw.TextAlign.justify,
                      style:
                          const pw.TextStyle(fontSize: 11.5, lineSpacing: 4)),
              ],
      ));
    }

    await Printing.sharePdf(
        bytes: await doc.save(), filename: '${_safeName(title)}.pdf');
  }

  // ---- Markdown ------------------------------------------------------------

  static Future<void> shareMarkdown({
    required Book book,
    required List<Note> pages,
    required String author,
    required String untitledLabel,
  }) async {
    final title = _titleOf(book, untitledLabel);
    final buffer = StringBuffer()..writeln('# $title');
    if (author.isNotEmpty) buffer.writeln('\n*by $author*');
    if (book.description.trim().isNotEmpty) {
      buffer.writeln('\n> ${book.description.trim()}');
    }
    for (final page in pages) {
      if (page.bookPageKind == BookPageKind.contents) continue;
      final heading = page.title.trim();
      buffer.writeln('\n\n## ${heading.isEmpty ? '-' : heading}\n');
      buffer.writeln(page.textPreview.trim());
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}.md');
    await file.writeAsString(buffer.toString());
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], title: title));
  }

  // ---- ePub ----------------------------------------------------------------

  /// A minimal but valid ePub 2: mimetype (stored first, uncompressed),
  /// container.xml, an OPF manifest/spine, an NCX table of contents, and one
  /// XHTML file per page.
  static Future<void> shareEpub({
    required Book book,
    required List<Note> pages,
    required String author,
    required String untitledLabel,
    required String contentsLabel,
  }) async {
    final title = _titleOf(book, untitledLabel);
    final listed =
        pages.where((p) => p.bookPageKind != BookPageKind.contents).toList();
    final archive = Archive();

    void addText(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    // The mimetype entry must be first and stored, not deflated.
    final mime = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile('mimetype', mime.length, mime)
      ..compression = CompressionType.none);

    addText('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

    // Cover image, when there is one.
    var coverItem = '';
    var coverMeta = '';
    final coverFile = book.coverPath != null ? File(book.coverPath!) : null;
    if (coverFile != null && coverFile.existsSync()) {
      final bytes = coverFile.readAsBytesSync();
      final ext = coverFile.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      archive.addFile(
          ArchiveFile('OEBPS/cover.$ext', bytes.length, bytes));
      coverItem =
          '<item id="cover-image" href="cover.$ext" media-type="image/${ext == 'png' ? 'png' : 'jpeg'}"/>';
      coverMeta = '<meta name="cover" content="cover-image"/>';
    }

    // Embed the book's typeface and a stylesheet so the ePub reads in the same
    // face it was written in (readers that honour embedded fonts pick it up).
    var fontItems = '';
    var fontFace = '';
    try {
      final (reg, bold) = BookFonts.assets(book.fontFamily);
      final regBytes = (await rootBundle.load(reg)).buffer.asUint8List();
      final boldBytes = (await rootBundle.load(bold)).buffer.asUint8List();
      archive.addFile(
          ArchiveFile('OEBPS/fonts/body.ttf', regBytes.length, regBytes));
      archive.addFile(ArchiveFile(
          'OEBPS/fonts/body-bold.ttf', boldBytes.length, boldBytes));
      fontItems =
          '<item id="font-body" href="fonts/body.ttf" media-type="application/x-font-ttf"/>\n'
          '    <item id="font-body-bold" href="fonts/body-bold.ttf" media-type="application/x-font-ttf"/>';
      fontFace = '''
@font-face { font-family: "BookFont"; font-weight: normal; font-style: normal; src: url(fonts/body.ttf); }
@font-face { font-family: "BookFont"; font-weight: bold; font-style: normal; src: url(fonts/body-bold.ttf); }
''';
    } catch (_) {
      // Font unavailable: fall back to the reader's default serif.
    }
    addText('OEBPS/style.css', '''
$fontFace
body { font-family: "BookFont", Georgia, serif; line-height: 1.5; margin: 5%; }
h1 { font-weight: bold; }
.matter { text-align: center; font-style: italic; margin-top: 30%; color: #444; }
''');

    // One XHTML document per page.
    final items = StringBuffer();
    final spine = StringBuffer();
    final nav = StringBuffer();
    var navOrder = 0;
    for (var i = 0; i < listed.length; i++) {
      final page = listed[i];
      final id = 'page$i';
      final quiet = BookPageKind.isQuietMatter(page.bookPageKind);
      final heading = _escape(
          page.title.trim().isEmpty ? '-' : page.title.trim());
      final paragraphs = page.textPreview
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => '<p>${_escape(l.trim())}</p>')
          .join('\n');
      // Quiet matter (dedication/epigraph) prints centred with no heading.
      final bodyHtml = quiet
          ? '<div class="matter">\n$paragraphs\n</div>'
          : '<h1>$heading</h1>\n$paragraphs';
      addText('OEBPS/$id.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$heading</title><meta charset="utf-8"/>
<link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
$bodyHtml
</body></html>''');
      items.writeln(
          '<item id="$id" href="$id.xhtml" media-type="application/xhtml+xml"/>');
      spine.writeln('<itemref idref="$id"/>');
      // Quiet matter stays out of the navigation table of contents.
      if (!quiet) {
        navOrder++;
        nav.writeln('''
    <navPoint id="nav$i" playOrder="$navOrder">
      <navLabel><text>$heading</text></navLabel>
      <content src="$id.xhtml"/>
    </navPoint>''');
      }
    }

    final bookId = 'urn:uuid:${book.id}';
    addText('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>${_escape(title)}</dc:title>
    <dc:creator opf:role="aut">${_escape(author)}</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">$bookId</dc:identifier>
    ${book.description.trim().isEmpty ? '' : '<dc:description>${_escape(book.description.trim())}</dc:description>'}
    $coverMeta
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="style" href="style.css" media-type="text/css"/>
    $coverItem
    $fontItems
$items  </manifest>
  <spine toc="ncx">
$spine  </spine>
</package>''');

    addText('OEBPS/toc.ncx', '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="$bookId"/></head>
  <docTitle><text>${_escape(title)}</text></docTitle>
  <navMap>
$nav  </navMap>
</ncx>''');

    final zipped = ZipEncoder().encode(archive);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}.epub');
    await file.writeAsBytes(zipped);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], title: title));
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
