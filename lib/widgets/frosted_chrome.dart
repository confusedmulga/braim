import 'dart:ui';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// A rounded frosted-glass surface: one clipped BackdropFilter over a
/// translucent tinted fill — the nav-island recipe. Shared by the floating top
/// bar and every screen's back button so all the app's chrome reads identically.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: AppPalette.whiteFill,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: AppPalette.cardOutline),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The 50px frosted chrome circle holding one icon (or a custom [child]) — the
/// menu, back and action bubbles across the app's top bars.
class FrostedCircleButton extends StatelessWidget {
  const FrostedCircleButton({
    super.key,
    this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.child,
    this.iconSize = 22,
  });

  /// Every top-bar chrome bubble is this wide, so back / menu / actions line up.
  static const double size = 50.0;

  final IconData? icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Optional press-and-hold action (e.g. the fold search bubble opens the sort
  /// options on a long-press).
  final VoidCallback? onLongPress;
  final Widget? child;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      borderRadius: size / 2,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: SizedBox(
              width: size,
              height: size,
              child: child ??
                  Icon(icon, size: iconSize, color: AppPalette.inkPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's one back button: a frosted circle with a back arrow that pops the
/// route. Sits in the exact spot the Home menu bubble occupies, on every screen.
class FrostedBackButton extends StatelessWidget {
  const FrostedBackButton({super.key, this.onTap, this.tooltip});

  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return FrostedCircleButton(
      icon: Icons.arrow_back_rounded,
      tooltip: tooltip ?? context.t.back,
      onTap: onTap ?? () => Navigator.maybePop(context),
    );
  }
}

/// A screen scaffold with the standard pinned frosted chrome: a back button at
/// the exact position of the Home menu bubble (top-left, in the safe area), an
/// optional centred [title], and optional [actions] on the right. The chrome
/// never scrolls. By default the [body] is inset below the chrome; pass
/// [bodyUnderChrome] to let a scroll view slide under it (as the book view does).
class FrostedScaffold extends StatelessWidget {
  const FrostedScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions = const [],
    this.onBack,
    this.backTooltip,
    this.floatingActionButton,
    this.background = true,
    this.bodyUnderChrome = false,
  });

  final Widget body;
  final String? title;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Widget? floatingActionButton;

  /// Paint the app's ambient background behind the scaffold.
  final bool background;

  /// When true the body fills the screen and scrolls under the pinned chrome;
  /// otherwise it's inset so its content starts just below the chrome.
  final bool bodyUnderChrome;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // Safe area + 8px lead + the 50px bubble + 8px trailing gap.
    final chromeHeight = topInset + 16 + FrostedCircleButton.size;

    final actionRow = actions.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                actions[i],
              ],
            ],
          );

    final content = Stack(
      children: [
        Positioned.fill(
          child: bodyUnderChrome
              ? body
              : Padding(
                  padding: EdgeInsets.only(top: chromeHeight),
                  child: body,
                ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: SizedBox(
                height: FrostedCircleButton.size,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FrostedBackButton(
                          onTap: onBack, tooltip: backTooltip),
                    ),
                    if (title != null)
                      Padding(
                        // Keep the title clear of the left/right chrome.
                        padding: const EdgeInsets.symmetric(horizontal: 64),
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.inkPrimary,
                            ),
                          ),
                        ),
                      ),
                    if (actionRow != null)
                      Align(alignment: Alignment.centerRight, child: actionRow),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: background ? Colors.transparent : null,
      floatingActionButton: floatingActionButton,
      body: content,
    );
    return background ? AppBackground(child: scaffold) : scaffold;
  }
}
