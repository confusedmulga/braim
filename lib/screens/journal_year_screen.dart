import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
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
                      fontWeight: FontWeight.w800,
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

/// One journal year as a two-column grid of month blocks, like the Cards
/// feed. Only months that have entries appear.
class JournalYearScreen extends StatelessWidget {
  const JournalYearScreen({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final z = _zodiacIndex(year);
    final months = [
      for (var m = 1; m <= 12; m++)
        if (state.journalEntriesInMonth(year, m).isNotEmpty) m,
    ];

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          foregroundColor: AppPalette.inkPrimary,
          title: Text('$year · ${_zodiacNames[z]} ${_zodiacEmoji[z]}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
          ),
          itemCount: months.length,
          itemBuilder: (context, i) {
            final month = months[i];
            return _MonthBlock(
              year: year,
              month: month,
              entryCount: state.journalEntriesInMonth(year, month).length,
              cover: _coverFor(state, year, month),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        JournalMonthScreen(year: year, month: month)),
              ),
              onLongPress: () => _pickCover(context, year, month),
            );
          },
        ),
      ),
    );
  }

  /// The user's chosen cover, else a stable pick from that month's photos.
  static String? _coverFor(AppState state, int year, int month) {
    final key = _monthKey(year, month);
    final chosen = state.journalMonthCover(key);
    if (chosen != null) return chosen;
    final images = _monthImages(state, year, month);
    if (images.isEmpty) return null;
    return images[(year * 12 + month) % images.length];
  }

  static String _monthKey(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  static List<String> _monthImages(AppState state, int year, int month) => [
        for (final n in state.journalEntriesInMonth(year, month))
          ...n.imagePaths,
      ];

  Future<void> _pickCover(BuildContext context, int year, int month) async {
    final state = context.read<AppState>();
    final images = _monthImages(state, year, month);
    if (images.isEmpty) return;
    final key = _monthKey(year, month);
    final current = state.journalMonthCover(key);

    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 28,
          strong: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(context.t.chooseCover,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppPalette.textPrimary)),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    // First cell clears back to the automatic pick.
                    GestureDetector(
                      onTap: () => Navigator.pop(context, '__auto__'),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: current == null
                                ? AppPalette.journalAccent
                                : Colors.white24,
                            width: current == null ? 2.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(context.t.coverAutomatic,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppPalette.textSecondary)),
                        ),
                      ),
                    ),
                    for (final path in images)
                      GestureDetector(
                        onTap: () => Navigator.pop(context, path),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: current == path
                                  ? AppPalette.journalAccent
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Image.file(File(path),
                              fit: BoxFit.cover, cacheWidth: 300),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected == null) return;
    await state.setJournalMonthCover(
        key, selected == '__auto__' ? null : selected);
  }
}

/// A month as a compact block tile (like the Cards feed): cover photo or
/// gradient, month name and entry count over a bottom scrim.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    required this.year,
    required this.month,
    required this.entryCount,
    required this.cover,
    required this.onTap,
    required this.onLongPress,
  });

  final int year;
  final int month;
  final int entryCount;
  final String? cover;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              Image.file(File(cover!),
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (_, _, _) => _plain())
            else
              _plain(),
            // Bottom scrim so the month name always reads.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMMM').format(DateTime(year, month)),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    context.t.itemsCount(entryCount),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xE6FFFFFF),
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

  Widget _plain() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppPalette.journalCalendarGradient,
        ),
      ),
    );
  }
}

/// All entries of one journal month, newest day first.
class JournalMonthScreen extends StatelessWidget {
  const JournalMonthScreen(
      {super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.journalEntriesInMonth(year, month);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          foregroundColor: AppPalette.inkPrimary,
          title: Text(DateFormat('MMMM yyyy').format(DateTime(year, month)),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: entries.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories_outlined,
                        size: 48, color: AppPalette.inkSecondary),
                    const SizedBox(height: 10),
                    Text(context.t.noEntriesThisMonth,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
                children: [
                  for (final n in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassMorph(
                        key: ValueKey(n.id),
                        openBuilder: (_) =>
                            NoteEditorScreen(note: n, isNew: false),
                        closedBuilder: (context, open) =>
                            JournalEntryTile(note: n, onTap: open),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
