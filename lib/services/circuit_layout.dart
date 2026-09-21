import 'dart:math' as math;
import 'dart:ui';

/// How a circuit's tree is arranged on the map.
enum CircuitLayoutMode { ltr, ttb, radial }

/// Fixed sizes for the layout. Every node is the same size, which keeps all
/// three layouts simple and makes "no overlaps" provable.
class CircuitMetrics {
  const CircuitMetrics({
    this.nodeW = 184,
    this.nodeH = 64,
    this.depthGap = 72, // left to right: gap between depth columns
    this.breadthGap = 18, // left to right: gap between sibling rows
    this.ttbBreadthGap = 24, // top down: gap between sibling columns
    this.ttbDepthGap = 64, // top down: gap between depth rows
    this.ringGap = 120, // radial: minimum gap between rings
    this.margin = 240,
  });

  final double nodeW;
  final double nodeH;
  final double depthGap;
  final double breadthGap;
  final double ttbBreadthGap;
  final double ttbDepthGap;
  final double ringGap;
  final double margin;

  /// The node's corner-to-corner size — the closest two node centres may sit
  /// without their rectangles overlapping.
  double get nodeDiagonal => math.sqrt(nodeW * nodeW + nodeH * nodeH);
}

/// The computed placement of a circuit: every visible node's rectangle in
/// canvas coordinates (all positive), the parent→child edges among them, and
/// the canvas bounds. [depths] and [breadths] expose the mode-independent slot
/// assignment (useful for the UI and for tests).
class CircuitLayout {
  CircuitLayout({
    required this.rects,
    required this.edges,
    required this.canvasSize,
    required this.mode,
    required this.depths,
    required this.breadths,
    required this.metrics,
    required Map<String, Offset> outwardDirs,
  }) : _outward = outwardDirs;

  final Map<String, Rect> rects;
  final List<(String parent, String child)> edges;
  final Size canvasSize;
  final CircuitLayoutMode mode;
  final Map<String, int> depths;
  final Map<String, double> breadths;
  final CircuitMetrics metrics;
  final Map<String, Offset> _outward;

  /// How far past a node's edge its + button sits.
  static const double plusReach = 20;

  /// The unit direction a node grows toward — where its + button and any new
  /// children extend.
  Offset outward(String id) => _outward[id] ?? const Offset(1, 0);

  /// The centre of a node's + button, just past its outward edge.
  Offset plusAnchor(String id) {
    final rect = rects[id];
    if (rect == null) return Offset.zero;
    final dir = outward(id);
    return rect.center + dir * (_edgeReach(dir) + plusReach);
  }

  /// The distance from a node's centre to its rectangle's boundary along [dir]
  /// (a unit vector).
  double _edgeReach(Offset dir) {
    final hw = metrics.nodeW / 2;
    final hh = metrics.nodeH / 2;
    final ax = dir.dx.abs();
    final ay = dir.dy.abs();
    if (ax < 1e-9) return hh;
    if (ay < 1e-9) return hw;
    return math.min(hw / ax, hh / ay);
  }
}

/// Lays out a circuit rooted at [rootId]. [children] maps a node id to its
/// children in `circuitOrder`. Children of a node in [collapsed] are hidden
/// (the node itself is drawn, as a leaf). Nodes not reachable from [rootId] are
/// ignored. The result is deterministic for a given input.
CircuitLayout layoutCircuit({
  required String rootId,
  required Map<String, List<String>> children,
  Set<String> collapsed = const {},
  CircuitLayoutMode mode = CircuitLayoutMode.ltr,
  CircuitMetrics metrics = const CircuitMetrics(),
}) {
  final depths = <String, int>{};
  final breadths = <String, double>{};
  var nextLeaf = 0;

  List<String> childrenOf(String id) =>
      collapsed.contains(id) ? const [] : (children[id] ?? const []);

  // ---- Core: leaf-slot assignment (depth-first, in child order) ----
  // A leaf takes the next integer slot. A parent's slot is the midpoint of its
  // first and last child's slots. Two visible nodes at the same depth end up at
  // least one slot apart, which is what makes "no overlaps" hold.
  double assign(String id, int depth) {
    depths[id] = depth;
    final kids = childrenOf(id);
    if (kids.isEmpty) {
      final slot = nextLeaf.toDouble();
      breadths[id] = slot;
      nextLeaf += 1;
      return slot;
    }
    var first = 0.0;
    var last = 0.0;
    for (var i = 0; i < kids.length; i++) {
      final b = assign(kids[i], depth + 1);
      if (i == 0) first = b;
      last = b;
    }
    final slot = (first + last) / 2;
    breadths[id] = slot;
    return slot;
  }

  assign(rootId, 0);
  final leafCount = math.max(1, nextLeaf);

  // ---- Radial ring radii ----
  // Rings are kept at least a node-diagonal apart so a parent and a single
  // child, stacked along one radius, can never overlap.
  final diag = metrics.nodeDiagonal;
  final ring = math.max(metrics.ringGap, diag + metrics.breadthGap);
  double radialRadius(int depth) {
    if (depth <= 0) return 0;
    final r1 = leafCount < 2
        ? ring
        : math.max(
            ring, (diag + metrics.breadthGap) / (2 * math.sin(math.pi / leafCount)));
    return depth == 1 ? r1 : r1 + (depth - 1) * ring;
  }

  // ---- Position every visible node ----
  final rects = <String, Rect>{};
  final outward = <String, Offset>{};
  breadths.forEach((id, breadth) {
    final depth = depths[id]!;
    switch (mode) {
      case CircuitLayoutMode.ltr:
        final x = depth * (metrics.nodeW + metrics.depthGap);
        final y = breadth * (metrics.nodeH + metrics.breadthGap);
        rects[id] = Rect.fromLTWH(x, y, metrics.nodeW, metrics.nodeH);
        outward[id] = const Offset(1, 0);
      case CircuitLayoutMode.ttb:
        final x = breadth * (metrics.nodeW + metrics.ttbBreadthGap);
        final y = depth * (metrics.nodeH + metrics.ttbDepthGap);
        rects[id] = Rect.fromLTWH(x, y, metrics.nodeW, metrics.nodeH);
        outward[id] = const Offset(0, 1);
      case CircuitLayoutMode.radial:
        final r = radialRadius(depth);
        final angle =
            -math.pi / 2 + 2 * math.pi * (breadth + 0.5) / leafCount;
        rects[id] = Rect.fromCenter(
          center: Offset(r * math.cos(angle), r * math.sin(angle)),
          width: metrics.nodeW,
          height: metrics.nodeH,
        );
        // The first note grows downward; every branch grows outward along its
        // radius.
        outward[id] = depth == 0
            ? const Offset(0, 1)
            : Offset(math.cos(angle), math.sin(angle));
    }
  });

  // ---- Shift so the top-left of the bounds sits at (margin, margin) ----
  var minX = double.infinity;
  var minY = double.infinity;
  for (final r in rects.values) {
    minX = math.min(minX, r.left);
    minY = math.min(minY, r.top);
  }
  if (rects.isEmpty) {
    minX = 0;
    minY = 0;
  }
  final shift = Offset(metrics.margin - minX, metrics.margin - minY);
  var maxX = 0.0;
  var maxY = 0.0;
  final shifted = <String, Rect>{};
  rects.forEach((id, r) {
    final s = r.shift(shift);
    shifted[id] = s;
    maxX = math.max(maxX, s.right);
    maxY = math.max(maxY, s.bottom);
  });
  final canvasSize = Size(maxX + metrics.margin, maxY + metrics.margin);

  // ---- Edges among visible nodes ----
  final edges = <(String, String)>[];
  for (final id in breadths.keys) {
    for (final c in childrenOf(id)) {
      if (breadths.containsKey(c)) edges.add((id, c));
    }
  }

  return CircuitLayout(
    rects: shifted,
    edges: edges,
    canvasSize: canvasSize,
    mode: mode,
    depths: depths,
    breadths: breadths,
    metrics: metrics,
    outwardDirs: outward,
  );
}
