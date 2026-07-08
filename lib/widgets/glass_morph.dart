import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps a feed card so it expands into a full screen and collapses back into
/// its exact place in the feed — Google Keep's container transform, kept
/// deliberately simple: one standard curve, a plain surface, content
/// crossfade, nothing flashy.
///
/// Built for smoothness: the opened screen is laid out ONCE at its final size
/// and revealed by a growing clip, so nothing relayouts per frame.
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

  /// Call from inside a morph-opened screen before popping it: the route
  /// slides down off-screen unchanged instead of collapsing back into its
  /// source. Used when a NEW note was actually created — collapsing into the
  /// + button it came from would read as the note being discarded.
  static void slideCloseOf(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is _GlassMorphRoute) route.slideClose = true;
  }

  @override
  State<GlassMorph> createState() => _GlassMorphState();
}

class _GlassMorphState extends State<GlassMorph> {
  final _key = GlobalKey();

  /// The original card hides while its twin flies; it reappears the moment
  /// the twin lands back on it.
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
      if (!mounted || !_hidden) return;
      // On a slide-close the source reappears immediately, revealed as the
      // sheet rides down, instead of blinking in at the end.
      if (s == AnimationStatus.dismissed ||
          (s == AnimationStatus.reverse && route.slideClose)) {
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

  /// When set (just before pop), the reverse transition slides the sheet
  /// down off-screen at full size rather than collapsing into [sourceRect].
  bool slideClose = false;

  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get opaque => false;
  @override
  bool get maintainState => true;
  // M3 container-transform timing: a touch longer so the emphasized curve's
  // gentle settle has room to breathe.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

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
        if (slideClose) {
          // The note was kept: the sheet rides down off-screen unchanged
          // (M3 emphasized-accelerate — the exit-motion token), while the
          // feed brightens behind it.
          final v = animation.value.clamp(0.0, 1.0);
          final drop =
              const Cubic(0.3, 0, 0.8, 0.15).transform(1 - v) * screen.height;
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.08 * v)),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: drop,
                  width: screen.width,
                  height: screen.height,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 22,
                          offset: const Offset(0, -4),
                        ),
                      ]),
                      // Raster the sheet once; each slide frame then only
                      // re-composites the cached layer at a new offset.
                      child: RepaintBoundary(
                          child: ColoredBox(
                              color: AppPalette.sheet, child: child)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // M3's emphasized easing — the motion token the container-transform
        // guideline specifies: quick departure, long graceful settle.
        final t = Curves.easeInOutCubicEmphasized.transform(
          animation.value.clamp(0.0, 1.0),
        );

        final left = lerpDouble(sourceRect.left, 0, t)!;
        final top = lerpDouble(sourceRect.top, 0, t)!;
        final width = lerpDouble(sourceRect.width, screen.width, t)!;
        final height = lerpDouble(sourceRect.height, screen.height, t)!;

        // Corners hold their roundness early and straighten near the end.
        final radius = lerpDouble(closedRadius, 0, Curves.easeInQuad.transform(t))!;

        // The card face carries the first frames, then dissolves into content.
        final faceO = (1 - (t / 0.4)).clamp(0.0, 1.0);
        final bodyO = ((t - 0.15) / 0.45).clamp(0.0, 1.0);
        // The feed dims slightly but never disappears.
        final scrim = 0.08 * t;

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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10 + 0.12 * t),
                        blurRadius: 14 + 20 * t,
                        offset: Offset(0, 5 + 7 * t),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The sheet's surface.
                        ColoredBox(color: AppPalette.sheet),
                        // The live screen, laid out once at final size and
                        // revealed by the growing clip — zero relayout. The
                        // RepaintBoundary rasters it once as its own layer,
                        // so the per-frame clip change only re-composites a
                        // cached texture instead of repainting the whole
                        // screen (images, panels, text) every frame.
                        OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: screen.width,
                          maxWidth: screen.width,
                          minHeight: screen.height,
                          maxHeight: screen.height,
                          child: RepaintBoundary(child: child),
                        ),
                        if (bodyO < 1)
                          IgnorePointer(
                            child: ColoredBox(
                              color: AppPalette.sheet
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
                      ],
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
