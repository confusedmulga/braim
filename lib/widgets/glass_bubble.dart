import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// A circular liquid-glass "bubble" around an icon button (back, menu, …).
class GlassBubble extends StatelessWidget {
  const GlassBubble({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = const Color(0xFF1B1C22),
    this.glassColor = const Color(0xA6FFFFFF),
    this.size = 44,
    this.iconSize = 24,
    this.shadow = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  /// Tint of the glass — a faint white over dark backgrounds, a faint dark over
  /// light backgrounds so the bubble stays visible.
  final Color glassColor;
  final double size;
  final double iconSize;

  /// Disable inside AppBars: their tight leading box clips the shadow.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
      child: FakeGlass(
      shape: const LiquidOval(),
      settings: LiquidGlassSettings(
        glassColor: glassColor,
        blur: 10,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
      ),
      ),
    );
  }
}
