import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/dnd_service.dart';
import '../state/pomodoro_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';

const _restColor = Color(0xFF3E8E7E);

/// The Pomodoro focus timer. Idle, it's a tick-marked dial (the reference) with
/// a pull-up sheet for the time and Do Not Disturb. Running, the screen goes
/// black with only the time — and it keeps running in the background (an ongoing
/// notification) if you leave.
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  final _c = PomodoroController.instance;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  FocusStrings _strings(BuildContext c) => FocusStrings(
        focus: c.t.pomodoroFocus,
        rest: c.t.pomodoroBreak,
        done: c.t.pomodoroComplete,
        round: c.t.pomodoroRound,
        paused: c.t.pomodoroPaused,
        breakSoon: c.t.pomodoroBreakSoon,
        backToFocus: c.t.pomodoroBackToFocus,
        sessionDone: c.t.pomodoroSessionDone,
      );

  Color get _phaseColor =>
      _c.isFocus ? AppPalette.scheme.primary : _restColor;

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _hideTimer?.cancel();
    if (_showControls) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) =>
          _c.running ? _focusMode(context) : _setupMode(context),
    );
  }

  // ---- Setup / paused -----------------------------------------------------

  Widget _setupMode(BuildContext context) {
    final paused = _c.paused;
    return FrostedScaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 4),
            Text(context.t.focusTitle,
                style: TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary)),
            Expanded(child: Center(child: _dialStack(context, dark: false))),
            _roundDots(dark: false),
            const SizedBox(height: 20),
            _setupControls(context, paused),
            const SizedBox(height: 14),
            _pullHandle(context),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
          ],
        ),
      ),
    );
  }

  Widget _setupControls(BuildContext context, bool paused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (paused) ...[
          _circleButton(Icons.stop_rounded, () => _c.reset()),
          const SizedBox(width: 16),
        ],
        _primaryButton(
          label: paused ? context.t.pomodoroResume : context.t.pomodoroStart,
          icon: Icons.play_arrow_rounded,
          onTap: () => _c.start(_strings(context)),
        ),
      ],
    );
  }

  Widget _pullHandle(BuildContext context) {
    return GestureDetector(
      onTap: () => _openSettings(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -80) _openSettings(context);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_up_rounded,
                size: 20, color: AppPalette.inkSecondary),
            const SizedBox(width: 6),
            Text(context.t.pomodoroSettings,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary)),
          ],
        ),
      ),
    );
  }

  // ---- Focus (running) ----------------------------------------------------

  Widget _focusMode(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          children: [
            Center(child: _dialStack(context, dark: true)),
            Positioned(
              top: pad.top + 14,
              left: 0,
              right: 0,
              child: Center(child: _roundDots(dark: true)),
            ),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    Positioned(
                      top: pad.top + 8,
                      left: 12,
                      child: _darkCircle(Icons.arrow_back_rounded,
                          () => Navigator.pop(context)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: pad.bottom + 40,
                      child: Column(
                        children: [
                          Text(context.t.focusRunningHint,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _darkCircle(
                                  Icons.stop_rounded, () => _c.reset()),
                              const SizedBox(width: 18),
                              _darkPill(context.t.pomodoroPause,
                                  Icons.pause_rounded, () => _c.pause()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Shared dial --------------------------------------------------------

  Widget _dialStack(BuildContext context, {required bool dark}) {
    final color = _phaseColor;
    final timeColor = dark
        ? Colors.white
        : (_c.completed ? AppPalette.inkSecondary : AppPalette.inkPrimary);
    return LayoutBuilder(
      builder: (context, cns) {
        final side = math.min(cns.maxWidth, cns.maxHeight).clamp(220.0, 340.0);
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(side),
                painter: _DialPainter(
                  fraction: _c.fraction,
                  color: color,
                  track: color.withValues(alpha: dark ? 0.22 : 0.16),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: side * 0.52,
                    height: side * 0.2,
                    child: CustomPaint(
                      painter: _DotClock(_c.clock, timeColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _phaseLabel(context).toUpperCase(),
                    style: TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: _c.completed
                            ? (dark
                                ? Colors.white70
                                : AppPalette.inkSecondary)
                            : color),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _phaseLabel(BuildContext context) {
    if (_c.completed) return context.t.pomodoroComplete;
    return _c.isFocus ? context.t.pomodoroFocus : context.t.pomodoroBreak;
  }

  Widget _roundDots({required bool dark}) {
    final on = dark ? Colors.white : AppPalette.scheme.primary;
    final off = dark ? Colors.white24 : AppPalette.cardOutline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 1; r <= _c.rounds; r++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (_c.completed || r <= _c.round) ? on : Colors.transparent,
              border: (_c.completed || r <= _c.round)
                  ? null
                  : Border.all(color: off),
            ),
          ),
      ],
    );
  }

  // ---- Buttons ------------------------------------------------------------

  Widget _primaryButton(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        decoration: BoxDecoration(
          color: AppPalette.inkPrimary,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.scheme.surface)),
            const SizedBox(width: 8),
            Icon(icon, size: 22, color: AppPalette.scheme.surface),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          shape: BoxShape.circle,
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Icon(icon, color: AppPalette.inkPrimary),
      ),
    );
  }

  Widget _darkCircle(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _darkPill(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black)),
            const SizedBox(width: 6),
            Icon(icon, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }

  // ---- Settings sheet -----------------------------------------------------

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(controller: _c),
    );
  }
}

/// The pull-up settings: the time steppers (locked once running) and the Do Not
/// Disturb selector.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.controller});
  final PomodoroController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final locked = !controller.idle;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            decoration: BoxDecoration(
              color: AppPalette.sheet,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppPalette.cardOutline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _label(context.t.pomodoroSettings),
                const SizedBox(height: 10),
                Opacity(
                  opacity: locked ? 0.5 : 1,
                  child: IgnorePointer(
                    ignoring: locked,
                    child: Row(
                      children: [
                        _stepper(context.t.pomodoroFocusMin,
                            '${controller.focusMin}m',
                            () => controller.setFocusMin(controller.focusMin - 5),
                            () => controller.setFocusMin(controller.focusMin + 5)),
                        const SizedBox(width: 10),
                        _stepper(context.t.pomodoroBreakMin,
                            '${controller.breakMin}m',
                            () => controller.setBreakMin(controller.breakMin - 1),
                            () => controller.setBreakMin(controller.breakMin + 1)),
                        const SizedBox(width: 10),
                        _stepper(context.t.pomodoroRounds, '${controller.rounds}',
                            () => controller.setRounds(controller.rounds - 1),
                            () => controller.setRounds(controller.rounds + 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _label(context.t.dndTitle),
                const SizedBox(height: 10),
                _dndTile(context, DndMode.off, context.t.dndOff,
                    context.t.dndOffDesc, Icons.notifications_active_outlined),
                const SizedBox(height: 8),
                _dndTile(context, DndMode.focus, context.t.dndFocus,
                    context.t.dndFocusDesc, Icons.do_not_disturb_on_outlined),
                const SizedBox(height: 8),
                _dndTile(context, DndMode.silence, context.t.dndSilence,
                    context.t.dndSilenceDesc, Icons.nightlight_round),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.call_outlined,
                        size: 15, color: AppPalette.inkSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.t.dndCallsNote,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppPalette.inkSecondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _label(String text) => Text(text.toUpperCase(),
      style: TextStyle(
          fontSize: 11.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: AppPalette.inkSecondary));

  Widget _dndTile(BuildContext context, DndMode mode, String title,
      String desc, IconData icon) {
    final selected = controller.dnd == mode;
    return GestureDetector(
      onTap: () => _pickDnd(context, mode),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.scheme.primary.withValues(alpha: 0.10)
              : AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppPalette.scheme.primary
                : AppPalette.cardOutline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected
                    ? AppPalette.scheme.primary
                    : AppPalette.inkSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 1),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 12, color: AppPalette.inkSecondary)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  size: 20, color: AppPalette.scheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDnd(BuildContext context, DndMode mode) async {
    if (mode != DndMode.off) {
      final ok = await DndService.instance.hasAccess();
      if (!ok && context.mounted) {
        final grant = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppPalette.sheet,
            title: Text(context.t.dndGrantTitle,
                style: TextStyle(color: AppPalette.inkPrimary)),
            content: Text(context.t.dndGrantBody,
                style: TextStyle(color: AppPalette.inkSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t.cancel)),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t.dndGrant)),
            ],
          ),
        );
        if (grant == true) await DndService.instance.openSettings();
      }
    }
    await controller.setDnd(mode);
  }

  Widget _stepper(
      String label, String value, VoidCallback minus, VoidCallback plus) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Column(
          children: [
            Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkSecondary)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn(Icons.remove_rounded, minus),
                SizedBox(
                  width: 40,
                  child: Text(value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                ),
                _stepBtn(Icons.add_rounded, plus),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppPalette.cardOutline),
          ),
          child: Icon(icon, size: 16, color: AppPalette.inkPrimary),
        ),
      );
}

/// The tick-marked dial: a light full track, a coloured progress arc with fine
/// ticks along it, and a rounded thumb at the leading edge (the reference).
class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const band = 22.0;
    final radius = (size.shortestSide - band) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2; // 12 o'clock
    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band
          ..color = track);

    if (sweep > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = band
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    const tickCount = 72;
    final tickPaint = Paint()
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i <= tickCount; i++) {
      final a = start + (2 * math.pi) * (i / tickCount);
      if (a > start + sweep) break;
      final outer = Offset(center.dx + math.cos(a) * (radius + band / 2 - 2),
          center.dy + math.sin(a) * (radius + band / 2 - 2));
      final inner = Offset(center.dx + math.cos(a) * (radius - band / 2 + 2),
          center.dy + math.sin(a) * (radius - band / 2 + 2));
      canvas.drawLine(inner, outer, tickPaint);
    }

    final ta = start + sweep;
    final tc = Offset(
        center.dx + math.cos(ta) * radius, center.dy + math.sin(ta) * radius);
    canvas.drawCircle(
        tc,
        band / 2 + 3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        tc,
        band / 2 + 3,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Renders a "MM:SS" string as a dot-matrix clock (the second reference's
/// number style), using a compact 3×5 dot font drawn with CustomPaint.
class _DotClock extends CustomPainter {
  const _DotClock(this.text, this.color);
  final String text;
  final Color color;

  static const _font = <String, List<String>>{
    '0': ['111', '101', '101', '101', '111'],
    '1': ['010', '110', '010', '010', '111'],
    '2': ['111', '001', '111', '100', '111'],
    '3': ['111', '001', '111', '001', '111'],
    '4': ['101', '101', '111', '001', '001'],
    '5': ['111', '100', '111', '001', '111'],
    '6': ['111', '100', '111', '101', '111'],
    '7': ['111', '001', '010', '010', '010'],
    '8': ['111', '101', '111', '101', '111'],
    '9': ['111', '101', '111', '001', '111'],
    ':': ['0', '0', '1', '0', '1'],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final glyphs = [for (final ch in text.split('')) _font[ch] ?? _font['0']!];
    var cols = 0;
    for (var i = 0; i < glyphs.length; i++) {
      cols += glyphs[i].first.length;
      if (i < glyphs.length - 1) cols += 1;
    }
    const rows = 5;
    final cell = math.min(size.width / cols, size.height / rows);
    final dot = cell * 0.82;
    final gridW = cols * cell;
    final gridH = rows * cell;
    final ox = (size.width - gridW) / 2;
    final oy = (size.height - gridH) / 2;

    final paint = Paint()..color = color;
    var cx = 0;
    for (var g = 0; g < glyphs.length; g++) {
      final pat = glyphs[g];
      final w = pat.first.length;
      for (var r = 0; r < rows; r++) {
        for (var col = 0; col < w; col++) {
          if (pat[r][col] == '1') {
            final c = Offset(
              ox + (cx + col) * cell + cell / 2,
              oy + r * cell + cell / 2,
            );
            canvas.drawCircle(c, dot / 2, paint);
          }
        }
      }
      cx += w + 1;
    }
  }

  @override
  bool shouldRepaint(_DotClock old) => old.text != text || old.color != color;
}
