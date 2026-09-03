import 'package:flutter/material.dart';

/// Grows its child out of the compose button in the bottom-right corner: a
/// short scale-and-fade anchored there. Once the animation completes it hands
/// back the bare child, so the steady state costs nothing.
class ExpandFromButton extends StatelessWidget {
  const ExpandFromButton(
      {super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.isCompleted) return child!;
        final v = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: v,
          child: Transform.scale(
            scale: 0.88 + 0.12 * v,
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The format island rising into place as the editor opens.
class SlideUpFromButton extends StatelessWidget {
  const SlideUpFromButton(
      {super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        if (animation.isCompleted) return child!;
        final v = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: v,
          child: FractionalTranslation(
            translation: Offset(0, 1 - v),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
