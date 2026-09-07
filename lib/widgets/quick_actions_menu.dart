import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The quick actions offered when a note/card is long-pressed.
enum QuickAction { move, select, pin, theme, archive, delete }

/// A frosted, rounded list of the quick actions, shown on long-press. [pinned]
/// picks the Pin vs Unpin label. Returns the chosen action, or null if dismissed.
Future<QuickAction?> showQuickActions(BuildContext context,
    {bool pinned = false}) {
  return showModalBottomSheet<QuickAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.scheme.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppPalette.cardOutline),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row(context, Icons.drive_file_move_outline,
                      context.t.moveToFolder, QuickAction.move),
                  _row(context, Icons.check_circle_outline_rounded,
                      context.t.select, QuickAction.select),
                  _row(
                      context,
                      pinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      pinned ? context.t.unpinFromFeed : context.t.pinToFeed,
                      QuickAction.pin),
                  _row(context, Icons.palette_outlined, context.t.chooseTheme,
                      QuickAction.theme),
                  _row(context, Icons.archive_outlined, context.t.archive,
                      QuickAction.archive),
                  _row(context, Icons.delete_outline_rounded, context.t.delete,
                      QuickAction.delete,
                      danger: true),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _row(BuildContext context, IconData icon, String label,
    QuickAction action,
    {bool danger = false}) {
  final color = danger ? const Color(0xFFE0567B) : AppPalette.inkPrimary;
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    onTap: () => Navigator.pop(context, action),
  );
}

/// Confirms before deleting note(s)/card(s). They go to Recently deleted, so
/// this is a soft delete — but it's easy to hit by accident, hence the check.
Future<bool> confirmDeleteItems(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t.deleteTitle),
      content: Text(context.t.deleteItemsConfirm(count)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0567B)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.t.delete),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The frosted, rounded action bar shown above the nav island while
/// multi-selecting. [onClose] (the ✕ at the far right) leaves the mode.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onMove,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    required this.onClose,
  });

  final int count;
  final VoidCallback onMove;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppPalette.scheme.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppPalette.cardOutline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Text(
                '$count',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppPalette.inkPrimary),
              ),
              const Spacer(),
              _act(Icons.drive_file_move_outline, onMove, AppPalette.inkPrimary),
              _act(Icons.push_pin_outlined, onPin, AppPalette.inkPrimary),
              _act(Icons.archive_outlined, onArchive, AppPalette.inkPrimary),
              _act(Icons.delete_outline_rounded, onDelete,
                  const Color(0xFFE0567B)),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: AppPalette.cardOutline,
              ),
              _act(Icons.close_rounded, onClose, AppPalette.inkPrimary),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _act(IconData icon, VoidCallback onTap, Color color) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: color),
        onPressed: onTap,
      );
}
