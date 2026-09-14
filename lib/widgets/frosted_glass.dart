import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A frosted-glass surface: a shape-clipped backdrop blur under a translucent
/// tint, with a hairline glass edge.
///
/// This is a local replacement for the dev-channel `liquid_glass_renderer`
/// package's `FakeGlass` — which was only ever its non-shader fallback path
/// (clip + [BackdropFilter] + tinted fill). Reproducing it here drops the one
/// pinned pre-release dependency the app carried, with the same visual result.
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.child,
    required this.color,
    this.blur = 12,
    this.circle = false,
    this.borderRadius = 0,
  });

  final Widget child;

  /// The translucent tint painted over the blurred backdrop.
  final Color color;
  final double blur;

  /// Clip as a circle (the nav bubbles) rather than a rounded rectangle.
  final bool circle;

  /// Corner radius when [circle] is false.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: AppPalette.cardOutline);
    final ShapeBorder shape = circle
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius), side: side);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: ShapeDecoration(color: color, shape: shape),
          child: child,
        ),
      ),
    );
  }
}
