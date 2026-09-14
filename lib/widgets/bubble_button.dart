import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'frosted_glass.dart';

/// A round liquid-glass "bubble" action button that squishes on press (reacting
/// like a bubble) before firing [onTap]. Part of the nav-island cluster, so it
/// keeps the frosted glass look the rest of the app dropped.
class BubbleButton extends StatefulWidget {
  const BubbleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 60,
    this.iconSize = 26,
    this.iconColor,
    this.glassColor,
    this.tooltip,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Optional long-press action (Home uses it for the Note/Article menu).
  final VoidCallback? onLongPress;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? glassColor;
  final String? tooltip;

  @override
  State<BubbleButton> createState() => _BubbleButtonState();
}

class _BubbleButtonState extends State<BubbleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bubble = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              setState(() => _pressed = false);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutBack,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: FrostedGlass(
            circle: true,
            // whiteFill is the nav island's translucent frost, so the two
            // stay visually paired in both modes.
            color: widget.glassColor ?? AppPalette.whiteFill,
            blur: 12,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Icon(widget.icon,
                  size: widget.iconSize,
                  color: widget.iconColor ?? AppPalette.inkPrimary),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child:
            Semantics(button: true, label: widget.tooltip, child: bubble),
      );
    }
    return bubble;
  }
}
