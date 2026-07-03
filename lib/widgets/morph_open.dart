import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Wraps a feed item so it morphs (container transform) into a full screen when
/// opened, and collapses back into its place in the feed when closed.
class MorphOpen extends StatelessWidget {
  const MorphOpen({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.borderRadius = 22,
    this.openColor = Colors.transparent,
  });

  /// Builds the collapsed feed item. Call [open] (e.g. from onTap) to expand.
  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;

  /// Builds the expanded full screen.
  final WidgetBuilder openBuilder;

  final double borderRadius;

  /// Colour the container fills with as it expands (the opened screen's base).
  final Color openColor;

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      tappable: false,
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      openColor: openColor,
      middleColor: openColor,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      // The Material container transform, like Google Keep.
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 300),
      closedBuilder: (context, open) => closedBuilder(context, open),
      openBuilder: (context, _) => openBuilder(context),
    );
  }
}
