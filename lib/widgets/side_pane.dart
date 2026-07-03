import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// The frosted side navigation pane. It blurs the live screen behind it.
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
    final width = MediaQuery.of(context).size.width * 0.74;

    // A floating liquid-glass panel (iPadOS-sidebar style): inset from the
    // edges, rounded, frosted-white glass with the app visible behind it.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 0, 12),
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 34,
                  offset: const Offset(6, 12),
                ),
              ],
            ),
            child: GlassPanel(
              borderRadius: 30,
              blur: 26,
              color: const Color(0xCCFFFFFF),
              borderColor: Colors.white.withValues(alpha: 0.55),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset('assets/logo.png',
                            width: 40, height: 40, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Braim',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.inkPrimary)),
                  ],
                ),
              ),
              _navItem(Icons.home_rounded, 'Home', currentIndex == 0,
                  () => onSelectTab(0)),
              _navItem(Icons.style_rounded, 'Cards', currentIndex == 1,
                  () => onSelectTab(1)),
              _navItem(Icons.grid_view_rounded, 'Cortex', currentIndex == 2,
                  () => onSelectTab(2)),
              const SizedBox(height: 8),
              _divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Text('YOUR CORTEX',
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
                        child: Text('No folders yet',
                            style:
                                TextStyle(color: AppPalette.inkSecondary)),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final s in spaces)
                            _navItem(Icons.folder_rounded, s.name, false,
                                () => onOpenSpace(s.id)),
                        ],
                      ),
              ),
              _divider(),
              _navItem(Icons.archive_outlined, 'Archive', false,
                  onOpenArchive),
              _navItem(Icons.delete_outline_rounded, 'Recently deleted', false,
                  onOpenTrash),
              _navItem(Icons.settings_rounded, 'Settings', false,
                  onOpenSettings),
              const SizedBox(height: 12),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        color: Colors.black.withValues(alpha: 0.08),
        height: 1,
        indent: 16,
        endIndent: 16,
      );

  Widget _navItem(
      IconData icon, String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? Colors.black.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
                    color: selected
                        ? AppPalette.inkPrimary
                        : AppPalette.inkSecondary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppPalette.inkPrimary
                          : AppPalette.inkPrimary.withValues(alpha: 0.8),
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
