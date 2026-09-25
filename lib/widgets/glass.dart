import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../platform/braim_image.dart';

/// The app background: a plain Material 3 surface everywhere, plus, on the main
/// feed shell only ([wallpaper] true), a backdrop. That backdrop is the user's
/// chosen image when one is set, otherwise the built-in per-theme line-art.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.child, this.wallpaper = false});

  final Widget? child;
  final bool wallpaper;

  @override
  Widget build(BuildContext context) {
    final custom = wallpaper
        ? context.watch<AppState>().feedBackgroundForTheme
        : '';
    final hasCustom = storedImageExists(custom);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: AppPalette.scheme.surface),
        if (wallpaper)
          Positioned.fill(
            child: RepaintBoundary(
              child: hasCustom
                  ? BraimImage(
                      custom,
                      fit: BoxFit.cover,
                      cacheWidth: 1440,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => _builtIn(),
                    )
                  : _builtIn(),
            ),
          ),
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }

  static Widget _builtIn() => Image.asset(
        AppPalette.dark
            ? 'assets/wallpapers/bg_dark.jpg'
            : 'assets/wallpapers/bg_light.jpg',
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
}

/// A solid surface colour that fades downward from the top edge. Used as a
/// short scrim over the status bar so the clock/battery stay readable over
/// scrolling content. A plain gradient, no BackdropFilter: zero per-frame cost.
/// [color] defaults to the sheet surface (white in light mode, near-black in
/// dark); pass the note's own surface so coloured notes stay seamless.
class TopScrimFade extends StatelessWidget {
  const TopScrimFade({super.key, required this.height, this.color});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppPalette.sheet;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Opaque through the status bar / toolbar zone, then an eased
            // tail so the cutoff reads soft instead of banded.
            colors: [
              c,
              c,
              c.withValues(alpha: 0.72),
              c.withValues(alpha: 0.28),
              c.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.42, 0.62, 0.82, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Fades scrolling content out along its top edge so it dissolves under the
/// header instead of clipping hard against it.
class TopFade extends StatelessWidget {
  const TopFade({super.key, required this.child, this.height = 34});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFFFFF), Colors.white],
      ).createShader(Rect.fromLTWH(0, 0, rect.width, height)),
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

/// A Material 3 outlined card surface for feed tiles: solid fill, hairline
/// outline-variant border, no shadow, 12dp corners.
class FlatCard extends StatelessWidget {
  const FlatCard({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.padding,
    this.fill,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Overrides the default tile surface (used for note colour tags).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill ?? AppPalette.cardSolid,
        borderRadius: radius,
        border: Border.all(color: AppPalette.cardOutline),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A solid Material 3 container surface (dialog/sheet style). The name is
/// historic — the glassy rim and blur are gone; [fill] tints the surface and
/// translucent fills are composited onto it so legacy callers stay readable.
class GlassEdge extends StatelessWidget {
  const GlassEdge({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blur = 0,
    this.fill,
    this.padding,
    this.shadow,
  });

  final Widget child;
  final double borderRadius;

  /// Ignored (kept for call-site compatibility; nothing blurs any more).
  final double blur;
  final Color? fill;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final base = AppPalette.scheme.surfaceContainerHigh;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Color.alphaBlend(fill ?? Colors.transparent, base),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppPalette.cardOutline),
        boxShadow: shadow,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A solid Material 3 panel (sheets, side pane, settings cards). The name is
/// historic — there is no backdrop blur any more.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 0,
    this.padding,
    this.color,
    this.borderColor,
    this.strong = false,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double borderRadius;

  /// Ignored (kept for call-site compatibility; nothing blurs any more).
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final bool strong;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final base = strong
        ? AppPalette.scheme.surfaceContainerHigh
        : AppPalette.scheme.surfaceContainerLow;
    final fill = Color.alphaBlend(color ?? Colors.transparent, base);

    Widget content = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border:
            borderColor != null ? Border.all(color: borderColor!) : null,
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap, onLongPress: onLongPress, child: content),
      );
    }
    return content;
  }
}
