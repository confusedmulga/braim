import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/journal_format.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import 'journal_year_screen.dart';
import 'note_editor_screen.dart';

/// The Journal tab: a swipeable week strip on top (today selected by
/// default), a swipeable month calendar with a jump-to-date picker, the
/// entries written on the selected day, and year cards for browsing back.
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
  late final PageController _monthCtrl;

  /// Months away from the current month shown by the calendar pager.
  int _monthDelta = 0;

  /// The day new entries are written for (read by the shell's pencil button).
  DateTime get selectedDate => _selected;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday of the week containing [d] (the strip runs Mon..Sun).
  static DateTime _mondayOf(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(DateTime.now());
    _weekCtrl = PageController(initialPage: _basePage);
    _monthCtrl = PageController(initialPage: _basePage);
  }

  @override
  void dispose() {
    _weekCtrl.dispose();
    _monthCtrl.dispose();
    super.dispose();
  }

  /// Snaps the strip and calendar back to now and re-selects today. Wired to
  /// the "Journal" title tap (and active-tab re-tap) in the shell.
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
    if (_monthCtrl.hasClients) {
      _monthCtrl.animateToPage(
        _basePage,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectDay(DateTime day, {bool syncCalendar = false}) {
    final today = _dateOnly(DateTime.now());
    setState(() => _selected = _dateOnly(day));
    if (_weekCtrl.hasClients) {
      final weeks = _mondayOf(day).difference(_mondayOf(today)).inDays ~/ 7;
      _weekCtrl.animateToPage(
        _basePage + weeks,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (syncCalendar && _monthCtrl.hasClients) {
      final months =
          (day.year - today.year) * 12 + day.month - today.month;
      setState(() => _monthDelta = months);
      _monthCtrl.animateToPage(
        _basePage + months,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: ThemeData(
          fontFamily: 'SpaceGrotesk',
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
    _selectDay(picked, syncCalendar: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = _dateOnly(DateTime.now());
    final entries = state.journalEntriesOn(_selected);
    final years = state.journalYears();

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 140),
      children: [
        _WeekStrip(
          controller: _weekCtrl,
          selected: _selected,
          today: today,
          onSelect: _selectDay,
        ),
        const SizedBox(height: 14),
        _CalendarCard(
          controller: _monthCtrl,
          monthDelta: _monthDelta,
          onMonthChanged: (delta) => setState(() => _monthDelta = delta),
          selected: _selected,
          today: today,
          daysWithEntries: state.journalDaysIn,
          onSelect: _selectDay,
          onJump: _pickDate,
        ),
        const SizedBox(height: 20),
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
                formatJournalDate(_selected),
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
                Text(context.t.noEntriesForDay,
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
          for (final n in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassMorph(
                key: ValueKey(n.id),
                openBuilder: (_) => NoteEditorScreen(note: n, isNew: false),
                closedBuilder: (context, open) =>
                    JournalEntryTile(note: n, onTap: open),
              ),
            ),
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

/// Static Mon..Sun labels over a week-per-page pager of day circles.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.controller,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final PageController controller;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = JournalScreenState._mondayOf(today);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat('EEE')
                        .format(monday.add(Duration(days: i))),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected.weekday == i + 1
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: selected.weekday == i + 1
                          ? AppPalette.inkPrimary
                          : AppPalette.inkSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: PageView.builder(
            controller: controller,
            itemBuilder: (context, page) {
              final weekMonday = monday.add(
                  Duration(days: 7 * (page - JournalScreenState._basePage)));
              return Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: _DayCircle(
                          day: weekMonday.add(Duration(days: i)),
                          selected: selected,
                          today: today,
                          onSelect: onSelect,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.day,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = day == selected;
    final isToday = day == today;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(day),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              isSelected ? AppPalette.journalAccent : AppPalette.bubbleGlass,
          border: Border.all(
            color: isToday && !isSelected
                ? AppPalette.journalAccent
                : AppPalette.cardOutline,
            width: isToday && !isSelected ? 1.6 : 1,
          ),
        ),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppPalette.inkPrimary,
          ),
        ),
      ),
    );
  }
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppPalette.cardOutline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppPalette.journalCalendarGradient,
        ),
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
          // Fixed height fits the tallest month, so swiping doesn't reflow.
          SizedBox(
            height: 240,
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
