import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../models/note.dart';
import '../services/journal_format.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_greeting.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import 'daily_day_screen.dart';
import 'journal_year_screen.dart';
import 'note_editor_screen.dart';
import 'reflexes_screen.dart';

/// The Narrative tab: a swipeable week strip on top (hold it for the month
/// calendar), then The Books / Journal tabs — the journal day view lives in
/// the Journal tab; The Books shelf comes later.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.controller});

  final ScrollController controller;

  @override
  JournalScreenState createState() => JournalScreenState();
}

class JournalScreenState extends State<JournalScreen> {
  /// Both pagers start here; page - base = weeks/months away from now.
  static const _basePage = 5000;

  late DateTime _selected;
  late final PageController _weekCtrl;

  /// Months away from the current month for the calendar sheet's pager.
  int _monthDelta = 0;

  /// The day new entries are written for (read by the shell's pencil button).
  DateTime get selectedDate => _selected;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// A "Wednesday, August 26" label for a journal entry's own date.
  static String _entryDayLabel(Note n) {
    final d = DateTime.tryParse(n.journalDate ?? '');
    return d == null ? '' : DateFormat('EEEE, MMMM d').format(d);
  }

  /// Monday of the week containing [d] (the strip runs Mon..Sun).
  static DateTime _mondayOf(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(DateTime.now());
    _weekCtrl = PageController(initialPage: _basePage);
  }

  @override
  void dispose() {
    _weekCtrl.dispose();
    super.dispose();
  }

  /// Snaps the strip back to now and re-selects today (active-tab re-tap).
  void resetToToday() {
    setState(() {
      _selected = _dateOnly(DateTime.now());
      _monthDelta = 0;
    });
    if (_weekCtrl.hasClients) {
      _weekCtrl.animateToPage(
        _basePage,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectDay(DateTime day) {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _selected = _dateOnly(day);
      // Remember the month so the calendar sheet reopens where it matters.
      _monthDelta =
          (day.year - today.year) * 12 + day.month - today.month;
    });
    if (_weekCtrl.hasClients) {
      final weeks = _mondayOf(day).difference(_mondayOf(today)).inDays ~/ 7;
      _weekCtrl.animateToPage(
        _basePage + weeks,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// The month calendar, summoned by holding the week strip.
  void _showCalendarSheet() {
    final state = context.read<AppState>();
    final today = _dateOnly(DateTime.now());
    final ctrl = PageController(initialPage: _basePage + _monthDelta);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _CalendarCard(
              controller: ctrl,
              monthDelta: _monthDelta,
              onMonthChanged: (d) {
                setSheet(() {});
                setState(() => _monthDelta = d);
              },
              selected: _selected,
              today: today,
              daysWithEntries: state.journalDaysIn,
              onSelect: (day) {
                Navigator.pop(ctx);
                _selectDay(day);
              },
              onJump: () async {
                Navigator.pop(ctx);
                await _pickDate();
              },
            ),
          ),
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData(
          fontFamily: 'Lora',
          colorScheme: AppPalette.dark
              ? const ColorScheme.dark(
                  primary: AppPalette.journalAccent,
                  onPrimary: Colors.white,
                  surface: Color(0xFF1E2028),
                )
              : const ColorScheme.light(
                  primary: AppPalette.journalAccent,
                  onPrimary: Colors.white,
                ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _selectDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = _dateOnly(DateTime.now());
    // The diary section lists the whole month's entries (each labelled with its
    // own date), not just the selected day.
    final entries =
        state.journalEntriesInMonth(_selected.year, _selected.month);
    final memories = state.journalOnThisDay(_selected);
    final years = state.journalYears();

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 140),
      children: [
        const FeedGreeting(picker: pickJournalGreeting),
        // Hold the strip to summon the month calendar.
        GestureDetector(
          onLongPress: _showCalendarSheet,
          child: _WeekStrip(
            controller: _weekCtrl,
            selected: _selected,
            today: today,
            pinned: state.pinnedReflex,
            onSelect: _selectDay,
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            context.t.holdForCalendar,
            style: TextStyle(
              fontSize: 10.5,
              color: AppPalette.inkSecondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Pinned just below the week strip: the green "today's progress"
        // dashboard, always visible regardless of the reorderable order below.
        const TodayProgressCard(),
        // The three movable sections, in the user's chosen order.
        for (final section in state.journalOrder) ...[
          _journalSection(
              context, section, state, today, entries, memories, years),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  /// Builds one of the journal's three reorderable sections: the daily-day
  /// tasks, the reflex date card, or the diary entries (with on-this-day and
  /// the year rail).
  Widget _journalSection(
    BuildContext context,
    String section,
    AppState state,
    DateTime today,
    List<Note> entries,
    List<Note> memories,
    List<int> years,
  ) {
    switch (section) {
      case 'tasks':
        return DailyDayList(date: _selected);
      case 'card':
        // The date card shows the combined completion across every reflex today
        // (the green card tracks a single chosen impulse instead).
        final combined = state.todayProgress;
        final cardProgress =
            combined.total == 0 ? null : combined.fraction;
        return GlassMorph(
          closedRadius: 20,
          openBuilder: (_) => ReflexesScreen(date: _selected),
          closedBuilder: (context, open) => DailyDayCard(
            date: _selected,
            projectCount: state.reflexes.length,
            progress: cardProgress,
            onTap: open,
          ),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Text(
                    context.t.sectionEntries,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('MMMM yyyy').format(_selected),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.journalAccent,
                    ),
                  ),
                ],
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Column(
                  children: [
                    Icon(Icons.auto_stories_outlined,
                        size: 42, color: AppPalette.inkSecondary),
                    const SizedBox(height: 10),
                    Text(context.t.noEntriesThisMonth,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                    // Entries can only be written on the day itself, so the
                    // pencil hint only applies when today is selected.
                    if (_selected == today) ...[
                      const SizedBox(height: 3),
                      Text(context.t.tapPencilToWrite,
                          style: TextStyle(
                              color: AppPalette.inkSecondary, fontSize: 12.5)),
                    ],
                  ],
                ),
              )
            else
              for (var i = 0; i < entries.length; i++) ...[
                // A date + day header at the start of each day's group, so every
                // entry across the month is clearly dated.
                if (i == 0 ||
                    entries[i].journalDate != entries[i - 1].journalDate)
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 10, 4, 6),
                    child: Text(
                      _entryDayLabel(entries[i]),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassMorph(
                    key: ValueKey(entries[i].id),
                    openBuilder: (_) =>
                        NoteEditorScreen(note: entries[i], isNew: false),
                    closedBuilder: (context, open) =>
                        JournalEntryTile(note: entries[i], onTap: open),
                  ),
                ),
              ],
            // On this day: entries written on this date in earlier years.
            if (memories.isNotEmpty) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded,
                        size: 15, color: AppPalette.journalAccent),
                    const SizedBox(width: 6),
                    Text(
                      context.t.onThisDay.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              for (final n in memories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassMorph(
                    key: ValueKey('otd-${n.id}'),
                    openBuilder: (_) => NoteEditorScreen(note: n, isNew: false),
                    closedBuilder: (context, open) => _MemoryTile(
                      note: n,
                      fromYear: _selected.year,
                      onTap: open,
                    ),
                  ),
                ),
            ],
            // Years appear only once something has been written in them.
            if (years.isNotEmpty) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  context.t.sectionYears,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkSecondary,
                  ),
                ),
              ),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final year in years)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: YearCard(
                          year: year,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => JournalYearScreen(year: year)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
    }
  }
}

/// A week-per-page day picker in a rounded frosted frame: each day is a column
/// of number-over-weekday, and the selected day sits in a white rounded pill.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.controller,
    required this.selected,
    required this.today,
    required this.pinned,
    required this.onSelect,
  });

  final PageController controller;
  final DateTime selected;
  final DateTime today;
  final Impulse pinned;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = JournalScreenState._mondayOf(today);
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 70,
        child: PageView.builder(
          controller: controller,
          itemBuilder: (context, page) {
            final weekMonday = monday.add(
                Duration(days: 7 * (page - JournalScreenState._basePage)));
            return Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _DayCell(
                      day: weekMonday.add(Duration(days: i)),
                      selected: selected,
                      today: today,
                      completion:
                          _completionFor(pinned, weekMonday.add(Duration(days: i))),
                      onSelect: onSelect,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The pinned reflex's completion (0–1) on [day], or null when there's
  /// nothing to show (no tasks, or a rest day not scheduled).
  static double? _completionFor(Impulse pinned, DateTime day) {
    if (pinned.threads.isEmpty) return null;
    if (!pinned.scheduledOn(day.weekday)) return null;
    return pinned.doneCount(AppState.dayKeyFor(day)) / pinned.threads.length;
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.completion,
    required this.onSelect,
  });

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final double? completion;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = day == selected;
    final isToday = day == today;
    final numberColor = isSelected
        ? AppPalette.journalAccent
        : (isToday ? AppPalette.journalAccent : AppPalette.inkPrimary);
    final labelColor =
        isSelected ? AppPalette.journalAccent : AppPalette.inkSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(day),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: isSelected
            ? BoxDecoration(
                color: AppPalette.sheet,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: numberColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('EEE').format(day).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 3),
            _completionPip(completion),
          ],
        ),
      ),
    );
  }
}

/// A day's completion glyph: a fire when fully done, a ring while partial,
/// nothing otherwise — the "streak" glance across the week. The partial ring
/// is a plain CustomPaint (no animation controller) so a week of them is cheap.
Widget _completionPip(double? fraction) {
  if (fraction == null || fraction <= 0) return const SizedBox(height: 14);
  if (fraction >= 1.0) {
    return const Icon(Icons.local_fire_department_rounded,
        size: 14, color: Color(0xFFF5A623));
  }
  return SizedBox(
    width: 13,
    height: 13,
    child: CustomPaint(painter: _RingPainter(fraction)),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.4;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppPalette.cardOutline;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppPalette.journalAccent;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -1.5707963, 6.2831853 * fraction.clamp(0.0, 1.0), false, progress);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

/// The month calendar on a lavender-to-sky diagonal gradient card. Swipes
/// month by month like the week strip; the button in the corner jumps
/// straight to any date. Days with entries carry a small dot.
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.controller,
    required this.monthDelta,
    required this.onMonthChanged,
    required this.selected,
    required this.today,
    required this.daysWithEntries,
    required this.onSelect,
    required this.onJump,
  });

  final PageController controller;
  final int monthDelta;
  final ValueChanged<int> onMonthChanged;
  final DateTime selected;
  final DateTime today;
  final Set<int> Function(int year, int month) daysWithEntries;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final shown = DateTime(today.year, today.month + monthDelta);
    // Size the grid to the shown month's week count so short months don't
    // leave a tall empty gap. Each day cell is 40px high.
    final daysInMonth = DateTime(shown.year, shown.month + 1, 0).day;
    final leading = DateTime(shown.year, shown.month, 1).weekday - 1;
    final gridHeight = ((leading + daysInMonth) / 7).ceil() * 40.0;
    final content = Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppPalette.scheme.surface.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  DateFormat('MMMM yyyy').format(shown),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: context.t.jumpToDate,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.event_outlined,
                    size: 20, color: AppPalette.inkSecondary),
                onPressed: onJump,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat('EEE')
                          .format(DateTime(2024, 1, i + 1))
                          .substring(0, 1),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Height tracks the shown month's week count — no empty gap below.
          SizedBox(
            height: gridHeight,
            child: PageView.builder(
              controller: controller,
              onPageChanged: (p) =>
                  onMonthChanged(p - JournalScreenState._basePage),
              itemBuilder: (context, page) {
                final m = DateTime(today.year,
                    today.month + page - JournalScreenState._basePage);
                return _MonthGrid(
                  month: m,
                  selected: selected,
                  today: today,
                  entryDays: daysWithEntries(m.year, m.month),
                  onSelect: onSelect,
                );
              },
            ),
          ),
        ],
      ),
    );
    // Frosted glass: one BackdropFilter blurs the dimmed journal behind the
    // sheet (the same recipe as the nav island / quick-actions menu).
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: content,
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.entryDays,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Set<int> entryDays;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child:
                      _cell(context, r * 7 + c - leading + 1, daysInMonth),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int day, int daysInMonth) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 40);
    final date = DateTime(month.year, month.month, day);
    final isToday = date == today;
    final isSelected = date == selected;
    final hasEntry = entryDays.contains(day);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(date),
      child: SizedBox(
        height: 40,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: isToday || isSelected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? AppPalette.journalAccent
                        : Colors.transparent,
                    border: isSelected && !isToday
                        ? Border.all(
                            color: AppPalette.journalAccent, width: 1.6)
                        : null,
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.0,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: isToday ? Colors.white : AppPalette.inkPrimary,
                  ),
                ),
                if (hasEntry)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday
                          ? Colors.white
                          : AppPalette.journalAccent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A journal entry tile. With a photo, the photo becomes the card's
/// background under a scrim so the title and preview stay readable; without
/// one it is a flat card like a note tile.
class JournalEntryTile extends StatelessWidget {
  const JournalEntryTile({super.key, required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(note.journalDate ?? '');
    final title = note.title.trim().isNotEmpty
        ? note.title.trim()
        : (date != null
            ? formatJournalDate(date)
            : context.t.untitledEntry);
    final preview = note.textPreview;
    final thumb = note.thumbnailPath;

    if (thumb != null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 140,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 900),
              // Bottom scrim so the text reads over any photo while the
              // picture stays mostly visible.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x14000000),
                      Color(0xB3000000),
                    ],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: FlatCard(
        fill: NoteColors.resolve(note.colorValue),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppPalette.inkPrimary,
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: AppPalette.inkSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact "on this day" memory: a "N years ago" pill over the entry's title
/// and a preview line. Tapping opens the entry.
class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.note,
    required this.fromYear,
    required this.onTap,
  });

  final Note note;

  /// The year being viewed, so the pill reads "N years ago" relative to it.
  final int fromYear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(note.journalDate ?? '');
    final years = date == null ? 1 : (fromYear - date.year).clamp(1, 9999);
    final title = note.title.trim().isNotEmpty
        ? note.title.trim()
        : (date != null
            ? formatJournalDate(date)
            : context.t.untitledEntry);
    final preview = note.textPreview.replaceAll('\n', ' ').trim();

    return GestureDetector(
      onTap: onTap,
      child: FlatCard(
        fill: NoteColors.resolve(note.colorValue),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppPalette.journalAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.t.onThisDayYearsAgo(years),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.journalAccent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppPalette.inkPrimary,
              ),
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppPalette.inkSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
