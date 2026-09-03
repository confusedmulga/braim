import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../theme/app_theme.dart';
import 'text_prompt.dart';

/// A compact tag strip under a note: chips for each `#tag`, plus an add button.
/// Editing mutates [note.tags] in place and calls [onChanged] so the editor can
/// autosave. In [readOnly] mode it just shows the chips (no add / remove).
class NoteTagsEditor extends StatefulWidget {
  const NoteTagsEditor({
    super.key,
    required this.note,
    required this.onChanged,
    this.readOnly = false,
  });

  final Note note;
  final VoidCallback onChanged;
  final bool readOnly;

  @override
  State<NoteTagsEditor> createState() => _NoteTagsEditorState();
}

class _NoteTagsEditorState extends State<NoteTagsEditor> {
  List<String> get _tags => widget.note.tags;

  void _remove(String tag) {
    setState(() => _tags.remove(tag));
    widget.onChanged();
  }

  Future<void> _add() async {
    final raw = await promptForText(
      context,
      title: context.t.addTag,
      hint: context.t.tagHint,
      confirmLabel: context.t.add,
      capitalization: TextCapitalization.none,
      prefixText: '#',
    );
    if (raw == null) return;
    // Accept several at once, separated by spaces or commas; strip any '#'.
    final added = raw
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.replaceAll('#', '').trim().toLowerCase())
        .where((t) => t.isNotEmpty && !_tags.contains(t));
    if (added.isEmpty) return;
    setState(() => _tags.addAll(added));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly && _tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in _tags) _chip(tag),
        if (!widget.readOnly)
          ActionChip(
            avatar: Icon(Icons.add_rounded,
                size: 16, color: AppPalette.inkSecondary),
            label: Text(context.t.tagLabel),
            labelStyle:
                TextStyle(fontSize: 12.5, color: AppPalette.inkSecondary),
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: AppPalette.cardOutline),
            backgroundColor: Colors.transparent,
            onPressed: _add,
          ),
      ],
    );
  }

  Widget _chip(String tag) {
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: widget.readOnly ? 10 : 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: AppPalette.scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('#$tag',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.inkPrimary)),
          if (!widget.readOnly) ...[
            const SizedBox(width: 2),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _remove(tag),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded,
                    size: 14, color: AppPalette.inkSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
