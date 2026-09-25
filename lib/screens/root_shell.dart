import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/note.dart';
import '../platform/app_shortcuts.dart';
import '../platform/file_open.dart';
import '../platform/image_store.dart';
import '../platform/platform_caps.dart';
import '../platform/shared_files.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bubble_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import '../widgets/island_nav.dart';
import '../widgets/side_pane.dart';
import '../widgets/top_bar.dart';
import '../widgets/tutorial_dialog.dart';
import '../widgets/universal_search.dart';
import 'archive_screen.dart';
import 'book_screen.dart';
import 'books_screen.dart';
import 'cards_screen.dart';
import 'daily_day_screen.dart';
import 'home_screen.dart';
import 'journal_screen.dart';
import 'journal_year_screen.dart';
import 'markdown_note_screen.dart';
import 'note_editor_screen.dart';
import 'pomodoro_screen.dart';
import 'recently_deleted_screen.dart';
import 'reflexes_screen.dart';
import 'settings_screen.dart';
import 'space_detail_screen.dart';
import 'spaces_screen.dart';

/// Springy page snapping for the Home/Cards/Cortex swipes — settles with a
/// soft, slightly underdamped bounce (Android SpringAnimation feel).
class _SpringPagePhysics extends PageScrollPhysics {
  const _SpringPagePhysics({super.parent});

  @override
  _SpringPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _SpringPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.6,
        stiffness: 150,
        ratio: 0.86,
      );
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _index = 0;
  bool _paneOpen = false;
  String _query = '';
  final _pageController = PageController();
  final _searchKey = GlobalKey();

  /// One scroll position per feed tab so re-tapping the active tab (or the
  /// screen title) can send that feed back to the top.
  final _feedScrolls = [
    ScrollController(), // Home
    ScrollController(), // Cards
    ScrollController(), // Narrative (books)
    ScrollController(), // Journal
    ScrollController(), // Cortex
  ];

  /// Lets the title tap snap the journal's week strip back to today.
  final _journalKey = GlobalKey<JournalScreenState>();

  /// Drives the side pane + scrim together so a finger can drag the pane
  /// partway and it settles open or closed from wherever it was released.
  late final AnimationController _paneCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PlatformCaps.current.canShareIntent) _initShareIntent();
    AppShortcuts.search = _shortcutSearch;
    AppShortcuts.newItem = _shortcutNew;
    AppShortcuts.stepTab = _shortcutStepTab;
    // First launch: walk through the basics once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.tutorialSeen) {
        await showTutorial(context);
        await state.setTutorialSeen();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(AppShortcuts.search, _shortcutSearch)) {
      AppShortcuts.search = null;
      AppShortcuts.newItem = null;
      AppShortcuts.stepTab = null;
    }
    _shareSub?.cancel();
    _searchDebounce?.cancel();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _pageController.dispose();
    _paneCtrl.dispose();
    for (final c in _feedScrolls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Debounced: search re-filters 250ms after the last keystroke.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) context.read<AppState>().updateSystemBrightness();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    // The share popup (its own engine) drops shares into the inbox; pick them
    // up on resume so links saved while we were backgrounded show up.
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        // A browser tab only goes as far as hidden.
        (state == AppLifecycleState.hidden && PlatformCaps.current.isWeb)) {
      // Backgrounding: make sure coalesced edits reach disk.
      final app = context.read<AppState>();
      app.flushNow();
      // A normal background (not a teardown) is a good moment for the silent
      // scheduled backups — they self-throttle, no-op when nothing changed, and
      // share a single zip when both the Drive and on-device schedules are due.
      if (state == AppLifecycleState.paused) {
        app.maybeBackupOnPause();
      }
    }
  }

  void _initShareIntent() {
    // Cold-start share.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleShared(files);
      ReceiveSharingIntent.instance.reset();
    });
    // While the app is running.
    _shareSub =
        ReceiveSharingIntent.instance.getMediaStream().listen(_handleShared);
  }

  Future<void> _handleShared(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    final state = context.read<AppState>();
    var addedCard = false;
    // Non-link text and any images collapse into a single new note.
    final imagePaths = <String>[];
    final textParts = <String>[];
    var addedDoc = false;
    for (final f in files) {
      if (f.type == SharedMediaType.image) {
        try {
          imagePaths.add(
              await ImageStore.instance.savePicked(XFile(f.path)));
        } catch (_) {
          // Skip an image we couldn't copy.
        }
        continue;
      }
      // A shared document (a Markdown or plain-text file) becomes a home note.
      // receive_sharing_intent hands us a real cached path for file shares and
      // the display-name extension isn't guaranteed, so probe f.path as a file
      // and parse its contents as Markdown rather than trusting the suffix.
      final content = await readSharedFileText(f.path);
      if (content != null) {
        try {
          if (content.trim().isNotEmpty) {
            // A shared document keeps its raw markdown as a full GitHub-style
            // Markdown node, rather than being flattened into a rich note.
            await state.addMarkdownNode(content);
            addedDoc = true;
          }
        } catch (_) {
          // A binary file we can't read as text: nothing to import.
        }
        continue; // f.path was a file — handled (or skipped), not share text.
      }
      // Only a bare link (the whole share is one URL) becomes a spark; a
      // document that merely contains a link stays a note. Mirrors the share
      // popup's note-vs-spark rule.
      final trimmed = f.path.trim();
      if (RegExp(r'^https?://\S+$').hasMatch(trimmed)) {
        await state.addCardFromUrl(trimmed);
        addedCard = true;
      } else if (trimmed.isNotEmpty) {
        textParts.add(trimmed);
      }
    }
    final text = textParts.isEmpty ? null : textParts.join('\n\n');
    final addedNote = imagePaths.isNotEmpty || text != null;
    if (addedNote) {
      if (imagePaths.isEmpty && text != null) {
        // Pure shared text: parse as Markdown so formatting renders instead of
        // its raw symbols (a no-op for plain text).
        await state.addSharedMarkdown(text);
      } else {
        await state.addSharedNote(text: text, imagePaths: imagePaths);
      }
    }
    if (!mounted) return;
    // A shared note wins the focus; otherwise land on the new card.
    if (addedNote || addedDoc) {
      _selectTab(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.savedToNotes)),
      );
    } else if (addedCard) {
      _selectTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.savedToCards)),
      );
    }
  }

  void _openPane() {
    if (!_paneOpen) setState(() => _paneOpen = true);
    _paneCtrl.animateTo(1, curve: Curves.easeOutCubic);
  }

  void _closePane() {
    if (_paneOpen) setState(() => _paneOpen = false);
    _paneCtrl.animateBack(0, curve: Curves.easeOutCubic);
  }

  /// How far the screen is pushed right while the drawer is out (old-Discord
  /// push style): the drawer owns the left two thirds of the screen.
  double get _paneWidth => MediaQuery.of(context).size.width * (2 / 3);

  void _paneDragUpdate(DragUpdateDetails d) {
    _paneCtrl.value =
        (_paneCtrl.value + d.delta.dx / _paneWidth).clamp(0.0, 1.0);
  }

  void _paneDragEnd(DragEndDetails d) {
    final fling = d.velocity.pixelsPerSecond.dx;
    if (fling < -350 || (fling < 350 && _paneCtrl.value < 0.55)) {
      _closePane();
    } else {
      _openPane();
    }
  }

  // ---- Keyboard shortcuts (browser) ---------------------------------------

  /// Shortcuts act on the shell only while nothing is pushed over it.
  bool get _shellOnTop => ModalRoute.of(context)?.isCurrent ?? true;

  void _shortcutSearch() {
    if (!mounted || !_shellOnTop) return;
    _closePane();
    _searchFocus.requestFocus();
  }

  /// The current tab's + / pencil action.
  void _shortcutNew() {
    if (!mounted || !_shellOnTop) return;
    switch (_index) {
      case 0:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NoteEditorScreen(note: Note(), isNew: true),
        ));
      case 1:
        _addLink();
      case 2:
        showCreateBook(context);
      case 3:
        _openNewJournalEntry();
      default:
        _createFolder();
    }
  }

  /// The tab a keyboard step is heading to while the pager is still sliding,
  /// so quick repeated presses each move one more tab.
  int? _steppingTo;

  void _shortcutStepTab(int delta) {
    if (!mounted || !_shellOnTop) return;
    final from = _steppingTo ?? _index;
    final i = (from + delta).clamp(0, 4);
    if (i == from) return;
    _steppingTo = i;
    _selectTab(i);
  }

  void _selectTab(int i) {
    _closePane();
    if (i == _index) {
      // Re-tapping the active tab scrolls its feed back to the top.
      _scrollFeedToTop(i);
      return;
    }
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollFeedToTop(int i) {
    // On the journal, coming "back to the top" also means coming back to
    // the current week after swiping into the past or future.
    if (i == 3) _journalKey.currentState?.resetToToday();
    final c = _feedScrolls[i];
    if (!c.hasClients) return;
    c.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _openSettings() {
    _closePane();
    Navigator.of(context).push(SettingsScreen.route());
  }

  void _openArchive() {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArchiveScreen()),
    );
  }

  void _openTrash() {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecentlyDeletedScreen()),
    );
  }

  void _openSpace(String spaceId) {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SpaceDetailScreen(spaceId: spaceId)),
    );
  }

  /// From the side pane's Home tag list: filter the Home feed to [tag] and show
  /// it (jumps to Home and closes the pane).
  void _openTag(String tag) {
    context.read<AppState>().setActiveTag(tag);
    _selectTab(0);
  }

  void _openJournalYear() {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => JournalYearScreen(year: DateTime.now().year)),
    );
  }

  void _openReflexesShortcut() {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReflexesScreen(date: DateTime.now())),
    );
  }

  void _openPomodoro() {
    _closePane();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PomodoroScreen()),
    );
  }

  Future<void> _addLink() async {
    final url = await showAddLinkDialog(context);
    if (url != null && url.trim().isNotEmpty && mounted) {
      await context.read<AppState>().addCardFromUrl(url.trim());
    }
  }

  Future<void> _createFolder() async {
    final result = await showSpaceEditor(context);
    if (result != null && mounted) {
      await context.read<AppState>().addSpace(result.name,
          thumbnailPath: result.thumbnailPath, colorValue: result.colorValue);
    }
  }

  /// Focus for the top search field (used to dismiss the keyboard on an
  /// outside tap).
  final FocusNode _searchFocus = FocusNode();


  /// Owned here so a back press can drop the search and hand the feed back.
  final TextEditingController _searchCtrl = TextEditingController();

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() => _query = '');
  }

  /// Long-pressing the Home pencil grows a small menu upward out of the button
  /// — new Markdown node, import a file, or a plain new node. Uses the same
  /// frosted-glass surface as the pencil so the chrome stays consistent.
  Future<void> _showCreateMenu(
      BuildContext anchorContext, VoidCallback openNote) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;

    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.05),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) {
        Widget item(String value, IconData icon, String label) => InkWell(
              onTap: () => Navigator.pop(ctx, value),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 22, color: AppPalette.inkPrimary),
                  const SizedBox(width: 14),
                  Text(label,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkPrimary)),
                ]),
              ),
            );
        return Stack(children: [
          Positioned(
            // Right edge lines up with the pencil; bottom sits just above it.
            right: overlay.size.width - anchor.right,
            bottom: overlay.size.height - anchor.top + 10,
            child: FrostedSurface(
              borderRadius: 24,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    item('circuit', Icons.account_tree_rounded,
                        context.t.newCircuit),
                    item('markdown', Icons.data_object_rounded,
                        context.t.newMarkdown),
                    item('import', Icons.upload_file_rounded,
                        context.t.importFile),
                    item('note', Icons.edit_outlined, context.t.newNote),
                  ],
                ),
              ),
            ),
          ),
        ]);
      },
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          // Grow out of the pencil's corner (bottom-right), expanding upward.
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(curved),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case 'circuit':
        _newCircuit();
      case 'markdown':
        _newMarkdown();
      case 'import':
        await _importFile();
      case 'note':
        openNote();
    }
  }

  /// Opens a new, empty first note for a circuit. Like a normal new note it's
  /// only persisted once it gains content or its first branch, so backing out
  /// of an untouched one leaves nothing behind.
  void _newCircuit() {
    final draft = context.read<AppState>().newCircuitRootDraft();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(note: draft, isNew: true),
    ));
  }

  /// Opens a blank Markdown node in its source editor. It only persists once
  /// it has content, so backing out of an empty one leaves nothing behind.
  void _newMarkdown() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          MarkdownNoteScreen(note: Note(markdown: true), isNew: true),
    ));
  }

  /// Picks a `.md`/`.txt` file and imports it as a Markdown node, keeping the
  /// raw markdown as-is, then opens the rendered result.
  Future<void> _importFile() async {
    final picked = await pickOneFile(
        extensions: const ['md', 'markdown', 'txt', 'text']);
    if (picked == null) return;
    String content;
    try {
      content = utf8.decode(picked.bytes);
    } catch (_) {
      return; // Not a readable text file.
    }
    if (content.trim().isEmpty || !mounted) return;
    final note = await context.read<AppState>().addMarkdownNode(content);
    if (!mounted) return;
    _selectTab(0);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MarkdownNoteScreen(note: note),
    ));
  }

  /// Opens a fresh journal entry for [day] (defaults to the journal's selected
  /// day). The plain tap on the journal pencil, and a double-tap on a day.
  void _openNewJournalEntry([DateTime? day]) {
    final date =
        day ?? _journalKey.currentState?.selectedDate ?? DateTime.now();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(
        note: Note(journalDate: AppState.journalKey(date)),
        isNew: true,
      ),
    ));
  }

  /// The journal pencil menu (long-press): add a daily-day task, a new reflex,
  /// or a journal entry for the selected day.
  void _showJournalCompose() {
    final date = _journalKey.currentState?.selectedDate ?? DateTime.now();
    final state = context.read<AppState>();
    final pinned = state.pinnedReflex;
    // The first option adds to whichever reflex is pinned into the feed.
    final addLabel = state.isDailyDay(pinned.id)
        ? context.t.composeDailyTask
        : context.t.addToName(pinned.title.trim().isEmpty
            ? context.t.untitledImpulse
            : pinned.title);
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
                _composeTile(
                  Icons.wb_sunny_rounded,
                  addLabel,
                  () {
                    Navigator.pop(sheetCtx);
                    openNewThread(context, pinned.id, date);
                  },
                ),
                _composeTile(
                  Icons.bolt_rounded,
                  context.t.composeReflex,
                  () {
                    Navigator.pop(sheetCtx);
                    showImpulseEditor(context);
                  },
                ),
                _composeTile(
                  Icons.edit_note_rounded,
                  context.t.composeEntry,
                  () {
                    Navigator.pop(sheetCtx);
                    _openNewJournalEntry(date);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lets the user reorder the journal's three sections (daily-day tasks, the
  /// reflex card, and the diary entries).
  void _showJournalRearrange() {
    final state = context.read<AppState>();
    final order = List<String>.from(state.journalOrder);
    IconData iconFor(String s) => switch (s) {
          'tasks' => Icons.wb_sunny_rounded,
          'card' => Icons.bolt_rounded,
          _ => Icons.auto_stories_outlined,
        };
    String labelFor(String s) => switch (s) {
          'tasks' => context.t.sectionDailyTasks,
          'card' => context.t.sectionReflexCard,
          _ => context.t.sectionDiaryEntries,
        };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassPanel(
              borderRadius: 26,
              strong: true,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t.rearrangeJournal,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 3),
                  Text(context.t.rearrangeJournalHint,
                      style: TextStyle(
                          fontSize: 12.5, color: AppPalette.inkSecondary)),
                  const SizedBox(height: 10),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: (oldI, newI) {
                      setSheet(() {
                        if (newI > oldI) newI -= 1;
                        order.insert(newI, order.removeAt(oldI));
                      });
                      state.setJournalOrder(List.of(order));
                    },
                    children: [
                      for (var i = 0; i < order.length; i++)
                        ListTile(
                          key: ValueKey(order[i]),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(iconFor(order[i]),
                              color: AppPalette.inkPrimary),
                          title: Text(labelFor(order[i]),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppPalette.inkPrimary)),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_handle_rounded,
                                color: AppPalette.inkSecondary),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composeTile(IconData icon, String label, VoidCallback onTap) =>
      ListTile(
        leading: Icon(icon, color: AppPalette.inkPrimary),
        title: Text(label,
            style: TextStyle(
                color: AppPalette.inkPrimary, fontWeight: FontWeight.w600)),
        onTap: onTap,
      );

  /// The universal + button: fixed bottom-right in line with the island; only
  /// its icon and action change with the current tab.
  Widget _fab() {
    final Widget button;
    if (_index == 0) {
      button = GlassMorph(
        key: const ValueKey('fab-note'),
        closedRadius: 34,
        openBuilder: (_) => NoteEditorScreen(note: Note(), isNew: true),
        closedBuilder: (context, open) => BubbleButton(
            icon: Icons.edit_rounded,
            tooltip: context.t.newNote,
            onTap: open,
            onLongPress: () => _showCreateMenu(context, open)),
      );
    } else if (_index == 1) {
      button = BubbleButton(
        key: const ValueKey('fab-link'),
        icon: Icons.add_link_rounded,
        tooltip: context.t.saveALink,
        onTap: _addLink,
      );
    } else if (_index == 2) {
      // Narrative: the button starts a new book.
      button = BubbleButton(
        key: const ValueKey('fab-book'),
        icon: Icons.add_rounded,
        tooltip: context.t.newBook,
        onTap: () => showCreateBook(context),
      );
    } else if (_index == 3) {
      // The pencil opens a bottom-up menu: a daily-day task, a new reflex, or
      // a journal entry for the day.
      // Tap writes a new journal entry; long-press opens the compose menu.
      button = BubbleButton(
        key: const ValueKey('fab-journal'),
        icon: Icons.edit_rounded,
        tooltip: context.t.add,
        onTap: () => _openNewJournalEntry(),
        onLongPress: _showJournalCompose,
      );
    } else {
      button = BubbleButton(
        key: const ValueKey('fab-folder'),
        icon: Icons.create_new_folder_rounded,
        tooltip: context.t.newFolder,
        onTap: _createFolder,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;

    return PopScope(
      // Back closes the drawer, then leaves a search — only then the app.
      canPop: !_paneOpen && !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_paneOpen) {
          _closePane();
        } else if (searching) {
          _clearSearch();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Status icons follow the surface: dark icons on the light theme,
        // light icons on the dark one.
        value: (AppPalette.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent),
        child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        // Any tap outside the search bar dismisses its cursor/keyboard.
        body: Listener(
          onPointerDown: (event) {
            final box =
                _searchKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null || !box.attached) return;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            if (!rect.contains(event.position)) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          child: Stack(
          children: [
            // Plain base so nothing bleeds through the drawer's rounded edge.
            const Positioned.fill(child: AppBackground()),
            // The drawer lives UNDER the screen (old-Discord push style): it
            // slides in from the left with a slight parallax while the whole
            // screen above it is pushed right by the drawer's width.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _paneWidth,
              child: AnimatedBuilder(
                animation: _paneCtrl,
                builder: (context, child) {
                  final v = _paneCtrl.value;
                  if (v == 0) return const SizedBox.shrink();
                  return Transform.translate(
                    offset: Offset(-_paneWidth * 0.3 * (1 - v), 0),
                    child: child,
                  );
                },
                child: GestureDetector(
                  onHorizontalDragUpdate: _paneDragUpdate,
                  onHorizontalDragEnd: _paneDragEnd,
                  child: SidePane(
                    currentIndex: _index,
                    onSelectTab: _selectTab,
                    onOpenSettings: _openSettings,
                    onOpenArchive: _openArchive,
                    onOpenTrash: _openTrash,
                    onOpenSpace: _openSpace,
                    onOpenTag: _openTag,
                    onOpenJournalYear: _openJournalYear,
                    onOpenReflexes: _openReflexesShortcut,
                    onOpenPomodoro: _openPomodoro,
                    onClose: _closePane,
                  ),
                ),
              ),
            ),
            // The main screen: everything (background, feed, island, fab)
            // slides right together, leaving the left two thirds to the
            // drawer.
            AnimatedBuilder(
              animation: _paneCtrl,
              builder: (context, child) {
                final v = _paneCtrl.value;
                final content = Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    // Dim the pushed screen and catch its taps/drags while
                    // the drawer is out.
                    if (v > 0)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closePane,
                          onHorizontalDragUpdate: _paneDragUpdate,
                          onHorizontalDragEnd: _paneDragEnd,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.22 * v),
                          ),
                        ),
                      ),
                  ],
                );
                // The pushed screen curls its corners in as it slides out,
                // like a lifted card. The radius reaches its full 24 within
                // the first sixth of the slide — tying it 1:1 to the slide
                // left a square grey corner flashing against the light
                // drawer early in the animation. The ClipRRect must ALWAYS
                // wrap the content (zero radius only at rest): swapping it
                // in and out changes the tree shape, which remounts the
                // feeds and silently resets the PageView to the first tab.
                return Transform.translate(
                  offset: Offset(_paneWidth * v, 0),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(24 * (v * 6).clamp(0.0, 1.0)),
                    child: content,
                  ),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned.fill(
                      child: AppBackground(wallpaper: true)),
                  // Feeds reach the top of the screen now; each opens with
                  // its big greeting instead of a title header.
                  Stack(
                    children: [
                      PageView(
                        controller: _pageController,
                        physics: const _SpringPagePhysics(),
                        // In a browser the mouse can swipe between tabs too.
                        scrollBehavior: PlatformCaps.current.isWeb
                            ? ScrollConfiguration.of(context).copyWith(
                                dragDevices: PointerDeviceKind.values.toSet())
                            : null,
                        onPageChanged: (i) => setState(() {
                          _index = i;
                          if (_steppingTo == i) _steppingTo = null;
                        }),
                        children: [
                          _KeepAlive(
                              child:
                                  HomeScreen(controller: _feedScrolls[0])),
                          _KeepAlive(
                              child:
                                  CardsScreen(controller: _feedScrolls[1])),
                          _KeepAlive(
                              child:
                                  BooksScreen(controller: _feedScrolls[2])),
                          _KeepAlive(
                              child: JournalScreen(
                                  key: _journalKey,
                                  controller: _feedScrolls[3])),
                          _KeepAlive(
                              child:
                                  SpacesScreen(controller: _feedScrolls[4])),
                        ],
                      ),
                      if (searching)
                        Positioned.fill(
                          // Keeps the wallpaper: results replace the feed,
                          // not the backdrop.
                          child: AppBackground(
                            wallpaper: true,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  top: MediaQuery.of(context).padding.top +
                                      78),
                              child: UniversalSearchResults(query: _query),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Status-bar scrim: the clock stays readable over tiles
                  // scrolling beneath it.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: TopScrimFade(
                        height: MediaQuery.of(context).padding.top + 8),
                  ),
                  // The fixed menu + search + sort + account bar.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: KeyedSubtree(
                          key: _searchKey,
                          child: FloatingTopBar(
                            onMenu: _openPane,
                            onQueryChanged: _onSearchChanged,
                            focusNode: _searchFocus,
                            controller: _searchCtrl,
                            // Sort applies to notes, cards and the folder
                            // grid — not the book shelf or the journal.
                            showSort: _index != 2 && _index != 3,
                            // The journal swaps sort for a rearrange control.
                            onRearrange:
                                _index == 3 ? _showJournalRearrange : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Floating island nav + the universal action bubble,
                  // centred as one group.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Five tabs plus the action bubble is a lot for
                            // a narrow phone: let the island shrink to fit
                            // rather than overflow.
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: IslandNav(
                                    currentIndex: _index, onTap: _selectTab),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _fab(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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

/// Keeps a swipeable page alive so its state (scroll position) survives.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
