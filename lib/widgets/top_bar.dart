import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'frosted_chrome.dart';
import 'sort_button.dart';

/// The fixed top row: a separate sandwich-menu bubble on the left, a search
/// bar filling the middle, then the sort bubble on the right — each its own
/// frosted-glass island (a real BackdropFilter, like the nav island). The row
/// stays put; it doesn't hide on scroll.
class FloatingTopBar extends StatelessWidget {
  const FloatingTopBar({
    super.key,
    required this.onMenu,
    required this.onQueryChanged,
    required this.focusNode,
    required this.controller,
    required this.showSort,
    this.onRearrange,
  });

  final VoidCallback onMenu;
  final ValueChanged<String> onQueryChanged;
  final FocusNode focusNode;

  /// Owned by the shell so a back press can clear the search.
  final TextEditingController controller;

  /// The sort bubble only appears on the sortable feeds (notes/cards/cortex).
  final bool showSort;

  /// The journal's rearrange bubble (reorders its three sections). Sits where
  /// the sort bubble does; shown when non-null.
  final VoidCallback? onRearrange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          FrostedCircleButton(
            icon: Icons.menu_rounded,
            tooltip: context.t.menu,
            onTap: onMenu,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SearchField(
              focusNode: focusNode,
              controller: controller,
              onChanged: onQueryChanged,
            ),
          ),
          if (showSort) ...[
            const SizedBox(width: 10),
            FrostedCircleButton(
              icon: Icons.sort_rounded,
              tooltip: context.t.sortBy,
              onTap: () => showSortSheet(context),
            ),
          ],
          if (onRearrange != null) ...[
            const SizedBox(width: 10),
            FrostedCircleButton(
              icon: Icons.swap_vert_rounded,
              tooltip: context.t.rearrangeJournal,
              onTap: onRearrange!,
            ),
          ],
        ],
      ),
    );
  }
}

/// The frosted search field that fills the space between the menu and the
/// sort/account bubbles.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.focusNode,
    required this.controller,
    required this.onChanged,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  void _clear() {
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      borderRadius: 25,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.search_rounded,
                size: 20, color: AppPalette.inkSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style:
                    TextStyle(fontSize: 14.5, color: AppPalette.inkPrimary),
                cursorColor: AppPalette.inkPrimary,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.t.searchHint,
                  hintStyle: TextStyle(
                      fontSize: 14.5, color: AppPalette.inkSecondary),
                  border: InputBorder.none,
                ),
              ),
            ),
            // Follows the shared controller, so a back press that clears the
            // search takes the ✕ away with it.
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox(width: 8)
                  : IconButton(
                      tooltip: context.t.clearSearch,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: AppPalette.inkSecondary),
                      onPressed: _clear,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


