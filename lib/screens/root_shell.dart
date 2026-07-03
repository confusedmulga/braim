import 'dart:async';

import 'package:flutter/material.dart';
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

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _paneOpen = false;
  String _query = '';
  final _pageController = PageController();
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initShareIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The share popup writes to the data file from its own engine; re-read on
    // resume so links saved while we were backgrounded show up.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppState>().init();
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
        const SnackBar(content: Text('Saved to Cards')),
      );
    }
  }

  void _openPane() => setState(() => _paneOpen = true);
  void _closePane() => setState(() => _paneOpen = false);

  void _selectTab(int i) {
    _closePane();
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
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

  static const _titles = ['Home', 'Cards', 'Cortex'];
  static const _subtitles = [
    'Your notes',
    'Tweets & links you saved',
    'Folders for notes & cards',
  ];

  Widget _topBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
        child: Row(
          children: [
            GlassBubble(
              icon: Icons.menu_rounded,
              onTap: _openPane,
              size: 46,
              iconSize: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[_index],
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                  Text(
                    _subtitles[_index],
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppPalette.inkSecondary,
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

  /// The universal + button: fixed bottom-right in line with the island; only
  /// its icon and action change with the current tab.
  Widget _fab() {
    final Widget button;
    if (_index == 0) {
      button = GlassMorph(
        key: const ValueKey('fab-note'),
        closedRadius: 34,
        openBuilder: (_) => NoteEditorScreen(note: Note(), isNew: true),
        closedBuilder: (context, open) =>
            BubbleButton(icon: Icons.edit_rounded, onTap: open),
      );
    } else if (_index == 1) {
      button = BubbleButton(
        key: const ValueKey('fab-link'),
        icon: Icons.add_link_rounded,
        onTap: _addLink,
      );
    } else {
      button = BubbleButton(
        key: const ValueKey('fab-folder'),
        icon: Icons.create_new_folder_rounded,
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const Positioned.fill(child: AppBackground()),
            Column(
              children: [
                _topBar(),
                SearchField(
                  hint: 'Search notes, cards, cortex',
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  // Content dissolves upward under the header instead of
                  // clipping hard against it.
                  child: TopFade(
                    child: Stack(
                      children: [
                        PageView(
                          controller: _pageController,
                          physics: const _SpringPagePhysics(),
                          onPageChanged: (i) => setState(() => _index = i),
                          children: const [
                            _KeepAlive(child: HomeScreen()),
                            _KeepAlive(child: CardsScreen()),
                            _KeepAlive(child: SpacesScreen()),
                          ],
                        ),
                        if (searching)
                          Positioned.fill(
                            child: AppBackground(
                              child: UniversalSearchResults(query: _query),
                            ),
                          ),
                      ],
                    ),
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
            // Scrim behind the side pane.
            IgnorePointer(
              ignoring: !_paneOpen,
              child: GestureDetector(
                onTap: _closePane,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _paneOpen ? 1 : 0,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
            ),
            // The side pane itself.
            AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: _paneOpen ? Offset.zero : const Offset(-1.1, 0),
              child: Align(
                alignment: Alignment.centerLeft,
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
          ],
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
