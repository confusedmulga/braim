import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/circuit_layout.dart';

// The four tree shapes from the plan's section 7 test list.
final shapes = <String, Map<String, List<String>>>{
  'single': <String, List<String>>{},
  'chain': {
    'r': ['a'],
    'a': ['b'],
    'b': ['c'],
  },
  'fan': {
    'r': ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'],
  },
  'mixed': {
    'r': ['a', 'b', 'c'],
    'a': ['a1', 'a2'],
    'b': ['b1', 'b2', 'b3'],
    'c': ['c1'],
  },
};

bool intersects(Rect a, Rect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

void expectNoOverlap(CircuitLayout layout) {
  final entries = layout.rects.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      expect(intersects(entries[i].value, entries[j].value), isFalse,
          reason:
              '${entries[i].key} overlaps ${entries[j].key} in ${layout.mode}');
    }
  }
}

void expectInsideCanvas(CircuitLayout layout) {
  for (final e in layout.rects.entries) {
    final r = e.value;
    expect(r.left, greaterThanOrEqualTo(-0.001), reason: '${e.key}.left');
    expect(r.top, greaterThanOrEqualTo(-0.001), reason: '${e.key}.top');
    expect(r.right, lessThanOrEqualTo(layout.canvasSize.width + 0.001),
        reason: '${e.key}.right in ${layout.mode}');
    expect(r.bottom, lessThanOrEqualTo(layout.canvasSize.height + 0.001),
        reason: '${e.key}.bottom in ${layout.mode}');
  }
}

void expectSiblingOrderAndMidpoints(
    CircuitLayout layout, Map<String, List<String>> children) {
  children.forEach((parent, kids) {
    final visible =
        kids.where((k) => layout.breadths.containsKey(k)).toList();
    if (visible.isEmpty) return;
    // Order preserved along the breadth axis: breadth strictly increases.
    for (var i = 0; i + 1 < visible.length; i++) {
      expect(layout.breadths[visible[i]]!,
          lessThan(layout.breadths[visible[i + 1]]!),
          reason: 'sibling order under $parent in ${layout.mode}');
    }
    // A parent's breadth is the midpoint of its first and last child.
    final first = layout.breadths[visible.first]!;
    final last = layout.breadths[visible.last]!;
    expect(layout.breadths[parent]!, closeTo((first + last) / 2, 1e-9),
        reason: '$parent breadth midpoint in ${layout.mode}');
  });
}

void main() {
  for (final shape in shapes.entries) {
    for (final mode in CircuitLayoutMode.values) {
      test('${shape.key} / ${mode.name}: no overlap, inside canvas, order, '
          'midpoints', () {
        final layout =
            layoutCircuit(rootId: 'r', children: shape.value, mode: mode);
        expect(layout.rects.containsKey('r'), isTrue);
        expectNoOverlap(layout);
        expectInsideCanvas(layout);
        expectSiblingOrderAndMidpoints(layout, shape.value);
        expect(layout.canvasSize.width, greaterThan(0));
        expect(layout.canvasSize.height, greaterThan(0));
      });
    }
  }

  test('ltr stacks siblings top-to-bottom in order at one depth', () {
    final layout = layoutCircuit(
        rootId: 'r', children: {'r': ['a', 'b', 'c']});
    expect(layout.rects['a']!.center.dy, lessThan(layout.rects['b']!.center.dy));
    expect(layout.rects['b']!.center.dy, lessThan(layout.rects['c']!.center.dy));
    expect(layout.rects['a']!.left, layout.rects['b']!.left); // same column
    // The child column sits to the right of the root column.
    expect(layout.rects['a']!.left, greaterThan(layout.rects['r']!.left));
  });

  test('ttb lines siblings left-to-right in order at one depth', () {
    final layout = layoutCircuit(
        rootId: 'r',
        children: {'r': ['a', 'b', 'c']},
        mode: CircuitLayoutMode.ttb);
    expect(layout.rects['a']!.center.dx, lessThan(layout.rects['b']!.center.dx));
    expect(layout.rects['b']!.center.dx, lessThan(layout.rects['c']!.center.dx));
    expect(layout.rects['a']!.top, layout.rects['b']!.top); // same row
    expect(layout.rects['a']!.top, greaterThan(layout.rects['r']!.top));
  });

  test('radial puts the first note at the centre', () {
    final layout = layoutCircuit(
        rootId: 'r',
        children: {'r': ['a', 'b', 'c', 'd']},
        mode: CircuitLayoutMode.radial);
    // With the root at radius 0, its centre is the centre of every child ring.
    final root = layout.rects['r']!.center;
    for (final child in ['a', 'b', 'c', 'd']) {
      final c = layout.rects[child]!.center;
      final d = (c - root).distance;
      // Every depth-1 node sits on the same ring.
      final first = (layout.rects['a']!.center - root).distance;
      expect(d, closeTo(first, 0.001));
    }
  });

  test('collapsed nodes hide their descendants (all modes)', () {
    final children = {
      'r': ['a', 'b'],
      'a': ['a1', 'a2'],
      'b': ['b1'],
    };
    for (final mode in CircuitLayoutMode.values) {
      final layout = layoutCircuit(
          rootId: 'r', children: children, collapsed: {'a'}, mode: mode);
      expect(layout.rects.containsKey('a'), isTrue); // the node itself is drawn
      expect(layout.rects.containsKey('a1'), isFalse);
      expect(layout.rects.containsKey('a2'), isFalse);
      expect(layout.rects.containsKey('b1'), isTrue);
      expect(layout.edges.any((e) => e.$2 == 'a1'), isFalse);
      expect(layout.edges.contains(('r', 'a')), isTrue);
      expectNoOverlap(layout);
    }
  });

  test('output is deterministic', () {
    for (final shape in shapes.entries) {
      for (final mode in CircuitLayoutMode.values) {
        final a =
            layoutCircuit(rootId: 'r', children: shape.value, mode: mode);
        final b =
            layoutCircuit(rootId: 'r', children: shape.value, mode: mode);
        expect(a.rects.length, b.rects.length);
        a.rects.forEach((id, rect) => expect(b.rects[id], rect));
        expect(a.canvasSize, b.canvasSize);
        expect(a.edges, b.edges);
      }
    }
  });

  test('edges connect every visible parent to its children', () {
    final children = {
      'r': ['a', 'b'],
      'a': ['a1'],
    };
    final layout = layoutCircuit(rootId: 'r', children: children);
    expect(
        layout.edges.toSet(), {('r', 'a'), ('r', 'b'), ('a', 'a1')});
  });

  test('plusAnchor sits outside the node along its outward direction', () {
    final ltr = layoutCircuit(rootId: 'r', children: {'r': ['a']});
    expect(ltr.outward('r'), const Offset(1, 0));
    expect(ltr.plusAnchor('r').dx, greaterThan(ltr.rects['r']!.right));

    final ttb = layoutCircuit(
        rootId: 'r', children: {'r': ['a']}, mode: CircuitLayoutMode.ttb);
    expect(ttb.outward('r'), const Offset(0, 1));
    expect(ttb.plusAnchor('r').dy, greaterThan(ttb.rects['r']!.bottom));
  });

  test('a single node lays out inside a positive canvas', () {
    for (final mode in CircuitLayoutMode.values) {
      final layout =
          layoutCircuit(rootId: 'solo', children: const {}, mode: mode);
      expect(layout.rects.keys, ['solo']);
      expect(layout.edges, isEmpty);
      expectInsideCanvas(layout);
    }
  });
}
