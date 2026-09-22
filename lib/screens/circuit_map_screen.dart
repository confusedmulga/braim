import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/circuit_layout.dart';
import '../services/note_pdf.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/circuit_sheets.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/note_background.dart';
import '../widgets/quick_actions_menu.dart';
import '../widgets/text_prompt.dart';
import 'note_open.dart';

/// The pop result a note screen hands back to the map: re-centre on [nodeId],
/// and pulse it when [highlight] is set.
class CircuitMapFocus {
  const CircuitMapFocus(this.nodeId, {this.highlight = false});
  final String nodeId;
  final bool highlight;
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
  });

  final String circuitId;
  final String? focusNodeId;
  final bool highlight;

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
  /// opens fully expanded.
  final Set<String> _collapsed = {};

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

  CircuitLayout _buildLayout(AppState state) {
    final root = state.noteById(widget.circuitId);
    final mode = _modeFromString(root?.circuitLayout ?? 'ltr');
    final nodes = state.circuitNodes(widget.circuitId);
    final children = <String, List<String>>{};
    for (final n in nodes) {
      children[n.id] = state.circuitChildren(n.id).map((c) => c.id).toList();
    }
    return layoutCircuit(
      rootId: widget.circuitId,
      children: children,
      collapsed: _collapsed,
      mode: mode,
    );
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
    _animateTo(_fitMatrix(_buildLayout(context.read<AppState>()), vp));
  }

  void _focusOn(String id, {required bool highlight}) {
    final vp = _viewport;
    if (vp == null) return;
    final layout = _buildLayout(context.read<AppState>());
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
  String _phTitleFmt(int n) => context.t.circuitPlaceholderTitle(n);

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
    final result = await Navigator.of(context).push<CircuitMapFocus>(
      MaterialPageRoute(
        builder: (_) => noteScreen(note,
            fromCircuitMap: true, startEditing: _bodyEmpty(note)),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _focusOn(result.nodeId, highlight: result.highlight);
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
        });
      case CircuitNodeAction.colour:
        await showNoteStylePicker(
          context,
          currentColor: note.colorValue,
          currentBackground: note.backgroundAsset,
          onColor: (v) => state.setCircuitNodeColor(id, v),
          onBackground: (v) {
            note.backgroundAsset = v;
            state.upsertNote(note);
          },
        );
      case CircuitNodeAction.moveUp:
        await state.moveCircuitNode(id, -1);
      case CircuitNodeAction.moveDown:
        await state.moveCircuitNode(id, 1);
      case CircuitNodeAction.indent:
        await state.indentCircuitNode(id);
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
      case CircuitNodeAction.shareOutline:
        await _shareOutline();
      case CircuitNodeAction.sharePdf:
        await _sharePdf();
      case CircuitNodeAction.delete:
        await _deleteNode(id);
    }
  }

  // ---- Share as an outline ------------------------------------------------

  /// The circuit as a Markdown outline: the first note as H1, each branch as a
  /// heading by depth, bullets once past H6. Placeholders are skipped, their
  /// children taking their level. Reused for the Markdown and PDF shares.
  String _circuitOutline() {
    final state = context.read<AppState>();
    final root = state.noteById(widget.circuitId);
    if (root == null) return '';
    final buf = StringBuffer();
    void visit(Note n, int depth) {
      if (n.circuitPlaceholder) {
        for (final c in state.circuitChildren(n.id)) {
          visit(c, depth);
        }
        return;
      }
      final title = n.title.trim().isEmpty
          ? (depth == 0 ? context.t.untitledCircuit : context.t.untitledNote)
          : n.title.trim();
      if (depth <= 5) {
        buf.writeln('${'#' * (depth + 1)} $title');
      } else {
        buf.writeln('${'  ' * (depth - 6)}- $title');
      }
      final body = _nodeBody(n);
      if (body.isNotEmpty) {
        buf
          ..writeln()
          ..writeln(body);
      }
      buf.writeln();
      for (final c in state.circuitChildren(n.id)) {
        visit(c, depth + 1);
      }
    }

    visit(root, 0);
    return buf.toString().trim();
  }

  String _nodeBody(Note n) {
    if (n.markdown) {
      final lines = n.markdownSource.split('\n');
      var start = 0;
      while (start < lines.length && lines[start].trim().isEmpty) {
        start++;
      }
      if (start < lines.length &&
          RegExp(r'^#\s+').hasMatch(lines[start].trim())) {
        start++;
      }
      return lines.sublist(start).join('\n').trim();
    }
    return n.textPreview.trim();
  }

  String _circuitTitle() {
    final root = context.read<AppState>().noteById(widget.circuitId);
    return (root == null || root.title.trim().isEmpty)
        ? context.t.untitledCircuit
        : root.title.trim();
  }

  String _circuitFileBase() {
    final root = context.read<AppState>().noteById(widget.circuitId);
    final t = root?.title.trim() ?? '';
    if (t.isEmpty) return 'circuit';
    return t
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  Future<void> _shareOutline() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_circuitFileBase()}.md');
      await file.writeAsString(_circuitOutline());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.shareFailed)));
      }
    }
  }

  Future<void> _sharePdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes =
          await NotePdf.fromMarkdown(_circuitOutline(), title: _circuitTitle());
      await Printing.sharePdf(
          bytes: bytes, filename: '${_circuitFileBase()}.pdf');
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.exportFailed)));
      }
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
    final state = context.read<AppState>();
    final note = state.noteById(id);
    if (note == null) return;
    if (note.isCircuitRoot) {
      final total = state
          .circuitNodes(widget.circuitId)
          .where((n) => !n.circuitPlaceholder)
          .length;
      final ok = await confirmDeleteCircuit(context,
          title: _displayTitle(note), count: total);
      if (ok && mounted) {
        await state.deleteCircuit(id);
        if (mounted) Navigator.of(context).maybePop();
      }
      return;
    }
    if (state.circuitChildren(id).isEmpty) {
      if (await confirmDeleteItems(context, 1) && mounted) {
        await state.deleteCircuitSubtree(id);
      }
      return;
    }
    final descendants = _descendantCount(state, id);
    final choice = await showCircuitDeleteWithChildrenDialog(context,
        title: _displayTitle(note), childCount: descendants);
    if (choice == CircuitDeleteChoice.all && mounted) {
      await state.deleteCircuitSubtree(id);
    } else if (choice == CircuitDeleteChoice.keepSlot && mounted) {
      await state.deleteCircuitNodeKeepSlot(id, placeholderTitle: _phTitleFmt);
    }
  }

  int _descendantCount(AppState state, String id) {
    var count = 0;
    final stack = [id];
    while (stack.isNotEmpty) {
      final pid = stack.removeLast();
      for (final c in state.circuitChildren(pid)) {
        count++;
        stack.add(c.id);
      }
    }
    return count;
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
    if (root == null || !root.isCircuitRoot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final title = _displayTitle(root);
    final layout = _buildLayout(state);

    // Drive the layout-change animation off a positional signature.
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
    final rects = _shownRects.isEmpty ? layout.rects : _shownRects;

    return FrostedScaffold(
      title: title,
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
                            note: state.noteById(id),
                            focused: _focusId == id && _pick == null,
                            highlight: _highlight,
                            pulse: _pulse,
                            collapsedCount: _collapsed.contains(id)
                                ? state.circuitChildren(id).length
                                : 0,
                            dimmed: _pick != null && !_isValidTarget(state, id),
                            onTap: _pick != null
                                ? (_isValidTarget(state, id)
                                    ? () => _handlePickTap(id)
                                    : null)
                                : () => _tapNode(id),
                            onLongPress:
                                _pick != null ? null : () => _longPressNode(id),
                          ),
                        ),
                      if (_pick == null)
                        for (final id in layout.rects.keys)
                          if (!(state.noteById(id)?.circuitPlaceholder ?? true) &&
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
