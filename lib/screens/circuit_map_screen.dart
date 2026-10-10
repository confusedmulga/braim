import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/circuit_layout.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/circuit_sheets.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/note_background.dart';
import '../widgets/text_prompt.dart';
import 'note_open.dart';

/// The pop result a note screen hands back to the map: re-centre on [nodeId],
/// and pulse it when [highlight] is set.
class CircuitMapFocus {
  const CircuitMapFocus(this.nodeId, {this.highlight = false});
  final String nodeId;
  final bool highlight;
}

/// The pop result of a note screen opened from the map when a link in it
/// leads to another note: the map opens [noteId] in its place, so back from
/// that note returns to the map too.
class CircuitMapOpenNote {
  const CircuitMapOpenNote(this.noteId);
  final String noteId;
}

enum _PickKind { move, fill }

/// An in-progress "tap where to move" interaction on the map.
class _PickState {
  const _PickState(this.kind, this.subjectId, this.title);
  final _PickKind kind;
  final String subjectId; // the node being moved, or the placeholder to fill
  final String title;
}

/// The full-screen circuit map (left-to-right layout). Pan, pinch-zoom, fit,
/// centre on a node, tap to open, long-press for the node/placeholder sheet,
/// and a **+** on each node to add a child. Structural edits animate.
class CircuitMapScreen extends StatefulWidget {
  const CircuitMapScreen({
    super.key,
    required this.circuitId,
    this.focusNodeId,
    this.highlight = false,
    this.openedFromNoteId,
  });

  final String circuitId;
  final String? focusNodeId;
  final bool highlight;

  /// The note whose screen opened this map, or null when it was opened from
  /// elsewhere (Home, after importing a circuit). Back returns to that screen
  /// while it is still open underneath; otherwise it lands on the circuit's
  /// first note, so back always reads map → first note → where you started.
  final String? openedFromNoteId;

  @override
  State<CircuitMapScreen> createState() => _CircuitMapScreenState();
}

class _CircuitMapScreenState extends State<CircuitMapScreen>
    with TickerProviderStateMixin {
  final _tc = TransformationController();
  Size? _viewport;
  bool _didInitialView = false;
  String? _focusId;
  bool _highlight = false;
  _PickState? _pick;

  /// Nodes whose subtree is collapsed (hidden on the map). In-memory: the map
  /// opens fully expanded. Bump [_collapsedRev] on every change.
  final Set<String> _collapsed = {};
  int _collapsedRev = 0;

  // The layout and the node lookup, cached for one library revision and one
  // collapse state — every build (and every animation frame) reuses them
  // instead of re-scanning the library.
  CircuitLayout? _layout;
  Map<String, Note> _nodes = const {};
  int _layoutRev = -1;
  int _layoutCollapsedRev = -1;
  CircuitLayout? _sigLayout;

  /// Set once the map has started closing itself, so it never pops twice.
  bool _leaving = false;

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  AnimationController? _moveCtrl;

  // Layout-change animation: the displayed rects glide from the old layout to
  // the new one over 250ms; nodes and edges are drawn from the same rects so
  // the branch lines never detach.
  late final AnimationController _layoutCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250));
  Map<String, Rect> _shownRects = {};
  Map<String, Rect> _fromRects = {};
  CircuitLayout? _target;
  String _sig = '';

  @override
  void initState() {
    super.initState();
    _focusId = widget.focusNodeId;
    _highlight = widget.highlight;
    _layoutCtrl.addListener(_onLayoutTick);
    _layoutCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && _target != null && mounted) {
        setState(() => _shownRects = Map.of(_target!.rects));
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _moveCtrl?.dispose();
    _layoutCtrl.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _onLayoutTick() {
    final target = _target;
    if (target == null) return;
    final t = Curves.easeOutCubic.transform(_layoutCtrl.value);
    final next = <String, Rect>{};
    target.rects.forEach((id, to) {
      final from = _fromRects[id] ?? to;
      next[id] = Rect.lerp(from, to, t) ?? to;
    });
    setState(() => _shownRects = next);
  }

  /// The circuit's layout, rebuilt only when the library or the collapse state
  /// has changed since the last call.
  CircuitLayout _layoutFor(AppState state) {
    final cached = _layout;
    if (cached != null &&
        _layoutRev == state.revision &&
        _layoutCollapsedRev == _collapsedRev) {
      return cached;
    }
    final root = state.noteById(widget.circuitId);
    final mode = _modeFromString(root?.circuitLayout ?? 'ltr');
    final nodes = state.circuitNodes(widget.circuitId);
    final children = <String, List<String>>{};
    for (final n in nodes) {
      children[n.id] = state.circuitChildren(n.id).map((c) => c.id).toList();
    }
    _nodes = {for (final n in nodes) n.id: n};
    _layoutRev = state.revision;
    _layoutCollapsedRev = _collapsedRev;
    return _layout = layoutCircuit(
      rootId: widget.circuitId,
      children: children,
      collapsed: _collapsed,
      mode: mode,
    );
  }

  /// Expands every collapsed node above [id], so [id] is on the map. Returns
  /// whether anything changed (the caller then rebuilds).
  bool _revealNode(String id) {
    var changed = false;
    for (final n in context.read<AppState>().circuitPath(id)) {
      if (n.id != id && _collapsed.remove(n.id)) changed = true;
    }
    if (changed) _collapsedRev++;
    return changed;
  }

  /// Closes the map once its circuit is gone — deleted here, or from a note
  /// screen opened on top of it. Removes only this map's own route (even when
  /// another screen still covers it), and only once.
  void _leaveMap() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else if (route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  static CircuitLayoutMode _modeFromString(String s) => switch (s) {
        'ttb' => CircuitLayoutMode.ttb,
        'radial' => CircuitLayoutMode.radial,
        _ => CircuitLayoutMode.ltr,
      };

  static String _modeToString(CircuitLayoutMode m) => switch (m) {
        CircuitLayoutMode.ltr => 'ltr',
        CircuitLayoutMode.ttb => 'ttb',
        CircuitLayoutMode.radial => 'radial',
      };

  static CircuitLayoutMode _nextMode(CircuitLayoutMode m) => switch (m) {
        CircuitLayoutMode.ltr => CircuitLayoutMode.ttb,
        CircuitLayoutMode.ttb => CircuitLayoutMode.radial,
        CircuitLayoutMode.radial => CircuitLayoutMode.ltr,
      };

  Future<void> _cycleLayout() async {
    final state = context.read<AppState>();
    final root = state.noteById(widget.circuitId);
    if (root == null) return;
    final next = _nextMode(_modeFromString(root.circuitLayout));
    await state.setCircuitLayout(widget.circuitId, _modeToString(next));
    if (!mounted) return;
    // The nodes glide via the layout-change animation; refit the viewport too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToScreen();
    });
  }

  IconData _layoutIcon(CircuitLayoutMode mode) => switch (mode) {
        CircuitLayoutMode.ltr => Icons.account_tree_rounded,
        CircuitLayoutMode.ttb => Icons.schema_rounded,
        CircuitLayoutMode.radial => Icons.hub_rounded,
      };

  String _layoutTooltip(CircuitLayoutMode mode) => switch (mode) {
        CircuitLayoutMode.ltr => context.t.circuitLayoutLtr,
        CircuitLayoutMode.ttb => context.t.circuitLayoutTtb,
        CircuitLayoutMode.radial => context.t.circuitLayoutRadial,
      };

  /// The centre of a node's + button for the given [rect] — mode-aware, so it
  /// follows the node during the layout-change animation.
  Offset _plusAnchorFor(CircuitLayout layout, Rect rect, String id) {
    final dir = layout.outward(id);
    final hw = layout.metrics.nodeW / 2;
    final hh = layout.metrics.nodeH / 2;
    final ax = dir.dx.abs();
    final ay = dir.dy.abs();
    final reach = ax < 1e-9
        ? hh
        : (ay < 1e-9 ? hw : math.min(hw / ax, hh / ay));
    return rect.center + dir * (reach + CircuitLayout.plusReach);
  }

  String _layoutSig(CircuitLayout layout) {
    final b = StringBuffer();
    final ids = layout.rects.keys.toList()..sort();
    for (final id in ids) {
      final r = layout.rects[id]!;
      b.write('$id:${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)};');
    }
    return b.toString();
  }

  // ---- Viewport maths -----------------------------------------------------

  Rect _contentBounds(CircuitLayout layout) {
    if (layout.rects.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final rect in layout.rects.values) {
      l = math.min(l, rect.left);
      t = math.min(t, rect.top);
      r = math.max(r, rect.right);
      b = math.max(b, rect.bottom);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Matrix4 _centreMatrix(Offset centre, Size vp, double scale) {
    final m = Matrix4.identity();
    m.setEntry(0, 0, scale);
    m.setEntry(1, 1, scale);
    m.setEntry(0, 3, vp.width / 2 - centre.dx * scale);
    m.setEntry(1, 3, vp.height / 2 - centre.dy * scale);
    return m;
  }

  Matrix4 _fitMatrix(CircuitLayout layout, Size vp) {
    final bounds = _contentBounds(layout);
    final raw =
        0.9 * math.min(vp.width / bounds.width, vp.height / bounds.height);
    final scale = raw.clamp(0.15, 1.0).toDouble();
    return _centreMatrix(bounds.center, vp, scale);
  }

  double _currentScale() => _tc.value.getMaxScaleOnAxis();

  void _animateTo(Matrix4 target) {
    _moveCtrl?.dispose();
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _moveCtrl = ctrl;
    final anim = Matrix4Tween(begin: _tc.value, end: target)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));
    anim.addListener(() => _tc.value = anim.value);
    ctrl.forward();
  }

  void _fitToScreen() {
    final vp = _viewport;
    if (vp == null) return;
    _animateTo(_fitMatrix(_layoutFor(context.read<AppState>()), vp));
  }

  void _focusOn(String id, {required bool highlight}) {
    final vp = _viewport;
    if (vp == null) return;
    // A node added or moved under a collapsed branch must not vanish: open
    // the branches above it first.
    _revealNode(id);
    final layout = _layoutFor(context.read<AppState>());
    final rect = layout.rects[id];
    if (rect == null) return;
    final scale = _currentScale().clamp(0.15, 1.0).toDouble();
    _animateTo(_centreMatrix(rect.center, vp, scale));
    setState(() {
      _focusId = id;
      _highlight = highlight;
    });
    if (highlight) _pulse.forward(from: 0);
  }

  // ---- Node interactions --------------------------------------------------

  bool _bodyEmpty(Note note) {
    if (note.markdown) {
      final lines = note.markdownSource
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      return lines.length <= 1; // only the "# heading" title line
    }
    return note.blocks
        .every((b) => !b.isText || richToPlain(b.text).trim().isEmpty);
  }

  String _noteTitleFmt(int n) => context.t.circuitNoteTitle(n);

  String _displayTitle(Note note) {
    final t = note.title.trim();
    if (t.isNotEmpty) return t;
    return note.isCircuitRoot ? context.t.untitledCircuit : context.t.untitledNote;
  }

  void _tapNode(String id) {
    final note = context.read<AppState>().noteById(id);
    if (note == null) return;
    if (note.circuitPlaceholder) {
      _showSlotSheet(id);
    } else {
      _openNode(id);
    }
  }

  void _longPressNode(String id) {
    final note = context.read<AppState>().noteById(id);
    if (note == null) return;
    if (note.circuitPlaceholder) {
      _showSlotSheet(id);
    } else {
      _showNodeSheet(id);
    }
  }

  Future<void> _openNode(String id) async {
    final state = context.read<AppState>();
    final note = state.noteById(id);
    if (note == null || note.circuitPlaceholder) return;
    final navigator = Navigator.of(context);
    // Its screen may already be open under the map (usually the first note,
    // which the map was opened from). Going back down to it would close the
    // map; instead it comes out from under the map and opens on top, so back
    // returns here like any other note. Never two screens on one note: the
    // one underneath saved itself before the map opened, and is removed
    // before the new one is built.
    final below = OpenNoteScreens.routeFor(note.id);
    if (below != null && identical(below.navigator, navigator)) {
      navigator.removeRoute(below);
    }
    // A note reached through a link may sit outside any circuit; it still
    // comes back here. One in another circuit keeps its own map button.
    final fromHere =
        note.circuitId == null || note.circuitId == widget.circuitId;
    final result = await navigator.push<Object?>(
      MaterialPageRoute(
        builder: (_) => noteScreen(note,
            fromCircuitMap: fromHere, startEditing: _bodyEmpty(note)),
      ),
    );
    if (!mounted) return;
    if (result is CircuitMapFocus) {
      _focusOn(result.nodeId, highlight: result.highlight);
    } else if (result is CircuitMapOpenNote) {
      // A link followed in that note: open its target from here instead of
      // on top of it, so back always lands on the map.
      await _openNode(result.noteId);
    } else {
      setState(() {});
    }
  }

  Future<void> _addChild(String parentId) async {
    final state = context.read<AppState>();
    final created = await state.addCircuitChild(parentId, noteTitle: _noteTitleFmt);
    if (!mounted) return;
    _focusOn(created.id, highlight: true);
  }

  Future<void> _showNodeSheet(String id) async {
    final state = context.read<AppState>();
    final note = state.noteById(id);
    if (note == null) return;
    var canUp = false, canDown = false, canIndent = false, canOutdent = false;
    if (note.isCircuitNode) {
      final sibs = state.circuitChildren(note.circuitParentId!);
      final idx = sibs.indexWhere((s) => s.id == id);
      canUp = idx > 0;
      canDown = idx >= 0 && idx < sibs.length - 1;
      canIndent = idx > 0;
      final parent = state.noteById(note.circuitParentId!);
      canOutdent = parent != null && parent.circuitParentId != null;
    }
    final action = await showCircuitNodeSheet(context,
        note: note,
        canMoveUp: canUp,
        canMoveDown: canDown,
        canIndent: canIndent,
        canOutdent: canOutdent,
        hasChildren: state.circuitChildren(id).isNotEmpty,
        collapsed: _collapsed.contains(id));
    if (action == null || !mounted) return;
    await _handleNodeAction(action, id);
  }

  Future<void> _handleNodeAction(CircuitNodeAction action, String id) async {
    final state = context.read<AppState>();
    final note = state.noteById(id);
    if (note == null) return;
    switch (action) {
      case CircuitNodeAction.open:
        await _openNode(id);
      case CircuitNodeAction.rename:
        final title = await promptForText(context,
            title: context.t.circuitRename, initial: note.title);
        if (title != null && mounted) {
          await state.renameCircuitNode(id, title.trim());
        }
      case CircuitNodeAction.toggleCollapse:
        setState(() {
          if (!_collapsed.remove(id)) _collapsed.add(id);
          _collapsedRev++;
        });
      case CircuitNodeAction.colour:
        await showNoteStylePicker(
          context,
          currentColor: note.colorValue,
          onColor: (v) => state.setCircuitNodeColor(id, v),
        );
      case CircuitNodeAction.moveUp:
        await state.moveCircuitNode(id, -1);
      case CircuitNodeAction.moveDown:
        await state.moveCircuitNode(id, 1);
      case CircuitNodeAction.indent:
        await state.indentCircuitNode(id);
        // Indenting under a collapsed sibling would hide the node — open it.
        if (mounted && _revealNode(id)) setState(() {});
      case CircuitNodeAction.outdent:
        await state.outdentCircuitNode(id);
      case CircuitNodeAction.moveTo:
        setState(() => _pick =
            _PickState(_PickKind.move, id, _displayTitle(note)));
      case CircuitNodeAction.addSibling:
        final c = await state.addCircuitSibling(id, noteTitle: _noteTitleFmt);
        if (mounted) _focusOn(c.id, highlight: true);
      case CircuitNodeAction.addChild:
        final c = await state.addCircuitChild(id, noteTitle: _noteTitleFmt);
        if (mounted) _focusOn(c.id, highlight: true);
      case CircuitNodeAction.addChildMarkdown:
        final c = await state.addCircuitChild(id,
            markdown: true, noteTitle: _noteTitleFmt);
        if (mounted) _focusOn(c.id, highlight: true);
      case CircuitNodeAction.addExisting:
        await _placeExisting(id);
      case CircuitNodeAction.toggleFeed:
        await state.setCircuitShowInFeed(id, !note.circuitShowInFeed);
      case CircuitNodeAction.remove:
        await state.removeFromCircuit(id);
      case CircuitNodeAction.delete:
        await _deleteNode(id);
    }
  }

  Future<void> _placeExisting(String parentId) async {
    final state = context.read<AppState>();
    final notes = state.notesPlaceableInCircuit();
    final chosen = await showCircuitExistingNotePicker(context, notes: notes);
    if (chosen == null || !mounted) return;
    final ok = await state.placeNoteInCircuit(chosen, parentId);
    if (ok && mounted) _focusOn(chosen, highlight: true);
  }

  Future<void> _deleteNode(String id) async {
    final note = context.read<AppState>().noteById(id);
    if (note == null) return;
    // Deleting the first note trashes the circuit; the build then sees it and
    // closes the map (_leaveMap).
    await confirmAndDeleteCircuitNote(context, note);
  }

  // ---- Placeholder sheet --------------------------------------------------

  Future<void> _showSlotSheet(String id) async {
    final state = context.read<AppState>();
    final slot = state.noteById(id);
    if (slot == null || !slot.circuitPlaceholder) return;
    final action = await showCircuitSlotSheet(context, placeholder: slot);
    if (action == null || !mounted) return;
    switch (action) {
      case CircuitSlotAction.writeNote:
        final n = await state.writeIntoPlaceholder(id, noteTitle: _noteTitleFmt);
        if (mounted) _openNode(n.id);
      case CircuitSlotAction.writeMarkdown:
        final n = await state.writeIntoPlaceholder(id,
            markdown: true, noteTitle: _noteTitleFmt);
        if (mounted) _openNode(n.id);
      case CircuitSlotAction.placeExisting:
        final notes = state.notesPlaceableInCircuit();
        final chosen =
            await showCircuitExistingNotePicker(context, notes: notes);
        if (chosen != null && mounted) {
          final ok = await state.fillPlaceholder(id, chosen);
          if (ok && mounted) _focusOn(chosen, highlight: true);
        }
      case CircuitSlotAction.moveHere:
        setState(() => _pick = _PickState(_PickKind.fill, id, ''));
      case CircuitSlotAction.remove:
        await state.deletePlaceholder(id);
    }
  }

  // ---- Pick mode ----------------------------------------------------------

  bool _isValidTarget(AppState state, String targetId) {
    final pick = _pick;
    if (pick == null) return true;
    final target = state.noteById(targetId);
    if (target == null) return false;
    if (pick.kind == _PickKind.move) {
      if (targetId == pick.subjectId) return false;
      if (state.isCircuitAncestor(pick.subjectId, targetId)) return false;
      return true; // a normal node or a placeholder (which it would fill)
    } else {
      if (targetId == pick.subjectId) return false;
      if (target.isCircuitRoot || target.circuitPlaceholder) return false;
      if (state.isCircuitAncestor(targetId, pick.subjectId)) return false;
      return true;
    }
  }

  Future<void> _handlePickTap(String targetId) async {
    final pick = _pick;
    if (pick == null) return;
    final state = context.read<AppState>();
    if (!_isValidTarget(state, targetId)) return;
    bool ok;
    String focusId;
    if (pick.kind == _PickKind.move) {
      final target = state.noteById(targetId);
      if (target != null && target.circuitPlaceholder) {
        ok = await state.fillPlaceholder(targetId, pick.subjectId);
      } else {
        ok = await state.moveCircuitNodeTo(pick.subjectId, targetId);
      }
      focusId = pick.subjectId;
    } else {
      ok = await state.fillPlaceholder(pick.subjectId, targetId);
      focusId = targetId;
    }
    if (!mounted) return;
    setState(() => _pick = null);
    if (ok) _focusOn(focusId, highlight: false);
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final root = state.noteById(widget.circuitId);
    // A trashed circuit is still found by id — close on that too, or the map
    // would keep editing a circuit that is in Recently Deleted.
    if (root == null || !root.isCircuitRoot || root.deletedAt != null) {
      _leaveMap();
      return const SizedBox.shrink();
    }
    final title = _displayTitle(root);
    final layout = _layoutFor(state);

    // Drive the layout-change animation off a positional signature, checked
    // only when the (cached) layout itself has changed.
    if (!identical(layout, _sigLayout)) {
      _sigLayout = layout;
      final sig = _layoutSig(layout);
      if (sig != _sig) {
        _sig = sig;
        if (_shownRects.isEmpty) {
          _shownRects = Map.of(layout.rects);
        } else {
          _fromRects = Map.of(_shownRects);
          _target = layout;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _layoutCtrl.forward(from: 0);
          });
        }
      }
    }
    final rects = _shownRects.isEmpty ? layout.rects : _shownRects;
    final validTargets = _pick == null
        ? const <String>{}
        : {
            for (final id in layout.rects.keys)
              if (_isValidTarget(state, id)) id
          };

    final map = FrostedScaffold(
      title: title,
      // The first note's title can be long; it drifts so all of it shows.
      scrollingTitle: true,
      bodyUnderChrome: true,
      onBack: _pick != null ? () => setState(() => _pick = null) : null,
      actions: [
        FrostedCircleButton(
          icon: _layoutIcon(layout.mode),
          tooltip: _layoutTooltip(layout.mode),
          onTap: _cycleLayout,
        ),
        FrostedCircleButton(
          icon: Icons.fit_screen_rounded,
          tooltip: context.t.circuitFit,
          onTap: _fitToScreen,
        ),
      ],
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final vp = Size(constraints.maxWidth, constraints.maxHeight);
              _viewport = vp;
              if (!_didInitialView) {
                _didInitialView = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final focus = _focusId;
                  final m = (focus != null && layout.rects.containsKey(focus))
                      ? _centreMatrix(layout.rects[focus]!.center, vp, 1.0)
                      : _fitMatrix(layout, vp);
                  _tc.value = m;
                  if (_highlight && focus != null) _pulse.forward(from: 0);
                });
              }
              return InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.15,
                maxScale: 2.5,
                child: SizedBox.fromSize(
                  size: layout.canvasSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _EdgePainter(
                                rects,
                                layout.edges,
                                layout.mode,
                                AppPalette.inkSecondary.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                      for (final id in layout.rects.keys)
                        Positioned.fromRect(
                          rect: rects[id] ?? layout.rects[id]!,
                          child: _NodeChip(
                            note: _nodes[id],
                            focused: _focusId == id && _pick == null,
                            highlight: _highlight,
                            pulse: _pulse,
                            collapsedCount: _collapsed.contains(id)
                                ? state.circuitChildren(id).length
                                : 0,
                            dimmed: _pick != null && !validTargets.contains(id),
                            onTap: _pick != null
                                ? (validTargets.contains(id)
                                    ? () => _handlePickTap(id)
                                    : null)
                                : () => _tapNode(id),
                            onLongPress:
                                _pick != null ? null : () => _longPressNode(id),
                          ),
                        ),
                      if (_pick == null)
                        for (final id in layout.rects.keys)
                          if (!(_nodes[id]?.circuitPlaceholder ?? true) &&
                              !_collapsed.contains(id))
                            _plusButton(rects, layout, id),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_pick != null) _pickBanner(),
        ],
      ),
    );
    // Back first cancels a pick in progress. Then it returns to the note that
    // opened the map while that is still underneath, or else lands on the
    // first note (_backToFirstNote).
    return PopScope(
      canPop: _pick == null && _openerBelow,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_pick != null) {
          setState(() => _pick = null);
        } else {
          _backToFirstNote();
        }
      },
      child: map,
    );
  }

  /// Whether the note screen that opened this map is still open under it
  /// (not taken out by [_openNode] to reopen above).
  bool get _openerBelow {
    final id = widget.openedFromNoteId;
    return id != null && OpenNoteScreens.routeFor(id) != null;
  }

  /// Back with no opener underneath: the map gives way to the circuit's first
  /// note, so back reads map → first note → where you started. If the first
  /// note is open further down after all, back goes down to it instead of
  /// opening it twice.
  void _backToFirstNote() {
    final navigator = Navigator.of(context);
    final root = context.read<AppState>().noteById(widget.circuitId);
    if (root == null || root.deletedAt != null) {
      navigator.pop();
      return;
    }
    final open = OpenNoteScreens.routeFor(root.id);
    if (open != null && identical(open.navigator, navigator)) {
      navigator.popUntil((r) => r == open);
      return;
    }
    // A plain fade: this is going back, so no forward page animation.
    navigator.pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => noteScreen(root),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  Widget _pickBanner() {
    final pick = _pick!;
    final message = pick.kind == _PickKind.move
        ? context.t.circuitMoveBanner(pick.title)
        : context.t.circuitSlotBanner;
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: GlassPanel(
        borderRadius: 20,
        strong: true,
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkPrimary)),
            ),
            TextButton(
              onPressed: () => setState(() => _pick = null),
              child: Text(context.t.cancel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plusButton(Map<String, Rect> rects, CircuitLayout layout, String id) {
    final rect = rects[id] ?? layout.rects[id]!;
    final a = _plusAnchorFor(layout, rect, id);
    return Positioned(
      left: a.dx - 20,
      top: a.dy - 20,
      width: 40,
      height: 40,
      child: Center(
        child: GestureDetector(
          onTap: () => _addChild(id),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppPalette.scheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.add_rounded,
                size: 18, color: AppPalette.scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// One node on the map. Fills the rect it is given.
class _NodeChip extends StatelessWidget {
  const _NodeChip({
    required this.note,
    required this.focused,
    required this.highlight,
    required this.pulse,
    required this.onTap,
    this.onLongPress,
    this.dimmed = false,
    this.collapsedCount = 0,
  });

  final Note? note;
  final bool focused;
  final bool highlight;
  final Animation<double> pulse;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dimmed;

  /// When > 0, this node is collapsed and hides [collapsedCount] children.
  final int collapsedCount;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    if (note == null) return const SizedBox.shrink();
    final isRoot = note.isCircuitRoot;
    final isPlaceholder = note.circuitPlaceholder;
    final fill = isPlaceholder ? null : NoteColors.resolveStrong(note.colorValue);
    final colored = fill != null;
    final ink = colored ? NoteColors.onSwatch : AppPalette.inkPrimary;
    final title = note.title.trim();

    final Color borderColor;
    double borderWidth;
    if (focused) {
      borderColor = AppPalette.scheme.primary;
      borderWidth = 2.5;
    } else if (isRoot) {
      borderColor = AppPalette.scheme.primary;
      borderWidth = 2;
    } else if (isPlaceholder) {
      borderColor = AppPalette.inkSecondary.withValues(alpha: 0.5);
      borderWidth = 1;
    } else {
      borderColor = AppPalette.cardOutline;
      borderWidth = 1;
    }

    final content = Container(
      decoration: BoxDecoration(
        color: fill ?? AppPalette.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (isRoot) ...[
            Icon(Icons.account_tree_rounded, size: 15, color: ink),
            const SizedBox(width: 6),
          ] else if (isPlaceholder) ...[
            Icon(Icons.crop_free_rounded, size: 14, color: ink),
            const SizedBox(width: 6),
          ] else if (note.markdown) ...[
            Icon(Icons.data_object_rounded, size: 14, color: ink),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title.isEmpty ? context.t.untitledNote : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.linear(MediaQuery.textScalerOf(context)
                  .scale(1)
                  .clamp(1.0, 1.3)
                  .toDouble()),
              style: TextStyle(
                fontFamily: kNoteHeadingFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.15,
                fontStyle: (title.isEmpty || isPlaceholder)
                    ? FontStyle.italic
                    : FontStyle.normal,
                color: (title.isEmpty || isPlaceholder)
                    ? ink.withValues(alpha: 0.6)
                    : ink,
              ),
            ),
          ),
          if (note.circuitShowInFeed && !isPlaceholder) ...[
            const SizedBox(width: 6),
            Icon(Icons.home_rounded, size: 13, color: ink.withValues(alpha: 0.7)),
          ],
          if (collapsedCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.unfold_more_rounded, size: 11, color: ink),
                  const SizedBox(width: 2),
                  Text('$collapsedCount',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: content,
    );

    final chip = dimmed ? Opacity(opacity: 0.35, child: tappable) : tappable;

    if (!focused) return chip;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow =
            highlight ? (1 - Curves.easeOut.transform(pulse.value)) : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: glow > 0.01
                ? [
                    BoxShadow(
                      color:
                          AppPalette.scheme.primary.withValues(alpha: 0.5 * glow),
                      blurRadius: 4 + 18 * glow,
                      spreadRadius: 6 * glow,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: chip,
    );
  }
}

/// Draws the branch lines from the given [rects], under the nodes. The edge
/// shape follows the layout mode: a horizontal cubic for left-to-right, a
/// vertical cubic for top-down, and a straight line for radial.
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.rects, this.edges, this.mode, this.color);

  final Map<String, Rect> rects;
  final List<(String, String)> edges;
  final CircuitLayoutMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final p = rects[edge.$1];
      final c = rects[edge.$2];
      if (p == null || c == null) continue;
      final Path path;
      switch (mode) {
        case CircuitLayoutMode.ltr:
          final start = Offset(p.right, p.center.dy);
          final end = Offset(c.left, c.center.dy);
          final midX = (start.dx + end.dx) / 2;
          path = Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
        case CircuitLayoutMode.ttb:
          final start = Offset(p.center.dx, p.bottom);
          final end = Offset(c.center.dx, c.top);
          final midY = (start.dy + end.dy) / 2;
          path = Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(start.dx, midY, end.dx, midY, end.dx, end.dy);
        case CircuitLayoutMode.radial:
          path = Path()
            ..moveTo(p.center.dx, p.center.dy)
            ..lineTo(c.center.dx, c.center.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.color != color ||
      old.rects != rects ||
      old.edges != edges ||
      old.mode != mode;
}
