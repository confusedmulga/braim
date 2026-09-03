import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Picks a note to link to, or types a new title to create one. Returns the
/// chosen title (to be inserted as `[[title]]`), or null if dismissed.
Future<String?> showNoteLinkPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NoteLinkPicker(),
  );
}

class _NoteLinkPicker extends StatefulWidget {
  const _NoteLinkPicker();

  @override
  State<_NoteLinkPicker> createState() => _NoteLinkPickerState();
}

class _NoteLinkPickerState extends State<_NoteLinkPicker> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final q = _query.trim().toLowerCase();
    final targets = state
        .linkTargets()
        .where((n) => q.isEmpty || n.title.toLowerCase().contains(q))
        .take(40)
        .toList();
    final exactExists = q.isNotEmpty &&
        state.linkTargets().any((n) => n.title.trim().toLowerCase() == q);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 8,
      ),
      child: GlassPanel(
        borderRadius: 26,
        strong: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.linkToNote,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppPalette.inkPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    color: AppPalette.inkSecondary),
                hintText: context.t.searchOrCreateNote,
                filled: true,
                fillColor: AppPalette.bubbleGlass,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Offer to create a note titled exactly what was typed.
                  if (q.isNotEmpty && !exactExists)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.add_circle_outline_rounded,
                          color: AppPalette.scheme.primary),
                      title: Text(
                        context.t.createNoteNamed(_ctrl.text.trim()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppPalette.inkPrimary),
                      ),
                      onTap: () => Navigator.pop(context, _ctrl.text.trim()),
                    ),
                  for (final n in targets)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.description_outlined,
                          color: AppPalette.inkSecondary),
                      title: Text(
                        n.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppPalette.inkPrimary),
                      ),
                      onTap: () => Navigator.pop(context, n.title.trim()),
                    ),
                  if (targets.isEmpty && q.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          context.t.noNotesToLink,
                          style: TextStyle(color: AppPalette.inkSecondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
