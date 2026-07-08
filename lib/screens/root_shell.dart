import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bubble_button.dart';
import '../widgets/glass.dart';
import '../widgets/glass_bubble.dart';
import '../widgets/glass_morph.dart';
import '../widgets/island_nav.dart';
import '../widgets/search_field.dart';
import '../widgets/side_pane.dart';
import '../widgets/sort_button.dart';
import '../widgets/tutorial_dialog.dart';
import '../widgets/universal_search.dart';
import 'archive_screen.dart';
import 'cards_screen.dart';
import 'home_screen.dart';
import 'note_editor_screen.dart';
import 'recently_deleted_screen.dart';
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
    ScrollController(),
    ScrollController(),
    ScrollController(),
  ];

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
    _initShareIntent();
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
    _shareSub?.cancel();
    _searchDebounce?.cancel();
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
    // The share popup writes to the data file from its own engine; re-read on
    // resume so links saved while we were backgrounded show up.
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().init();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Backgrounding: make sure coalesced edits reach disk.
      context.read<AppState>().flushNow();
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
    var added = false;
    for (final f in files) {
      final match = RegExp(r'https?://\S+').firstMatch(f.path);
      if (match != null) {
        await state.addCardFromUrl(match.group(0)!);
        added = true;
      }
    }
    if (added && mounted) {
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

  Future<void> _addLink() async {
    final url = await showAddLinkDialog(context);
    if (url != null && url.trim().isNotEmpty && mounted) {
      await context.read<AppState>().addCardFromUrl(url.trim());
    }
  }

  Future<void> _createFolder() async {
    final result = await showSpaceEditor(context);
    if (result != null && mounted) {
      await context
          .read<AppState>()
          .addSpace(result.name, thumbnailPath: result.thumbnailPath);
    }
  }

  Widget _topBar() {
    final titles = [context.t.tabHome, context.t.tabCards, context.t.tabCortex];
    final subtitles = [
      context.t.subtitleHome,
      context.t.subtitleCards,
      context.t.subtitleCortex,
    ];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
        child: Row(
          children: [
            GlassBubble(
              icon: Icons.menu_rounded,
              tooltip: context.t.menu,
              onTap: _openPane,
              size: 46,
              iconSize: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _scrollFeedToTop(_index),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titles[_index],
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                  Text(
                    subtitles[_index],
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            icon: Icons.edit_rounded, tooltip: context.t.newNote, onTap: open),
      );
    } else if (_index == 1) {
      button = BubbleButton(
        key: const ValueKey('fab-link'),
        icon: Icons.add_link_rounded,
        tooltip: context.t.saveALink,
        onTap: _addLink,
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
      canPop: !_paneOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _paneOpen) _closePane();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light
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
            const Positioned.fill(child: AppBackground()),
            Column(
              children: [
                _topBar(),
                KeyedSubtree(
                  key: _searchKey,
                  child: SearchField(
                    hint: context.t.searchHint,
                    onChanged: _onSearchChanged,
                    // Sort applies to the notes and cards feeds, not folders.
                    trailing: _index == 2 ? null : const SortButton(),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Content dissolves upward under the header instead of
                      // clipping hard against it.
                      TopFade(
                        child: Stack(
                          children: [
                            PageView(
                              controller: _pageController,
                              physics: const _SpringPagePhysics(),
                              onPageChanged: (i) =>
                                  setState(() => _index = i),
                              children: [
                                _KeepAlive(
                                    child: HomeScreen(
                                        controller: _feedScrolls[0])),
                                _KeepAlive(
                                    child: CardsScreen(
                                        controller: _feedScrolls[1])),
                                _KeepAlive(
                                    child: SpacesScreen(
                                        controller: _feedScrolls[2])),
                              ],
                            ),
                            if (searching)
                              Positioned.fill(
                                child: AppBackground(
                                  child:
                                      UniversalSearchResults(query: _query),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // The cards Open/Blocks toggle floats fixed in the fade
                      // zone (outside the mask so it never dims), always
                      // available while the feed scrolls beneath it.
                      Positioned(
                        top: 2,
                        right: 18,
                        child: IgnorePointer(
                          ignoring: _index != 1 || searching,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: (_index == 1 && !searching) ? 1 : 0,
                            child: Selector<AppState, bool>(
                              selector: (_, s) => s.cardsCompact,
                              builder: (context, compact, _) =>
                                  CardsViewToggle(
                                compact: compact,
                                onChanged: (v) => context
                                    .read<AppState>()
                                    .setCardsCompact(v),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Floating island nav + the universal action bubble, centred as
            // one group.
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IslandNav(currentIndex: _index, onTap: _selectTab),
                      const SizedBox(width: 12),
                      _fab(),
                    ],
                  ),
                ),
              ),
            ),
            // Scrim + side pane, driven by one controller so the pane can
            // be dragged closed with a finger and settles from wherever it
            // was released.
            AnimatedBuilder(
              animation: _paneCtrl,
              builder: (context, _) {
                final v = _paneCtrl.value;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (v > 0)
                      GestureDetector(
                        onTap: _closePane,
                        child: Container(
                            color:
                                Colors.black.withValues(alpha: 0.35 * v)),
                      ),
                    FractionalTranslation(
                      translation: Offset(-1.1 * (1 - v), 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) {
                            // The pane travels 1.1 screen-widths, so scale
                            // the finger delta to keep it tracking 1:1.
                            final travel =
                                MediaQuery.of(context).size.width * 1.1;
                            _paneCtrl.value = (_paneCtrl.value +
                                    d.delta.dx / travel)
                                .clamp(0.0, 1.0);
                          },
                          onHorizontalDragEnd: (d) {
                            final fling = d.velocity.pixelsPerSecond.dx;
                            if (fling < -350 ||
                                (fling < 350 && _paneCtrl.value < 0.55)) {
                              _closePane();
                            } else {
                              _openPane();
                            }
                          },
                          child: SidePane(
                            currentIndex: _index,
                            onSelectTab: _selectTab,
                            onOpenSettings: _openSettings,
                            onOpenArchive: _openArchive,
                            onOpenTrash: _openTrash,
                            onOpenSpace: _openSpace,
                            onClose: _closePane,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
