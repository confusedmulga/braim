import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Shows a sheet to move a note or card into a space. Returns the chosen
/// space id, the sentinel `'__none__'` for no space, or null if dismissed.
Future<String?> showMoveToSpaceSheet(
  BuildContext context, {
  required String? currentSpaceId,
}) {
  final spaces = context.read<AppState>().spaces;
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
        borderRadius: 28,
        strong: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Move to cortex',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.inbox_rounded, color: AppPalette.textPrimary),
              title: const Text('No folder'),
              trailing: currentSpaceId == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, '__none__'),
            ),
            ListTile(
              leading: Icon(Icons.lock_rounded, color: AppPalette.textPrimary),
              title: const Text('Crypt'),
              subtitle: Text('Locked, secret',
                  style: TextStyle(color: AppPalette.textSecondary)),
              trailing: currentSpaceId == kCryptSpaceId
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, kCryptSpaceId),
            ),
            if (spaces.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No folders yet — create one in Cortex.',
                    style: TextStyle(color: AppPalette.textSecondary)),
              ),
            for (final s in spaces)
              ListTile(
                leading:
                    Icon(Icons.folder_rounded, color: AppPalette.textPrimary),
                title: Text(s.name),
                trailing: currentSpaceId == s.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, s.id),
              ),
          ],
        ),
      ),
    ),
  );
}
