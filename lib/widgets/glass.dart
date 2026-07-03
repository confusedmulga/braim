import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The feed background image (Home / Cards / Cortex). Shown sharp — the blur
/// now lives only in the glass elements (island, search bar, menu button).
const String kBackgroundAsset = 'assets/BG1.jpg';

/// The feed background: the reference photo, drawn sharp (no blur layer).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _backgroundLayer(),
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }

  Widget _backgroundLayer() {
    return Image.asset(
      kBackgroundAsset,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _orbs(),
    );
  }

  Widget _orbs() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppPalette.bgTop, AppPalette.bgBottom],
        ),
      ),
      child: const Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: _Blob(color: AppPalette.blobA, size: 280),
          ),
          Positioned(
            top: 120,
            right: -90,
            child: _Blob(color: AppPalette.blobB, size: 260),
          ),
          Positioned(
            bottom: -40,
            left: -40,
            child: _Blob(color: AppPalette.blobD, size: 240),
          ),
          Positioned(
            bottom: 160,
            right: -30,
            child: _Blob(color: AppPalette.blobC, size: 200),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// A translucent frosted-white background used when a note is opened: it blurs
/// and whitens whatever is behind so the screen reads as white but lets a faint
/// hint of the background through.
class FrostedWhiteBackground extends StatelessWidget {
  const FrostedWhiteBackground({
    super.key,
    required this.child,
    this.opacity = 0.88,
  });

  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: ColoredBox(color: Colors.white.withValues(alpha: opacity)),
        ),
        child,
      ],
    );
  }
}

/// A blur that fades with distance from one edge, approximated with stacked
/// horizontal bands of decreasing sigma. Used at the top/bottom of the editors
/// so content scrolling under the app bar / island softly dissolves into blur.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    super.key,
    required this.height,
    this.fromTop = true,
    this.maxSigma = 10,
    this.bands = 6,
    this.tint,
  });

  final double height;

  /// When true the blur is strongest at the top and fades downward; when false
  /// it is strongest at the bottom and fades upward.
  final bool fromTop;
  final double maxSigma;
  final int bands;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final bandH = height / bands;
    final layers = <Widget>[];
    for (var i = 0; i < bands; i++) {
      // 0 at the blurred edge → 1 at the clear edge.
      final idxFromEdge = fromTop ? i : (bands - 1 - i);
      final t = idxFromEdge / (bands - 1);
      // Cubic ease so the tail decays smoothly to ~0 (no visible end seam).
      final sigma = maxSigma * (1 - t) * (1 - t) * (1 - t);
      if (sigma < 0.12) continue;
      layers.add(Positioned(
        top: i * bandH,
        left: 0,
        right: 0,
        height: bandH + 2.0, // overlap to blend band seams
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const SizedBox.expand(),
          ),
        ),
      ));
    }

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            ...layers,
            if (tint != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: fromTop
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      end: fromTop
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      colors: [tint!, tint!.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
          ],
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

/// A frosted surface with a soft glassy refractive rim, an inner sheen and a
/// shadow. [fill] sets the base tint behind the blur. (A lightweight
/// backdrop-filter look; the real shader-based glass is the `liquid_glass_renderer`
/// package, used for the islands and button bubbles.)
class GlassEdge extends StatelessWidget {
  const GlassEdge({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blur = 18,
    this.fill,
    this.padding,
    this.shadow,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final Color? fill;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final innerRadius =
        BorderRadius.circular((borderRadius - 1.4).clamp(0.0, borderRadius));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: Container(
        // A soft glassy rim: bright where light catches the curved edge, with
        // only a whisper of cool refraction — no rainbow.
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xD9FFFFFF), // light-catching highlight
              Color(0x33EAFBFF), // faint cool glint
              Color(0x1FFFFFFF),
              Color(0x99FFFFFF), // soft white
            ],
            stops: [0.0, 0.3, 0.62, 1.0],
          ),
        ),
        padding: const EdgeInsets.all(1.4),
        child: ClipRRect(
          borderRadius: innerRadius,
          child: _MaybeBlur(
            blur: blur,
            child: ColoredBox(
              color: fill ?? AppPalette.glassFill,
              child: DecoratedBox(
                // A top-down sheen for the glassy specular highlight.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps [child] in a backdrop blur only when [blur] > 0. Skipping the
/// BackdropFilter keeps scrolling lists cheap (e.g. the feed cards use blur: 0).
class _MaybeBlur extends StatelessWidget {
  const _MaybeBlur({required this.blur, required this.child});
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (blur <= 0) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// A reusable frosted-glass surface: backdrop blur + translucent fill + border.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 18,
    this.padding,
    this.color,
    this.borderColor,
    this.strong = false,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final fill =
        color ?? (strong ? AppPalette.glassFillStrong : AppPalette.glassFill);
    Widget content = ClipRRect(
      borderRadius: radius,
      child: _MaybeBlur(
        blur: blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? AppPalette.glassBorder,
              width: 1,
            ),
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              // Subtle sheen layered over the fill (kept separate so [color]
              // isn't overridden by the gradient).
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      );
    }
    return content;
  }
}
