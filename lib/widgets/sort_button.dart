import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';
import 'glass_bubble.dart';

/// A compact glass button that sits to the right of the search bar and opens a
/// sheet to choose the feed sort order. Only its own subtree rebuilds when the
/// sort changes (via [Selector]), so the shell isn't rebuilt wholesale.
class SortButton extends StatelessWidget {
  const SortButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, NoteSort>(
      selector: (_, s) => s.sortMode,
      builder: (context, mode, _) => GlassBubble(
        icon: Icons.sort_rounded,
        tooltip: context.t.sortBy,
        size: 46,
        iconSize: 22,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _SortSheet(current: mode),
        ),
      ),
    );
  }
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
