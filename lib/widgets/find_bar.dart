import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'frosted_chrome.dart';

/// What a read view marks while Find is open: every match of [query], and the
/// [current] one (counted in reading order), which carries [currentKey] so
/// the screen can scroll to it.
class FindHighlight {
  const FindHighlight(this.query, this.current, this.currentKey);

  final String query;
  final int current;
  final GlobalKey currentKey;
}

/// Every match of [query] in [text], ignoring case.
List<TextRange> findRanges(String text, String query) {
  if (query.isEmpty || text.isEmpty) return const [];
  return [
    for (final m
        in RegExp(RegExp.escape(query), caseSensitive: false).allMatches(text))
      if (m.end > m.start) TextRange(start: m.start, end: m.end),
  ];
}

/// The marker on a match, and the stronger one on the current match. Dark
/// ink on both so the text stays readable in the dark theme too.
const _matchFill = Color(0xFFFFF176);
const _currentFill = Color(0xFFFFA726);
const _matchInk = Color(0xFF202124);

/// [spans] (plain TextSpans, no children, as a read view builds them) with
/// the matches [ranges] marked. Offsets count over the spans' text in order.
/// The current match — [ranges] index [current] — is set as its own small
/// widget keyed with [currentKey], so it can be found and scrolled to; it
/// needs [baseStyle], the style the spans inherit, to look the same.
List<InlineSpan> highlightSpans(
  List<InlineSpan> spans,
  List<TextRange> ranges, {
  required TextStyle baseStyle,
  int? current,
  GlobalKey? currentKey,
}) {
  if (ranges.isEmpty) return spans;
  final out = <InlineSpan>[];
  var pos = 0;
  var ri = 0;
  var keyed = false;
  for (final span in spans) {
    final text = span is TextSpan ? span.text ?? '' : '';
    if (span is! TextSpan || text.isEmpty) {
      out.add(span);
      continue;
    }
    final start = pos;
    final end = pos + text.length;
    var cut = start;
    while (ri < ranges.length && ranges[ri].start < end) {
      final r = ranges[ri];
      final a = r.start > cut ? r.start : cut;
      final b = r.end < end ? r.end : end;
      if (a > cut) {
        out.add(_piece(span, text.substring(cut - start, a - start)));
      }
      if (b > a) {
        final isCurrent = ri == current;
        final piece = text.substring(a - start, b - start);
        final style = baseStyle.merge(span.style).copyWith(
            backgroundColor: isCurrent ? _currentFill : _matchFill,
            color: _matchInk,
            decorationColor: _matchInk);
        if (isCurrent && currentKey != null && !keyed) {
          keyed = true;
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(piece, key: currentKey, style: style),
          ));
        } else {
          out.add(TextSpan(
              text: piece, style: style, recognizer: span.recognizer));
        }
      }
      cut = b;
      if (r.end <= end) {
        ri++;
      } else {
        break;
      }
    }
    if (cut < end) out.add(_piece(span, text.substring(cut - start)));
    pos = end;
  }
  return out;
}

TextSpan _piece(TextSpan of, String text) =>
    TextSpan(text: text, style: of.style, recognizer: of.recognizer);

/// Scrolls [key]'s widget about a third of the way down the screen, clear of
/// the pinned bars (and into view in any sideways scroller, such as a table).
void revealKey(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return;
  Scrollable.ensureVisible(ctx,
      alignment: 0.3,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic);
}

/// Scrolls the scroll view around [context] so [rect] (in [target]'s own
/// coordinates) sits about a third of the way down.
void revealRect(BuildContext context, RenderObject target, Rect rect) {
  final position = Scrollable.maybeOf(context)?.position;
  final viewport = RenderAbstractViewport.maybeOf(target);
  if (position == null || viewport == null) return;
  final offset = viewport
      .getOffsetToReveal(target, 0.3, rect: rect)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  position.animateTo(offset,
      duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
}

/// The Find bar pinned under a note's top bar: the search field, where the
/// current match is among all of them, previous / next, and close.
class FindBar extends StatelessWidget {
  const FindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.total,
    required this.current,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// How many matches there are, and which one (from 0) is showing.
  final int total;
  final int current;

  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ink = AppPalette.inkPrimary;
    return FrostedSurface(
      borderRadius: FrostedCircleButton.size / 2,
      child: SizedBox(
        height: FrostedCircleButton.size,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.search_rounded, size: 20, color: AppPalette.inkSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: (_) {
                  onNext();
                  focusNode.requestFocus();
                },
                style: TextStyle(fontSize: 16, color: ink),
                decoration: InputDecoration.collapsed(
                  hintText: t.findInNote,
                  hintStyle: TextStyle(color: AppPalette.inkSecondary),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  total == 0
                      ? t.matchesFound(0)
                      : t.findPosition(current + 1, total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.inkSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.findPrevious,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: total > 0 ? onPrevious : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.findNext,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: total > 0 ? onNext : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: t.findClose,
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
