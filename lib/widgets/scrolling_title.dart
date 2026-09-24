import 'dart:async';

import 'package:flutter/material.dart';

/// A one-line title for a top bar. A title that fits sits still, centred. One
/// that doesn't drifts slowly toward its end so the whole of it can be read,
/// pauses, returns to the start and goes again. A tap sends it back to the
/// start; dragging left or right scrolls it by hand, and the drift resumes a
/// few seconds after the finger lifts. With animations turned off in the
/// system settings it never drifts, but can still be dragged.
class ScrollingTitle extends StatefulWidget {
  const ScrollingTitle(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<ScrollingTitle> createState() => _ScrollingTitleState();
}

class _ScrollingTitleState extends State<ScrollingTitle> {
  final _ctrl = ScrollController();

  /// Reading pace of the drift, in logical pixels per second.
  static const _speed = 28.0;

  /// How long the title rests at each end before moving on.
  static const _pause = Duration(milliseconds: 1600);

  /// After a manual drag, how long to wait before drifting again.
  static const _resumeAfterDrag = Duration(seconds: 3);

  /// The fade at each edge; the text is inset by the same amount so that at
  /// rest its first and last letters sit clear of the fade.
  static const _edge = 14.0;

  /// Bumped to cancel the running drift loop (tap, drag, new title, dispose).
  int _run = 0;

  /// The one pending wait of the drift loop, cancellable so no timer outlives
  /// the widget.
  Timer? _timer;
  bool _dragging = false;

  /// Whether the last layout overflowed; null forces a re-check.
  bool? _overflowed;

  @override
  void didUpdateWidget(ScrollingTitle old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _stop();
      _overflowed = null;
      if (_ctrl.hasClients) _ctrl.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _stop();
    _ctrl.dispose();
    super.dispose();
  }

  void _stop() {
    _run++;
    _timer?.cancel();
    _timer = null;
  }

  /// Waits [d] unless the loop is cancelled first (then never completes, and
  /// the suspended loop is simply dropped).
  Future<void> _sleep(Duration d) {
    final done = Completer<void>();
    _timer?.cancel();
    _timer = Timer(d, done.complete);
    return done.future;
  }

  bool get _canScroll =>
      _ctrl.hasClients && _ctrl.position.maxScrollExtent > 0;

  /// The drift loop: rest, glide to the end, rest, return, repeat.
  Future<void> _drift() async {
    _stop();
    final run = _run;
    bool live() => mounted && run == _run && _canScroll;
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    while (true) {
      await _sleep(_pause);
      if (!live()) return;
      final end = _ctrl.position.maxScrollExtent;
      final left = end - _ctrl.offset;
      if (left > 0) {
        await _ctrl.animateTo(
          end,
          duration: Duration(milliseconds: (left / _speed * 1000).round()),
          curve: Curves.linear,
        );
      }
      if (!live()) return;
      await _sleep(_pause);
      if (!live()) return;
      await _returnToStart();
      if (!live()) return;
    }
  }

  /// How the title gets back to its first letter after resting at the end.
  /// It snaps straight back: the next rest at the start gives the eye time to
  /// find the first letter again.
  Future<void> _returnToStart() async {
    _ctrl.jumpTo(0);
  }

  /// A tap: back to the start, then drift again from there.
  void _onTap() {
    if (!_canScroll) return;
    _stop();
    _ctrl.animateTo(0,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    _drift();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      // The finger takes over; the drift waits until it lets go.
      _dragging = true;
      _stop();
    } else if (n is ScrollEndNotification && _dragging) {
      _dragging = false;
      _stop();
      _timer = Timer(_resumeAfterDrag, _drift);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final overflows = painter.width > constraints.maxWidth;
      painter.dispose();

      if (overflows != _overflowed) {
        _overflowed = overflows;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          overflows ? _drift() : _stop();
        });
      }

      final text = Text(widget.text,
          maxLines: 1, softWrap: false, style: widget.style);
      if (!overflows) return Center(child: text);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ShaderMask(
            // Soft edges show there is more title beyond the bar.
            shaderCallback: (rect) => LinearGradient(
              colors: const [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [
                0,
                _edge / rect.width,
                1 - _edge / rect.width,
                1,
              ],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _ctrl,
              scrollDirection: Axis.horizontal,
              // No rubber-banding past either end of the title.
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: _edge),
              child: Center(child: text),
            ),
          ),
        ),
      );
    });
  }
}
