import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';

/// The analytics view for an impulse (or, in "All" scope, every reflex). Today's
/// completion ring, streaks, a global thread + writing-time readout, and a
/// Duolingo-style consistency chart with a range selector.
class ImpulseAnalyticsScreen extends StatelessWidget {
  const ImpulseAnalyticsScreen({super.key, required this.impulseId});
  final String impulseId;

  static const _ink = Colors.white;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showAll = state.progressShowAll;
    final impulse = state.impulseById(impulseId) ?? state.dailyDay;

    final impulseName = state.isDailyDay(impulse.id)
        ? context.t.dailyDay
        : (impulse.title.trim().isEmpty
            ? context.t.untitledImpulse
            : impulse.title);

    // The set the metrics/chart cover: every live reflex, or just this impulse.
    final scope = showAll ? state.reflexes : [impulse];
    final progress =
        showAll ? state.todayProgress : state.todayProgressFor(impulse);
    final streak = state.streakFor(impulse);
    final currentStreak = showAll ? state.activityStreak() : streak.current;
    final bestStreak = showAll
        ? _bestAcross(state)
        : math.max(streak.best, streak.current);

    final minutes = state.typingTime.inMinutes;
    final writing = minutes < 60
        ? '${minutes}m'
        : '${(minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1)}h';

    return FrostedScaffold(
      title: context.t.analyticsTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
        children: [
          // Scope toggle: all reflexes, or just this impulse.
          _ScopeToggle(
            allSelected: showAll,
            impulseLabel: impulseName,
            onAll: () => state.setProgressShowAll(true),
            onOne: () => state.setProgressShowAll(false),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12362B), Color(0xFF1D4C3B)],
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CustomPaint(
                    painter: _RingPaint(progress.fraction),
                    child: Center(
                      child: Text('${(progress.fraction * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          showAll
                              ? context.t.analyticsAllReflexes
                              : impulseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                      const SizedBox(height: 2),
                      Text(context.t.todaysProgress,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _ink.withValues(alpha: 0.6))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _stat(progress.total, context.t.progressTotal),
                          _stat(progress.done, context.t.progressCompleted),
                          _stat(progress.pending, context.t.progressPending),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFFF5A623),
                  value: '$currentStreak',
                  label: context.t.analyticsCurrentStreak,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.emoji_events_outlined,
                  color: const Color(0xFFF5A623),
                  value: '$bestStreak',
                  label: context.t.analyticsBestStreak,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.dns_rounded,
                  color: AppPalette.scheme.primary,
                  value: '${state.totalThreadCount}',
                  label: context.t.analyticsThreads,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  icon: Icons.edit_note_rounded,
                  color: AppPalette.scheme.primary,
                  value: writing,
                  label: context.t.analyticsWritingTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ConsistencyChart(impulses: scope),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surfaceGlass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Row(
              children: [
                Icon(Icons.insights_rounded, color: AppPalette.inkSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(context.t.analyticsComingSoon,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: AppPalette.inkSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _bestAcross(AppState state) {
    var best = 0;
    for (final i in state.reflexes) {
      best = math.max(best, state.streakFor(i).best);
    }
    return best;
  }

  Widget _stat(int value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
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

/// The all-vs-one scope selector at the top of the analytics screen.
class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({
    required this.allSelected,
    required this.impulseLabel,
    required this.onAll,
    required this.onOne,
  });
  final bool allSelected;
  final String impulseLabel;
  final VoidCallback onAll;
  final VoidCallback onOne;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Row(
        children: [
          _seg(context, context.t.analyticsScopeAll, allSelected, onAll),
          _seg(context, impulseLabel, !allSelected, onOne),
        ],
      ),
    );
  }

  Widget _seg(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected ? AppPalette.scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppPalette.scheme.onPrimary
                      : AppPalette.inkSecondary)),
        ),
      ),
    );
  }
}

enum _Period { week, month, year, max }

/// A Duolingo-style bar chart of threads completed over the selected range, with
/// a range selector in the top-right corner.
class _ConsistencyChart extends StatefulWidget {
  const _ConsistencyChart({required this.impulses});
  final List<Impulse> impulses;

  @override
  State<_ConsistencyChart> createState() => _ConsistencyChartState();
}

class _ConsistencyChartState extends State<_ConsistencyChart> {
  _Period _period = _Period.week;

  /// A day-key -> completions map across every thread in scope.
  Map<String, int> _completionsByDay() {
    final map = <String, int>{};
    for (final imp in widget.impulses) {
      for (final t in imp.allThreads) {
        for (final d in t.doneDays) {
          map[d] = (map[d] ?? 0) + 1;
        }
      }
    }
    return map;
  }

  DateTime _earliest(Map<String, int> byDay) {
    DateTime? min;
    for (final k in byDay.keys) {
      final d = DateTime.tryParse(k);
      if (d != null && (min == null || d.isBefore(min))) min = d;
    }
    for (final imp in widget.impulses) {
      final c = imp.consistencyStart;
      if (min == null || c.isBefore(min)) min = c;
    }
    return min ?? DateTime.now();
  }

  List<(String, int)> _buckets(Map<String, int> byDay) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int dayVal(DateTime d) => byDay[AppState.dayKeyFor(d)] ?? 0;
    int monthVal(int year, int month) {
      final prefix =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
      var sum = 0;
      byDay.forEach((k, v) {
        if (k.startsWith(prefix)) sum += v;
      });
      return sum;
    }

    switch (_period) {
      case _Period.week:
        return [
          for (var i = 6; i >= 0; i--)
            () {
              final d = today.subtract(Duration(days: i));
              return (DateFormat('E').format(d)[0], dayVal(d));
            }(),
        ];
      case _Period.month:
        return [
          for (var i = 29; i >= 0; i--)
            () {
              final d = today.subtract(Duration(days: i));
              // Label only the 1st and every 7th day back, else blank.
              final lbl = (i == 0 || i == 7 || i == 14 || i == 21 || i == 28)
                  ? DateFormat('d').format(d)
                  : '';
              return (lbl, dayVal(d));
            }(),
        ];
      case _Period.year:
        return [
          for (var i = 11; i >= 0; i--)
            () {
              final m = DateTime(today.year, today.month - i, 1);
              return (DateFormat('MMM').format(m)[0], monthVal(m.year, m.month));
            }(),
        ];
      case _Period.max:
        final start = _earliest(byDay);
        final months = (today.year - start.year) * 12 +
            (today.month - start.month) +
            1;
        final n = months.clamp(1, 24);
        return [
          for (var i = n - 1; i >= 0; i--)
            () {
              final m = DateTime(today.year, today.month - i, 1);
              return (DateFormat('MMM').format(m)[0], monthVal(m.year, m.month));
            }(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _completionsByDay();
    final buckets = _buckets(byDay);
    final maxVal = buckets.fold<int>(1, (m, b) => math.max(m, b.$2));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppPalette.surfaceGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.t.analyticsConsistency.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary)),
              const Spacer(),
              _selector(),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: buckets.length > 14 ? 0.6 : 2.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: math.max(0.04, b.$2 / maxVal),
                          child: Container(
                            decoration: BoxDecoration(
                              color: b.$2 == 0
                                  ? AppPalette.cardOutline
                                  : const Color(0xFF5FD08C),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final b in buckets)
                Expanded(
                  child: Text(b.$1,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selector() {
    final items = <(_Period, String)>[
      (_Period.week, context.t.analyticsPeriodWeek),
      (_Period.month, context.t.analyticsPeriodMonth),
      (_Period.year, context.t.analyticsPeriodYear),
      (_Period.max, context.t.analyticsPeriodMax),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => setState(() => _period = it.$1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _period == it.$1
                      ? AppPalette.scheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(it.$2,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _period == it.$1
                            ? AppPalette.scheme.onPrimary
                            : AppPalette.inkSecondary)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.inkSecondary)),
        ],
      ),
    );
  }
}

class _RingPaint extends CustomPainter {
  const _RingPaint(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
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
        -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), false, fill);
  }

  @override
  bool shouldRepaint(_RingPaint oldDelegate) =>
      oldDelegate.fraction != fraction;
}
