import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show HitTestResult, PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderEditable, RenderSemanticsGestureHandler, SemanticsAnnotationsMixin;
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
        child: _RightClickAsLongPress(
            child: DesktopFrame(child: child ?? const SizedBox.shrink())),
      ),
    );

/// Right-click does what a long-press does on the phone (select, the item
/// menu…), everywhere a long-press exists, without touching each widget: the
/// click hit-tests the pointer and runs the innermost long-press handler the
/// way accessibility would. Pressing and holding the mouse still long-presses
/// natively. Text fields keep right-click for their own menu.
class _RightClickAsLongPress extends StatelessWidget {
  const _RightClickAsLongPress({required this.child});

  final Widget child;

  static void _onDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse ||
        e.buttons != kSecondaryMouseButton) {
      return;
    }
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, e.position, e.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderEditable) return;
      final VoidCallback? longPress = switch (target) {
        RenderSemanticsGestureHandler(:final onLongPress) => onLongPress,
        SemanticsAnnotationsMixin(:final properties) => properties.onLongPress,
        _ => null,
      };
      if (longPress != null) {
        longPress();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        child: child,
      );
}

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
class _WebShortcuts extends StatefulWidget {
  const _WebShortcuts({required this.child});

  final Widget child;

  @override
  State<_WebShortcuts> createState() => _WebShortcutsState();
}

class _WebShortcutsState extends State<_WebShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onParkedKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onParkedKey);
    super.dispose();
  }

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

  /// Runs the shortcut for [event], if there is one. Returns whether it did.
  static bool _dispatch(KeyEvent event, {required bool typing}) {
    if (event is! KeyDownEvent) return false;
    final k = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final mod = hw.isControlPressed || hw.isMetaPressed;
    bool run(VoidCallback? f) {
      if (f == null) return false;
      f();
      return true;
    }

    if (k == LogicalKeyboardKey.escape && !hw.isShiftPressed) {
      navigatorKey.currentState?.maybePop();
      return true;
    }
    if (mod && !hw.isAltPressed) {
      if (k == LogicalKeyboardKey.keyK) return run(AppShortcuts.search);
      if (k == LogicalKeyboardKey.keyN) return run(AppShortcuts.newItem);
      if (k == LogicalKeyboardKey.enter) return run(AppShortcuts.done);
      return false;
    }
    if (typing || hw.isAltPressed) return false;
    if (k == LogicalKeyboardKey.slash) return run(AppShortcuts.search);
    final step = AppShortcuts.stepTab;
    if (step != null && k == LogicalKeyboardKey.arrowLeft) {
      step(-1);
      return true;
    }
    if (step != null && k == LogicalKeyboardKey.arrowRight) {
      step(1);
      return true;
    }
    return false;
  }

  /// When the page loses DOM focus (a text field closes, a click lands on the
  /// page margin) the framework parks focus at the root, above this widget,
  /// and key events stop reaching it. Handle them globally only then, so no
  /// key is ever acted on twice.
  bool _onParkedKey(KeyEvent event) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != FocusManager.instance.rootScope) {
      return false;
    }
    return _dispatch(event, typing: false);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) => _dispatch(event, typing: _typing())
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: widget.child,
    );
  }
}
