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
              _TagFilterRow(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A "Filter by tag" row inside the sort sheet: a dropdown listing every tag in
/// the library (plus "All tags" to clear it). Hidden when there are no tags.
class _TagFilterRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final state = context.watch<AppState>();
    final tags = state.allTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 12),
      child: Row(
        children: [
          Icon(Icons.label_outline_rounded, color: AppPalette.inkSecondary),
          const SizedBox(width: 12),
          Text(t.filterByTag,
              style: TextStyle(color: AppPalette.inkPrimary, fontSize: 15)),
          const Spacer(),
          DropdownButton<String?>(
            value: state.activeTag,
            underline: const SizedBox.shrink(),
            dropdownColor: AppPalette.sheet,
            borderRadius: BorderRadius.circular(12),
            // A dropdown's explicit style with no family falls back to the
            // platform sans; name the app font so it reads like the rest.
            style: TextStyle(
                fontFamily: kNoteHeadingFont,
                color: AppPalette.inkPrimary,
                fontSize: 15),
            items: [
              DropdownMenuItem<String?>(
                  value: null, child: Text(t.tagAll)),
              for (final tag in tags)
                DropdownMenuItem<String?>(value: tag, child: Text('#$tag')),
            ],
            onChanged: (v) {
              context.read<AppState>().setActiveTag(v);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
