import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class IslandNavItem {
  const IslandNavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The floating "island" tab bar that hovers above the content. The one piece
/// of chrome that keeps a real frosted blur — a single BackdropFilter clipped
/// tightly to the island's small pill, so the per-frame cost stays tiny
/// (unlike the stacked, screen-wide filters that were removed elsewhere).
class IslandNav extends StatelessWidget {
  const IslandNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    IslandNavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    IslandNavItem(Icons.style_outlined, Icons.style_rounded, 'Sparks'),
    IslandNavItem(
        Icons.menu_book_outlined, Icons.menu_book_rounded, 'Narrative'),
    IslandNavItem(Icons.book_outlined, Icons.book_rounded, 'Journal'),
    IslandNavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Cortex'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: AppPalette.whiteFill,
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _NavButton(
                      item: _items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final IslandNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: selected ? AppPalette.selFill : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          button: true,
          selected: selected,
          label: item.label,
          child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            // Tight enough that five tabs plus the expanded label still fit
            // beside the pencil bubble (the shell also scales the island
            // down on very narrow screens rather than overflowing).
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 12 : 9,
              vertical: 11,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 22,
                  color: selected
                      ? AppPalette.inkPrimary
                      : AppPalette.inkSecondary,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 7),
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.inkPrimary,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
