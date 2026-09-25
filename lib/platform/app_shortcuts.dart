import 'package:flutter/widgets.dart';

/// Keyboard-shortcut targets registered by whichever screen can act on them
/// (the main shell, an open editor). The browser's shortcut layer calls these;
/// on the phone nothing ever does.
class AppShortcuts {
  AppShortcuts._();

  /// Focus the universal search.
  static VoidCallback? search;

  /// The current tab's "new" action (the + / pencil button).
  static VoidCallback? newItem;

  /// Step to the previous / next main tab.
  static void Function(int delta)? stepTab;

  /// "Done" in an editor (commit and leave edit mode).
  static VoidCallback? done;

  /// Clears [done] only if it's still [owner]'s (a newer editor may have
  /// replaced it).
  static void releaseDone(VoidCallback owner) {
    if (identical(done, owner)) done = null;
  }
}
