import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show navigatorKey;
import '../platform/app_shortcuts.dart';
import '../widgets/glass.dart';

/// The app on a PC screen: the phone layout, pixel for pixel, in a centred
/// phone-width column, with the feed wallpaper blurred behind it; plus the
/// keyboard shortcuts a desktop user expects.
Widget webFrame(BuildContext context, Widget? child) => FocusTraversalGroup(
      policy: _LaidOutReadingOrderPolicy(),
      child: _WebShortcuts(
          child: DesktopFrame(child: child ?? const SizedBox.shrink())),
    );

/// Reading-order traversal that skips focus nodes not laid out yet. When the
/// browser hands focus back to the page (after a file dialog, or tabbing in
/// from the address bar) the framework sorts every focus node by position to
/// pick one; a node whose box hasn't been laid out (a page kept alive off
/// screen, a route still building) threw there and left nothing focused.
class _LaidOutReadingOrderPolicy extends ReadingOrderTraversalPolicy {
  static bool _laidOut(FocusNode node) {
    final box = node.context?.findRenderObject();
    return box is! RenderBox || box.hasSize;
  }

  @override
  Iterable<FocusNode> sortDescendants(
          Iterable<FocusNode> descendants, FocusNode currentNode) =>
      super.sortDescendants(descendants.where(_laidOut), currentNode);
}

class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key, required this.child});

  final Widget child;

  /// The widest the app column gets: a large phone.
  static const double maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = math.min(maxWidth, mq.size.width);
    // A narrow window (or a phone browser) gets the app edge to edge.
    if (mq.size.width <= maxWidth + 1) return child;
    final column = MediaQuery(
      // Every screen reads MediaQuery for its size; they must see a phone.
      data: mq.copyWith(
        size: Size(width, mq.size.height),
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
      ),
      child: child,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // The feed wallpaper, blurred and dimmed, fills the rest of the window.
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: const AppBackground(wallpaper: true),
        ),
        const ColoredBox(color: Color(0x33000000)),
        Center(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SizedBox(
              width: width,
              height: mq.size.height,
              child: ClipRect(child: column),
            ),
          ),
        ),
      ],
    );
  }
}

/// Esc = back, Ctrl/Cmd+K or / = search, Ctrl/Cmd+N = new, Ctrl/Cmd+Enter =
/// done in an editor, ←/→ = previous/next tab (when not typing).
class _WebShortcuts extends StatelessWidget {
  const _WebShortcuts({required this.child});

  final Widget child;

  /// Whether the keyboard is feeding a text field right now (then plain keys
  /// like / and the arrows belong to it).
  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    var typing = ctx is StatefulElement && ctx.state is TextInputClient;
    if (typing) return true;
    ctx.visitAncestorElements((e) {
      if (e is StatefulElement && e.state is TextInputClient) {
        typing = true;
        return false;
      }
      return true;
    });
    return typing;
  }

  static void _call(VoidCallback? f) => f?.call();

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            navigatorKey.currentState?.maybePop(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _call(AppShortcuts.search),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _call(AppShortcuts.search),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _call(AppShortcuts.newItem),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            _call(AppShortcuts.newItem),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _call(AppShortcuts.done),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            _call(AppShortcuts.done),
      },
      child: Focus(
        // Plain keys only when no text field has the keyboard.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || _typing()) {
            return KeyEventResult.ignored;
          }
          final k = event.logicalKey;
          if (k == LogicalKeyboardKey.slash && AppShortcuts.search != null) {
            AppShortcuts.search!();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowLeft &&
              AppShortcuts.stepTab != null) {
            AppShortcuts.stepTab!(-1);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.arrowRight &&
              AppShortcuts.stepTab != null) {
            AppShortcuts.stepTab!(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}
