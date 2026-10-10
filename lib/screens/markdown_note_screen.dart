import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../services/note_markdown.dart';
import '../services/wiki_links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bubble_button.dart';
import '../widgets/circuit_sheets.dart';
import '../widgets/dictionary_popup.dart';
import '../widgets/find_bar.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/markdown_view.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_info.dart';
import '../widgets/quick_actions_menu.dart';
import '../widgets/share_as.dart';
import 'card_detail_screen.dart';
import 'circuit_map_screen.dart';
import 'note_open.dart';

/// A GitHub-flavored Markdown node. Reading renders the raw markdown like a
/// committed README; editing swaps to a monospace source editor (with a live
/// preview toggle) and re-renders on save. Distinct from the handwriting-style
/// rich [NoteEditorScreen] — this is the app's "document" surface.
class MarkdownNoteScreen extends StatefulWidget {
  const MarkdownNoteScreen({
    super.key,
    required this.note,
    this.isNew = false,
    this.fromCircuitMap = false,
    this.startEditing = false,
  });

  final Note note;
  final bool isNew;

  /// Opened from the circuit map: **+** and **map** pop back to it.
  final bool fromCircuitMap;

  /// Open straight into the source editor (a fresh circuit branch) without the
  /// empty-note cleanup that [isNew] also drives.
  final bool startEditing;

  @override
  State<MarkdownNoteScreen> createState() => _MarkdownNoteScreenState();
}

class _MarkdownNoteScreenState extends State<MarkdownNoteScreen> {
  late final Note _note = widget.note;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.note.markdownSource);

  /// New nodes (and fresh circuit branches) open into the editor; existing
  /// ones open rendered.
  late bool _editing = widget.isNew || widget.startEditing;

  /// Within the editor, flip between the source and a live preview.
  bool _preview = false;

  // ---- Find in note (while reading) ------------------------------------------

  bool _finding = false;
  final _findCtrl = TextEditingController();
  final _findFocus = FocusNode();
  final _findKey = GlobalKey();

  /// How many matches there are (counted by the view), and which one (from
  /// 0) is current.
  int _findTotal = 0;
  int _findAt = 0;

  void _openFind() => setState(() {
        _finding = true;
        _findAt = 0;
      });

  void _closeFind() {
    if (!_finding) return;
    _findFocus.unfocus();
    setState(() {
      _finding = false;
      _findTotal = 0;
      _findAt = 0;
    });
  }

  void _stepFind(int by) {
    if (_findTotal == 0) return;
    setState(() => _findAt = (_findAt + by) % _findTotal);
  }

  /// True once written to the library, so an emptied node is cleaned up.
  late bool _persisted = !widget.isNew;

  /// This screen's route, registered in [OpenNoteScreens] while it is open.
  ModalRoute<Object?>? _route;

  /// The library, kept for [dispose], where the context may no longer be used.
  late final AppState _appState;

  /// Whether this screen holds the note's edit lease, so a browser on Braim
  /// Web can't edit it at the same time.
  bool _holdsLease = false;

  /// Takes the edit lease; false, with a message, while a browser holds it.
  bool _takeLease() {
    if (_appState.acquireEditLease(_note.id, kPhoneLease)) {
      _holdsLease = true;
      return true;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.t.webEditingOnComputer)));
    return false;
  }

  void _releaseLease() {
    if (!_holdsLease) return;
    _holdsLease = false;
    _appState.releaseEditLease(_note.id, kPhoneLease);
  }

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    if (_editing) {
      if (_appState.acquireEditLease(_note.id, kPhoneLease)) {
        _holdsLease = true;
      } else {
        _editing = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(context.t.webEditingOnComputer)));
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route != null) return;
    final route = ModalRoute.of(context);
    if (route != null) {
      _route = route;
      OpenNoteScreens.register(_note.id, route);
    }
  }

  @override
  void dispose() {
    final route = _route;
    if (route != null) OpenNoteScreens.unregister(_note.id, route);
    _releaseLease();
    _ctrl.dispose();
    _findCtrl.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final src = _ctrl.text;
    final state = context.read<AppState>();
    if (src.trim().isEmpty) {
      // A circuit note that others hang off is never deleted for being empty —
      // that would orphan them (section 9). That is every branch, and a first
      // note with branches: a first note starts out rich, but a restore or a
      // repair can promote a Markdown branch into one. Keep the emptied source,
      // exactly as the rich editor keeps an emptied note.
      if (_note.isCircuitNode ||
          (_note.isCircuitRoot &&
              state.circuitChildren(_note.id).isNotEmpty)) {
        _note
          ..title = markdownTitle(src)
          ..blocks = [NoteBlock(type: NoteBlockType.text, text: src)];
        await state.upsertNote(_note);
        _persisted = true;
        return;
      }
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

  /// Back button: persist any edits, then leave, handing [result] to the
  /// screen below (the circuit map reads a [CircuitMapOpenNote]).
  Future<void> _leave({Object? result}) async {
    if (_editing) await _save();
    _releaseLease();
    if (mounted) Navigator.of(context).pop(result);
  }

  /// Follows a `[[wiki-link]]` tapped in the rendered Markdown: opens the
  /// resolved note or card, or creates the note when the title is new — the
  /// same behaviour as the rich editor's links.
  Future<void> _openWikiLink(String title) async {
    final state = context.read<AppState>();
    final ref = state.resolveLink(title);
    if (ref == null) {
      if (_note.inCircuit) await state.ensureCircuitRootSaved(_note);
      final created = await state.createLinkedNote(title,
          circuitParent: _note.inCircuit ? _note : null);
      if (!mounted) return;
      // Opened from the circuit map: the map opens it in this note's place,
      // so back returns to the map.
      if (widget.fromCircuitMap) {
        await _leave(result: CircuitMapOpenNote(created.id));
        return;
      }
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
    if (note != null && mounted && widget.fromCircuitMap) {
      await _leave(result: CircuitMapOpenNote(note.id));
      return;
    }
    if (note != null && mounted) {
      // Save first: going back to an already-open screen pops this one.
      if (_editing) await _save();
      if (!mounted) return;
      await pushNoteScreen(context, note,
          () => MaterialPageRoute(builder: (_) => noteScreen(note)));
    }
  }

  Future<void> _done() async {
    await _save();
    _releaseLease();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = false;
      _preview = false;
    });
  }

  void _startEditing() {
    if (!_takeLease()) return;
    _closeFind();
    // A browser may have changed the source while it was being read here.
    if (_ctrl.text != _note.markdownSource) _ctrl.text = _note.markdownSource;
    setState(() {
      _editing = true;
      _preview = false;
    });
  }

  // ---- Circuit map --------------------------------------------------------

  Future<void> _goToMap(String focusNodeId, {required bool highlight}) async {
    final circuitId = _note.circuitId;
    if (circuitId == null) return;
    if (widget.fromCircuitMap) {
      Navigator.of(context)
          .pop(CircuitMapFocus(focusNodeId, highlight: highlight));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CircuitMapScreen(
            circuitId: circuitId,
            focusNodeId: focusNodeId,
            highlight: highlight,
            openedFromNoteId: _note.id)));
    _afterMap();
  }

  /// Back from a map pushed over this screen. The map edits the same note, so
  /// it may have renamed it (a rename rewrites the source's `# heading`; take
  /// it, or leaving would save the old source back) or deleted it.
  void _afterMap() {
    if (!mounted) return;
    final live = context.read<AppState>().noteById(_note.id);
    if (live == null || live.deletedAt != null) {
      Navigator.of(context).pop();
      return;
    }
    final src = _note.markdownSource;
    if (_ctrl.text != src) setState(() => _ctrl.text = src);
  }

  Future<void> _circuitMap() async {
    await _save();
    if (!mounted) return;
    _goToMap(_note.id, highlight: false);
  }

  Future<void> _circuitAdd() async {
    await _save();
    if (!mounted) return;
    final state = context.read<AppState>();
    final choice =
        await showCircuitAddSheet(context, rootOnly: _note.isCircuitRoot);
    if (choice == null || !mounted) return;
    String title(int n) => context.t.circuitNoteTitle(n);
    final created = (choice.under || _note.isCircuitRoot)
        ? await state.addCircuitChild(_note.id,
            markdown: choice.markdown, noteTitle: title)
        : await state.addCircuitSibling(_note.id,
            markdown: choice.markdown, noteTitle: title);
    if (!mounted) return;
    _goToMap(created.id, highlight: true);
  }

  // ---- Overflow menu ------------------------------------------------------

  void _showMenu() {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      // As tall as its rows need (not the default cap), scrolling only on a
      // screen too short for them all.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
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
                ShareAsTile(
                  formats: _note.inCircuit && !_note.circuitPlaceholder
                      ? ShareFormat.forCircuit
                      : ShareFormat.note,
                  onShare: (format) {
                    Navigator.pop(sheetCtx);
                    _share(format);
                  },
                ),
                _tile(sheetCtx, Icons.search_rounded, context.t.findInNote,
                    _openFind),
                // A branch follows its first note's folder and archive state,
                // so it shows neither control.
                if (!_note.isCircuitNode)
                  _tile(sheetCtx, Icons.drive_file_move_outline,
                      context.t.moveToFolder, _move),
                if (!_note.isCircuitNode)
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
                _tile(
                    sheetCtx,
                    Icons.delete_outline_rounded,
                    _note.isCircuitRoot
                        ? context.t.circuitDeleteCircuitAction
                        : context.t.delete,
                    _confirmDelete,
                    danger: true),
              ],
              ),
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

  /// Shares the source as written right now (unsaved edits included) in
  /// [format].
  void _share(ShareFormat format) {
    // A circuit note goes with every note under it (the first note: the
    // whole circuit), or as the whole circuit's file.
    if (_note.inCircuit) {
      shareCircuitAs(context, _note, format);
      return;
    }
    final src = _ctrl.text.trim().isEmpty ? _note.markdownSource : _ctrl.text;
    final title =
        _note.title.trim().isEmpty ? markdownTitle(src) : _note.title.trim();
    shareNoteAs(context, markdown: src, title: title, format: format);
  }

  Future<void> _move() async {
    final choice = await showMoveToSpaceSheet(context,
        currentSpaceId: _note.spaceId, allowCrypt: !_note.inCircuit);
    if (choice == null || !mounted) return;
    await context
        .read<AppState>()
        .bulkMoveNotes({_note.id}, choice == '__none__' ? null : choice);
  }

  Future<void> _confirmDelete() async {
    // A circuit note gets the circuit dialogs (section 8.1): the whole circuit
    // for a first note, the keep-a-placeholder choice for one with notes below.
    if (_note.inCircuit) {
      if (await confirmAndDeleteCircuitNote(context, _note) && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
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
    List<Widget> actions;
    final Widget fab;

    // A circuit branch (never a placeholder) gets + and map buttons before its
    // own actions, in both view and edit mode.
    final circuitButtons = _note.inCircuit && !_note.circuitPlaceholder
        ? <Widget>[
            FrostedCircleButton(
              icon: Icons.add_rounded,
              tooltip: context.t.circuitAddTitle,
              onTap: _circuitAdd,
            ),
            FrostedCircleButton(
              icon: Icons.account_tree_rounded,
              tooltip: context.t.circuitMap,
              onTap: _circuitMap,
            ),
          ]
        : const <Widget>[];

    if (_editing) {
      body = _preview
          ? MarkdownView(
              _ctrl.text.trim().isEmpty
                  ? '_Nothing to preview yet._'
                  : _ctrl.text,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: TextField(
                controller: _ctrl,
                expands: true,
                maxLines: null,
                minLines: null,
                autofocus: widget.isNew || widget.startEditing,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                contextMenuBuilder: definableFieldMenu,
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
      // MarkdownView scrolls itself, building only the blocks on screen.
      final Widget view = src.trim().isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 44, 16, 140),
              child: Text(context.t.emptyNote,
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppPalette.inkSecondary)),
            )
          : MarkdownView(src,
              onWikiTap: _openWikiLink,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
              find: _finding && _findCtrl.text.isNotEmpty
                  ? FindHighlight(_findCtrl.text, _findAt, _findKey)
                  : null,
              onFindTotal: (n) {
                if (n == _findTotal || !_finding) return;
                setState(() {
                  _findTotal = n;
                  if (_findAt >= n) _findAt = 0;
                });
              });
      body = !_finding
          ? view
          : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: FindBar(
                controller: _findCtrl,
                focusNode: _findFocus,
                total: _findTotal,
                current: _findAt,
                onChanged: (text) => setState(() {
                  _findAt = 0;
                  if (text.isEmpty) _findTotal = 0;
                }),
                onPrevious: () => _stepFind(-1),
                onNext: () => _stepFind(1),
                onClose: _closeFind,
              ),
            ),
            Expanded(child: view),
          ],
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

    actions = [...circuitButtons, ...actions];

    return PopScope(
      // Let the back gesture pop directly while viewing (so Android's
      // predictive-back peek can play); only intercept mid-edit to save first.
      canPop: !_editing && !_finding,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_finding) {
          _closeFind();
        } else {
          _leave();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: FrostedScaffold(
          onBack: _finding ? _closeFind : _leave,
          actions: actions,
          floatingActionButton: fab,
          body: body,
        ),
      ),
    );
  }
}
