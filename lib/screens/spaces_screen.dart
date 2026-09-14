import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/space.dart';
import '../services/crypt_auth.dart';
import '../services/image_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_greeting.dart';
import '../widgets/glass.dart';
import '../widgets/space_tile.dart';
import 'space_detail_screen.dart';

class SpacesScreen extends StatefulWidget {
  const SpacesScreen({super.key, this.controller});

  /// Owned by the shell so it can scroll this feed back to the top.
  final ScrollController? controller;

  @override
  State<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends State<SpacesScreen> {
  void _open(Space space) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SpaceDetailScreen(spaceId: space.id)),
    );
  }

  Future<void> _openCrypt() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await authenticateForCrypt(reason: context.t.unlockCrypt);
    if (!mounted) return;
    if (ok) {
      nav.push(MaterialPageRoute(
          builder: (_) => const SpaceDetailScreen(spaceId: kCryptSpaceId)));
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(context.t.unlockFailed)),
      );
    }
  }

  Future<void> _edit(Space space) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpaceActionsSheet(space: space),
    );
    if (action == 'edit' && mounted) {
      final result = await showSpaceEditor(context, existing: space);
      if (result != null && mounted) {
        space.name = result.name;
        space.thumbnailPath = result.thumbnailPath;
        space.colorValue = result.colorValue;
        await context.read<AppState>().updateSpace(space);
      }
    } else if (action == 'toggleFeed' && mounted) {
      space.hiddenFromFeed = !space.hiddenFromFeed;
      await context.read<AppState>().updateSpace(space);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(space.hiddenFromFeed
                ? context.t.hideFromFeed
                : context.t.showInFeed)));
      }
    } else if (action == 'archive' && mounted) {
      await context.read<AppState>().setSpaceArchived(space.id, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.folderArchived)),
        );
      }
    } else if (action == 'delete' && mounted) {
      await context.read<AppState>().deleteSpace(space.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.movedToTrash)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spaces = state.spaces;
    final tileCount = spaces.length + 1; // +1 for the Crypt tile

    return CustomScrollView(
      controller: widget.controller,
      slivers: [
        const SliverToBoxAdapter(
          child: FeedGreeting(text: kCortexGreeting),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 150),
          // Lazy masonry: square thumbnail tiles and half-height plain tiles
          // pack into whichever column is shorter.
          sliver: SliverMasonryGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childCount: tileCount,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _CryptTile(
                  key: const ValueKey('__crypt_tile__'),
                  itemCount: state.itemCountForSpace(kCryptSpaceId),
                  onTap: _openCrypt,
                );
              }
              final s = spaces[i - 1];
              return SpaceTile(
                key: ValueKey(s.id),
                space: s,
                itemCount: state.itemCountForSpace(s.id),
                onTap: () => _open(s),
                onLongPress: () => _edit(s),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The locked, secret Crypt tile: a compact half-height dark tile.
class _CryptTile extends StatelessWidget {
  const _CryptTile({super.key, required this.itemCount, required this.onTap});
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2340), Color(0xFF44356B)],
            ),
          ),
          child: AspectRatio(
            aspectRatio: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t.crypt,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(context.t.itemsCount(itemCount),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
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

class SpaceEditorResult {
  SpaceEditorResult(this.name, this.thumbnailPath, this.colorValue);
  final String name;
  final String? thumbnailPath;
  final int? colorValue;
}

Future<SpaceEditorResult?> showSpaceEditor(
  BuildContext context, {
  Space? existing,
}) {
  return showDialog<SpaceEditorResult>(
    context: context,
    builder: (_) => _SpaceEditorDialog(existing: existing),
  );
}

class _SpaceEditorDialog extends StatefulWidget {
  const _SpaceEditorDialog({this.existing});
  final Space? existing;

  @override
  State<_SpaceEditorDialog> createState() => _SpaceEditorDialogState();
}

class _SpaceEditorDialogState extends State<_SpaceEditorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late String? _thumb = widget.existing?.thumbnailPath;
  late int? _color = widget.existing?.colorValue;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickThumb() async {
    final path = await ImageService.pickThumbnail();
    if (path != null) setState(() => _thumb = path);
  }

  Widget _colorChoice(int? c) {
    final selected = _color == c;
    final fill = c == null ? null : Color(c);
    return GestureDetector(
      onTap: () => setState(() => _color = c),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill ?? Colors.transparent,
          border: Border.all(
            color: selected ? AppPalette.textPrimary : Colors.black26,
            width: selected ? 2.5 : 1.2,
          ),
        ),
        child: c == null
            ? Icon(Icons.format_color_reset_rounded,
                size: 15, color: AppPalette.textSecondary)
            : (selected
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.black54)
                : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: GlassPanel(
        borderRadius: 24,
        strong: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? context.t.newSpace
                  : context.t.editSpace,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickThumb,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.white.withValues(alpha: 0.08),
                  child: _thumb != null
                      ? Image.file(File(_thumb!),
                          fit: BoxFit.cover, cacheWidth: 720)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: AppPalette.textSecondary, size: 28),
                            const SizedBox(height: 6),
                            Text(context.t.addThumbnail,
                                style: TextStyle(
                                    color: AppPalette.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                hintText: context.t.spaceName,
                hintStyle: TextStyle(color: AppPalette.textSecondary),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(context.t.folderColor,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _colorChoice(null),
                for (final c in NoteColors.swatches) _colorChoice(c),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _ctrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(
                        context, SpaceEditorResult(name, _thumb, _color));
                  },
                  child: Text(context.t.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceActionsSheet extends StatelessWidget {
  const _SpaceActionsSheet({required this.space});
  final Space space;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    Icon(Icons.edit_rounded, color: AppPalette.textPrimary),
                title: Text(context.t.editNamed(space.name)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(
                    space.hiddenFromFeed
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(space.hiddenFromFeed
                    ? context.t.showInFeed
                    : context.t.hideFromFeed),
                subtitle: Text(context.t.hideFromFeedSubtitle,
                    style: TextStyle(color: AppPalette.textSecondary)),
                onTap: () => Navigator.pop(context, 'toggleFeed'),
              ),
              ListTile(
                leading: Icon(Icons.archive_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.archiveFolder),
                subtitle: Text(context.t.archiveFolderSubtitle,
                    style: TextStyle(color: AppPalette.textSecondary)),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF8A9B)),
                title: Text(context.t.deleteFolder),
                subtitle: Text(context.t.deleteKeptSubtitle,
                    style: TextStyle(color: AppPalette.textSecondary)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

