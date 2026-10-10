import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../services/file_names.dart';
import '../services/note_docx.dart';
import '../services/note_markdown.dart';
import '../services/note_pdf.dart';
import '../theme/app_theme.dart';

/// The formats a note can be shared in; a circuit can also go as a whole
/// `.braim` file ([circuit], see `shareCircuitAs`).
enum ShareFormat {
  markdown,
  text,
  pdf,
  docx,
  circuit;

  /// What a note's menu offers.
  static const note = [markdown, text, pdf, docx];

  /// What a circuit's menus offer: every note format, then the circuit file.
  static const forCircuit = [markdown, text, pdf, docx, circuit];
}

String _label(ShareFormat format, AppLocalizations t) => switch (format) {
      ShareFormat.markdown => t.shareFormatMarkdown,
      ShareFormat.text => t.shareFormatText,
      ShareFormat.pdf => t.shareFormatPdf,
      ShareFormat.docx => t.shareFormatDocx,
      ShareFormat.circuit => t.shareFormatCircuit,
    };

/// Shares a note, given as its [markdown], in [format]: a .md, .pdf or .docx
/// file through the share sheet, or plain text (which the share sheet can
/// also copy). [title] names the file and the document.
Future<void> shareNoteAs(
  BuildContext context, {
  required String markdown,
  required String title,
  required ShareFormat format,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final t = context.t;
  final base = safeFileBase(title, fallback: 'note');
  try {
    switch (format) {
      case ShareFormat.markdown:
        await _shareFile('$base.md', utf8.encode(markdown),
            mimeType: 'text/markdown');
      case ShareFormat.text:
        await SharePlus.instance.share(ShareParams(
          text: markdownToPlainText(markdown),
          subject: title.isEmpty ? null : title,
        ));
      case ShareFormat.pdf:
        final bytes = await NotePdf.fromMarkdown(markdown, title: title);
        await Printing.sharePdf(bytes: bytes, filename: '$base.pdf');
      case ShareFormat.docx:
        await _shareFile(
          '$base.docx',
          NoteDocx.fromMarkdown(markdown, title: title),
          mimeType: 'application/vnd.openxmlformats-officedocument.'
              'wordprocessingml.document',
        );
      case ShareFormat.circuit:
        throw UnsupportedError('A circuit file is shared by shareCircuitAs');
    }
  } catch (_) {
    final failed = format == ShareFormat.markdown || format == ShareFormat.text
        ? t.shareFailed
        : t.exportFailed;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}

Future<void> _shareFile(String name, List<int> bytes,
    {required String mimeType}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance
      .share(ShareParams(files: [XFile(file.path, mimeType: mimeType)]));
}

/// A note menu's one share row: "Share as" with the format beside it.
/// Tapping the row shares as Markdown, the default; the format opens a
/// rounded list of [formats], and picking one shares in it.
class ShareAsTile extends StatelessWidget {
  const ShareAsTile({
    super.key,
    required this.onShare,
    this.formats = ShareFormat.note,
    this.dense = false,
  });

  final ValueChanged<ShareFormat> onShare;
  final List<ShareFormat> formats;

  /// Matches a sheet of dense rows (the circuit map's).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ink = AppPalette.inkPrimary;
    return ListTile(
      dense: dense,
      leading: Icon(Icons.ios_share_rounded, color: AppPalette.inkSecondary),
      title: Text(t.shareAs,
          style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
      onTap: () => onShare(ShareFormat.markdown),
      trailing: PopupMenuButton<ShareFormat>(
        tooltip: t.shareFormat,
        position: PopupMenuPosition.under,
        color: AppPalette.sheet,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: onShare,
        itemBuilder: (_) => [
          for (final format in formats)
            PopupMenuItem(
              value: format,
              child: Text(_label(format, t),
                  style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('.md',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
              Icon(Icons.arrow_drop_down_rounded,
                  color: AppPalette.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
