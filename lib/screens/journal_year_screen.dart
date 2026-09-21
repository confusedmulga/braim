import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import 'journal_screen.dart';
import 'note_editor_screen.dart';

/// Chinese zodiac, anchored on 2020 = Rat.
const _zodiacNames = [
  'Rat', 'Ox', 'Tiger', 'Rabbit', 'Dragon', 'Snake',
  'Horse', 'Goat', 'Monkey', 'Rooster', 'Dog', 'Pig',
];
const _zodiacEmoji = [
  '🐀', '🐂', '🐅', '🐇', '🐉', '🐍',
  '🐴', '🐐', '🐒', '🐓', '🐕', '🐖',
];

int _zodiacIndex(int year) => ((year - 2020) % 12 + 12) % 12;

/// A small horizontal card for one journal year, dressed as its Chinese
/// zodiac animal (every year is a different one).
class YearCard extends StatelessWidget {
  const YearCard({super.key, required this.year, required this.onTap});

  final int year;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final z = _zodiacIndex(year);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x33FFD28A)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFA93226), Color(0xFF6E1F14)],
          ),
        ),
        child: Stack(
          children: [
            // The animal, oversized and cropped like a print.
            Positioned(
              right: -8,
              bottom: -12,
              child: Opacity(
                opacity: 0.9,
                child: Text(_zodiacEmoji[z],
                    style: const TextStyle(fontSize: 56)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$year',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _zodiacNames[z],
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFD28A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One journal year as a single Jan→Dec stream of entries, split by month
/// section headers, with a right-edge month scrubber for quick jumps — no
/// month folders.
class JournalYearScreen extends StatefulWidget {
  const JournalYearScreen({super.key, required this.year});

  final int year;

  @override
  State<JournalYearScreen> createState() => _JournalYearScreenState();
}

class _JournalYearScreenState extends State<JournalYearScreen> {
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _headerKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final year = widget.year;
    final z = _zodiacIndex(year);

    // Each month's entries, oldest-first, so the year reads top-to-bottom.
    final byMonth = <int, List<Note>>{};
    for (var m = 1; m <= 12; m++) {
      final entries = state.journalEntriesInMonth(year, m);
      if (entries.isNotEmpty) byMonth[m] = entries.reversed.toList();
    }
    final months = byMonth.keys.toList()..sort();
    for (final m in months) {
      _headerKeys.putIfAbsent(m, GlobalKey.new);
    }

    final counts = state.journalCountsForYear(year);
    final total = counts.values.fold(0, (a, b) => a + b);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: _YearHeatmap(year: year, counts: counts, total: total),
      ),
    ];
    for (final m in months) {
      children.add(_MonthHeader(
        key: _headerKeys[m],
        label: DateFormat('MMMM').format(DateTime(year, m)),
        count: byMonth[m]!.length,
      ));
      for (final n in byMonth[m]!) {
        children.add(Padding(
          // A little right margin clears the slim scroll bar.
          padding: const EdgeInsets.fromLTRB(14, 0, 20, 12),
          child: GlassMorph(
            key: ValueKey(n.id),
            openBuilder: (_) => NoteEditorScreen(note: n, isNew: false),
            closedBuilder: (context, open) =>
                JournalEntryTile(note: n, onTap: open),
          ),
        ));
      }
    }
    children.add(const SizedBox(height: 60));

    return FrostedScaffold(
      title: '$year · ${_zodiacNames[z]} ${_zodiacEmoji[z]}',
      body: Stack(
        children: [
          ListView(controller: _scroll, children: children),
          if (months.length > 1)
            Positioned(
              top: 12,
              bottom: 18,
              right: 2,
              child: _MonthScrubber(
                controller: _scroll,
                months: months,
                headerKeys: _headerKeys,
              ),
            ),
        ],
      ),
    );
  }
}

/// A month divider in the year stream: the month name in the journal accent
/// with a hairline rule and the entry count.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader(
      {super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppPalette.journalAccent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppPalette.inkSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
                height: 1, color: AppPalette.cardOutline),
          ),
        ],
      ),
    );
  }
}

/// A sleek fast-scroll bar on the right edge. It stays a slim thumb that
/// reflects the scroll position and never covers content; grab it and it
/// thickens, scrolls the stream, and shows a bubble naming the month you're in.
class _MonthScrubber extends StatefulWidget {
  const _MonthScrubber({
    required this.controller,
    required this.months,
    required this.headerKeys,
  });

  final ScrollController controller;
  final List<int> months; // sorted, with entries
  final Map<int, GlobalKey> headerKeys;

  @override
  State<_MonthScrubber> createState() => _MonthScrubberState();
}

class _MonthScrubberState extends State<_MonthScrubber> {
  bool _active = false;
  double _frac = 0; // 0..1 thumb position
  double _viewFrac = 0.3; // viewport / content, sets the thumb length
  bool _scrollable = false;
  int? _month; // current month, for the bubble

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final pos = widget.controller.position;
    final max = pos.maxScrollExtent;
    final vp = pos.viewportDimension;
    final scrollable = max > 4;
    final frac = max > 0 ? (pos.pixels / max).clamp(0.0, 1.0) : 0.0;
    final viewFrac = (vp <= 0) ? 0.3 : (vp / (vp + max)).clamp(0.12, 1.0);
    if (scrollable != _scrollable ||
        (viewFrac - _viewFrac).abs() > 0.01 ||
        (!_active && (frac - _frac).abs() > 0.001)) {
      setState(() {
        _scrollable = scrollable;
        _viewFrac = viewFrac;
        if (!_active) _frac = frac;
      });
    }
  }

  /// The month whose header sits at or above the current scroll offset.
  int? _monthAtOffset(double offset) {
    int? current = widget.months.isNotEmpty ? widget.months.first : null;
    for (final m in widget.months) {
      final ctx = widget.headerKeys[m]?.currentContext;
      final ro = ctx?.findRenderObject();
      if (ro == null) continue;
      final reveal = RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0);
      if (reveal.offset <= offset + 4) current = m;
    }
    return current;
  }

  void _drag(double localY, double h, double thumbH) {
    if (!widget.controller.hasClients) return;
    final frac = ((localY - thumbH / 2) / (h - thumbH)).clamp(0.0, 1.0);
    final offset = frac * widget.controller.position.maxScrollExtent;
    widget.controller.jumpTo(offset);
    setState(() {
      _active = true;
      _frac = frac;
      _month = _monthAtOffset(offset);
    });
  }

  void _end() => setState(() => _active = false);

  @override
  Widget build(BuildContext context) {
    if (!_scrollable) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final thumbH = (h * _viewFrac).clamp(40.0, h);
        final top = _frac * (h - thumbH);
        return SizedBox(
          width: 16, // hit target tucked into the entries' right margin
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The thumb: slim at rest, thicker and accented while dragging.
              Positioned(
                right: 3,
                top: top,
                height: thumbH,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  width: _active ? 8 : 4,
                  decoration: BoxDecoration(
                    color: _active
                        ? AppPalette.journalAccent
                        : AppPalette.inkSecondary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              // The month-name bubble, shown only while dragging.
              if (_active && _month != null)
                Positioned(
                  right: 20,
                  top: (top + thumbH / 2 - 16).clamp(0.0, h - 32),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppPalette.journalAccent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      DateFormat('MMMM').format(DateTime(2024, _month!)),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              // The gesture layer over the whole strip.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (d) =>
                      _drag(d.localPosition.dy, h, thumbH),
                  onVerticalDragUpdate: (d) =>
                      _drag(d.localPosition.dy, h, thumbH),
                  onVerticalDragEnd: (_) => _end(),
                  onVerticalDragCancel: _end,
                  onTapDown: (d) => _drag(d.localPosition.dy, h, thumbH),
                  onTapUp: (_) => _end(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A GitHub-style contribution grid for a journal year: one small square per
/// day, tinted by how many entries were written. Passive and motivating — it
/// fills in as the year goes, no streaks to break.
class _YearHeatmap extends StatelessWidget {
  const _YearHeatmap({
    required this.year,
    required this.counts,
    required this.total,
  });

  final int year;
  final Map<String, int> counts;
  final int total;

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Color _levelColor(int count) {
    final a = count <= 0
        ? 0.10
        : count == 1
            ? 0.40
            : count == 2
                ? 0.65
                : 1.0;
    return AppPalette.journalAccent.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, 1, 1);
    // Monday on or before Jan 1 — the top-left of the grid.
    final firstMonday = first.subtract(Duration(days: first.weekday - 1));
    final last = DateTime(year, 12, 31);
    final cols = (last.difference(firstMonday).inDays ~/ 7) + 1;
    const gap = 2.5;

    return GlassPanel(
      borderRadius: 18,
      blur: 0,
      color: AppPalette.surfaceGlass,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t.journalYearEntries(total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
              Text(context.t.heatmapLess,
                  style: TextStyle(
                      fontSize: 10.5, color: AppPalette.inkSecondary)),
              const SizedBox(width: 5),
              for (final c in const [0, 1, 2, 3]) ...[
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: _levelColor(c),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              const SizedBox(width: 5),
              Text(context.t.heatmapMore,
                  style: TextStyle(
                      fontSize: 10.5, color: AppPalette.inkSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cell =
                  ((c.maxWidth - (cols - 1) * gap) / cols).clamp(2.0, 16.0);
              return Column(
                children: [
                  for (var r = 0; r < 7; r++) ...[
                    if (r > 0) const SizedBox(height: gap),
                    Row(
                      children: [
                        for (var col = 0; col < cols; col++) ...[
                          if (col > 0) const SizedBox(width: gap),
                          _cell(firstMonday.add(Duration(days: col * 7 + r)),
                              cell),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(DateTime date, double size) {
    // Days spilling out of the year (padding at the ends) are left blank.
    if (date.year != year) return SizedBox(width: size, height: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _levelColor(counts[_key(date)] ?? 0),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
