import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/app_theme.dart';

/// A round liquid-glass "bubble" action button that squishes on press (reacting
/// like a bubble) before firing [onTap].
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
  });

  final IconData icon;
  final VoidCallback onTap;
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
          child: FakeGlass(
            shape: const LiquidOval(),
            settings: LiquidGlassSettings(
              glassColor: widget.glassColor ?? AppPalette.bubbleGlass,
              blur: 12,
            ),
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
