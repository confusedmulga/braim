import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../services/circuit_layout.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';
import 'note_open.dart';

/// The pop result a note screen hands back to the map: re-centre on [nodeId],
/// and pulse it when [highlight] is set.
class CircuitMapFocus {
  const CircuitMapFocus(this.nodeId, {this.highlight = false});
  final String nodeId;
  final bool highlight;
}

/// The full-screen circuit map. Phase 3 draws the left-to-right layout only:
/// pan, pinch-zoom, fit, centre on a node, tap to open, and a **+** on each
/// node to add a child. Layout switching (Phase 5) and the node/placeholder
/// sheets (Phase 4) come later.
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

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  AnimationController? _moveCtrl;

  @override
  void initState() {
    super.initState();
    _focusId = widget.focusNodeId;
    _highlight = widget.highlight;
  }

  @override
  void dispose() {
    _pulse.dispose();
    _moveCtrl?.dispose();
    _tc.dispose();
    super.dispose();
  }

  CircuitLayout _buildLayout(AppState state) {
    final nodes = state.circuitNodes(widget.circuitId);
    final children = <String, List<String>>{};
    for (final n in nodes) {
      children[n.id] = state.circuitChildren(n.id).map((c) => c.id).toList();
    }
    return layoutCircuit(
      rootId: widget.circuitId,
      children: children,
      mode: CircuitLayoutMode.ltr,
    );
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
    final anim = Matrix4Tween(begin: _tc.value, end: target).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));
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

  // ---- Actions ------------------------------------------------------------

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

  Future<void> _openNode(String id) async {
    final state = context.read<AppState>();
    final note = state.noteById(id);
    if (note == null || note.circuitPlaceholder) return; // Phase 4: slot sheet
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
      setState(() {}); // reflect any edits made in the note screen
    }
  }

  Future<void> _addChild(String parentId) async {
    final state = context.read<AppState>();
    final created = await state.addCircuitChild(
      parentId,
      noteTitle: (n) => context.t.circuitNoteTitle(n),
    );
    if (!mounted) return;
    _focusOn(created.id, highlight: true);
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final root = state.noteById(widget.circuitId);
    if (root == null || !root.isCircuitRoot) {
      // The circuit was deleted out from under the map; leave.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final title = root.title.trim().isEmpty
        ? context.t.untitledCircuit
        : root.title.trim();
    final layout = _buildLayout(state);

    return FrostedScaffold(
      title: title,
      bodyUnderChrome: true,
      actions: [
        FrostedCircleButton(
          icon: Icons.fit_screen_rounded,
          tooltip: context.t.circuitFit,
          onTap: _fitToScreen,
        ),
      ],
      body: LayoutBuilder(
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
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _EdgePainter(
                            layout, AppPalette.inkSecondary.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                  for (final entry in layout.rects.entries)
                    Positioned.fromRect(
                      rect: entry.value,
                      child: _NodeChip(
                        note: state.noteById(entry.key),
                        focused: _focusId == entry.key,
                        highlight: _highlight,
                        pulse: _pulse,
                        onTap: () => _openNode(entry.key),
                      ),
                    ),
                  for (final entry in layout.rects.entries)
                    if (!(state.noteById(entry.key)?.circuitPlaceholder ?? true))
                      _plusButton(layout, entry.key),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _plusButton(CircuitLayout layout, String id) {
    final a = layout.plusAnchor(id);
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

/// One node on the map. Wrapped in its own [RepaintBoundary] by the caller's
/// Positioned; here it fills the rect it is given.
class _NodeChip extends StatelessWidget {
  const _NodeChip({
    required this.note,
    required this.focused,
    required this.highlight,
    required this.pulse,
    required this.onTap,
  });

  final Note? note;
  final bool focused;
  final bool highlight;
  final Animation<double> pulse;
  final VoidCallback onTap;

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
          ] else if (note.markdown) ...[
            Icon(Icons.data_object_rounded, size: 14, color: ink),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title.isEmpty ? context.t.untitledNote : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3).toDouble()),
              style: TextStyle(
                fontFamily: kNoteHeadingFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.15,
                fontStyle: title.isEmpty ? FontStyle.italic : FontStyle.normal,
                color: title.isEmpty ? ink.withValues(alpha: 0.6) : ink,
              ),
            ),
          ),
          if (note.circuitShowInFeed && !isPlaceholder) ...[
            const SizedBox(width: 6),
            Icon(Icons.home_rounded, size: 13, color: ink.withValues(alpha: 0.7)),
          ],
        ],
      ),
    );

    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );

    if (!focused) return tappable;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = highlight ? (1 - Curves.easeOut.transform(pulse.value)) : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: glow > 0.01
                ? [
                    BoxShadow(
                      color: AppPalette.scheme.primary.withValues(alpha: 0.5 * glow),
                      blurRadius: 4 + 18 * glow,
                      spreadRadius: 6 * glow,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: tappable,
    );
  }
}

/// Draws the branch lines: a cubic from each parent's right-middle to its
/// child's left-middle, under the nodes.
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.layout, this.color);

  final CircuitLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in layout.edges) {
      final p = layout.rects[edge.$1];
      final c = layout.rects[edge.$2];
      if (p == null || c == null) continue;
      final start = Offset(p.right, p.center.dy);
      final end = Offset(c.left, c.center.dy);
      final midX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.color != color || old.layout != layout;
}
