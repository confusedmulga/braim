import 'package:flutter/material.dart';

import '../models/note.dart';
import '../models/note_block.dart';
import '../theme/app_theme.dart';
import 'wiki_text.dart';
import '../platform/braim_image.dart';

/// The read view of a rich-text body — a note's, or the note on a spark. It
/// draws the saved Quill blocks without building any editor: every inline mark
/// (bold, italic, highlight, hyperlinks), block format (headings, quotes,
/// lists, checkboxes, indent, alignment), images and link cards, with inline
/// hyperlinks and `[[links]]` tappable. Both read views use this one widget so
/// a saved body looks and behaves the same wherever it is opened.
class NoteReadBody extends StatelessWidget {
  const NoteReadBody({
    super.key,
    required this.blocks,
    this.fontScale = 1.0,
    this.checkedToBottom = false,
    this.fontFamily,
    this.onOpenLink,
    this.onOpenMention,
    this.onToggleCheck,
  });

  final List<NoteBlock> blocks;

  /// The per-note text-size multiplier, so the read view matches the editor.
  final double fontScale;

  /// Shows ticked checklist items after the unticked ones (display only).
  final bool checkedToBottom;

  /// A book page's face, so the still frame shown during the open transition
  /// matches the live editor and doesn't flash a different font.
  final String? fontFamily;

  /// Follows a `[[wiki-link]]` tapped in the body; null disables link taps
  /// (during the open animation, or for articles).
  final void Function(String title)? onOpenLink;

  /// Follows a `[[@Name]]` impulse/thread mention tapped in the body.
  final void Function(String name)? onOpenMention;

  /// Ticks the checkbox on line [lineIndex] of block [blockIndex] straight from
  /// the read view. Null renders checkboxes read-only (open transition frame).
  final void Function(int blockIndex, int lineIndex, bool nowChecked)?
      onToggleCheck;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      if (b.isImage && b.imagePath.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BraimImage(b.imagePath,
                fit: BoxFit.cover, width: double.infinity, cacheWidth: 1440),
          ),
        ));
      } else if (b.isLink && b.url.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.bubbleGlass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 18, color: AppPalette.inkSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.linkTitle.isNotEmpty ? b.linkTitle : b.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
      } else if (b.isText) {
        // Render line by line from the styled delta so every inline mark
        // (bold/italic/…) and block format (headings, quotes, lists, indent,
        // alignment) the editor showed survives into the saved read view.
        final lines = richToStyledLines(b.text);
        if (lines.isEmpty) continue;
        // Keep each line's original index (for tap-to-tick), then optionally
        // sink ticked items to the bottom for display only.
        var indexed = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
        if (checkedToBottom) {
          indexed = [
            ...indexed.where((e) => e.$2.kind != RichLineKind.checkedItem),
            ...indexed.where((e) => e.$2.kind == RichLineKind.checkedItem),
          ];
        }
        final lineWidgets = <Widget>[];
        var ordinal = 0;
        for (final (li, l) in indexed) {
          if (l.kind == RichLineKind.ordered) {
            ordinal++;
          } else {
            ordinal = 0;
          }
          lineWidgets.add(_lineWidget(l, bi, li, ordinal));
        }
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lineWidgets,
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The base text style for a line, honouring its heading level / quote.
  /// Inline run marks are layered on top of this by [RichBodyText].
  TextStyle _baseStyle(RichLine l) {
    final book = fontFamily != null;
    final color = AppPalette.inkPrimary;
    // The per-note multiplier keeps the read view in step with the editor.
    final scale = fontScale;
    if (l.header == 1) {
      return TextStyle(
        fontFamily: fontFamily ?? kNoteHeadingFont,
        fontSize: (book ? 24 : 26) * scale,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: color,
      );
    }
    if (l.header == 2) {
      return TextStyle(
        fontFamily: fontFamily ?? kNoteHeadingFont,
        fontSize: (book ? 20 : 21) * scale,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      );
    }
    var s = TextStyle(
      fontFamily: fontFamily ?? activeBodyFont,
      fontSize: (book ? 18 : 21) * scale,
      height: book ? 1.5 : 1.35,
      color: color,
    );
    if (l.quote) {
      s = s.copyWith(
          color: color.withValues(alpha: 0.72), fontStyle: FontStyle.italic);
    }
    return s;
  }

  TextAlign? _alignOf(RichLine l) {
    switch (l.align) {
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

  Widget _text(RichLine l, TextStyle style) => RichBodyText(
        runs: l.runs.isEmpty ? [RichRun(l.text)] : l.runs,
        style: style,
        onOpenLink: onOpenLink,
        onOpenMention: onOpenMention,
        textAlign: _alignOf(l),
      );

  Widget _lineWidget(RichLine l, int blockIndex, int lineIndex, int ordinal) {
    final style = _baseStyle(l);
    Widget content;
    switch (l.kind) {
      case RichLineKind.plain:
        content = _text(l, style);
      case RichLineKind.checkedItem:
      case RichLineKind.uncheckedItem:
        final checked = l.kind == RichLineKind.checkedItem;
        final itemStyle = checked
            ? style.copyWith(
                decoration: TextDecoration.lineThrough,
                color: AppPalette.inkSecondary,
                // Tie the strike line to the text colour, else it can render in
                // the ambient (white) ink and look like it's crossing out air.
                decorationColor: AppPalette.inkSecondary)
            : style;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 10),
              child: Icon(
                checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: checked
                    ? AppPalette.scheme.primary
                    : AppPalette.inkSecondary,
              ),
            ),
            Expanded(child: _text(l, itemStyle)),
          ],
        );
        content = onToggleCheck == null
            ? row
            : InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onToggleCheck!(blockIndex, lineIndex, !checked),
                child: row,
              );
      case RichLineKind.bullet:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 10),
              child: Text('•', style: style),
            ),
            Expanded(child: _text(l, style)),
          ],
        );
      case RichLineKind.ordered:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 10),
              child: Text('$ordinal.', style: style),
            ),
            Expanded(child: _text(l, style)),
          ],
        );
    }
    // A quote gets a soft left rule; indent shifts the whole line in.
    if (l.quote) {
      content = Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: AppPalette.inkPrimary.withValues(alpha: 0.28),
                width: 3),
          ),
        ),
        child: content,
      );
    }
    final topPad = l.header == 1 ? 10.0 : (l.header == 2 ? 8.0 : 3.0);
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 3, left: l.indent * 20.0),
      child: content,
    );
  }
}
