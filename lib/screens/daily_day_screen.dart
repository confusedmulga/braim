import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/text_prompt.dart';
import 'impulse_analytics_screen.dart';

const _sunColor = Color(0xFFF5A623);
const _greenChip = Color(0xFF2FA36B);

// Priority flag colours.
const _flagRed = Color(0xFFE5484D);
const _flagGreen = Color(0xFF2FA36B);
const _flagYellow = Color(0xFFE0A93B);

Color _flagColor(String flag) {
  switch (flag) {
    case TaskFlag.important:
      return _flagRed;
    case TaskFlag.best:
      return _flagGreen;
    case TaskFlag.optional:
      return _flagYellow;
    default:
      return AppPalette.inkSecondary;
  }
}

String _flagLabel(BuildContext c, String flag) {
  switch (flag) {
    case TaskFlag.important:
      return c.t.important;
    case TaskFlag.best:
      return c.t.flagBest;
    case TaskFlag.optional:
      return c.t.flagOptional;
    default:
      return '';
  }
}

/// A compact weekday label for a thread's [days] (1 = Mon ... 7 = Sun). Empty
/// (every day) returns '' so no chip is shown; specific days read as
/// "Mon, Wed, Fri", with "Weekdays"/"Weekends" shorthands.
String _weekdaysLabel(Set<int> days) {
  const abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final sorted = days.where((d) => d >= 1 && d <= 7).toList()..sort();
  if (sorted.isEmpty || sorted.length == 7) return '';
  if (sorted.length == 5 && sorted.every((d) => d <= 5)) return 'Weekdays';
  if (sorted.length == 2 && sorted.contains(6) && sorted.contains(7)) {
    return 'Weekends';
  }
  return sorted.map((d) => abbr[d - 1]).join(', ');
}

String _monthYear(DateTime d) => DateFormat("MMM''yy").format(d); // Aug'25
String _timeStr(BuildContext c, int m) =>
    TimeOfDay(hour: m ~/ 60, minute: m % 60).format(c);

/// The desk-calendar date card that now opens the whole Reflexes section.
class DailyDayCard extends StatelessWidget {
  const DailyDayCard({
    super.key,
    required this.date,
    required this.projectCount,
    required this.progress,
    required this.onTap,
  });

  final DateTime date;
  final int projectCount;

  /// Today's completion of the pinned reflex (0–1), or null when it has no
  /// tasks — then the progress bar is hidden.
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${date.day}',
                    style: TextStyle(
                        fontSize: 40,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.inkPrimary)),
                const SizedBox(width: 5),
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPalette.journalAccent,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_monthYear(date),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.inkSecondary)),
                    Text(DateFormat('EEEE').format(date),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.inkPrimary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: _sunColor),
                const SizedBox(width: 8),
                Text(context.t.reflexes,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary)),
                const Spacer(),
                if (progress != null) ...[
                  Text('${(progress! * 100).round()}%',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.journalAccent)),
                  const SizedBox(width: 8),
                ],
                Text(context.t.reflexesProjects(projectCount),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.inkSecondary)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppPalette.inkSecondary),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppPalette.cardOutline,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppPalette.journalAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The journal's "Today's progress" card: one unified view of the whole daily
/// day — the cumulative list of everything due today across every reflex. A
/// completion ring, Total / Completed / Pending, a 7-day mini history strip
/// (tap it for the full calendar), the next unfinished task, and a perfect-day /
/// rest-day flourish. A self-contained deep-green card, readable in either theme.
class _TodayProgressRing extends StatelessWidget {
  const _TodayProgressRing({
    required this.progress,
    required this.streak,
    required this.history,
    required this.pending,
    required this.onTap,
  });
  final TodayProgress progress;

  /// Consecutive fully-cleared days, ending at the last completed day.
  final int streak;

  /// The last 7 days of cumulative completion, oldest first (the mini strip).
  final List<TodayProgress> history;

  /// Today's still-unfinished tasks, earliest first (the "next up" hint).
  final List<Thread> pending;

  /// Opens the full analytics screen (period graph, dropdown, heatmap).
  final VoidCallback onTap;

  static const _ink = Colors.white;
  static const _fill = Color(0xFF5FD08C);

  @override
  Widget build(BuildContext context) {
    final rest = progress.total == 0;
    final perfect = progress.total > 0 && progress.done >= progress.total;
    final pct = (progress.fraction * 100).round();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12362B), Color(0xFF1D4C3B)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_rounded, size: 16, color: _fill),
              const SizedBox(width: 7),
              Expanded(
                child: Text(context.t.todaysProgress,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
              ),
              if (streak > 0) ...[
                const Icon(Icons.local_fire_department_rounded,
                    size: 15, color: Color(0xFFFFC65C)),
                const SizedBox(width: 3),
                Text(context.t.streakDays(streak),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink.withValues(alpha: 0.9))),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 74,
                height: 74,
                child: CustomPaint(
                  painter: _RingPaint(rest ? 0 : progress.fraction),
                  child: Center(
                    child: perfect
                        ? const Icon(Icons.check_rounded,
                            size: 30, color: _ink)
                        : Text(rest ? '—' : '$pct%',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _ink)),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _stat(Icons.dns_rounded, progress.total,
                            context.t.progressTotal),
                        _stat(Icons.check_circle_rounded, progress.done,
                            context.t.progressCompleted),
                        _stat(Icons.schedule_rounded, progress.pending,
                            context.t.progressPending),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _statusLine(context, rest: rest, perfect: perfect),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _miniStrip(context),
        ],
      ),
      ),
    );
  }

  /// The next-up hint, or the perfect-day / rest-day flourish.
  Widget _statusLine(BuildContext context,
      {required bool rest, required bool perfect}) {
    if (perfect) {
      return Row(
        children: [
          const Icon(Icons.celebration_rounded,
              size: 15, color: Color(0xFFFFC65C)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(context.t.perfectDay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _ink)),
          ),
        ],
      );
    }
    if (rest) {
      return Text(context.t.progressAllClear,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ink.withValues(alpha: 0.8)));
    }
    final titles = pending
        .map((t) => t.title.trim().isEmpty
            ? context.t.untitledEntry
            : t.title.trim())
        .join('   ·   ');
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: [
        TextSpan(
            text: '${context.t.nextUp}   ',
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: _fill)),
        TextSpan(
            text: titles.isEmpty ? '—' : titles,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _ink.withValues(alpha: 0.92))),
      ]),
    );
  }

  /// A 7-day sparkline of daily completion (the whole card taps to analytics).
  Widget _miniStrip(BuildContext context) {
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < history.length; i++)
          _miniBar(
            history[i],
            label: letters[now
                    .subtract(Duration(days: history.length - 1 - i))
                    .weekday -
                1],
            isToday: i == history.length - 1,
          ),
        const Icon(Icons.chevron_right_rounded,
            size: 18, color: Colors.white54),
      ],
    );
  }

  Widget _miniBar(TodayProgress p,
      {required String label, required bool isToday}) {
    final has = p.total > 0;
    final frac = has ? p.fraction.clamp(0.0, 1.0) : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: isToday
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.55), width: 1)
                : null,
          ),
          child: FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: frac,
            child: Container(
              decoration: BoxDecoration(
                color: has ? _fill : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: _ink.withValues(alpha: isToday ? 0.9 : 0.5))),
      ],
    );
  }

  Widget _stat(IconData icon, int value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: _fill),
                const SizedBox(width: 4),
                Text('$value',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _ink.withValues(alpha: 0.7))),
          ],
        ),
      );
}

/// A determinate ring for the progress card (no controller — static paint).
class _RingPaint extends CustomPainter {
  const _RingPaint(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.18);
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF5FD08C);
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -1.5707963, 6.2831853 * fraction.clamp(0.0, 1.0), false, fill);
  }

  @override
  bool shouldRepaint(_RingPaint oldDelegate) =>
      oldDelegate.fraction != fraction;
}

/// The green "Today's progress" dashboard as a standalone, always-visible card,
/// pinned just below the journal's week strip (rather than living inside a
/// reorderable section). It shows one thing: the whole daily day — the
/// cumulative list of everything due today across every reflex — so it always
/// matches the list below it. The 7-day strip taps through to the history.
class TodayProgressCard extends StatelessWidget {
  const TodayProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return _TodayProgressRing(
      progress: state.dueProgressOn(DateTime.now()),
      streak: state.dueStreak(),
      history: state.dueHistory(7),
      pending: state.pendingDueToday(limit: 2),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ImpulseAnalyticsScreen(),
        ),
      ),
    );
  }
}

/// The pinned reflex's task list for [date]: reference-styled rows. Long-press
/// a row for its detail sheet; the tickbox marks it done for the shown day.
/// Which reflex shows here (and the header title) follows the pinned reflex.
class DailyDayList extends StatelessWidget {
  const DailyDayList({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // The daily day is the cumulative list of every thread due on [date] across
    // all impulses (daily and long-term; checklist milestones excluded).
    final due = state.dueThreadsOn(date);
    final dueProgress = state.dueProgressOn(date);
    // Note: the green "Today's progress" card used to live here; it's now the
    // standalone [TodayProgressCard], pinned below the journal's week strip.

    return _FrostedBox(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.wb_sunny_rounded, size: 18, color: _sunColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.t.dailyDay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary)),
            ),
            const SizedBox(width: 8),
            if (due.isNotEmpty)
              Text('${(dueProgress.fraction * 100).round()}%',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        if (due.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(context.t.dailyDayEmpty,
                style: TextStyle(color: AppPalette.inkSecondary)),
          )
        else
          DueTaskTimeline(items: due, date: date),
        // An always-visible inline add, straight to the daily-day list.
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _AddRow(
            icon: Icons.add_rounded,
            label: context.t.composeDailyTask,
            onTap: () => openNewThread(context, AppState.dailyDayId, date),
          ),
        ),
      ],
      ),
    );
  }
}

/// A rounded, theme-aware frosted panel: one clipped [BackdropFilter] with a
/// translucent fill so content over the feed wallpaper stays legible. Wrapped in
/// a [RepaintBoundary] and used for a single card (never per-row), so the blur
/// stays cheap while scrolling.
class _FrostedBox extends StatelessWidget {
  const _FrostedBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.dark;
    final radius = BorderRadius.circular(20);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF191B23).withValues(alpha: 0.42)
                  : Colors.white.withValues(alpha: 0.52),
              borderRadius: radius,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.60),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A cumulative task timeline for a day: threads due from every impulse,
/// ordered by time, each ticked against its own impulse. Shared by the journal
/// feed and the calendar's day view, so both read and tick the same way.
class DueTaskTimeline extends StatelessWidget {
  const DueTaskTimeline({super.key, required this.items, required this.date});
  final List<({String impulseId, Thread thread})> items;
  final DateTime date;

  Future<void> _toggle(BuildContext context, AppState state, String impulseId,
      String threadId, String dayKey) async {
    // Editing a day more than 2 days from today asks once (per that day) before
    // the first change; cancelling leaves the list exactly as it was.
    if (state.farEditNeedsConfirm(dayKey)) {
      final future = state.isFutureDay(dayKey);
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(future
              ? context.t.editFutureTitle
              : context.t.editPastTitle),
          content: Text(future
              ? context.t.editFutureBody
              : context.t.editPastBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(context.t.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(context.t.proceed)),
          ],
        ),
      );
      if (ok != true) return;
      state.confirmFarEdit(dayKey);
    }
    if (!context.mounted) return;
    final before = state.dueProgressOn(date);
    HapticFeedback.selectionClick();
    await state.toggleThreadOn(impulseId, threadId, dayKey);
    if (!context.mounted) return;
    final after = state.dueProgressOn(date);
    if (after.total > 0 &&
        after.done == after.total &&
        before.done != before.total) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.dayComplete),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dayKey = AppState.dayKeyFor(date);
    // Past and future days are both tickable; far edits are guarded in _toggle.
    const canToggle = true;

    final ordered = [...items];
    ordered.sort((a, b) {
      final am = a.thread.reminderMinutes;
      final bm = b.thread.reminderMinutes;
      if (am == null && bm == null) return 0;
      if (am == null) return 1;
      if (bm == null) return -1;
      return am.compareTo(bm);
    });

    final decoration = BoxDecoration(
      color: AppPalette.bubbleGlass,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppPalette.cardOutline),
    );

    return Column(
      children: [
        for (var i = 0; i < ordered.length; i++)
          Builder(builder: (context) {
            final item = ordered[i];
            final imp = state.impulseById(item.impulseId);
            final done = imp?.threadDone(item.thread, dayKey) ?? false;
            return _TimelineEntry(
              minutes: item.thread.reminderMinutes,
              done: done,
              isFirst: i == 0,
              isLast: i == ordered.length - 1,
              child: Container(
                decoration: decoration,
                clipBehavior: Clip.antiAlias,
                child: _TaskRow(
                  thread: item.thread,
                  done: done,
                  canToggle: canToggle,
                  onOpen: () => showTaskDetailSheet(
                      context, item.impulseId, item.thread.id, date),
                  onToggle: () => _toggle(context, state, item.impulseId,
                      item.thread.id, dayKey),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// A bordered card of task rows for any impulse — the daily-day and each reflex
/// project render their threads with this. Long-press a row for its task sheet;
/// the tickbox toggles it done for [date]. Pass [onReorder] to make the rows
/// drag-reorderable (each gains a handle).
class TaskRowsList extends StatelessWidget {
  const TaskRowsList({
    super.key,
    required this.impulseId,
    required this.threads,
    required this.date,
    this.onReorder,
    this.timeline = false,
    this.allowOpen = true,
  });

  final String impulseId;
  final List<Thread> threads;
  final DateTime date;
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// When true, the rows are ordered by their time and laid out as a vertical
  /// timeline (a time gutter + a connecting rail), rather than a bordered card.
  final bool timeline;

  /// Whether long-pressing a row opens its detail sheet. False in an impulse's
  /// read-only view (tick only); the pencil re-enables it.
  final bool allowOpen;

  /// Threads ordered by time — earliest first, untimed ones last (keeping their
  /// existing order among themselves).
  static List<Thread> timeSorted(List<Thread> list) {
    final indexed = [
      for (var i = 0; i < list.length; i++) (i, list[i]),
    ];
    indexed.sort((a, b) {
      final am = a.$2.reminderMinutes;
      final bm = b.$2.reminderMinutes;
      if (am == null && bm == null) return a.$1.compareTo(b.$1);
      if (am == null) return 1;
      if (bm == null) return -1;
      if (am != bm) return am.compareTo(bm);
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Ticks a thread, with a light haptic — and a celebration the moment the
  /// last one is checked off for the day.
  Future<void> _toggle(BuildContext context, AppState state, String threadId,
      String dayKey) async {
    final imp = state.impulseById(impulseId);
    // Celebrate over the list actually shown (a subsection, or the flat list),
    // not the impulse's flat threads.
    final wasAllDone = imp != null &&
        threads.isNotEmpty &&
        threads.every((t) => imp.threadDone(t, dayKey));
    HapticFeedback.selectionClick();
    await state.toggleThreadOn(impulseId, threadId, dayKey);
    if (!context.mounted) return;
    final now = state.impulseById(impulseId);
    final nowAllDone = now != null &&
        threads.isNotEmpty &&
        threads.every((t) => now.threadDone(t, dayKey));
    if (nowAllDone && !wasAllDone) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.dayComplete),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final impulse = state.impulseById(impulseId);
    final dayKey = AppState.dayKeyFor(date);
    // A future day is view-only: its threads can't be marked complete yet.
    final canToggle = dayKey.compareTo(state.todayKey) <= 0;

    Widget rowFor(Thread t, {Widget? handle}) => _TaskRow(
          thread: t,
          done: impulse?.threadDone(t, dayKey) ?? false,
          canToggle: canToggle,
          dragHandle: handle,
          onOpen: allowOpen
              ? () => showTaskDetailSheet(context, impulseId, t.id, date)
              : null,
          onToggle: () => _toggle(context, state, t.id, dayKey),
        );
    Widget row(int i, {Widget? handle}) => rowFor(threads[i], handle: handle);

    final decoration = BoxDecoration(
      color: AppPalette.bubbleGlass,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppPalette.cardOutline),
    );

    // Timeline: order by time, each task its own card on a connecting rail.
    if (timeline) {
      final ordered = timeSorted(threads);
      return Column(
        children: [
          for (var i = 0; i < ordered.length; i++)
            _TimelineEntry(
              minutes: ordered[i].reminderMinutes,
              done: impulse?.threadDone(ordered[i], dayKey) ?? false,
              isFirst: i == 0,
              isLast: i == ordered.length - 1,
              child: Container(
                decoration: decoration,
                clipBehavior: Clip.antiAlias,
                child: rowFor(ordered[i]),
              ),
            ),
        ],
      );
    }

    if (onReorder != null) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: threads.length,
          onReorder: onReorder!,
          itemBuilder: (context, i) => DecoratedBox(
            key: ValueKey(threads[i].id),
            decoration: BoxDecoration(
              color: AppPalette.bubbleGlass,
              border: Border(
                bottom: i < threads.length - 1
                    ? BorderSide(
                        color: AppPalette.cardOutline.withValues(alpha: 0.6))
                    : BorderSide.none,
              ),
            ),
            child: row(i,
                handle: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_indicator_rounded,
                      color: AppPalette.inkSecondary),
                )),
          ),
        ),
      );
    }

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < threads.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: AppPalette.cardOutline.withValues(alpha: 0.6)),
            row(i),
          ],
        ],
      ),
    );
  }
}

/// One task row in the reference to-do style: title + time, a description line
/// and (only) a flag chip, with a rounded tickbox in the bottom-right corner.
/// Long-press opens the detail sheet; the tickbox toggles done for the day.
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.thread,
    required this.done,
    required this.canToggle,
    required this.onOpen,
    required this.onToggle,
    this.dragHandle,
  });

  // (onOpen may be null in an impulse's read-only view — long-press does
  // nothing then.)

  final Thread thread;
  final bool done;

  /// False for a future day — the tickbox is shown but can't be ticked.
  final bool canToggle;
  final VoidCallback? onOpen;
  final VoidCallback onToggle;

  /// A drag handle shown at the leading edge when the list is reorderable.
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final title =
        thread.title.trim().isEmpty ? context.t.untitledEntry : thread.title;
    final desc = thread.description.trim();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title, with the time in the top-right corner.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color:
                      done ? AppPalette.inkSecondary : AppPalette.inkPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: AppPalette.inkSecondary,
                ),
              ),
            ),
            if (thread.reminderMinutes != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(_timeStr(context, thread.reminderMinutes!),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.inkSecondary)),
              ),
            ],
          ],
        ),
        // Only render the description line when there actually is one, so an
        // empty task doesn't leave a blank gap.
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, color: AppPalette.inkSecondary),
          ),
        ],
        const SizedBox(height: 8),
        // Priority flag and the thread's weekday label on the left, tickbox in
        // the bottom-right corner.
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (thread.flag.isNotEmpty)
                    _chip(
                        Icons.flag_rounded,
                        _flagLabel(context, thread.flag),
                        _flagColor(thread.flag)),
                  if (thread.once)
                    _chip(Icons.looks_one_rounded, context.t.repeatOnce,
                        AppPalette.inkSecondary)
                  else if (_weekdaysLabel(thread.days).isNotEmpty)
                    _chip(Icons.event_repeat_rounded,
                        _weekdaysLabel(thread.days), AppPalette.inkSecondary),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Opacity(
              opacity: canToggle ? 1 : 0.4,
              child: GestureDetector(
                onTap: canToggle ? onToggle : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color:
                        done ? AppPalette.journalAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: done
                          ? AppPalette.journalAccent
                          : AppPalette.inkSecondary,
                      width: 1.8,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 17, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final body = dragHandle == null
        ? content
        : Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: dragHandle,
              ),
              Expanded(child: content),
            ],
          );

    return InkWell(
      onLongPress: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: body,
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

/// One entry on the daily-day timeline: a time in the left gutter, a connecting
/// rail with a node, and the task card on the right.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.minutes,
    required this.done,
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final int? minutes;
  final bool done;
  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final railColor = AppPalette.cardOutline;
    final nodeColor = done ? AppPalette.journalAccent : AppPalette.inkSecondary;
    final t = minutes == null ? null : TimeOfDay(hour: minutes! ~/ 60, minute: minutes! % 60);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time gutter.
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, right: 6),
              child: minutes == null
                  ? Text('-',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkSecondary
                              .withValues(alpha: 0.5)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_hour12(t!),
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                color: done
                                    ? AppPalette.inkSecondary
                                    : AppPalette.inkPrimary)),
                        Text(t.period == DayPeriod.am ? 'AM' : 'PM',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.inkSecondary)),
                      ],
                    ),
            ),
          ),
          // Rail with a node.
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                    width: 2,
                    height: 14,
                    color: isFirst ? Colors.transparent : railColor),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? nodeColor : AppPalette.scheme.surface,
                    border: Border.all(color: nodeColor, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : railColor),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  /// The hour:minute part in 12-hour form (the AM/PM is shown beneath it).
  String _hour12(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ---- Task detail sheet (the reference) -------------------------------------

Future<void> showTaskDetailSheet(
    BuildContext context, String impulseId, String threadId, DateTime date,
    {bool isNew = false}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TaskDetailSheet(
        impulseId: impulseId, threadId: threadId, date: date, isNew: isNew),
  );
}

/// Creates a fresh blank thread in [impulseId] and opens its task sheet — the
/// same editor the daily day uses. Blank threads are cleaned up on close.
Future<void> openNewThread(
    BuildContext context, String impulseId, DateTime date) async {
  final id = await context.read<AppState>().addBlankThread(impulseId);
  if (id == null || !context.mounted) return;
  await showTaskDetailSheet(context, impulseId, id, date, isNew: true);
}

class _TaskDetailSheet extends StatefulWidget {
  const _TaskDetailSheet({
    required this.impulseId,
    required this.threadId,
    required this.date,
    this.isNew = false,
  });

  final String impulseId;
  final String threadId;
  final DateTime date;
  final bool isNew;

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  late final AppState _state;
  late final TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _titleCtrl = TextEditingController(text: _thread()?.title ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Thread? _thread() =>
      _state.impulseById(widget.impulseId)?.findThread(widget.threadId);

  /// Syncs the typed title, applies [mutate], then persists — so the title is
  /// always saved alongside any inline change.
  void _persist(void Function(Thread t) mutate) {
    final t = _thread();
    if (t == null) return;
    t.title = _titleCtrl.text.trim();
    mutate(t);
    _state.updateThread(widget.impulseId, t);
  }

  bool _isBlank(Thread t) =>
      t.title.trim().isEmpty &&
      t.description.trim().isEmpty &&
      t.reminderMinutes == null &&
      t.endMinutes == null &&
      t.startDate == null &&
      t.deadline == null &&
      t.links.isEmpty &&
      t.location.trim().isEmpty &&
      t.flag.isEmpty &&
      t.doneDays.isEmpty;

  /// On close: drop a task left completely blank, else save the final title.
  void _onClose() {
    final t = _thread();
    if (t == null) return;
    t.title = _titleCtrl.text.trim();
    if (_isBlank(t)) {
      _state.deleteThread(widget.impulseId, t.id);
    } else {
      _state.updateThread(widget.impulseId, t);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final thread = _thread();
    if (thread == null) return const SizedBox.shrink();

    // Long-term tasks get calendar start/deadline dates (a study task's span);
    // daily/checklist tasks keep just the time-of-day slots.
    final isLong =
        _state.impulseById(widget.impulseId)?.isLongTerm ?? false;

    final dayKey = AppState.dayKeyFor(widget.date);
    final today = DateTime.now();
    final isToday = AppState.dayKeyFor(today) == dayKey;
    final dayLabel = isToday
        ? context.t.todayLabel
        : DateFormat('EEE, MMM d').format(widget.date);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onClose();
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        builder: (context, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppPalette.sheet,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppPalette.cardOutline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(dayLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkSecondary)),
              const SizedBox(height: 2),
              // Editable title — empty and focused for a brand-new task.
              TextField(
                controller: _titleCtrl,
                autofocus: widget.isNew,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.inkPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: context.t.dailyDayAdd,
                  hintStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkSecondary.withValues(alpha: 0.45)),
                ),
              ),
              if (thread.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(thread.description.trim(),
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppPalette.inkSecondary)),
              ],
              const SizedBox(height: 18),
              // Add description / Edit / Remove
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.notes_rounded,
                      label: context.t.descriptionAction,
                      onTap: _editDescription,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.drive_file_move_outlined,
                      label: context.t.moveTask,
                      onTap: _moveTask,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.close_rounded,
                      label: context.t.taskRemove,
                      danger: true,
                      onTap: _remove,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              // Priority flag.
              _sectionLabel(context, context.t.priority),
              Row(
                children: [
                  for (final f in TaskFlag.all) ...[
                    _flagChoice(context, thread, f),
                    if (f != TaskFlag.all.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              _TimeSlots(
                start: thread.reminderMinutes,
                end: thread.endMinutes,
                endEnabled: thread.reminderMinutes != null,
                onPickStart: () => _pickTime(start: true),
                onPickEnd: () => _pickTime(start: false),
                // Clearing the start also drops the end and the reminder, since
                // both depend on it.
                onClearStart: () => _persist((t) {
                  t.reminderMinutes = null;
                  t.endMinutes = null;
                  t.notify = false;
                }),
                onClearEnd: () => _persist((t) => t.endMinutes = null),
              ),
              // The notification opt-in only appears once a start time is set.
              if (thread.reminderMinutes != null) ...[
                const SizedBox(height: 12),
                _NotifyToggle(
                  value: thread.notify,
                  onChanged: _setNotify,
                ),
              ],
              const SizedBox(height: 22),
              _sectionLabel(context, context.t.daysSection),
              const SizedBox(height: 8),
              // "Once" = a one-time task; "Everyday" = runs daily. Picking a
              // specific weekday below drops into a custom recurrence (and
              // switches "once" off), so the selector works either way.
              _RepeatToggle(
                once: thread.once,
                everyday: !thread.once && thread.days.isEmpty,
                onOnce: () => _persist((t) {
                  t.once = true;
                  t.days.clear();
                }),
                onEveryday: () => _persist((t) {
                  t.once = false;
                  t.days.clear();
                }),
              ),
              const SizedBox(height: 12),
              Opacity(
                // Dimmed but still tappable while "once" — a tap adopts that
                // day and turns the one-time flag off.
                opacity: thread.once ? 0.4 : 1,
                child: _WeekPicker(
                  days: thread.days,
                  onToggle: (d) => _persist((t) {
                    t.once = false;
                    if (!t.days.remove(d)) t.days.add(d);
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    thread.once
                        ? context.t.repeatOnceHint
                        : context.t.daysHint,
                    style: TextStyle(
                        fontSize: 12, color: AppPalette.inkSecondary)),
              ),
              if (isLong) ...[
                const SizedBox(height: 22),
                _sectionLabel(context, context.t.datesSection),
                Row(
                  children: [
                    Expanded(
                      child: _ThreadDateTile(
                        label: context.t.startShort,
                        date: thread.startDate,
                        icon: Icons.play_circle_outline_rounded,
                        onPick: () => _pickThreadDate(start: true),
                        onClear: () => _persist((t) => t.startDate = null),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ThreadDateTile(
                        label: context.t.dueShort,
                        date: thread.deadline,
                        icon: Icons.event_outlined,
                        onPick: () => _pickThreadDate(start: false),
                        onClear: () => _persist((t) => t.deadline = null),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              _sectionLabel(context, context.t.linksSection),
              for (final link in thread.links)
                _LinkRow(
                  link: link,
                  onOpen: () => _open(link.url),
                  onRemove: () => _persist((t) => t.links.remove(link)),
                ),
              _AddRow(
                icon: Icons.add_link_rounded,
                label: context.t.addLink,
                onTap: _addLink,
              ),
              const SizedBox(height: 22),
              _sectionLabel(context, context.t.locationSection),
              if (thread.location.trim().isNotEmpty)
                _LocationRow(
                  address: thread.location.trim(),
                  onOpen: () => _openMaps(thread.location.trim()),
                  onEdit: _editLocation,
                )
              else
                _AddRow(
                  icon: Icons.location_on_outlined,
                  label: context.t.addLocation,
                  onTap: _editLocation,
                ),
              const SizedBox(height: 24),
              if (thread.reminderMinutes != null && isToday)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppPalette.bubbleGlass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppPalette.cardOutline),
                    ),
                    child: Text(
                      _countdown(context, thread.reminderMinutes!),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flagChoice(BuildContext context, Thread thread, String flag) {
    final color = _flagColor(flag);
    final selected = thread.flag == flag;
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            _persist((t) => t.flag = t.flag == flag ? TaskFlag.none : flag),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? color : AppPalette.cardOutline,
                width: selected ? 1.6 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_rounded, size: 16, color: color),
              const SizedBox(height: 3),
              Text(
                _flagLabel(context, flag),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppPalette.inkSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: AppPalette.inkSecondary)),
      );

  String _countdown(BuildContext context, int minutes) {
    final now = DateTime.now();
    final target =
        DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    final diff = target.difference(now);
    if (diff.isNegative) return context.t.timePassed;
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final rel = h > 0 ? '${h}h ${m}m' : '${m}m';
    return context.t.inTime(rel);
  }

  Future<void> _pickTime({required bool start}) async {
    final t = _thread();
    if (t == null) return;
    final current = start ? t.reminderMinutes : t.endMinutes;
    final initial = current != null
        ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    if (start) {
      // Choosing a reminder time turns the notification on by default — that is
      // the point of setting a time — and asks for the OS permission the first
      // time. The notify toggle below still lets a task keep a time silently.
      final needPermission = !t.notify;
      _persist((th) {
        th.reminderMinutes = minutes;
        th.notify = true;
      });
      if (needPermission) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t.notifPermNeeded)));
        }
      }
    } else {
      _persist((th) => th.endMinutes = minutes);
    }
  }

  /// Picks a calendar start/deadline date for the task (long-term goals). These
  /// are whole dates, separate from the [_pickTime] times of day.
  Future<void> _pickThreadDate({required bool start}) async {
    final t = _thread();
    if (t == null) return;
    final now = DateTime.now();
    final DateTime first;
    final DateTime last;
    if (start) {
      first = DateTime(now.year - 5);
      last = t.deadline ?? now.add(const Duration(days: 365 * 10));
    } else {
      first = t.startDate ?? now;
      last = first.add(const Duration(days: 365 * 10));
    }
    var init = (start ? t.startDate : t.deadline) ??
        (start ? now : (t.startDate ?? now).add(const Duration(days: 7)));
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final picked = await showDatePicker(
        context: context, initialDate: init, firstDate: first, lastDate: last);
    if (picked == null || !mounted) return;
    if (start) {
      _persist((th) => th.startDate = picked);
    } else {
      _persist((th) => th.deadline = picked);
    }
  }

  /// Turns the thread's start-time notification on/off, asking for the OS
  /// permission the first time it's enabled.
  Future<void> _setNotify(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.notifPermNeeded)),
        );
      }
    }
    _persist((t) => t.notify = value);
  }

  Future<void> _editDescription() async {
    final result = await promptForText(
      context,
      title: context.t.descriptionAction,
      hint: context.t.descriptionHint,
      initial: _thread()?.description ?? '',
      minLines: 2,
      maxLines: 5,
    );
    if (result == null) return;
    _persist((t) => t.description = result.trim());
  }

  /// Moves this thread into another reflex (e.g. promote a daily task).
  Future<void> _moveTask() async {
    // Commit any typed title first, then move to the chosen reflex.
    final t = _thread();
    if (t == null) return;
    t.title = _titleCtrl.text.trim();
    final targets = _state.reflexes.where((i) => i.id != widget.impulseId);
    final destId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final imp in targets)
                  ListTile(
                    leading: Icon(
                        _state.isDailyDay(imp.id)
                            ? Icons.wb_sunny_rounded
                            : Icons.bolt_rounded,
                        color: AppPalette.inkPrimary),
                    title: Text(_state.isDailyDay(imp.id)
                        ? context.t.dailyDay
                        : (imp.title.trim().isEmpty
                            ? context.t.untitledImpulse
                            : imp.title)),
                    onTap: () => Navigator.pop(context, imp.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (destId == null) return;
    await _state.moveThread(widget.impulseId, widget.threadId, destId);
    if (mounted) Navigator.pop(context); // the thread now lives elsewhere
  }

  Future<void> _remove() async {
    final ok = await _confirmRemove(context);
    if (!ok || !mounted) return;
    await _state.deleteThread(widget.impulseId, widget.threadId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addLink() async {
    final link = await showDialog<TaskLink>(
      context: context,
      builder: (_) => const _AddTaskLinkDialog(),
    );
    if (link == null) return;
    _persist((t) => t.links.add(link));
  }

  Future<void> _editLocation() async {
    final address = await promptForText(
      context,
      title: context.t.locationSection,
      hint: context.t.addLocation,
      initial: _thread()?.location ?? '',
    );
    if (address == null) return;
    _persist((t) => t.location = address.trim());
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t.taskRemove),
        content: Text(context.t.removeTaskConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE0567B)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t.taskRemove),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _open(String url) async {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openMaps(String address) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// Add a link (label + URL) to a task. Owns its controllers.
class _AddTaskLinkDialog extends StatefulWidget {
  const _AddTaskLinkDialog();

  @override
  State<_AddTaskLinkDialog> createState() => _AddTaskLinkDialogState();
}

class _AddTaskLinkDialogState extends State<_AddTaskLinkDialog> {
  final _label = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  void _add() {
    final url = _url.text.trim();
    if (url.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final label = _label.text.trim();
    Navigator.pop(
        context, TaskLink(label: label.isEmpty ? url : label, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.addLink),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _label,
            autofocus: true,
            decoration: InputDecoration(hintText: context.t.linkLabelHint),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(hintText: context.t.urlHint),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t.cancel)),
        FilledButton(onPressed: _add, child: Text(context.t.add)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFE0567B) : AppPalette.inkPrimary;
    final bg = danger
        ? const Color(0xFFE0567B).withValues(alpha: 0.10)
        : AppPalette.bubbleGlass;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSlots extends StatelessWidget {
  const _TimeSlots({
    required this.start,
    required this.end,
    required this.endEnabled,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearStart,
    required this.onClearEnd,
  });

  final int? start;
  final int? end;

  /// The end slot only unlocks once a start time is picked.
  final bool endEnabled;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onClearStart;
  final VoidCallback onClearEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _slot(context, filled: true, minutes: start,
              label: context.t.startTime, onPick: onPickStart,
              onClear: onClearStart),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _slot(context,
              filled: false,
              minutes: end,
              enabled: endEnabled,
              label: context.t.endTime,
              hint: endEnabled ? context.t.setTime : context.t.setStartFirst,
              onPick: onPickEnd,
              onClear: onClearEnd),
        ),
      ],
    );
  }

  Widget _slot(BuildContext context,
      {required bool filled,
      required int? minutes,
      required String label,
      required VoidCallback onPick,
      required VoidCallback onClear,
      bool enabled = true,
      String? hint}) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
      onTap: enabled ? onPick : null,
      onLongPress: enabled && minutes != null ? onClear : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(
          children: [
            Icon(
              filled ? Icons.circle : Icons.circle_outlined,
              size: 18,
              color: filled ? AppPalette.inkPrimary : AppPalette.inkSecondary,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The Start/End label always shows, so each slot is clear even
                // before a time is picked.
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkSecondary)),
                Text(
                    minutes != null
                        ? _timeStr(context, minutes)
                        : (hint ?? context.t.setTime),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: minutes != null
                            ? AppPalette.inkPrimary
                            : AppPalette.inkSecondary)),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The start-time notification opt-in for a thread.
class _NotifyToggle extends StatelessWidget {
  const _NotifyToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Row(
        children: [
          Icon(
              value
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              size: 20,
              color:
                  value ? AppPalette.scheme.primary : AppPalette.inkSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(context.t.notifyAtStart,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.inkPrimary)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A compact start/deadline date chip for a long-term task's Dates row. Tapping
/// opens the date picker; the × clears it.
class _ThreadDateTile extends StatelessWidget {
  const _ThreadDateTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.onPick,
    required this.onClear,
  });
  final String label;
  final DateTime? date;
  final IconData icon;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.bubbleGlass,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppPalette.inkSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: AppPalette.inkSecondary)),
                    const SizedBox(height: 1),
                    Text(
                      date == null
                          ? '-'
                          : DateFormat('MMM d, yyyy').format(date!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: date == null
                              ? AppPalette.inkSecondary
                              : AppPalette.inkPrimary),
                    ),
                  ],
                ),
              ),
              if (date != null)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppPalette.inkSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-option recurrence toggle for a thread: a one-time "Once" task or an
/// "Everyday" one. Neither pill is lit when the thread instead runs on a
/// specific set of weekdays (a custom recurrence).
class _RepeatToggle extends StatelessWidget {
  const _RepeatToggle({
    required this.once,
    required this.everyday,
    required this.onOnce,
    required this.onEveryday,
  });
  final bool once;
  final bool everyday;
  final VoidCallback onOnce;
  final VoidCallback onEveryday;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _seg(context.t.repeatOnce, once, onOnce)),
        const SizedBox(width: 10),
        Expanded(child: _seg(context.t.repeatEveryday, everyday, onEveryday)),
      ],
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected ? AppPalette.scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppPalette.scheme.primary
                : AppPalette.cardOutline,
            width: 1.4,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected
                    ? AppPalette.scheme.onPrimary
                    : AppPalette.inkSecondary)),
      ),
    );
  }
}

/// A Mon–Sun weekday picker for a thread's active days (empty = every day).
class _WeekPicker extends StatelessWidget {
  const _WeekPicker({required this.days, required this.onToggle});
  final Set<int> days;
  final void Function(int day) onToggle;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          GestureDetector(
            onTap: () => onToggle(d),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: days.contains(d)
                    ? AppPalette.scheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: days.contains(d)
                      ? AppPalette.scheme.primary
                      : AppPalette.cardOutline,
                  width: 1.4,
                ),
              ),
              child: Text(_letters[d - 1],
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: days.contains(d)
                          ? AppPalette.scheme.onPrimary
                          : AppPalette.inkSecondary)),
            ),
          ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.link, required this.onOpen, required this.onRemove});
  final TaskLink link;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 20, color: AppPalette.inkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onLongPress: onRemove,
              child: Text(link.label.isEmpty ? link.url : link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkPrimary)),
            ),
          ),
          const SizedBox(width: 8),
          _pillButton(Icons.open_in_new_rounded, context.t.open, onOpen),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow(
      {required this.address, required this.onOpen, required this.onEdit});
  final String address;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.location_on_rounded, size: 20, color: _greenChip),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onLongPress: onEdit,
            child: Text(address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, color: AppPalette.inkPrimary)),
          ),
        ),
        const SizedBox(width: 8),
        _pillButton(Icons.map_rounded, context.t.openInMaps, onOpen),
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppPalette.scheme.primary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.scheme.primary)),
          ],
        ),
      ),
    );
  }
}

Widget _pillButton(IconData icon, String label, VoidCallback onTap) {
  return Builder(
    builder: (context) => Material(
      color: AppPalette.inkPrimary,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppPalette.sheet),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.sheet)),
            ],
          ),
        ),
      ),
    ),
  );
}
