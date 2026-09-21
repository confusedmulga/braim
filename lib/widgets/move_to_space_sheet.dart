import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Shows a sheet to move a note or card into a space. Returns the chosen
/// space id, the sentinel `'__none__'` for no space, or null if dismissed.
///
/// Pass [allowCrypt] false to hide the Crypt row — used when moving a circuit
/// note, which can never be filed into the Crypt (section 6.8).
Future<String?> showMoveToSpaceSheet(
  BuildContext context, {
  required String? currentSpaceId,
  bool allowCrypt = true,
}) {
  final spaces = context.read<AppState>().spaces;
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
        borderRadius: 28,
        strong: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        // Cap the sheet at 70% of the screen so a long folder list scrolls
        // instead of overflowing off-screen.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
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
                  child: Text(context.t.moveToCortex,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary)),
                ),
              ),
              // The scrollable list: fixed header above, folders scroll here.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom),
                  children: [
                    ListTile(
                      leading: Icon(Icons.inbox_rounded,
                          color: AppPalette.textPrimary),
                      title: Text(context.t.noFolder),
                      trailing: currentSpaceId == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, '__none__'),
                    ),
                    if (allowCrypt)
                      ListTile(
                        leading: Icon(Icons.lock_rounded,
                            color: AppPalette.textPrimary),
                        title: Text(context.t.crypt),
                        subtitle: Text(context.t.cryptLockedSecret,
                            style: TextStyle(color: AppPalette.textSecondary)),
                        trailing: currentSpaceId == kCryptSpaceId
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, kCryptSpaceId),
                      ),
                    if (spaces.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(context.t.noFoldersYetCreate,
                            style:
                                TextStyle(color: AppPalette.textSecondary)),
                      ),
                    for (final s in spaces)
                      ListTile(
                        leading: Icon(Icons.folder_rounded,
                            color: AppPalette.textPrimary),
                        title: Text(s.name),
                        trailing: currentSpaceId == s.id
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, s.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
