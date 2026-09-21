import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import 'daily_day_screen.dart';

/// A view-only history for one impulse: a vertical, month-by-month calendar in
/// which every day that had tasks scheduled is lit — shaded by how many of that
/// day's threads were ticked — while days with no tasks (or outside the goal's
/// span) are greyed. Tapping a lit day shows that day's completed / not-done
/// tally. Opened by tapping the consistency heatmap on the impulse screen.
class ImpulseHistoryScreen extends StatefulWidget {
  const ImpulseHistoryScreen({super.key, this.impulseId});

  /// The impulse whose history to show, or null for the cumulative daily-day
  /// history — every task due each day across every reflex, matching the
  /// journal's daily list.
  final String? impulseId;

  @override
  State<ImpulseHistoryScreen> createState() => _ImpulseHistoryScreenState();
}

class _ImpulseHistoryScreenState extends State<ImpulseHistoryScreen> {
  final _scrollCtrl = ScrollController();
  final _monthKeys = <int, GlobalKey>{};
  bool _didAutoScroll = false;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The threads scheduled on [day] with whether each was ticked that day. A
  /// one-time [Thread.once] task, and every milestone of a checklist reflex,
  /// surfaces only on the day it was completed; every other thread surfaces on
  /// the weekdays it runs (empty = every day). Mirrors the heatmap's tally.
  List<({Thread thread, bool done})> _tasksOn(Impulse impulse, DateTime day) {
    final key = AppState.dayKeyFor(day);
    final threads = impulse.isLongTerm ? impulse.allThreads : impulse.threads;
    final onceLike = impulse.mode == ImpulseMode.checklist;
    final out = <({Thread thread, bool done})>[];
    for (final t in threads) {
      if (t.once || onceLike) {
        if (t.doneDays.contains(key)) out.add((thread: t, done: true));
      } else if (t.days.isEmpty || t.days.contains(day.weekday)) {
        out.add((thread: t, done: t.doneDays.contains(key)));
      }
    }
    return out;
  }

  /// The cumulative daily list for [day]: every thread due that day across all
  /// reflexes, with whether it was ticked — mirrors the journal's daily list.
  List<({Thread thread, bool done})> _cumulativeTasksOn(
      AppState state, DateTime day) {
    final key = AppState.dayKeyFor(day);
    final out = <({Thread thread, bool done})>[];
    for (final item in state.dueThreadsOn(day)) {
      final imp = state.impulseById(item.impulseId);
      out.add((
        thread: item.thread,
        done: imp != null && imp.threadDone(item.thread, key),
      ));
    }
    return out;
  }

  List<DateTime> _months(DateTime start, DateTime end) {
    final out = <DateTime>[];
    var m = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    while (!m.isAfter(last)) {
      out.add(m);
      m = DateTime(m.year, m.month + 1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cumulative = widget.impulseId == null;
    final impulse = cumulative ? null : state.impulseById(widget.impulseId!);
    if (!cumulative && impulse == null) {
      return FrostedScaffold(
        title: context.t.historyTitle,
        body: const SizedBox.shrink(),
      );
    }

    final today = _dateOnly(DateTime.now());
    late final DateTime startDay;
    late final DateTime endDay;
    if (cumulative) {
      // Always show at least the last month (so recent days can be back-filled)
      // and a fortnight ahead (so near-future days can be ticked too).
      var start = state.earliestActivityDay() ?? today;
      final monthAgo = today.subtract(const Duration(days: 30));
      if (start.isAfter(monthAgo)) start = monthAgo;
      startDay = start;
      endDay = today.add(const Duration(days: 14));
    } else {
      startDay = impulse!.consistencyStart;
      var end = impulse.deadline == null ? today : _dateOnly(impulse.deadline!);
      if (end.isBefore(startDay)) end = startDay;
      // Always show at least through today so recent activity is visible.
      if (end.isBefore(today)) end = today;
      endDay = end;
    }

    // The per-day task tally: one impulse's threads, or the whole daily list.
    List<({Thread thread, bool done})> tasksOn(DateTime day) => cumulative
        ? _cumulativeTasksOn(state, day)
        : _tasksOn(impulse!, day);

    final title = cumulative
        ? context.t.dailyDay
        : (impulse!.title.trim().isEmpty
            ? context.t.historyTitle
            : impulse.title);

    final months = _months(startDay, endDay);

    // Open scrolled to the current month (or the last one) so recent activity
    // is in view; the earlier months are a scroll up away.
    if (!_didAutoScroll && months.isNotEmpty) {
      _didAutoScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final idx = months.indexWhere(
            (m) => m.year == today.year && m.month == today.month);
        final ctx = _monthKeys[idx >= 0 ? idx : months.length - 1]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.02);
      });
    }

    return FrostedScaffold(
      title: title,
      actions: [
        FrostedCircleButton(
          icon: Icons.calendar_month_rounded,
          tooltip: context.t.historyJumpToDate,
          onTap: () => _jumpToDate(context, startDay, endDay, months),
        ),
      ],
      body: Column(
        children: [
          _weekdayHeader(),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
              child: months.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(context.t.historyEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppPalette.inkSecondary)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < months.length; i++)
                          _monthBlock(tasksOn, months[i],
                              startDay, endDay, today, i),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekdayHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          for (final w in _weekdayLetters)
            Expanded(
              child: Center(
                child: Text(w,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthBlock(
      List<({Thread thread, bool done})> Function(DateTime) tasksOn,
      DateTime month,
      DateTime startDay,
      DateTime endDay,
      DateTime today,
      int index) {
    final key = _monthKeys.putIfAbsent(index, () => GlobalKey());
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Pad so the 1st lands under its weekday (Mon-anchored grid).
    final lead = first.weekday - 1;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = <Widget>[];
    for (var r = 0; r < cells.length; r += 7) {
      rows.add(Row(
        children: [
          for (var c = 0; c < 7; c++)
            _dayCell(tasksOn, cells[r + c], startDay, endDay, today),
        ],
      ));
    }

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(DateFormat('MMMM yyyy').format(month),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary)),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _dayCell(
      List<({Thread thread, bool done})> Function(DateTime) tasksOn,
      DateTime? day,
      DateTime startDay,
      DateTime endDay,
      DateTime today) {
    if (day == null) {
      return const Expanded(child: SizedBox(height: 46));
    }
    final inWindow = !day.isBefore(startDay) && !day.isAfter(endDay);
    final tasks =
        inWindow ? tasksOn(day) : const <({Thread thread, bool done})>[];
    final active = tasks.isNotEmpty;
    final isToday = day == today;
    final future = day.isAfter(today);

    Color bg;
    Color fg;
    if (!active) {
      bg = Colors.transparent;
      fg = AppPalette.inkSecondary.withValues(alpha: 0.4);
    } else if (future) {
      bg = AppPalette.cardOutline.withValues(alpha: 0.16);
      fg = AppPalette.inkSecondary;
    } else {
      final total = tasks.length;
      final done = tasks.where((t) => t.done).length;
      final frac = done / total;
      if (frac >= 1.0) {
        bg = AppPalette.journalAccent;
        fg = Colors.white;
      } else if (frac > 0) {
        bg = Color.lerp(AppPalette.cardOutline, AppPalette.journalAccent,
            0.3 + frac * 0.5)!;
        fg = AppPalette.inkPrimary;
      } else {
        bg = AppPalette.cardOutline.withValues(alpha: 0.4);
        fg = AppPalette.inkPrimary;
      }
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: GestureDetector(
          onTap: active ? () => _openDay(day) : null,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: isToday
                  ? Border.all(color: AppPalette.scheme.primary, width: 2)
                  : null,
            ),
            child: Text('${day.day}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: fg)),
          ),
        ),
      ),
    );
  }

  Future<void> _jumpToDate(BuildContext context, DateTime startDay,
      DateTime endDay, List<DateTime> months) async {
    final now = _dateOnly(DateTime.now());
    final initial = now.isBefore(startDay)
        ? startDay
        : (now.isAfter(endDay) ? endDay : now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: startDay,
      lastDate: endDay,
      helpText: context.t.historyJumpToDate,
    );
    if (picked == null || !mounted) return;
    final idx = months.indexWhere(
        (m) => m.year == picked.year && m.month == picked.month);
    if (idx < 0) return;
    final ctx = _monthKeys[idx]?.currentContext;
    if (ctx == null) return;
    // Safe: guarded by the `mounted` check above; `ctx` is the month tile's.
    // ignore: use_build_context_synchronously
    await Scrollable.ensureVisible(ctx,
        alignment: 0.02, duration: const Duration(milliseconds: 350));
  }

  void _openDay(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DayDetailSheet(day: day, impulseId: widget.impulseId),
    );
  }
}

/// The tap-through detail for one day: a completed/total summary and the day's
/// threads shown journal-feed style and tickable (with the far-past/future edit
/// guard). Editing this day live-updates the summary.
class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({required this.day, required this.impulseId});
  final DateTime day;

  /// null = the cumulative daily-day list; else one impulse's threads.
  final String? impulseId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final key = AppState.dayKeyFor(day);
    final items = _itemsFor(state);
    var done = 0;
    for (final it in items) {
      final imp = state.impulseById(it.impulseId);
      if (imp != null && imp.threadDone(it.thread, key)) done++;
    }
    final total = items.length;
    final frac = total == 0 ? 0.0 : done / total;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(DateFormat('EEEE, MMM d, yyyy').format(day),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(context.t.historyCompletedOf(done, total),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.inkSecondary)),
                const Spacer(),
                Text('${(frac * 100).round()}%',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: frac >= 1
                            ? AppPalette.journalAccent
                            : AppPalette.inkSecondary)),
              ],
            ),
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: AppPalette.cardOutline,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppPalette.journalAccent),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Flexible(
            child: total == 0
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Text(context.t.historyNoTasksDay,
                        style: TextStyle(color: AppPalette.inkSecondary)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: DueTaskTimeline(items: items, date: day),
                  ),
          ),
        ],
      ),
    );
  }

  /// The threads due on [day] — the cumulative list, or one impulse's own.
  List<({String impulseId, Thread thread})> _itemsFor(AppState state) {
    if (impulseId == null) return state.dueThreadsOn(day);
    final imp = state.impulseById(impulseId!);
    if (imp == null) return const [];
    final threads = imp.isLongTerm ? imp.allThreads : imp.threads;
    final onceLike = imp.mode == ImpulseMode.checklist;
    final key = AppState.dayKeyFor(day);
    final out = <({String impulseId, Thread thread})>[];
    for (final t in threads) {
      if (t.once || onceLike) {
        if (t.doneDays.contains(key)) out.add((impulseId: imp.id, thread: t));
      } else if (t.days.isEmpty || t.days.contains(day.weekday)) {
        out.add((impulseId: imp.id, thread: t));
      }
    }
    return out;
  }
}
