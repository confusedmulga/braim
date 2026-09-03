import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// The Material 3 navigation drawer: a full-height surface that sits under
/// the screen and is revealed when the shell pushes the screen right
/// (old-Discord style). The shell owns its width.
class SidePane extends StatefulWidget {
  const SidePane({
    super.key,
    required this.currentIndex,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.onOpenArchive,
    required this.onOpenTrash,
    required this.onOpenSpace,
    required this.onOpenJournalYear,
    required this.onOpenReflexes,
    required this.onOpenPomodoro,
    required this.onClose,
  });

  final int currentIndex;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenTrash;
  final ValueChanged<String> onOpenSpace;
  final VoidCallback onOpenJournalYear;
  final VoidCallback onOpenReflexes;
  final VoidCallback onOpenPomodoro;
  final VoidCallback onClose;

  @override
  State<SidePane> createState() => _SidePaneState();
}

class _SidePaneState extends State<SidePane> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spaces = state.spaces;
    final journalOpen = state.journalPaneOpen;
    final cortexOpen = state.cortexPaneOpen;

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
            // Nav lives in a scrollable list so the expandable Journal/Cortex
            // shortcuts (and a long fold list) can grow and scroll.
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _navItem(context, Icons.home_rounded, context.t.tabHome,
                      widget.currentIndex == 0,
                      () => widget.onSelectTab(0)),
                  _navItem(context, Icons.style_rounded, context.t.tabCards,
                      widget.currentIndex == 1,
                      () => widget.onSelectTab(1)),
                  _navItem(context, Icons.menu_book_rounded,
                      context.t.tabNarrative, widget.currentIndex == 2,
                      () => widget.onSelectTab(2)),
                  // Journal, with an expand arrow that reveals quick shortcuts.
                  _navItem(
                    context,
                    Icons.book_rounded,
                    context.t.tabJournal,
                    widget.currentIndex == 3,
                    () => widget.onSelectTab(3),
                    trailing: _expandArrow(journalOpen,
                        () => state.setJournalPaneOpen(!journalOpen)),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: journalOpen
                        ? Column(
                            children: [
                              _subItem(context, Icons.calendar_month_rounded,
                                  context.t.navEntries,
                                  widget.onOpenJournalYear),
                              _subItem(context, Icons.bolt_rounded,
                                  context.t.reflexes, widget.onOpenReflexes),
                              _subItem(context, Icons.timer_outlined,
                                  context.t.pomodoro, widget.onOpenPomodoro),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  // Cortex, with the same expand arrow — its folds nest inside.
                  _navItem(
                    context,
                    Icons.grid_view_rounded,
                    context.t.tabCortex,
                    widget.currentIndex == 4,
                    () => widget.onSelectTab(4),
                    trailing: _expandArrow(cortexOpen,
                        () => state.setCortexPaneOpen(!cortexOpen)),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: cortexOpen
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (spaces.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      48, 6, 22, 8),
                                  child: Text(context.t.noFoldersYet,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppPalette.inkSecondary)),
                                )
                              else
                                for (final s in spaces)
                                  _subItem(context, Icons.folder_rounded,
                                      s.name,
                                      () => widget.onOpenSpace(s.id)),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
            _divider(),
            const SizedBox(height: 8),
            _navItem(context, Icons.archive_outlined,
                context.t.archiveTitle, false,
                widget.onOpenArchive),
            _navItem(context, Icons.delete_outline_rounded,
                context.t.recentlyDeleted, false,
                widget.onOpenTrash),
            _navItem(context, Icons.settings_rounded, context.t.settings,
                false,
                widget.onOpenSettings),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _expandArrow(bool open, VoidCallback onToggle) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedRotation(
          turns: open ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.keyboard_arrow_down_rounded,
              size: 22, color: AppPalette.scheme.onSurfaceVariant),
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
      bool selected, VoidCallback onTap,
      {Widget? trailing}) {
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
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// An indented shortcut under an expanded destination.
  Widget _subItem(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
    final scheme = AppPalette.scheme;
    return Padding(
      padding: const EdgeInsets.only(left: 34, right: 12, top: 1, bottom: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 19, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
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
