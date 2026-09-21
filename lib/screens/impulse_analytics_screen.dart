import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import 'impulse_history_screen.dart';

/// The reflex analytics screen, opened from the journal's green card. It tracks
/// every reflex at once by default, with a dropdown to focus one; a period
/// selector (Today / 1W / 1M / 1Y / All) drives a headline completion rate, the
/// scheduled/done/missed breakdown, and a smooth completion curve; a scrollable
/// consistency heatmap taps through to the calendar.
class ImpulseAnalyticsScreen extends StatefulWidget {
  const ImpulseAnalyticsScreen({super.key});

  @override
  State<ImpulseAnalyticsScreen> createState() => _ImpulseAnalyticsScreenState();
}

enum _Range { week, month, year, all }

class _ImpulseAnalyticsScreenState extends State<ImpulseAnalyticsScreen> {
  _Range _range = _Range.week;

  /// null = every reflex ("All impulses"); otherwise the focused impulse id.
  String? _scopeId;

  static const _ink = Colors.white;

  List<Impulse> _scope(AppState state) => _scopeId == null
      ? state.reflexes
      : [state.impulseById(_scopeId!) ?? state.dailyDay];

  int _windowDays(AppState state) {
    switch (_range) {
      case _Range.week:
        return 7;
      case _Range.month:
        return 30;
      case _Range.year:
        return 365;
      case _Range.all:
        final e = state.earliestActivityDay();
        if (e == null) return 1;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        return today.difference(e).inDays + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scope = _scope(state);
    final scopeName = _scopeId == null
        ? context.t.analyticsAllImpulses
        : () {
            final imp = state.impulseById(_scopeId!);
            if (imp == null) return context.t.analyticsAllImpulses;
            return imp.title.trim().isEmpty
                ? context.t.untitledImpulse
                : imp.title;
          }();

    final (done, scheduled) = state.scopeTallyOver(scope, _windowDays(state));
    final pct = scheduled == 0 ? 0 : (done / scheduled * 100).round();
    final missed = (scheduled - done).clamp(0, scheduled);

    final currentStreak = state.activityStreak();
    final bestStreak = _bestStreak(state, scope);

    return FrostedScaffold(
      title: context.t.analyticsTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
        children: [
          _scopePicker(context, state, scopeName),
          const SizedBox(height: 14),
          _periodSelector(context),
          const SizedBox(height: 16),
          _headerCard(context, pct, scheduled, done, missed, scope, state),
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
          const SizedBox(height: 20),
          _AnalyticsHeatmap(
            scope: scope,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ImpulseHistoryScreen(impulseId: _scopeId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _bestStreak(AppState state, List<Impulse> scope) {
    var best = 0;
    for (final i in scope) {
      best = math.max(best, state.streakFor(i).best);
    }
    return best;
  }

  // ---- The scope dropdown --------------------------------------------------

  Widget _scopePicker(BuildContext context, AppState state, String name) {
    return GestureDetector(
      onTap: () => _pickScope(context, state),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(
          children: [
            Icon(_scopeId == null ? Icons.dashboard_rounded : Icons.bolt_rounded,
                size: 18, color: AppPalette.scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
            ),
            Icon(Icons.arrow_drop_down_rounded,
                color: AppPalette.inkSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _pickScope(BuildContext context, AppState state) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppPalette.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(context.t.analyticsTrackLabel.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _scopeRow(sheetCtx, null, context.t.analyticsAllImpulses,
                      Icons.dashboard_rounded),
                  for (final imp in state.reflexes)
                    _scopeRow(
                        sheetCtx,
                        imp.id,
                        imp.title.trim().isEmpty
                            ? context.t.untitledImpulse
                            : imp.title,
                        Icons.bolt_rounded),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    // A null result means the sheet was dismissed; only 'sentinel' distinguishes
    // picking "All". We encode All as the empty string and map it back here.
    if (picked == '__all__') {
      setState(() => _scopeId = null);
    } else if (picked != null) {
      setState(() => _scopeId = picked);
    }
  }

  Widget _scopeRow(BuildContext sheetCtx, String? id, String label,
      IconData icon) {
    final selected = id == _scopeId;
    return ListTile(
      leading: Icon(icon,
          color: selected ? AppPalette.scheme.primary : AppPalette.inkSecondary),
      title: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: FontWeight.w700, color: AppPalette.inkPrimary)),
      trailing: selected
          ? Icon(Icons.check_rounded, color: AppPalette.scheme.primary)
          : null,
      onTap: () => Navigator.pop(sheetCtx, id ?? '__all__'),
    );
  }

  // ---- The period selector -------------------------------------------------

  Widget _periodSelector(BuildContext context) {
    final items = <(_Range, String)>[
      (_Range.week, context.t.analyticsPeriodWeek),
      (_Range.month, context.t.analyticsPeriodMonth),
      (_Range.year, context.t.analyticsPeriodYear),
      (_Range.all, context.t.analyticsPeriodAll),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _range = it.$1),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _range == it.$1
                        ? AppPalette.scheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(it.$2,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _range == it.$1
                              ? AppPalette.scheme.onPrimary
                              : AppPalette.inkSecondary)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- The headline card (stats + curve/ring) ------------------------------

  Widget _headerCard(BuildContext context, int pct, int scheduled, int done,
      int missed, List<Impulse> scope, AppState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
              _chip(scheduled, context.t.progressTotal),
              _chip(done, context.t.progressCompleted),
              _chip(missed, context.t.analyticsMissed),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pct%',
                  style: const TextStyle(
                      fontSize: 40,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      color: _ink)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(context.t.analyticsAverage,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _ink.withValues(alpha: 0.7))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 138,
            child: _CurveGraph(
              values: _curveValues(state, scope),
              axisLabels: _axisLabels(state),
              pointLabels: _pointLabels(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(int value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _ink.withValues(alpha: 0.7))),
          ],
        ),
      );

  // ---- Curve data ----------------------------------------------------------

  double _frac((int, int) t) => t.$2 == 0 ? 0.0 : t.$1 / t.$2;

  (int done, int scheduled) _monthTally(
      AppState state, List<Impulse> scope, int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    var done = 0;
    var scheduled = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var d = 1; d <= days; d++) {
      final day = DateTime(year, month, d);
      if (day.isAfter(today)) break;
      final (dd, ss) = state.scopeTallyOn(scope, day);
      done += dd;
      scheduled += ss;
    }
    return (done, scheduled);
  }

  List<double> _curveValues(AppState state, List<Impulse> scope) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.week:
        return [
          for (var i = 6; i >= 0; i--)
            _frac(state.scopeTallyOn(scope, today.subtract(Duration(days: i))))
        ];
      case _Range.month:
        return [
          for (var i = 29; i >= 0; i--)
            _frac(state.scopeTallyOn(scope, today.subtract(Duration(days: i))))
        ];
      case _Range.year:
        return [
          for (var i = 11; i >= 0; i--)
            () {
              final m = DateTime(today.year, today.month - i, 1);
              return _frac(_monthTally(state, scope, m.year, m.month));
            }()
        ];
      case _Range.all:
        final e = state.earliestActivityDay() ?? today;
        final months = ((today.year - e.year) * 12 + today.month - e.month + 1)
            .clamp(1, 24).toInt();
        return [
          for (var i = months - 1; i >= 0; i--)
            () {
              final m = DateTime(today.year, today.month - i, 1);
              return _frac(_monthTally(state, scope, m.year, m.month));
            }()
        ];
    }
  }

  int _allMonths(AppState state, DateTime today) {
    final e = state.earliestActivityDay() ?? today;
    return ((today.year - e.year) * 12 + today.month - e.month + 1)
        .clamp(1, 24)
        .toInt();
  }

  /// The sparse x-axis labels under the curve. In the All range these are the
  /// year numbers, shown once where the year changes.
  List<String> _axisLabels(AppState state) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.week:
        return [
          for (var i = 6; i >= 0; i--)
            DateFormat('E').format(today.subtract(Duration(days: i)))[0]
        ];
      case _Range.month:
        return [
          for (var i = 29; i >= 0; i--)
            (i == 0 || i == 7 || i == 14 || i == 21 || i == 28)
                ? DateFormat('d').format(today.subtract(Duration(days: i)))
                : ''
        ];
      case _Range.year:
        return [
          for (var i = 11; i >= 0; i--)
            DateFormat('MMM').format(DateTime(today.year, today.month - i, 1))[0]
        ];
      case _Range.all:
        // Year numbers, printed once at each year boundary.
        final months = _allMonths(state, today);
        final out = <String>[];
        int? lastYear;
        for (var i = months - 1; i >= 0; i--) {
          final m = DateTime(today.year, today.month - i, 1);
          out.add(m.year != lastYear ? '${m.year}' : '');
          lastYear = m.year;
        }
        return out;
    }
  }

  /// The full label for each point, shown in the scrub bubble.
  List<String> _pointLabels(AppState state) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.week:
        return [
          for (var i = 6; i >= 0; i--)
            DateFormat('EEE').format(today.subtract(Duration(days: i)))
        ];
      case _Range.month:
        return [
          for (var i = 29; i >= 0; i--)
            DateFormat('MMM d').format(today.subtract(Duration(days: i)))
        ];
      case _Range.year:
        return [
          for (var i = 11; i >= 0; i--)
            DateFormat('MMM').format(DateTime(today.year, today.month - i, 1))
        ];
      case _Range.all:
        final months = _allMonths(state, today);
        return [
          for (var i = months - 1; i >= 0; i--)
            DateFormat('MMM yyyy')
                .format(DateTime(today.year, today.month - i, 1))
        ];
    }
  }
}

/// A smooth completion curve with a soft gradient fill. A circle rides the end
/// of the line; touch-and-glide moves it along the curve and reveals a bubble
/// with that point's completion percentage (and its date). No value shows until
/// the graph is touched. The current bucket's axis label sits in a pill.
class _CurveGraph extends StatefulWidget {
  const _CurveGraph({
    required this.values,
    required this.axisLabels,
    required this.pointLabels,
  });
  final List<double> values;
  final List<String> axisLabels;
  final List<String> pointLabels;

  @override
  State<_CurveGraph> createState() => _CurveGraphState();
}

class _CurveGraphState extends State<_CurveGraph> {
  /// The coral line + fill, matching the reference graph.
  static const _line = Color(0xFFF3849E);
  static const _topPad = 14.0;
  static const _botPad = 6.0;

  /// The point the finger is currently over, or null when not scrubbing.
  int? _active;

  void _scrub(double localX, double width) {
    final n = widget.values.length;
    if (n == 0) return;
    final i =
        n == 1 ? 0 : (localX / width * (n - 1)).round().clamp(0, n - 1);
    if (i != _active) setState(() => _active = i);
  }

  void _clear() {
    if (_active != null) setState(() => _active = null);
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    if (values.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final hh = c.maxHeight;
              final n = values.length;
              final active = _active;
              double px(int i) => n == 1 ? w / 2 : w * i / (n - 1);
              double py(int i) =>
                  _topPad +
                  (hh - _topPad - _botPad) * (1 - values[i].clamp(0.0, 1.0));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _scrub(d.localPosition.dx, w),
                onTapUp: (_) => _clear(),
                onTapCancel: _clear,
                onHorizontalDragStart: (d) => _scrub(d.localPosition.dx, w),
                onHorizontalDragUpdate: (d) => _scrub(d.localPosition.dx, w),
                onHorizontalDragEnd: (_) => _clear(),
                onHorizontalDragCancel: _clear,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CurvePainter(values,
                            line: _line, active: active),
                      ),
                    ),
                    if (active != null)
                      _bubble(active, px(active), py(active), w),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < widget.axisLabels.length; i++)
              Expanded(
                child: _axisLabel(widget.axisLabels[i],
                    current: i == widget.axisLabels.length - 1),
              ),
          ],
        ),
      ],
    );
  }

  Widget _bubble(int i, double px, double py, double w) {
    final pct = (widget.values[i].clamp(0.0, 1.0) * 100).round();
    final label =
        i < widget.pointLabels.length ? widget.pointLabels[i] : '';
    const bw = 92.0;
    final left = (px - bw / 2).clamp(0.0, w - bw);
    final top = (py - 46).clamp(0.0, double.infinity);
    return Positioned(
      left: left,
      top: top,
      width: bw,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0C241C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$pct%',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            if (label.isNotEmpty)
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _axisLabel(String label, {required bool current}) {
    if (label.isEmpty) return const SizedBox.shrink();
    if (!current) {
      return Text(label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.55)));
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label,
            maxLines: 1,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, {required this.line, this.active});
  final List<double> values;
  final Color line;

  /// The scrubbed point, or null; the marker sits on the last point when null.
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const topPad = 14.0;
    const botPad = 6.0;
    final h = size.height - topPad - botPad;
    final n = values.length;
    Offset pt(int i) {
      final x = n == 1 ? size.width / 2 : size.width * i / (n - 1);
      final y = topPad + h * (1 - values[i].clamp(0.0, 1.0));
      return Offset(x, y);
    }

    final pts = [for (var i = 0; i < n; i++) pt(i)];
    final path = _smooth(pts);

    final fillPath = Path.from(path)
      ..lineTo(pts.last.dx, size.height - botPad)
      ..lineTo(pts.first.dx, size.height - botPad)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.32), line.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = line
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Faint dots on each point.
    for (final p in pts) {
      canvas.drawCircle(p, 2.0, Paint()..color = line.withValues(alpha: 0.4));
    }

    // The marker: a vertical guide while scrubbing, then the travelling circle
    // (at the finger when scrubbing, otherwise resting on the last point).
    final mi = (active ?? pts.length - 1).clamp(0, pts.length - 1);
    final marker = pts[mi];
    if (active != null) {
      canvas.drawLine(
        Offset(marker.dx, topPad - 6),
        Offset(marker.dx, size.height - botPad),
        Paint()
          ..color = line.withValues(alpha: 0.45)
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawCircle(marker, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(
        marker,
        5.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = line);
  }

  Path _smooth(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length < 3) {
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 >= pts.length ? pts.length - 1 : i + 2];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.values != values || old.line != line || old.active != active;
}

/// A GitHub-style completion heatmap over the scope's active span, one square
/// per day shaded by that day's completion percentage. Horizontally scrollable,
/// opens to today, and taps through to the calendar.
class _AnalyticsHeatmap extends StatefulWidget {
  const _AnalyticsHeatmap({required this.scope, required this.onOpen});
  final List<Impulse> scope;
  final VoidCallback onOpen;

  @override
  State<_AnalyticsHeatmap> createState() => _AnalyticsHeatmapState();
}

class _AnalyticsHeatmapState extends State<_AnalyticsHeatmap> {
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _colW = _cell + _gap;

  final _scrollCtrl = ScrollController();
  bool _didAutoScroll = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var startDay = widget.scope.length == 1
        ? widget.scope.first.consistencyStart
        : (state.earliestActivityDay() ?? today.subtract(const Duration(days: 27)));
    if (startDay.isAfter(today)) startDay = today;
    // Cap the span so a very old start doesn't build an enormous grid.
    final earliestAllowed = today.subtract(const Duration(days: 365 * 2));
    if (startDay.isBefore(earliestAllowed)) startDay = earliestAllowed;

    final gridOrigin = startDay.subtract(Duration(days: startDay.weekday - 1));
    final cols = (today.difference(gridOrigin).inDays / 7).floor() + 1;

    if (!_didAutoScroll) {
      _didAutoScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final col = (today.difference(gridOrigin).inDays / 7).floor();
        final target =
            (col + 1) * _colW - _scrollCtrl.position.viewportDimension;
        _scrollCtrl
            .jumpTo(target.clamp(0.0, _scrollCtrl.position.maxScrollExtent));
      });
    }

    return GestureDetector(
      onTap: widget.onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                Text(context.t.consistencyHeatmap.toUpperCase(),
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkSecondary)),
                const SizedBox(width: 5),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppPalette.inkSecondary),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 7 * _cell + 6 * _gap,
              child: ListView.builder(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                itemCount: cols,
                padding: EdgeInsets.zero,
                itemBuilder: (ctx, w) => Padding(
                  padding: const EdgeInsets.only(right: _gap),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var d = 0; d < 7; d++)
                        Padding(
                          padding: EdgeInsets.only(bottom: d == 6 ? 0 : _gap),
                          child: _cell2(state,
                              gridOrigin.add(Duration(days: w * 7 + d)),
                              startDay, today),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell2(
      AppState state, DateTime day, DateTime startDay, DateTime today) {
    if (day.isBefore(startDay) || day.isAfter(today)) {
      return const SizedBox(width: _cell, height: _cell);
    }
    final (done, scheduled) = state.scopeTallyOn(widget.scope, day);
    Color color;
    if (scheduled == 0) {
      color = AppPalette.cardOutline.withValues(alpha: 0.25);
    } else {
      final frac = done / scheduled;
      if (frac >= 1.0) {
        color = AppPalette.journalAccent;
      } else if (frac > 0) {
        color = Color.lerp(AppPalette.cardOutline, AppPalette.journalAccent,
            0.3 + frac * 0.5)!;
      } else {
        color = AppPalette.cardOutline.withValues(alpha: 0.4);
      }
    }
    return Container(
      width: _cell,
      height: _cell,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: day == today
            ? Border.all(color: AppPalette.scheme.primary, width: 1.4)
            : null,
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
                      fontWeight: FontWeight.w700,
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
