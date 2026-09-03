import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/journal_format.dart';
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
import '../widgets/note_link_picker.dart';
import '../widgets/note_links_section.dart';
import '../widgets/note_tags_editor.dart';
import '../widgets/text_prompt.dart';
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

  /// Articles are notes with a byline and a reading view.
  bool get _isArticle => _note.isArticle;

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
    if (_isArticle) {
      _saveArticle(draft: false);
      return;
    }
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

  /// True once this note has been written to the library, so an emptied note
  /// gets cleaned up on close even if it was created in this session.
  bool _persisted = false;

  final _menuKey = GlobalKey();

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

  /// Saves the article: stamps the save time, snapshots the byline from the
  /// signed-in account, and (for a real save) flips into the reading view.
  void _saveArticle({required bool draft}) {
    _collect();
    if (_note.isEmpty) return;
    final state = context.read<AppState>();
    setState(() {
      _note.articleDraft = draft;
      _note.articleSavedAt = DateTime.now();
      if (_note.authorName.isEmpty) {
        _note.authorName = state.accountName ?? state.accountEmail ?? '';
        _note.authorPhoto = state.accountPhotoUrl ?? '';
      }
      _savedFingerprint = _fingerprint();
      _persisted = true;
      if (!draft) _editing = false;
    });
    state.upsertNote(_note);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          draft ? context.t.draftSavedToast : context.t.articleSavedToast),
    ));
  }

  /// The article's overflow menu: save as draft, then archive and delete.
  Future<void> _articleMenu() async {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final choice = await showMenu<String>(
      context: context,
      // Softly rounded, matching the island language.
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(26))),
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + box.size.height + 6,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      items: [
        PopupMenuItem(
          value: 'draft',
          child: Row(children: [
            Icon(Icons.drafts_outlined, color: AppPalette.inkSecondary),
            const SizedBox(width: 12),
            Text(context.t.saveAsDraft),
          ]),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Row(children: [
            Icon(
                _note.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                color: AppPalette.inkSecondary),
            const SizedBox(width: 12),
            Text(_note.archived ? context.t.unarchive : context.t.archive),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded,
                color: AppPalette.inkSecondary),
            const SizedBox(width: 12),
            Text(context.t.delete),
          ]),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'draft':
        _saveArticle(draft: true);
      case 'archive':
        _note.archived = !_note.archived;
        _close();
      case 'delete':
        final state = context.read<AppState>();
        setState(() => _closing = true);
        Navigator.of(context).pop();
        _persistLater(state, delete: true);
    }
  }

  void _close() {
    // Reading a saved article changes nothing — leave without rewriting it.
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
            .push(bouncyRoute(CardDetailScreen(card: card)));
      }
      return;
    }
    final target = state.noteById(ref.id);
    if (target != null) {
      await Navigator.of(context)
          .push(bouncyRoute(NoteEditorScreen(note: target, isNew: false)));
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
        .push(bouncyRoute(NoteEditorScreen(note: created, isNew: true)));
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

    // The right-hand chrome: a saved article keeps only its overflow menu;
    // everything else gets the copy / archive / delete pill.
    final Widget topActions = _isArticle
        ? GlassBubble(
            key: _menuKey,
            icon: Icons.more_vert_rounded,
            tooltip: context.t.moreOptions,
            iconColor: AppPalette.inkPrimary,
            glassColor: const Color(0x14000000),
            size: 44,
            iconSize: 22,
            shadow: false,
            onTap: _articleMenu,
          )
        : BubblePill(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.t.copyNote,
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: _copyNote,
              ),
              if (!widget.isNew && !_isJournal)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _note.archived
                      ? context.t.unarchive
                      : context.t.archive,
                  icon: Icon(_note.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined),
                  onPressed: () {
                    _note.archived = !_note.archived;
                    _close();
                  },
                ),
              if (!widget.isNew)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    final state = context.read<AppState>();
                    setState(() => _closing = true);
                    Navigator.of(context).pop();
                    _persistLater(state, delete: true);
                  },
                ),
            ],
          );

    return PopScope(
      canPop: false,
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
                    // A finished article: its title is set in type, not in
                    // a text field.
                    _Entrance(
                      animation: routeAnim,
                      interval:
                          const Interval(0.30, 0.72, curve: Curves.easeOut),
                      blur: true,
                      child: Text(
                        _note.title,
                        style: TextStyle(
                          fontFamily: titleFont,
                          // Articles carry a slightly grander headline.
                          fontSize: _isArticle ? 28 : 24,
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
                    _StaticBody(
                        note: _note,
                        fontFamily: bookFont,
                        onOpenLink: _isArticle ? null : _openWikiLink,
                        onOpenMention: _isArticle ? null : _openMention,
                        onToggleCheck: _isArticle ? null : _toggleCheck)
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
                  // The byline signs the piece off, article-style.
                  if (_isArticle) _ArticleByline(note: _note),
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

/// The article's sign-off: the author's picture, their name, and the date the
/// piece was saved. The name comes from the byline snapshot taken at save
/// time, falling back to the signed-in account while the piece is unsaved.
class _ArticleByline extends StatelessWidget {
  const _ArticleByline({required this.note});

  final Note note;

  Future<void> _editAuthor(BuildContext context, Note note) async {
    final state = context.read<AppState>();
    final name = await promptForText(
      context,
      title: context.t.bookAuthor,
      hint: context.t.authorHint,
      initial: note.authorName.isNotEmpty
          ? note.authorName
          : (state.accountName ?? state.accountEmail ?? ''),
      capitalization: TextCapitalization.words,
    );
    if (name == null) return;
    note.authorName = name.trim();
    await state.upsertNote(note);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final name = note.authorName.isNotEmpty
        ? note.authorName
        : (state.accountName ?? state.accountEmail ?? '');
    if (name.isEmpty) return const SizedBox.shrink();
    final photo =
        note.authorPhoto.isNotEmpty ? note.authorPhoto : state.accountPhotoUrl;
    final saved = note.articleSavedAt;

    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppPalette.cardOutline, height: 26),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppPalette.scheme.secondaryContainer,
                foregroundImage:
                    photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                onForegroundImageError:
                    photo != null && photo.isNotEmpty ? (_, _) {} : null,
                child: Text(
                  name[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tap the byline to write under a different name.
                    GestureDetector(
                      onTap: () => _editAuthor(context, note),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kNoteHeadingFont,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      saved == null
                          ? context.t.draftLabel
                          : DateFormat('MMMM d, yyyy').format(saved),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (note.articleDraft && saved != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.chipFill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.t.draftLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A cheap, static lookalike of the note body shown while the open animation
/// runs — mirrors the editor's text style and image layout so the swap to the
/// real Quill editors is invisible. It doubles as the article reading view.
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
        final lines = richToLines(b.text);
        if (lines.isEmpty) continue;
        final style = TextStyle(
          fontFamily: fontFamily ?? activeBodyFont,
          fontSize: fontFamily != null ? 18 : 21,
          height: fontFamily != null ? 1.5 : 1.35,
          color: AppPalette.inkPrimary,
        );
        final hasStructure =
            lines.any((l) => l.kind != RichLineKind.plain);
        if (!hasStructure) {
          // Ordinary prose: keep the old single-Text path so paragraph flow
          // and wiki-links across the whole block are unchanged.
          final plain = richToPlain(b.text);
          if (plain.isEmpty) continue;
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: onOpenLink != null && plain.contains('[[')
                ? WikiText(
                    text: plain,
                    style: style,
                    onOpenLink: onOpenLink!,
                    onOpenMention: onOpenMention)
                : Text(plain, style: style),
          ));
        } else {
          // Checklist / bulleted / numbered content: render line by line so
          // the checkboxes and markers survive into the read view.
          final lineWidgets = <Widget>[];
          var ordinal = 0;
          for (var li = 0; li < lines.length; li++) {
            final l = lines[li];
            if (l.kind == RichLineKind.ordered) {
              ordinal++;
            } else {
              ordinal = 0;
            }
            lineWidgets.add(_lineWidget(l, bi, li, ordinal, style));
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
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _text(RichLine l, TextStyle style) =>
      onOpenLink != null && l.text.contains('[[')
          ? WikiText(
              text: l.text,
              style: style,
              onOpenLink: onOpenLink!,
              onOpenMention: onOpenMention)
          : Text(l.text, style: style);

  Widget _lineWidget(
      RichLine l, int blockIndex, int lineIndex, int ordinal, TextStyle style) {
    switch (l.kind) {
      case RichLineKind.plain:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _text(l, style),
        );
      case RichLineKind.checkedItem:
      case RichLineKind.uncheckedItem:
        final checked = l.kind == RichLineKind.checkedItem;
        final itemStyle = checked
            ? style.copyWith(
                decoration: TextDecoration.lineThrough,
                color: AppPalette.inkSecondary)
            : style;
        final row = Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
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
          ),
        );
        if (onToggleCheck == null) return row;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onToggleCheck!(blockIndex, lineIndex, !checked),
          child: row,
        );
      case RichLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 10),
                child: Text('•', style: style),
              ),
              Expanded(child: _text(l, style)),
            ],
          ),
        );
      case RichLineKind.ordered:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 10),
                child: Text('$ordinal.', style: style),
              ),
              Expanded(child: _text(l, style)),
            ],
          ),
        );
    }
  }
}

