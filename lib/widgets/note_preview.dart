import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_theme.dart';
import 'wiki_text.dart';

/// A compact body preview for feed cards. Plain prose wraps as before (now with
/// coloured `[[links]]`/mentions instead of raw brackets); checklists, bullets
/// and numbered lists keep their markers and tick state so the card mirrors the
/// note instead of flattening everything to prose.
class NotePreview extends StatelessWidget {
  const NotePreview({
    super.key,
    required this.note,
    required this.maxLines,
    required this.style,
    this.onColor = false,
  });

  final Note note;
  final int maxLines;
  final TextStyle style;

  /// True when this sits on a colour-swatch card. Then checkbox markers, ticked
  /// items and links derive from the card's dark ink instead of the theme
  /// accents (which are tuned for the dark app surface, not a bright tile).
  final bool onColor;

  Color get _ink => style.color ?? AppPalette.inkPrimary;
  Color get _muted =>
      onColor ? _ink.withValues(alpha: 0.6) : AppPalette.inkSecondary;
  Color get _accent => onColor ? _ink : AppPalette.scheme.primary;

  @override
  Widget build(BuildContext context) {
    final lines = <(RichLine, int)>[]; // (line, ordinal-for-numbered-lists)
    var ordinal = 0;
    var structured = false;
    outer:
    for (final b in note.blocks) {
      if (b.isText) {
        for (final l in richToLines(b.text)) {
          if (l.kind == RichLineKind.plain && l.text.trim().isEmpty) continue;
          if (l.kind != RichLineKind.plain) structured = true;
          if (l.kind == RichLineKind.ordered) {
            ordinal++;
          } else {
            ordinal = 0;
          }
          lines.add((l, ordinal));
          if (lines.length >= maxLines) break outer;
        }
      } else if (b.isLink && (b.linkTitle.isNotEmpty || b.url.isNotEmpty)) {
        lines.add((
          RichLine(b.linkTitle.isNotEmpty ? b.linkTitle : b.url,
              RichLineKind.plain),
          0
        ));
        if (lines.length >= maxLines) break;
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    // No list structure: keep the flowing single-Text look (long notes still
    // fill the card), just with coloured links/mentions.
    if (!structured) {
      return WikiText(
          text: note.textPreview,
          style: style,
          maxLines: maxLines,
          accent: onColor ? _ink : null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (l, ord) in lines) _row(l, ord)],
    );
  }

  Widget _row(RichLine l, int ordinal) {
    switch (l.kind) {
      case RichLineKind.plain:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: WikiText(
              text: l.text,
              style: style,
              maxLines: 2,
              accent: onColor ? _ink : null),
        );
      case RichLineKind.checkedItem:
      case RichLineKind.uncheckedItem:
        final checked = l.kind == RichLineKind.checkedItem;
        final itemStyle = checked
            ? style.copyWith(
                decoration: TextDecoration.lineThrough,
                color: _muted,
                // Match the strike line to the text colour so it never renders
                // in the ambient (white) ink over a checked item.
                decorationColor: _muted)
            : style;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 7),
                child: Icon(
                  checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 17,
                  color: checked ? _accent : _muted,
                ),
              ),
              Expanded(
                  child: WikiText(
                      text: l.text,
                      style: itemStyle,
                      maxLines: 1,
                      accent: onColor ? _ink : null)),
            ],
          ),
        );
      case RichLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 8),
                child: Text('•', style: style),
              ),
              Expanded(
                  child: WikiText(
                      text: l.text,
                      style: style,
                      maxLines: 1,
                      accent: onColor ? _ink : null)),
            ],
          ),
        );
      case RichLineKind.ordered:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 8),
                child: Text('$ordinal.', style: style),
              ),
              Expanded(
                  child: WikiText(
                      text: l.text,
                      style: style,
                      maxLines: 1,
                      accent: onColor ? _ink : null)),
            ],
          ),
        );
    }
  }
}
