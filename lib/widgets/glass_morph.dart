import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A soft spring curve: gentle acceleration, ~2–3% overshoot, no wobble —
/// a droplet finding equilibrium rather than a ball bouncing.
class _SoftSpring extends Curve {
  const _SoftSpring();

  /// Overshoot strength (easeOutBack's c1): 0.55 ≈ a 2–3% overshoot.
  static const double back = 0.55;

  @override
  double transformInternal(double t) {
    final c3 = back + 1;
    final p = t - 1.0;
    return 1 + c3 * p * p * p + back * p * p;
  }
}

/// Wraps a feed card so it morphs into a full screen like a sheet of living
/// glass (Keep-style spatial continuity), and collapses back into its exact
/// place in the feed when closed.
///
/// Built for smoothness: the opened screen is laid out ONCE at its final size
/// and revealed by a growing clip, so nothing relayouts per frame; the spring,
/// sheen and shadow are paint-time only.
class GlassMorph extends StatefulWidget {
  const GlassMorph({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.closedRadius = 22,
  });

  /// Builds the collapsed feed item. Call [open] (e.g. from onTap) to expand.
  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;

  /// Builds the expanded full screen.
  final WidgetBuilder openBuilder;

  /// Corner radius of the collapsed card.
  final double closedRadius;

  @override
  State<GlassMorph> createState() => _GlassMorphState();
}

class _GlassMorphState extends State<GlassMorph> {
  final _key = GlobalKey();

  /// The original card hides while its glass twin flies; it reappears the
  /// moment the twin lands back on it.
  bool _hidden = false;

  void _open() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;

    final route = _GlassMorphRoute<void>(
      sourceRect: rect,
      closedRadius: widget.closedRadius,
      closedFace: Builder(builder: (c) => widget.closedBuilder(c, () {})),
      builder: widget.openBuilder,
    );
    setState(() => _hidden = true);
    Navigator.of(context).push(route);
    route.animation!.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) {
        setState(() => _hidden = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: IgnorePointer(
        ignoring: _hidden,
        child: Opacity(
          opacity: _hidden ? 0 : 1,
          child: widget.closedBuilder(context, _open),
        ),
      ),
    );
  }
}

class _GlassMorphRoute<T> extends PageRoute<T> {
  _GlassMorphRoute({
    required this.sourceRect,
    required this.closedRadius,
    required this.closedFace,
    required this.builder,
  });

  final Rect sourceRect;
  final double closedRadius;
  final Widget closedFace;
  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get opaque => false;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 360);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 290);

  // Width leads, height lags ~40ms behind — the sheet unfolds rather than
  // uniformly scales.
  static const _xCurve = Interval(0.0, 0.90, curve: _SoftSpring());
  static const _yCurve = Interval(0.10, 1.0, curve: _SoftSpring());

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final screen = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final tc = t.clamp(0.0, 1.0);
        final tx = _xCurve.transform(tc);
        final ty = _yCurve.transform(tc);

        final left = lerpDouble(sourceRect.left, 0, tx)!;
        final width = lerpDouble(sourceRect.width, screen.width, tx)!;
        final top = lerpDouble(sourceRect.top, 0, ty)!;
        final height = lerpDouble(sourceRect.height, screen.height, ty)!;

        // Corners hold their roundness early and straighten near the end.
        final radius =
            lerpDouble(closedRadius, 0, Curves.easeInQuad.transform(tc))!;

        // Microscopic compression as the glass gathers itself, then release.
        final squash = tc < 0.08
            ? lerpDouble(1.0, 0.988, tc / 0.08)!
            : lerpDouble(0.988, 1.0, ((tc - 0.08) / 0.92).clamp(0.0, 1.0))!;

        final shadowT = Curves.easeOut.transform(tc);
        // Highlight travels across the surface, peaking mid-flight.
        final sheen = math.sin(math.pi * tc);
        // The card face carries the first frames, then dissolves into content.
        final faceO = (1 - (tc / 0.42)).clamp(0.0, 1.0);
        final bodyO = ((tc - 0.16) / 0.5).clamp(0.0, 1.0);
        // The feed dims a touch but never disappears — context is preserved.
        final scrim = 0.10 * Curves.easeOut.transform(tc);

        // Material ancestor so the card face's text/ink render normally
        // inside the route (outside it, they'd get the yellow fallback style).
        return Material(
          type: MaterialType.transparency,
          child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child:
                    ColoredBox(color: Colors.black.withValues(alpha: scrim)),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: Transform.scale(
                scale: squash,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: 0.10 + 0.16 * shadowT),
                        blurRadius: 16 + 26 * shadowT,
                        offset: Offset(0, 6 + 8 * shadowT),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The glass sheet's own surface.
                        const ColoredBox(color: Color(0xF7FFFFFF)),
                        // The live screen, laid out once at final size and
                        // revealed by the growing clip — zero relayout. It
                        // emerges from a white veil (cheap alpha paint) rather
                        // than a whole-layer Opacity fade.
                        OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: screen.width,
                          maxWidth: screen.width,
                          minHeight: screen.height,
                          maxHeight: screen.height,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - ty).clamp(0.0, 1.0)),
                            child: child,
                          ),
                        ),
                        if (bodyO < 1)
                          IgnorePointer(
                            child: ColoredBox(
                              color: Colors.white
                                  .withValues(alpha: 1 - bodyO),
                            ),
                          ),
                        if (faceO > 0.002)
                          Positioned(
                            left: 0,
                            top: 0,
                            width: sourceRect.width,
                            child: Opacity(
                              opacity: faceO,
                              child: IgnorePointer(child: closedFace),
                            ),
                          ),
                        // Specular highlight sweeping with the motion.
                        if (sheen > 0.02)
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-1.4 + 2.4 * tc, -1),
                                  end: Alignment(-0.4 + 2.4 * tc, 1),
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white
                                        .withValues(alpha: 0.10 * sheen),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // A whisper of edge glow that stretches with motion.
                        if (radius > 1)
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(radius),
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.35 * sheen),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}
