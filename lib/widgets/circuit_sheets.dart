import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Where a new circuit note goes, and what kind it is — the result of the
/// note screen's **+** sheet.
class CircuitAddChoice {
  const CircuitAddChoice({required this.under, required this.markdown});

  /// true = under this note (a child); false = next to it (a sibling).
  final bool under;
  final bool markdown;
}

/// The sheet a note's **+** button opens: place a new note next to or under
/// this one, as a rich note or a Markdown note. On the first note only "under"
/// applies (a first note has no siblings), so [rootOnly] hides the sibling row.
/// Returns null if dismissed.
Future<CircuitAddChoice?> showCircuitAddSheet(
  BuildContext context, {
  required bool rootOnly,
}) {
  return showModalBottomSheet<CircuitAddChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.t.circuitAddTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary),
                  ),
                ),
              ),
              if (!rootOnly)
                _tile(sheetCtx, Icons.arrow_forward_rounded,
                    context.t.circuitAddSibling,
                    const CircuitAddChoice(under: false, markdown: false)),
              _tile(sheetCtx, Icons.subdirectory_arrow_right_rounded,
                  context.t.circuitAddChild,
                  const CircuitAddChoice(under: true, markdown: false)),
              _tile(sheetCtx, Icons.data_object_rounded,
                  context.t.circuitAddChildMarkdown,
                  const CircuitAddChoice(under: true, markdown: true)),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _tile(
  BuildContext ctx,
  IconData icon,
  String label,
  CircuitAddChoice choice,
) =>
    ListTile(
      leading: Icon(icon, color: AppPalette.inkSecondary),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppPalette.inkPrimary)),
      onTap: () => Navigator.pop(ctx, choice),
    );

// ---- Node sheet (long-press a node) ---------------------------------------

/// Every action a node's long-press sheet can return. The map screen turns the
/// choice into an AppState call (some, like rename or move, gather more input).
enum CircuitNodeAction {
  open,
  rename,
  colour,
  toggleCollapse,
  moveUp,
  moveDown,
  indent,
  outdent,
  moveTo,
  addSibling,
  addChild,
  addChildMarkdown,
  addExisting,
  toggleFeed,
  remove,
  shareOutline,
  sharePdf,
  delete,
}

/// The long-press sheet for a node. A branch shows the full set (with actions
/// that don't apply disabled); the first note shows a reduced set. [canMoveUp]
/// / [canMoveDown] / [canIndent] / [canOutdent] gate the reorder actions.
Future<CircuitNodeAction?> showCircuitNodeSheet(
  BuildContext context, {
  required Note note,
  required bool canMoveUp,
  required bool canMoveDown,
  required bool canIndent,
  required bool canOutdent,
  bool hasChildren = false,
  bool collapsed = false,
}) {
  final t = context.t;
  final isRoot = note.isCircuitRoot;
  final headerTitle = note.title.trim().isEmpty
      ? (isRoot ? t.untitledCircuit : t.untitledNote)
      : note.title.trim();

  return showModalBottomSheet<CircuitNodeAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppPalette.inkPrimary)),
                    ),
                  ),
                  _act(sheetCtx, Icons.open_in_full_rounded, t.circuitOpen,
                      CircuitNodeAction.open),
                  _act(sheetCtx, Icons.edit_outlined, t.circuitRename,
                      CircuitNodeAction.rename),
                  _act(sheetCtx, Icons.palette_outlined, t.circuitColour,
                      CircuitNodeAction.colour),
                  if (hasChildren)
                    _act(
                        sheetCtx,
                        collapsed
                            ? Icons.unfold_more_rounded
                            : Icons.unfold_less_rounded,
                        collapsed ? t.circuitExpand : t.circuitCollapse,
                        CircuitNodeAction.toggleCollapse),
                  if (!isRoot) ...[
                    _act(sheetCtx, Icons.arrow_upward_rounded, t.circuitMoveUp,
                        CircuitNodeAction.moveUp, enabled: canMoveUp),
                    _act(sheetCtx, Icons.arrow_downward_rounded,
                        t.circuitMoveDown, CircuitNodeAction.moveDown,
                        enabled: canMoveDown),
                    _act(sheetCtx, Icons.format_indent_increase_rounded,
                        t.circuitIndent, CircuitNodeAction.indent,
                        enabled: canIndent),
                    _act(sheetCtx, Icons.format_indent_decrease_rounded,
                        t.circuitOutdent, CircuitNodeAction.outdent,
                        enabled: canOutdent),
                    _act(sheetCtx, Icons.drive_file_move_outline,
                        t.circuitMoveTo, CircuitNodeAction.moveTo),
                    _act(sheetCtx, Icons.arrow_forward_rounded,
                        t.circuitAddSibling, CircuitNodeAction.addSibling),
                  ],
                  _act(sheetCtx, Icons.subdirectory_arrow_right_rounded,
                      t.circuitAddChild, CircuitNodeAction.addChild),
                  _act(sheetCtx, Icons.data_object_rounded,
                      t.circuitAddChildMarkdown,
                      CircuitNodeAction.addChildMarkdown),
                  _act(sheetCtx, Icons.playlist_add_rounded,
                      t.circuitAddExisting, CircuitNodeAction.addExisting),
                  if (!isRoot)
                    _act(
                        sheetCtx,
                        note.circuitShowInFeed
                            ? Icons.visibility_off_outlined
                            : Icons.home_outlined,
                        note.circuitShowInFeed
                            ? t.circuitHideFromFeed
                            : t.circuitShowInFeed,
                        CircuitNodeAction.toggleFeed),
                  if (!isRoot)
                    _act(sheetCtx, Icons.link_off_rounded, t.circuitRemove,
                        CircuitNodeAction.remove),
                  if (isRoot) ...[
                    _act(sheetCtx, Icons.ios_share_rounded,
                        t.circuitShareOutline, CircuitNodeAction.shareOutline),
                    _act(sheetCtx, Icons.picture_as_pdf_outlined,
                        t.circuitSharePdf, CircuitNodeAction.sharePdf),
                  ],
                  _act(
                      sheetCtx,
                      Icons.delete_outline_rounded,
                      isRoot ? t.circuitDeleteCircuitAction : t.delete,
                      CircuitNodeAction.delete,
                      danger: true),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _act(
  BuildContext ctx,
  IconData icon,
  String label,
  CircuitNodeAction action, {
  bool enabled = true,
  bool danger = false,
}) {
  final tint = danger ? const Color(0xFFE0567B) : null;
  final color = enabled
      ? (tint ?? AppPalette.inkPrimary)
      : AppPalette.inkSecondary.withValues(alpha: 0.4);
  return ListTile(
    dense: true,
    enabled: enabled,
    leading: Icon(icon, color: enabled ? (tint ?? AppPalette.inkSecondary) : color),
    title: Text(label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color)),
    onTap: enabled ? () => Navigator.pop(ctx, action) : null,
  );
}

// ---- Placeholder sheet ----------------------------------------------------

enum CircuitSlotAction { writeNote, writeMarkdown, placeExisting, moveHere, remove }

/// The sheet a placeholder opens: turn it into a note, fill it, or remove it.
Future<CircuitSlotAction?> showCircuitSlotSheet(
  BuildContext context, {
  required Note placeholder,
}) {
  final t = context.t;
  return showModalBottomSheet<CircuitSlotAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      placeholder.title.trim().isEmpty
                          ? t.circuitPlaceholderTitle(1)
                          : placeholder.title.trim(),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppPalette.inkPrimary)),
                ),
              ),
              _slotTile(sheetCtx, Icons.edit_outlined, t.circuitSlotWrite,
                  CircuitSlotAction.writeNote),
              _slotTile(sheetCtx, Icons.data_object_rounded,
                  t.circuitSlotWriteMarkdown, CircuitSlotAction.writeMarkdown),
              _slotTile(sheetCtx, Icons.playlist_add_rounded,
                  t.circuitSlotPlace, CircuitSlotAction.placeExisting),
              _slotTile(sheetCtx, Icons.open_with_rounded, t.circuitSlotMove,
                  CircuitSlotAction.moveHere),
              _slotTile(sheetCtx, Icons.delete_outline_rounded,
                  t.circuitSlotRemove, CircuitSlotAction.remove,
                  danger: true),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _slotTile(
  BuildContext ctx,
  IconData icon,
  String label,
  CircuitSlotAction action, {
  bool danger = false,
}) {
  final color = danger ? const Color(0xFFE0567B) : AppPalette.inkPrimary;
  return ListTile(
    leading: Icon(icon, color: danger ? color : AppPalette.inkSecondary),
    title:
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
    onTap: () => Navigator.pop(ctx, action),
  );
}

// ---- Existing-note picker -------------------------------------------------

/// A searchable sheet over [notes] (from `notesPlaceableInCircuit`). Returns the
/// chosen note's id, or null if dismissed.
Future<String?> showCircuitExistingNotePicker(
  BuildContext context, {
  required List<Note> notes,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ExistingNotePicker(notes: notes),
  );
}

class _ExistingNotePicker extends StatefulWidget {
  const _ExistingNotePicker({required this.notes});
  final List<Note> notes;

  @override
  State<_ExistingNotePicker> createState() => _ExistingNotePickerState();
}

class _ExistingNotePickerState extends State<_ExistingNotePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.notes
        : widget.notes.where((n) {
            final title = n.title.toLowerCase();
            final preview = n.textPreview.toLowerCase();
            return title.contains(q) || preview.contains(q);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.all(14),
        child: GlassEdge(
          borderRadius: 28,
          fill: AppPalette.whiteFill,
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(t.circuitPickNote,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppPalette.inkPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t.circuitPickNote,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(t.noNotesOrCards,
                            style:
                                TextStyle(color: AppPalette.inkSecondary)))
                    : ListView.builder(
                        controller: controller,
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final n = rows[i];
                          final title = n.title.trim().isEmpty
                              ? t.untitledNote
                              : n.title.trim();
                          final previewLines = n.textPreview.trim().split('\n');
                          final preview =
                              previewLines.isEmpty ? '' : previewLines.first;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                                n.markdown
                                    ? Icons.data_object_rounded
                                    : Icons.description_outlined,
                                color: AppPalette.inkSecondary),
                            title: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: AppPalette.inkPrimary)),
                            subtitle: preview.isEmpty
                                ? null
                                : Text(preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppPalette.inkSecondary)),
                            onTap: () => Navigator.pop(context, n.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Delete dialogs -------------------------------------------------------

enum CircuitDeleteChoice { all, keepSlot }

/// The choice dialog for deleting a branch that has notes under it.
/// [childCount] is the number of descendants; "Delete all" removes childCount+1.
Future<CircuitDeleteChoice?> showCircuitDeleteWithChildrenDialog(
  BuildContext context, {
  required String title,
  required int childCount,
}) {
  final t = context.t;
  return showDialog<CircuitDeleteChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.circuitDeleteTitle(title)),
      content: Text(t.circuitDeleteBody(childCount)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, CircuitDeleteChoice.keepSlot),
          child: Text(t.circuitDeleteOnly),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, CircuitDeleteChoice.all),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0567B)),
          child: Text(t.circuitDeleteAll(childCount + 1)),
        ),
      ],
    ),
  );
}

/// The confirmation for deleting a whole circuit.
Future<bool> confirmDeleteCircuit(
  BuildContext context, {
  required String title,
  required int count,
}) async {
  final t = context.t;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.circuitDeleteCircuit(title, count)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFE0567B)),
          child: Text(t.delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}
