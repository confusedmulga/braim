import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart';
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
    this.accent,
  });

  final String text;
  final TextStyle style;
  final void Function(String title)? onOpenLink;
  final void Function(String name)? onOpenMention;
  final int? maxLines;

  /// Overrides the link/mention colour. Feed cards with a colour swatch pass the
  /// card's dark ink here so links stay legible on the light tile (the theme
  /// accents are tuned for the dark app surface, not a bright card).
  final Color? accent;

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
      color: widget.accent ?? AppPalette.scheme.primary,
      fontWeight: FontWeight.w700,
    );
    final mentionStyle = widget.style.copyWith(
      color: widget.accent ?? AppPalette.mentionAccent,
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

/// Like [WikiText] but for pre-parsed [RichRun]s: it paints each run's inline
/// formatting (bold/italic/underline/strikethrough/highlight) on top of [style]
/// while still turning `[[Title]]` links and `[[@Name]]` mentions inside a run
/// into coloured, tappable spans. Used by the note read view so saved notes
/// look exactly like they did in the editor.
class RichBodyText extends StatefulWidget {
  const RichBodyText({
    super.key,
    required this.runs,
    required this.style,
    this.onOpenLink,
    this.onOpenMention,
    this.textAlign,
  });

  final List<RichRun> runs;
  final TextStyle style;
  final void Function(String title)? onOpenLink;
  final void Function(String name)? onOpenMention;
  final TextAlign? textAlign;

  @override
  State<RichBodyText> createState() => _RichBodyTextState();
}

class _RichBodyTextState extends State<RichBodyText> {
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

  /// The run's own inline marks applied over [widget.style].
  TextStyle _runStyle(RichRun run) {
    var s = widget.style;
    if (run.bold) s = s.copyWith(fontWeight: FontWeight.w700);
    if (run.italic) s = s.copyWith(fontStyle: FontStyle.italic);
    final decos = <TextDecoration>[];
    if (run.underline) decos.add(TextDecoration.underline);
    if (run.strike) decos.add(TextDecoration.lineThrough);
    if (decos.isNotEmpty) {
      s = s.copyWith(decoration: TextDecoration.combine(decos));
    }
    // Highlight: light background plus a fixed dark ink so it stays readable in
    // dark theme too (where the body ink is light).
    if (run.highlight) {
      s = s.copyWith(
        backgroundColor: const Color(0xFFFFE082),
        color: const Color(0xFF202124),
      );
    }
    // An inline hyperlink reads as one: accent-coloured and underlined.
    if (run.link != null) {
      s = s.copyWith(
        color: AppPalette.scheme.primary,
        decoration: TextDecoration.combine([
          if (s.decoration != null) s.decoration!,
          TextDecoration.underline,
        ]),
      );
    }
    return s;
  }

  Future<void> _openUrl(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing to do: the note stays put.
    }
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final spans = <InlineSpan>[];
    for (final run in widget.runs) {
      final runStyle = _runStyle(run);
      final link = run.link;
      if (link != null) {
        // A hyperlink run is one tappable span that opens in the browser.
        final rec = TapGestureRecognizer()..onTap = () => _openUrl(link);
        _recognizers.add(rec);
        spans.add(TextSpan(text: run.text, style: runStyle, recognizer: rec));
        continue;
      }
      for (final s in splitWikiSpans(run.text)) {
        if (s.isMention || s.isLink) {
          final accent =
              s.isMention ? AppPalette.mentionAccent : AppPalette.scheme.primary;
          final linkStyle =
              runStyle.copyWith(color: accent, fontWeight: FontWeight.w700);
          final handler = s.isMention ? widget.onOpenMention : widget.onOpenLink;
          if (handler == null) {
            spans.add(TextSpan(text: s.text, style: linkStyle));
          } else {
            final rec = TapGestureRecognizer()..onTap = () => handler(s.linkTitle!);
            _recognizers.add(rec);
            spans.add(
                TextSpan(text: s.text, style: linkStyle, recognizer: rec));
          }
        } else {
          spans.add(TextSpan(text: s.text, style: runStyle));
        }
      }
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign ?? TextAlign.start,
    );
  }
}
