import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import 'note_open.dart';
import '../services/journal_format.dart';
import '../services/note_markdown.dart';
import '../services/note_pdf.dart';
import '../services/notification_service.dart';
import '../services/wiki_links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_route.dart';
import '../widgets/bubble_button.dart';
import '../widgets/expand_from_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_bubble.dart';
import '../widgets/glass_morph.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_background.dart';
import '../widgets/note_body_editor.dart';
import '../widgets/note_info.dart';
import '../widgets/note_link_picker.dart';
import '../widgets/note_links_section.dart';
import '../widgets/note_tags_editor.dart';
import '../widgets/wiki_text.dart';
import 'card_detail_screen.dart';
import 'reflexes_screen.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.isNew,
  });

  final Note note;
  final bool isNew;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with SingleTickerProviderStateMixin {
  late Note _note;
  late TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();

  /// Moves the caret up into the title (Backspace on an empty first body line).
  void _focusTitle() {
    _titleFocus.requestFocus();
    _titleCtrl.selection =
        TextSelection.collapsed(offset: _titleCtrl.text.length);
  }
  final _editorKey = GlobalKey<NoteBodyEditorState>();
  final _activeController = ValueNotifier<QuillController?>(null);

  /// True once the open animation has finished. Heavy children (Quill editors,
  /// backdrop blurs, the bottom island) mount only then, so the opening stays
  /// smooth; a static lookalike body is shown during the transition.
  bool _settled = false;
  bool _settleHooked = false;

  /// True while collapsing back into the feed: the frosted backdrop blur is
  /// dropped for the collapse so the shrinking glass stays perfectly paced.
  bool _closing = false;

  /// Journal entries get a centered date header instead of the folder chip
  /// and no folder controls; everything else works like a note.
  bool get _isJournal => _note.journalDate != null;

  /// Every note opens as a page you read; the pencil starts the writing.
  /// A note created just now skips straight to the editor — the compose
  /// button it grew out of already made that intent clear.
  bool _editing = true;
  bool get _readOnly => !_editing;

  /// Grows the editor out of the compose button when writing begins. Starts
  /// completed so a brand-new note doesn't replay it on top of the route's
  /// own open animation.
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  void _startEditing() {
    setState(() => _editing = true);
    _expand.forward(from: 0);
  }

  /// Done writing: fold the editor away and commit the note.
  void _finishEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    _collect();
    final state = context.read<AppState>();
    setState(() => _editing = false);
    if (!_note.isEmpty) {
      _persisted = true;
      state.upsertNote(_note);
    }
  }

  /// Ticks a checklist item straight from the read view (no need to enter the
  /// editor). Mutates the block's delta in place and persists at once.
  void _toggleCheck(int blockIndex, int lineIndex, bool nowChecked) {
    if (blockIndex < 0 || blockIndex >= _note.blocks.length) return;
    final b = _note.blocks[blockIndex];
    if (!b.isText) return;
    final updated = toggleChecklistLine(b.text, lineIndex);
    if (updated == b.text) return;
    setState(() => b.text = updated);
    _persisted = true;
    _savedFingerprint = _fingerprint();
    context.read<AppState>().upsertNote(_note);
  }

  /// Adjusts the whole note's text size (a per-note multiplier). Rebuilds the
  /// editor (and read view) live and persists the choice.
  void _pickFontSize() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          void set(double v) {
            _collect();
            setState(() => _note.fontScale = v.clamp(0.8, 1.6));
            setSheet(() {});
            _persisted = true;
            context.read<AppState>().upsertNote(_note);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                decoration: BoxDecoration(
                  color: AppPalette.sheet,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t.textSize,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.inkPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _sizeButton('A', 15,
                            () => set(_note.fontScale - 0.1)),
                        const SizedBox(width: 12),
                        _sizeButton('A', 26,
                            () => set(_note.fontScale + 0.1)),
                        const Spacer(),
                        Text('${(_note.fontScale * 100).round()}%',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.inkSecondary)),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () => set(1.0),
                            child: Text(context.t.resetSize)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sizeButton(String label, double size, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          child: Text(label,
              style: TextStyle(fontSize: size, color: AppPalette.inkPrimary)),
        ),
      );

  /// Whether the note has any checklist lines (so the "sink ticked items"
  /// option is worth showing).
  bool _hasChecklist() => _note.blocks
      .any((b) => b.isText && richToLines(b.text).any((l) => l.isCheckItem));

  /// The overflow menu behind the 3-dots button: share as Markdown, copy, sink
  /// ticked items, archive, delete.
  void _showNoteMenu() {
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
                  charCount: _note.charCount,
                ),
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppPalette.cardOutline),
                const SizedBox(height: 4),
                _menuTile(sheetCtx, Icons.ios_share_rounded, context.t.share,
                    _shareMarkdown),
                _menuTile(sheetCtx, Icons.picture_as_pdf_outlined,
                    context.t.exportAsPdf, _exportPdf),
                _menuTile(sheetCtx, Icons.copy_all_rounded, context.t.copyNote,
                    _copyNote),
                if (_hasChecklist())
                  _menuTile(
                    sheetCtx,
                    _note.checkedToBottom
                        ? Icons.check_box_rounded
                        : Icons.vertical_align_bottom_rounded,
                    context.t.moveCheckedToBottom,
                    () {
                      setState(() =>
                          _note.checkedToBottom = !_note.checkedToBottom);
                      _persisted = true;
                      state.upsertNote(_note);
                    },
                  ),
                if (!widget.isNew && !_isJournal)
                  _menuTile(
                    sheetCtx,
                    _note.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    _note.archived ? context.t.unarchive : context.t.archive,
                    () {
                      _note.archived = !_note.archived;
                      _close();
                    },
                  ),
                if (!widget.isNew)
                  _menuTile(
                    sheetCtx,
                    Icons.delete_outline_rounded,
                    context.t.delete,
                    () {
                      setState(() => _closing = true);
                      Navigator.of(context).pop();
                      _persistLater(state, delete: true);
                    },
                    danger: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuTile(BuildContext sheetCtx, IconData icon, String label,
      VoidCallback onTap,
      {bool danger = false}) {
    final tint = danger ? const Color(0xFFE0567B) : null;
    return ListTile(
      leading: Icon(icon, color: tint ?? AppPalette.inkSecondary),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: tint ?? AppPalette.inkPrimary)),
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );
  }

  String _fileBase() => _note.title.trim().isEmpty
      ? 'note'
      : _note.title
          .trim()
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '-');

  /// Writes the note to a temporary `.md` file and opens the share sheet.
  Future<void> _shareMarkdown() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final md = noteToMarkdown(_note);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_fileBase()}.md');
      await file.writeAsString(md);
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.shareFailed)));
      }
    }
  }

  /// Renders the note (via its Markdown form) to a PDF and shares it.
  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await NotePdf.fromMarkdown(noteToMarkdown(_note),
          title: _note.title.trim());
      await Printing.sharePdf(bytes: bytes, filename: '${_fileBase()}.pdf');
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.exportFailed)));
      }
    }
  }

  /// True once this note has been written to the library, so an emptied note
  /// gets cleaned up on close even if it was created in this session.
  bool _persisted = false;

  /// Live save while writing: every few seconds, changed content is
  /// persisted (and synced when signed in) — an open note updates on other
  /// devices mid-writing, Keep-style, and nothing is lost if the app dies.
  Timer? _autosave;
  String _savedFingerprint = '';

  String _fingerprint() => jsonEncode([
        _note.title,
        _note.colorValue,
        _note.backgroundAsset,
        _note.spaceId,
        _note.tags,
        _note.reminderAt?.toIso8601String(),
        for (final b in _note.blocks) b.toJson(),
      ]);

  void _autosaveTick() {
    // A saved article is being read, not written — nothing to autosave.
    if (_closing || _readOnly || !mounted) return;
    _collect();
    if (_note.isEmpty) return;
    final fp = _fingerprint();
    if (fp == _savedFingerprint) return;
    _savedFingerprint = fp;
    _persisted = true;
    context.read<AppState>().upsertNote(_note);
  }

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleCtrl = TextEditingController(text: _note.title);
    _savedFingerprint = _fingerprint();
    // Saved notes open as a page to read; a note being created opens ready
    // to write.
    _editing = widget.isNew;
    _autosave = Timer.periodic(
        const Duration(seconds: 3), (_) => _autosaveTick());
    // Snapshot a book chapter's pre-edit state when a writing session opens,
    // so a heavy revise stays reversible (throttled inside AppState).
    if (_note.isManuscriptPage && !widget.isNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<AppState>().maybeAutoSnapshotChapter(_note.id);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settleHooked) return;
    _settleHooked = true;
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation == null || animation.isCompleted) {
      _settled = true;
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(onStatus);
        if (mounted) setState(() => _settled = true);
      }
    }

    animation.addStatusListener(onStatus);
    // Fallback in case the route animation never reports completion.
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted && !_settled) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _expand.dispose();
    _titleCtrl.dispose();
    _titleFocus.dispose();
    _activeController.dispose();
    super.dispose();
  }

  /// Writes the live editors back into [_note] (cheap, synchronous).
  void _collect() {
    _note.title = _titleCtrl.text;
    _editorKey.currentState?.sync();
  }

  /// Persists after the close animation so the JSON encode + file write + feed
  /// rebuild don't jank the pop transition.
  void _persistLater(AppState state, {bool delete = false}) {
    Future.delayed(const Duration(milliseconds: 380), () async {
      if (delete) {
        await state.deleteNote(_note.id);
        return;
      }
      if (_note.isEmpty) {
        // Emptied out: drop it, including a note this session created and
        // already wrote (autosave or an article Save).
        if (!widget.isNew || _persisted) await state.deleteNote(_note.id);
        return;
      }
      await state.upsertNote(_note);
    });
  }

  void _close() {
    // Reading a saved note changes nothing — leave without rewriting it.
    if (_readOnly) {
      Navigator.of(context).pop();
      return;
    }
    final state = context.read<AppState>();
    _collect();
    // A brand-new note that has content doesn't belong back in the + button
    // it morphed out of — slide the sheet down instead so it doesn't read
    // as the note being discarded.
    if (widget.isNew && !_note.isEmpty) GlassMorph.slideCloseOf(context);
    setState(() => _closing = true);
    Navigator.of(context).pop();
    _persistLater(state);
  }

  /// Copies the whole note (title + text) to the clipboard for sharing.
  void _copyNote() {
    _collect();
    final buffer = StringBuffer();
    if (_note.title.trim().isNotEmpty) buffer.writeln(_note.title.trim());
    final body = _note.textPreview;
    if (body.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(body);
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.noteCopied)),
    );
  }

  Future<void> _pickSpace() async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: _note.spaceId);
    if (selected == null) return;
    setState(() => _note.spaceId = selected == '__none__' ? null : selected);
  }

  /// One menu for the note's look: colour swatches on top, backgrounds below.
  /// Each tap applies live, so the note restyles behind the open sheet.
  Future<void> _pickStyle() async {
    await showNoteStylePicker(
      context,
      currentColor: _note.colorValue,
      currentBackground: _note.backgroundAsset,
      onColor: (value) => setState(() => _note.colorValue = value),
      onBackground: (value) => setState(() => _note.backgroundAsset = value),
    );
  }

  Future<void> _pickReminder() async {
    // With one already set, offer to change or clear it first.
    if (_note.reminderAt != null) {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassPanel(
              borderRadius: 26,
              strong: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.edit_calendar_outlined,
                        color: AppPalette.inkPrimary),
                    title: Text(context.t.reminderChange),
                    onTap: () => Navigator.pop(context, 'change'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_off_outlined,
                        color: Color(0xFFE0567B)),
                    title: Text(context.t.reminderClear),
                    onTap: () => Navigator.pop(context, 'clear'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (action == 'clear') return _setReminder(null);
      if (action != 'change' || !mounted) return;
    }
    final now = DateTime.now();
    final base = _note.reminderAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base.isBefore(now) ? now : base,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    await _setReminder(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _setReminder(DateTime? at) async {
    final messenger = ScaffoldMessenger.of(context);
    final permText = context.t.notifPermNeeded;
    final granted = at == null
        ? true
        : await NotificationService.instance.requestPermission();
    if (!mounted) return;
    setState(() => _note.reminderAt = at);
    // Persist now so the reminder survives even before the next autosave.
    _persisted = true;
    context.read<AppState>().upsertNote(_note);
    await NotificationService.instance.syncNote(_note);
    if (at != null && !granted && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(permText)));
    }
  }

  // ---- Wiki-links ---------------------------------------------------------

  /// Commits the current note so the graph is consistent, then opens the
  /// resolved target — a note or a card.
  Future<void> _openRef(LinkRef ref) async {
    _collect();
    final state = context.read<AppState>();
    if (!_note.isEmpty) state.upsertNote(_note);
    if (!mounted) return;
    if (ref.kind == LinkKind.card) {
      final card = state.cardById(ref.id);
      if (card != null) {
        await Navigator.of(context)
            .push(cupertinoRoute(CardDetailScreen(card: card)));
      }
      return;
    }
    final target = state.noteById(ref.id);
    if (target != null) {
      await Navigator.of(context).push(cupertinoRoute(noteScreen(target)));
    }
  }

  /// Creates a note for an unresolved `[[title]]` and opens it ready to write.
  Future<void> _createAndOpenLinkedNote(String title) async {
    _collect();
    final state = context.read<AppState>();
    if (!_note.isEmpty) state.upsertNote(_note);
    final created = await state.createLinkedNote(title);
    if (!mounted) return;
    await Navigator.of(context)
        .push(cupertinoRoute(NoteEditorScreen(note: created, isNew: true)));
  }

  /// Follows a `[[link]]` tapped in the body: open the target, or create it.
  void _openWikiLink(String title) {
    final ref = context.read<AppState>().resolveLink(title);
    if (ref != null) {
      _openRef(ref);
    } else {
      _createAndOpenLinkedNote(title);
    }
  }

  /// Follows a `[[@Name]]` mention: open the referenced impulse (a thread
  /// mention opens its parent impulse). Silently does nothing if it no longer
  /// resolves.
  void _openMention(String name) {
    final target = context.read<AppState>().resolveMention(name);
    if (target == null) return;
    _collect();
    if (!_note.isEmpty) context.read<AppState>().upsertNote(_note);
    Navigator.of(context).push(
        cupertinoRoute(ImpulseDetailScreen(impulseId: target.impulseId)));
  }

  /// Inserts a `[[Note]]` link at the caret via the note picker.
  Future<void> _insertNoteLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final hint = context.t.tapNoteThenLink;
    final title = await showNoteLinkPicker(context);
    if (title == null || title.trim().isEmpty || !mounted) return;
    final ctrl = _activeController.value;
    final insert = '[[${title.trim()}]] ';
    if (ctrl == null) {
      messenger.showSnackBar(SnackBar(content: Text(hint)));
      return;
    }
    final len = ctrl.document.length;
    final at = ctrl.selection.baseOffset < 0
        ? (len - 1).clamp(0, len)
        : ctrl.selection.baseOffset.clamp(0, len - 1);
    ctrl.replaceText(at, 0, insert,
        TextSelection.collapsed(offset: at + insert.length));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final space = state.spaceById(_note.spaceId);
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final routeAnim =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    // A manuscript page is typeset in its book's chosen face (title and body);
    // workshop notes and ordinary notes keep the app's note typography.
    final bookFont =
        _note.isManuscriptPage ? state.bookById(_note.bookId!)?.fontFamily : null;
    final titleFont = bookFont ?? kNoteHeadingFont;

    // The right-hand chrome: a single overflow button whose menu collects
    // share / copy / (sink ticked) / archive / delete.
    final Widget topActions = BubblePill(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.t.moreOptions,
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: _showNoteMenu,
              ),
            ],
          );

    return PopScope(
      // While viewing a saved note, let the back gesture pop directly so
      // Android's predictive-back peek can play; intercept only while editing,
      // where _close() collects and persists the note before popping.
      canPop: _readOnly,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: NoteBackground(
        asset: _note.backgroundAsset,
        color: NoteColors.resolve(_note.colorValue),
        // Status-bar clock/battery must stay readable over the sheet: dark
        // icons on the light sheet, light icons on the dark one.
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (AppPalette.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              ListView(
                // A little breathing room between the pinned back button and
                // the title/first line below it.
                padding: EdgeInsets.fromLTRB(18, topInset + 24, 18, 200),
                children: [
                  if (space != null)
                    Builder(builder: (context) {
                      final tint = NoteColors.resolveStrong(space.colorValue);
                      final fg = tint != null
                          ? NoteColors.onSwatch
                          : AppPalette.inkSecondary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  tint ?? Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_rounded,
                                    size: 13,
                                    color: fg.withValues(alpha: 0.85)),
                                const SizedBox(width: 6),
                                Text(space.name, style: TextStyle(color: fg)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  if (_isJournal)
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.30, 0.72, curve: Curves.easeOut),
                      blur: true,
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          // The entry's default identity: its day.
                          Text(
                            formatJournalDate(
                                DateTime.parse(_note.journalDate!)),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: AppPalette.journalAccent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (_readOnly)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 4),
                              child: Text(
                                _note.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: kNoteHeadingFont,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.inkPrimary,
                                ),
                              ),
                            )
                          else
                            TextField(
                              controller: _titleCtrl,
                              focusNode: _titleFocus,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: kNoteHeadingFont,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.inkPrimary,
                              ),
                              maxLines: null,
                              scrollPhysics:
                                  const NeverScrollableScrollPhysics(),
                              decoration: InputDecoration(
                                hintText: context.t.addATitle,
                                hintStyle: TextStyle(
                                  color: AppPalette.inkSecondary
                                      .withValues(alpha: 0.6),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (_readOnly)
                    // Reading: the title is set in type, not a text field.
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.30, 0.72, curve: Curves.easeOut),
                      blur: true,
                      child: Text(
                        _note.title,
                        style: TextStyle(
                          fontFamily: titleFont,
                          fontSize: 24,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.inkPrimary,
                        ),
                      ),
                    )
                  else
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.30, 0.72, curve: Curves.easeOut),
                      blur: true,
                      child: TextField(
                        controller: _titleCtrl,
                        focusNode: _titleFocus,
                        style: TextStyle(
                          fontFamily: titleFont,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.inkPrimary,
                        ),
                        maxLines: null,
                        // The field grows with its text; without this, the
                        // app-wide bouncy physics let the title rubber-band
                        // on its own instead of scrolling with the note.
                        scrollPhysics: const NeverScrollableScrollPhysics(),
                        decoration: InputDecoration(
                          hintText: context.t.title,
                          hintStyle: TextStyle(
                            color:
                                AppPalette.inkSecondary.withValues(alpha: 0.6),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_readOnly)
                    // Reading: no Quill controllers are built at all, which
                    // is why opening a note is cheap.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StaticBody(
                            note: _note,
                            fontFamily: bookFont,
                            onOpenLink: _openWikiLink,
                            onOpenMention: _openMention,
                            onToggleCheck: _toggleCheck),
                      ],
                    )
                  else
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.42, 0.92, curve: Curves.easeOut),
                      child: ExpandFromButton(
                        animation: _expand,
                        child: _settled
                            ? NoteBodyEditor(
                                key: _editorKey,
                                blocks: _note.blocks,
                                activeController: _activeController,
                                onLight: true,
                                bodyFontFamily: bookFont,
                                fontScale: _note.fontScale,
                                onBackspaceAtStart: _focusTitle,
                                onRemoveImagePath: (path) => context
                                    .read<AppState>()
                                    .refreshAfterImageRemoval(path),
                              )
                            : _StaticBody(note: _note, fontFamily: bookFont),
                      ),
                    ),
                  // A pending reminder, shown as a chip you can clear.
                  if (!_note.isBookPage && _note.reminderAt != null)
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.42, 0.92, curve: Curves.easeOut),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _ReminderChip(
                            at: _note.reminderAt!,
                            onClear: _readOnly ? null : () => _setReminder(null),
                          ),
                        ),
                      ),
                    ),
                  // Tags: a light cross-cutting label, on regular notes only.
                  if (!_note.isBookPage)
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.42, 0.92, curve: Curves.easeOut),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: NoteTagsEditor(
                          note: _note,
                          readOnly: _readOnly,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ),
                  // The note's place in the graph: outgoing [[links]] and the
                  // notes that mention this one.
                  if (!_note.isBookPage)
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.42, 0.92, curve: Curves.easeOut),
                      child: NoteLinksSection(
                        selfId: _note.id,
                        title: _note.title,
                        scanText: '${_note.title}\n${_note.textPreview}',
                        onOpen: _openRef,
                        onCreateOpen: _createAndOpenLinkedNote,
                      ),
                    ),
                ],
              ),
              if (_settled && !_closing) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Scrim confined to the status bar so the clock/battery stay
                  // readable over whatever scrolls beneath; the note text
                  // itself stays fully visible under the toolbar.
                  child: TopScrimFade(
                    height: MediaQuery.of(context).padding.top + 8,
                    color: _note.backgroundAsset == null
                        ? (NoteColors.resolve(_note.colorValue) ??
                            AppPalette.sheet)
                        : AppPalette.sheet,
                  ),
                ),
                // Nothing to format while reading.
                if (!_readOnly)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SlideUpFromButton(
                      animation: _expand,
                      child: EditorBottomBar(
                        activeController: _activeController,
                        onAddPhotos: () =>
                            _editorKey.currentState?.addPhotos(),
                        // Book pages have no wallpaper, folder or reminder —
                        // just the writing tools.
                        onPickSpace: _note.isBookPage ? null : _pickSpace,
                        onPickColor: _note.isBookPage ? null : _pickStyle,
                        onReminder: _note.isBookPage ? null : _pickReminder,
                        reminderSet: _note.reminderAt != null,
                        onLinkNote: _note.isBookPage ? null : _insertNoteLink,
                        onFontSize: _pickFontSize,
                      ),
                    ),
                  ),
                // The compose button keeps its place from the feed: it opens
                // the editor out of itself, and finishes the piece when the
                // writing is done.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  right: 18,
                  // Steps above the format island while writing.
                  bottom: (_editing ? 148 : 18) +
                      MediaQuery.of(context).padding.bottom,
                  child: BubbleButton(
                    icon: _editing ? Icons.check_rounded : Icons.edit_rounded,
                    tooltip:
                        _editing ? context.t.save : context.t.editAction,
                    onTap: _editing ? _finishEditing : _startEditing,
                  ),
                ),
              ],
              // The back button + actions, pinned at the standard chrome spot.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        FrostedBackButton(onTap: _close),
                        const Spacer(),
                        topActions,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Staged content reveal driven by the route animation: the child drifts up a
/// few pixels while fading in; [blur] additionally sharpens it from a subtle
/// blur (used for the title). Renders the bare child once the route settles,
/// so there is zero steady-state cost.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.interval,
    required this.child,
    this.blur = false,
  });

  final Animation<double> animation;
  final Interval interval;
  final Widget child;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        if (animation.isCompleted) return child;
        final v = interval.transform(animation.value.clamp(0.0, 1.0));
        Widget w = Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - v)),
            child: child,
          ),
        );
        if (blur && v < 0.999) {
          final sigma = 2.2 * (1 - v);
          w = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: w,
          );
        }
        return w;
      },
    );
  }
}

/// A small chip showing a note's reminder time, with a clear button (unless
/// read-only). Turns red once the time has passed.
class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.at, this.onClear});

  final DateTime at;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final overdue = at.isBefore(DateTime.now());
    final color =
        overdue ? const Color(0xFFE0567B) : AppPalette.scheme.primary;
    return Container(
      padding: EdgeInsets.only(
          left: 10, right: onClear != null ? 4 : 10, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_active_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            DateFormat('EEE, MMM d · h:mm a').format(at),
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 2),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded,
                    size: 14, color: color.withValues(alpha: 0.8)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StaticBody extends StatelessWidget {
  const _StaticBody(
      {required this.note,
      this.fontFamily,
      this.onOpenLink,
      this.onOpenMention,
      this.onToggleCheck});
  final Note note;

  /// A book page's face, so the still frame shown during the open transition
  /// matches the live editor and doesn't flash a different font.
  final String? fontFamily;

  /// Follows a `[[wiki-link]]` tapped in the body; null disables link taps
  /// (during the open animation, or for articles).
  final void Function(String title)? onOpenLink;

  /// Follows a `[[@Name]]` impulse/thread mention tapped in the body.
  final void Function(String name)? onOpenMention;

  /// Ticks the checkbox on line [lineIndex] of block [blockIndex] straight from
  /// the read view. Null renders checkboxes read-only (open transition frame).
  final void Function(int blockIndex, int lineIndex, bool nowChecked)?
      onToggleCheck;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var bi = 0; bi < note.blocks.length; bi++) {
      final b = note.blocks[bi];
      if (b.isImage && b.imagePath.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(b.imagePath),
                fit: BoxFit.cover, width: double.infinity, cacheWidth: 1440),
          ),
        ));
      } else if (b.isLink && b.url.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.bubbleGlass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 18, color: AppPalette.inkSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.linkTitle.isNotEmpty ? b.linkTitle : b.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
      } else if (b.isText) {
        // Render line by line from the styled delta so every inline mark
        // (bold/italic/…) and block format (headings, quotes, lists, indent,
        // alignment) the editor showed survives into the saved read view.
        final lines = richToStyledLines(b.text);
        if (lines.isEmpty) continue;
        // Keep each line's original index (for tap-to-tick), then optionally
        // sink ticked items to the bottom for display only.
        var indexed = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
        if (note.checkedToBottom) {
          indexed = [
            ...indexed.where((e) => e.$2.kind != RichLineKind.checkedItem),
            ...indexed.where((e) => e.$2.kind == RichLineKind.checkedItem),
          ];
        }
        final lineWidgets = <Widget>[];
        var ordinal = 0;
        for (final (li, l) in indexed) {
          if (l.kind == RichLineKind.ordered) {
            ordinal++;
          } else {
            ordinal = 0;
          }
          lineWidgets.add(_lineWidget(l, bi, li, ordinal));
        }
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: lineWidgets,
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The base text style for a line, honouring its heading level / quote.
  /// Inline run marks are layered on top of this by [RichBodyText].
  TextStyle _baseStyle(RichLine l) {
    final book = fontFamily != null;
    final color = AppPalette.inkPrimary;
    // The per-note multiplier keeps the read view in step with the editor.
    final scale = note.fontScale;
    if (l.header == 1) {
      return TextStyle(
        fontFamily: fontFamily ?? kNoteHeadingFont,
        fontSize: (book ? 24 : 26) * scale,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: color,
      );
    }
    if (l.header == 2) {
      return TextStyle(
        fontFamily: fontFamily ?? kNoteHeadingFont,
        fontSize: (book ? 20 : 21) * scale,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: color,
      );
    }
    var s = TextStyle(
      fontFamily: fontFamily ?? activeBodyFont,
      fontSize: (book ? 18 : 21) * scale,
      height: book ? 1.5 : 1.35,
      color: color,
    );
    if (l.quote) {
      s = s.copyWith(
          color: color.withValues(alpha: 0.72), fontStyle: FontStyle.italic);
    }
    return s;
  }

  TextAlign? _alignOf(RichLine l) {
    switch (l.align) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      default:
        return null;
    }
  }

  Widget _text(RichLine l, TextStyle style) => RichBodyText(
        runs: l.runs.isEmpty ? [RichRun(l.text)] : l.runs,
        style: style,
        onOpenLink: onOpenLink,
        onOpenMention: onOpenMention,
        textAlign: _alignOf(l),
      );

  Widget _lineWidget(RichLine l, int blockIndex, int lineIndex, int ordinal) {
    final style = _baseStyle(l);
    Widget content;
    switch (l.kind) {
      case RichLineKind.plain:
        content = _text(l, style);
      case RichLineKind.checkedItem:
      case RichLineKind.uncheckedItem:
        final checked = l.kind == RichLineKind.checkedItem;
        final itemStyle = checked
            ? style.copyWith(
                decoration: TextDecoration.lineThrough,
                color: AppPalette.inkSecondary,
                // Tie the strike line to the text colour, else it can render in
                // the ambient (white) ink and look like it's crossing out air.
                decorationColor: AppPalette.inkSecondary)
            : style;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 10),
              child: Icon(
                checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: checked
                    ? AppPalette.scheme.primary
                    : AppPalette.inkSecondary,
              ),
            ),
            Expanded(child: _text(l, itemStyle)),
          ],
        );
        content = onToggleCheck == null
            ? row
            : InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onToggleCheck!(blockIndex, lineIndex, !checked),
                child: row,
              );
      case RichLineKind.bullet:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 10),
              child: Text('•', style: style),
            ),
            Expanded(child: _text(l, style)),
          ],
        );
      case RichLineKind.ordered:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 10),
              child: Text('$ordinal.', style: style),
            ),
            Expanded(child: _text(l, style)),
          ],
        );
    }
    // A quote gets a soft left rule; indent shifts the whole line in.
    if (l.quote) {
      content = Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                color: AppPalette.inkPrimary.withValues(alpha: 0.28),
                width: 3),
          ),
        ),
        child: content,
      );
    }
    final topPad = l.header == 1 ? 10.0 : (l.header == 2 ? 8.0 : 3.0);
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: 3, left: l.indent * 20.0),
      child: content,
    );
  }
}

