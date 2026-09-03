import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Opens the feed-sort chooser sheet (used by the top bar's sort bubble).
void showSortSheet(BuildContext context) {
  final current = context.read<AppState>().sortMode;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SortSheet(current: current),
  );
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});
  final NoteSort current;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final items = <(NoteSort, String, IconData)>[
      (NoteSort.recent, t.sortRecent, Icons.schedule_rounded),
      (NoteSort.oldest, t.sortOldest, Icons.history_rounded),
      (NoteSort.azTitle, t.sortAz, Icons.sort_by_alpha_rounded),
      (NoteSort.zaTitle, t.sortZa, Icons.sort_by_alpha_rounded),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassEdge(
          borderRadius: 28,
          fill: AppPalette.whiteFill,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.sortBy,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppPalette.inkPrimary)),
                ),
              ),
              for (final (mode, label, icon) in items)
                ListTile(
                  leading: Icon(icon, color: AppPalette.inkSecondary),
                  title: Text(label,
                      style: TextStyle(color: AppPalette.inkPrimary)),
                  trailing: mode == current
                      ? Icon(Icons.check_rounded,
                          color: AppPalette.inkPrimary)
                      : null,
                  onTap: () {
                    context.read<AppState>().setSortMode(mode);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
