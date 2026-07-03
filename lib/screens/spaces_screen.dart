import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/space.dart';
import '../services/crypt_auth.dart';
import '../services/image_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/space_tile.dart';
import 'space_detail_screen.dart';

class SpacesScreen extends StatefulWidget {
  const SpacesScreen({super.key});

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
    final ok = await authenticateForCrypt();
    if (!mounted) return;
    if (ok) {
      nav.push(MaterialPageRoute(
          builder: (_) => const SpaceDetailScreen(spaceId: kCryptSpaceId)));
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unlock failed')),
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
        await context.read<AppState>().updateSpace(space);
      }
    } else if (action == 'delete' && mounted) {
      await context.read<AppState>().deleteSpace(space.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spaces = state.spaces;
    final tileCount = spaces.length + 1; // +1 for the Crypt tile

    return CustomScrollView(
      slivers: [
        SliverPadding(
          // Top padding clears the header fade band (see home_screen).
          padding: const EdgeInsets.fromLTRB(18, 40, 18, 150),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (i == 0) {
                  return _CryptTile(
                    itemCount: state.itemCountForSpace(kCryptSpaceId),
                    onTap: _openCrypt,
                  );
                }
                final s = spaces[i - 1];
                return SpaceTile(
                  space: s,
                  itemCount: state.itemCountForSpace(s.id),
                  onTap: () => _open(s),
                  onLongPress: () => _edit(s),
                );
              },
              childCount: tileCount,
            ),
          ),
        ),
      ],
    );
  }
}

/// The locked, secret Crypt tile shown at the front of the Cortex grid.
class _CryptTile extends StatelessWidget {
  const _CryptTile({required this.itemCount, required this.onTap});
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Colors.white, size: 20),
                ),
                const Spacer(),
                const Text('Crypt',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(itemCount == 1 ? '1 item' : '$itemCount items',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceEditorResult {
  SpaceEditorResult(this.name, this.thumbnailPath);
  final String name;
  final String? thumbnailPath;
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickThumb() async {
    final path = await ImageService.pickThumbnail();
    if (path != null) setState(() => _thumb = path);
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
              widget.existing == null ? 'New space' : 'Edit space',
              style: const TextStyle(
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
                            Text('Add thumbnail',
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
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Space name',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _ctrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(context, SpaceEditorResult(name, _thumb));
                  },
                  child: const Text('Save'),
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
                title: Text('Edit "${space.name}"'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF8A9B)),
                title: const Text('Delete folder'),
                subtitle: Text('Notes & cards inside move to no cortex',
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

