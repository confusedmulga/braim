import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../screens/spaces_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'move_to_space_sheet.dart';
import 'quick_actions_menu.dart';

/// Long-press actions for a feed note/card: pin, archive, move to cortex,
/// create a new folder and file the item into it, or move it to the trash.
///
/// Handles everything internally; shows snackbars for pin-limit and results.
Future<void> showItemActions(
  BuildContext context, {
  required bool pinned,
  required bool archived,
  required String? currentSpaceId,
  required Future<bool> Function(bool pinned) onSetPinned,
  required Future<void> Function(bool archived) onSetArchived,
  required Future<void> Function(String? spaceId) onMove,
  required Future<void> Function() onDelete,
  bool allowCrypt = true,
}) async {
  final t = context.t;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _ActionsSheet(pinned: pinned, archived: archived),
  );
  if (action == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case 'pin':
      final ok = await onSetPinned(!pinned);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text(t.pinLimitReached(kMaxPins))),
        );
      }
    case 'archive':
      await onSetArchived(!archived);
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(archived ? t.unarchived : t.archived)),
      );
    case 'move':
      final selected = await showMoveToSpaceSheet(context,
          currentSpaceId: currentSpaceId, allowCrypt: allowCrypt);
      if (selected == null) return;
      await onMove(selected == '__none__' ? null : selected);
    case 'newfolder':
      final result = await showSpaceEditor(context);
      if (result == null || !context.mounted) return;
      final space = await context
          .read<AppState>()
          .addSpace(result.name, thumbnailPath: result.thumbnailPath);
      await onMove(space.id);
      messenger.showSnackBar(
        SnackBar(content: Text(t.movedToName(space.name))),
      );
    case 'delete':
      if (!context.mounted) return;
      final sure = await confirmDeleteItems(context, 1);
      if (!sure) return;
      await onDelete();
      messenger.showSnackBar(
        SnackBar(content: Text(t.movedToTrash)),
      );
  }
}

class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.pinned, required this.archived});
  final bool pinned;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassEdge(
          borderRadius: 26,
          fill: AppPalette.whiteFill,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  color: AppPalette.inkPrimary,
                ),
                title: Text(pinned ? context.t.unpin : context.t.pin,
                    style: TextStyle(color: AppPalette.inkPrimary)),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
              ListTile(
                leading: Icon(
                  archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  color: AppPalette.inkPrimary,
                ),
                title: Text(
                    archived ? context.t.unarchive : context.t.archive,
                    style: TextStyle(color: AppPalette.inkPrimary)),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
              ListTile(
                leading: Icon(Icons.drive_file_move_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.moveToCortex,
                    style: TextStyle(color: AppPalette.inkPrimary)),
                onTap: () => Navigator.pop(context, 'move'),
              ),
              ListTile(
                leading: Icon(Icons.create_new_folder_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.newFolder,
                    style: TextStyle(color: AppPalette.inkPrimary)),
                subtitle: Text(context.t.newFolderSubtitle,
                    style: TextStyle(
                        color: AppPalette.inkSecondary, fontSize: 12.5)),
                onTap: () => Navigator.pop(context, 'newfolder'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFE5557A)),
                title: Text(context.t.delete,
                    style: TextStyle(color: Color(0xFFE5557A))),
                subtitle: Text(context.t.deleteKeptSubtitle,
                    style: TextStyle(
                        color: AppPalette.inkSecondary, fontSize: 12.5)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
