import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/wiki_links.dart';
import '../theme/app_theme.dart';

/// Renders body text with `[[Title]]` node/spark links (blue) and `[[@Name]]`
/// impulse/thread mentions (lavender) — brackets and the `@` hidden, colour
/// carrying the meaning. When [onOpenLink]/[onOpenMention] are given the runs
/// are tappable (the note viewer); the feed passes none so previews are inert.
class WikiText extends StatefulWidget {
  const WikiText({
    super.key,
    required this.text,
    required this.style,
    this.onOpenLink,
    this.onOpenMention,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final void Function(String title)? onOpenLink;
  final void Function(String name)? onOpenMention;
  final int? maxLines;

  @override
  State<WikiText> createState() => _WikiTextState();
}

class _WikiTextState extends State<WikiText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final linkStyle = widget.style.copyWith(
      color: AppPalette.scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final mentionStyle = widget.style.copyWith(
      color: AppPalette.mentionAccent,
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    for (final s in splitWikiSpans(widget.text)) {
      if (s.isMention) {
        final handler = widget.onOpenMention;
        if (handler == null) {
          spans.add(TextSpan(text: s.text, style: mentionStyle));
        } else {
          final rec = TapGestureRecognizer()
            ..onTap = () => handler(s.linkTitle!);
          _recognizers.add(rec);
          spans.add(
              TextSpan(text: s.text, style: mentionStyle, recognizer: rec));
        }
      } else if (s.isLink) {
        final handler = widget.onOpenLink;
        if (handler == null) {
          spans.add(TextSpan(text: s.text, style: linkStyle));
        } else {
          final rec = TapGestureRecognizer()
            ..onTap = () => handler(s.linkTitle!);
          _recognizers.add(rec);
          spans.add(TextSpan(text: s.text, style: linkStyle, recognizer: rec));
        }
      } else {
        spans.add(TextSpan(text: s.text));
      }
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow:
          widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}
