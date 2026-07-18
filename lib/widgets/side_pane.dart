import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// The Material 3 navigation drawer: a full-height surface that sits under
/// the screen and is revealed when the shell pushes the screen right
/// (old-Discord style). The shell owns its width.
class SidePane extends StatelessWidget {
  const SidePane({
    super.key,
    required this.currentIndex,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.onOpenArchive,
    required this.onOpenTrash,
    required this.onOpenSpace,
    required this.onClose,
  });

  final int currentIndex;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenTrash;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<AppState>().spaces;

    // A full-height M3 navigation drawer: solid container surface, rounded
    // trailing edge, destination pills. No float, no shadow, no blur.
    return Material(
      color: AppPalette.paneFill,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 12),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset('assets/logo.png',
                        width: 40, height: 40, fit: BoxFit.cover,
                        cacheWidth: 120),
                  ),
                  const SizedBox(width: 12),
                  Text(context.t.appTitle,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.inkPrimary)),
                ],
              ),
            ),
            _navItem(context, Icons.home_rounded, context.t.tabHome,
                currentIndex == 0,
                () => onSelectTab(0)),
            _navItem(context, Icons.style_rounded, context.t.tabCards,
                currentIndex == 1,
                () => onSelectTab(1)),
            _navItem(context, Icons.book_rounded, context.t.tabJournal,
                currentIndex == 2,
                () => onSelectTab(2)),
            _navItem(context, Icons.grid_view_rounded, context.t.tabCortex,
                currentIndex == 3,
                () => onSelectTab(3)),
            const SizedBox(height: 8),
            _divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Text(context.t.sectionYourCortex,
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary)),
            ),
            Expanded(
              child: spaces.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(context.t.noFoldersYet,
                          style:
                              TextStyle(color: AppPalette.inkSecondary)),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final s in spaces)
                          _navItem(context, Icons.folder_rounded, s.name,
                              false,
                              () => onOpenSpace(s.id)),
                      ],
                    ),
            ),
            _divider(),
            const SizedBox(height: 8),
            _navItem(context, Icons.archive_outlined,
                context.t.archiveTitle, false,
                onOpenArchive),
            _navItem(context, Icons.delete_outline_rounded,
                context.t.recentlyDeleted, false,
                onOpenTrash),
            _navItem(context, Icons.settings_rounded, context.t.settings,
                false,
                onOpenSettings),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        color: AppPalette.paneBorder,
        height: 1,
        indent: 16,
        endIndent: 16,
      );

  Widget _navItem(BuildContext context, IconData icon, String label,
      bool selected, VoidCallback onTap) {
    final scheme = AppPalette.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        // M3 drawer destination: full pill, secondary container when active.
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
