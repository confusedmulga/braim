import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pill-shaped bubble wrapping a row of action icons (the editor top
/// bars). Matches [GlassBubble]'s faint fill so the back bubble and the
/// action cluster read as one aligned line of chrome.
class BubblePill extends StatelessWidget {
  const BubblePill({super.key, required this.children, this.glassColor});

  final List<Widget> children;
  final Color? glassColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: glassColor ?? const Color(0x14000000),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// A circular "bubble" around an icon button (back, menu, …). A flat
/// near-opaque fill, no live blur: these float over scrolling feeds, and a
/// backdrop filter here re-samples the feed on every frame.
class GlassBubble extends StatelessWidget {
  const GlassBubble({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.glassColor,
    this.size = 44,
    this.iconSize = 24,
    this.shadow = true,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  /// Tint of the glass — a faint white over dark backgrounds, a faint dark over
  /// light backgrounds so the bubble stays visible. Defaults to the theme's
  /// bubble glass.
  final Color? glassColor;
  final double size;
  final double iconSize;

  /// Disable inside AppBars: their tight leading box clips the shadow.
  final bool shadow;

  /// Accessibility label + long-press tooltip.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget bubble = _bubble();
    if (tooltip != null) {
      bubble = Tooltip(
        message: tooltip!,
        child: Semantics(button: true, label: tooltip, child: bubble),
      );
    }
    return bubble;
  }

  Widget _bubble() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glassColor ?? AppPalette.bubbleGlass,
        border: Border.all(color: AppPalette.cardOutline),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon,
              color: iconColor ?? AppPalette.inkPrimary, size: iconSize),
        ),
      ),
    );
  }
}
