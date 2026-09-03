import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

/// An iOS-style push: the incoming screen slides in from the right with a
/// subtle parallax on the outgoing one — no fade — and an interactive
/// edge-swipe back. Used for navigation within the Narrative section (opening a
/// book, its chapters, contents, history and find/replace) so it reads the way
/// Apple's navigation does.
Route<T> cupertinoRoute<T>(Widget page) {
  return CupertinoPageRoute<T>(builder: (_) => page);
}

/// A springy push transition that matches the app's bouncy character: the new
/// screen fades in while scaling up from slightly small, overshooting a touch
/// (easeOutBack) before it settles, and eases cleanly back out on pop.
Route<T> bouncyRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: animation.drive(
            CurveTween(curve: const Interval(0, 0.55, curve: Curves.easeOut))),
        child: ScaleTransition(
          scale: Tween(begin: 0.93, end: 1.0).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          )),
          child: child,
        ),
      );
    },
  );
}
