import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../services/note_markdown.dart';
import '../services/note_pdf.dart';
import '../services/wiki_links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bubble_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/markdown_view.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_info.dart';
import '../widgets/quick_actions_menu.dart';
import 'card_detail_screen.dart';
import 'note_open.dart';

/// A GitHub-flavored Markdown node. Reading renders the raw markdown like a
/// committed README; editing swaps to a monospace source editor (with a live
/// preview toggle) and re-renders on save. Distinct from the handwriting-style
/// rich [NoteEditorScreen] — this is the app's "document" surface.
class MarkdownNoteScreen extends StatefulWidget {
  const MarkdownNoteScreen({super.key, required this.note, this.isNew = false});

  final Note note;
  final bool isNew;

  @override
  State<MarkdownNoteScreen> createState() => _MarkdownNoteScreenState();
}

class _MarkdownNoteScreenState extends State<MarkdownNoteScreen> {
  late final Note _note = widget.note;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.note.markdownSource);

  /// New nodes open straight into the editor; existing ones open rendered.
  late bool _editing = widget.isNew;

  /// Within the editor, flip between the source and a live preview.
  bool _preview = false;

  /// True once written to the library, so an emptied node is cleaned up.
  late bool _persisted = !widget.isNew;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final src = _ctrl.text;
    final state = context.read<AppState>();
    if (src.trim().isEmpty) {
      // An emptied node leaves nothing behind.
      if (_persisted) await state.deleteNote(_note.id);
      _persisted = false;
      return;
    }
    _note
      ..markdown = true
      ..title = markdownTitle(src)
      ..blocks = [NoteBlock(type: NoteBlockType.text, text: src)];
    await state.upsertNote(_note);
    _persisted = true;
  }

  /// Back button: persist any edits, then leave.
  Future<void> _leave() async {
    if (_editing) await _save();
    if (mounted) Navigator.of(context).pop();
  }

  /// Follows a `[[wiki-link]]` tapped in the rendered Markdown: opens the
  /// resolved note or card, or creates the note when the title is new — the
  /// same behaviour as the rich editor's links.
  Future<void> _openWikiLink(String title) async {
    final state = context.read<AppState>();
    final ref = state.resolveLink(title);
    if (ref == null) {
      final created = await state.createLinkedNote(title);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => noteScreen(created, isNew: true)));
      return;
    }
    if (ref.kind == LinkKind.card) {
      final card = state.cardById(ref.id);
      if (card != null && mounted) {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CardDetailScreen(card: card)));
      }
      return;
    }
    final note = state.noteById(ref.id);
    if (note != null && mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => noteScreen(note)));
    }
  }

  Future<void> _done() async {
    await _save();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = false;
      _preview = false;
    });
  }

  void _startEditing() => setState(() {
        _editing = true;
        _preview = false;
      });

  // ---- Overflow menu ------------------------------------------------------

  void _showMenu() {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
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
                noteInfoBlock(
                  context,
                  created: _note.createdAt,
                  modified: _note.updatedAt,
                  charCount: _note.markdownSource.length,
                ),
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppPalette.cardOutline),
                const SizedBox(height: 4),
                _tile(sheetCtx, Icons.ios_share_rounded, context.t.share,
                    _shareMarkdown),
                _tile(sheetCtx, Icons.picture_as_pdf_outlined,
                    context.t.exportAsPdf, _exportPdf),
                _tile(sheetCtx, Icons.drive_file_move_outline,
                    context.t.moveToFolder, _move),
                _tile(
                  sheetCtx,
                  _note.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  _note.archived ? context.t.unarchive : context.t.archive,
                  () async {
                    await state.bulkArchiveNotes({_note.id}, !_note.archived);
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
                _tile(sheetCtx, Icons.delete_outline_rounded, context.t.delete,
                    _confirmDelete,
                    danger: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext sheetCtx, IconData icon, String label,
      VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? const Color(0xFFE0567B) : AppPalette.inkPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );
  }

  Future<void> _shareMarkdown() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final md = _ctrl.text.trim().isEmpty ? _note.markdownSource : _ctrl.text;
      final dir = await getTemporaryDirectory();
      final base = _note.title.trim().isEmpty
          ? 'note'
          : _note.title
              .trim()
              .replaceAll(RegExp(r'[^\w\s-]'), '')
              .replaceAll(RegExp(r'\s+'), '-');
      final file = File('${dir.path}/$base.md');
      await file.writeAsString(md);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.shareFailed)));
      }
    }
  }

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final src = _ctrl.text.trim().isEmpty ? _note.markdownSource : _ctrl.text;
      final title =
          _note.title.trim().isEmpty ? markdownTitle(src) : _note.title.trim();
      final bytes = await NotePdf.fromMarkdown(src, title: title);
      final base = title.isEmpty
          ? 'note'
          : title
              .replaceAll(RegExp(r'[^\w\s-]'), '')
              .replaceAll(RegExp(r'\s+'), '-');
      await Printing.sharePdf(bytes: bytes, filename: '$base.pdf');
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.exportFailed)));
      }
    }
  }

  Future<void> _move() async {
    final choice = await showMoveToSpaceSheet(context, currentSpaceId: _note.spaceId);
    if (choice == null || !mounted) return;
    await context
        .read<AppState>()
        .bulkMoveNotes({_note.id}, choice == '__none__' ? null : choice);
  }

  Future<void> _confirmDelete() async {
    if (!await confirmDeleteItems(context, 1) || !mounted) return;
    if (_persisted) await context.read<AppState>().deleteNote(_note.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final overlay = (AppPalette.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    final Widget body;
    final List<Widget> actions;
    final Widget fab;

    if (_editing) {
      body = _preview
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
              child: MarkdownView(
                  _ctrl.text.trim().isEmpty ? '_Nothing to preview yet._' : _ctrl.text),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: TextField(
                controller: _ctrl,
                expands: true,
                maxLines: null,
                minLines: null,
                autofocus: widget.isNew,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 14, height: 1.5),
                decoration: InputDecoration.collapsed(
                  hintText: context.t.markdownHint,
                  hintStyle: TextStyle(
                      fontFamily: 'monospace',
                      color: AppPalette.inkSecondary),
                ),
              ),
            );
      actions = [
        FrostedCircleButton(
          icon: _preview ? Icons.code_rounded : Icons.visibility_outlined,
          tooltip: context.t.preview,
          onTap: () => setState(() => _preview = !_preview),
        ),
      ];
      fab = BubbleButton(
        key: const ValueKey('md-done'),
        icon: Icons.check_rounded,
        tooltip: context.t.done,
        onTap: _done,
      );
    } else {
      final src = _note.markdownSource;
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
        child: src.trim().isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(context.t.emptyNote,
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppPalette.inkSecondary)),
              )
            : MarkdownView(src, onWikiTap: _openWikiLink),
      );
      actions = [
        FrostedCircleButton(
          icon: Icons.more_horiz_rounded,
          tooltip: context.t.moreOptions,
          onTap: _showMenu,
        ),
      ];
      fab = BubbleButton(
        key: const ValueKey('md-edit'),
        icon: Icons.edit_rounded,
        tooltip: context.t.edit,
        onTap: _startEditing,
      );
    }

    return PopScope(
      // Let the back gesture pop directly while viewing (so Android's
      // predictive-back peek can play); only intercept mid-edit to save first.
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: FrostedScaffold(
          onBack: _leave,
          actions: actions,
          floatingActionButton: fab,
          body: body,
        ),
      ),
    );
  }
}
