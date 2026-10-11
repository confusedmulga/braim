import 'package:flutter/widgets.dart';

/// Decides which of two columns each feed item goes in, and keeps it there.
///
/// A masonry grid re-packs every tile into the shortest column on every
/// layout, so when one tile changes height (a link preview arriving, a
/// picture failing to load) the tiles after it hop between columns. Here an
/// item's column is chosen once, when it first appears, from an estimate of
/// its height, and then kept; a tile that changes height only moves the
/// tiles below it in its own column. A new [place] with a different `layout`
/// (a re-sort, a pin) starts over with a fresh, balanced placement.
class StickyColumnPlacer {
  final Map<String, int> _columnOf = {};
  Object? _layout;

  /// Splits [ids] (in feed order) into a left and a right column of ids.
  /// [estimate] gives each item's rough height, used to weigh the columns
  /// when an item that has no column yet is placed.
  (List<String>, List<String>) place(
    List<String> ids, {
    required double Function(String id) estimate,
    required Object layout,
    double spacing = 0,
  }) {
    if (layout != _layout) {
      _columnOf.clear();
      _layout = layout;
    }
    // Items already placed keep their column. A new one joins whichever
    // column is shorter overall (on a fresh layout, every item is new, so the
    // columns fill in feed order). Judged at its own spot instead, a spark
    // saved just now — first in the feed, where both columns start level —
    // would always go left, and the left column would run away.
    final totals = [0.0, 0.0];
    for (final id in ids) {
      final column = _columnOf[id];
      if (column != null) totals[column] += estimate(id) + spacing;
    }
    final columns = (<String>[], <String>[]);
    final present = <String>{};
    for (final id in ids) {
      present.add(id);
      var column = _columnOf[id];
      if (column == null) {
        column = totals[0] <= totals[1] ? 0 : 1;
        _columnOf[id] = column;
        totals[column] += estimate(id) + spacing;
      }
      (column == 0 ? columns.$1 : columns.$2).add(id);
    }
    // Forget items that have gone, so one that comes back is placed afresh.
    _columnOf.removeWhere((id, _) => !present.contains(id));
    return columns;
  }
}

/// A lazy two-column feed sliver whose items stay in the column they were
/// first placed in (see [StickyColumnPlacer]).
class StickyColumnsSliver<T> extends StatefulWidget {
  const StickyColumnsSliver({
    super.key,
    required this.items,
    required this.idOf,
    required this.estimateHeight,
    required this.itemBuilder,
    required this.layout,
    this.mainAxisSpacing = 10,
    this.crossAxisSpacing = 10,
  });

  final List<T> items;
  final String Function(T item) idOf;

  /// A rough height for an item, from its data alone.
  final double Function(T item) estimateHeight;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Changes when the feed is re-sorted or re-pinned; the columns are then
  /// balanced afresh.
  final Object layout;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  State<StickyColumnsSliver<T>> createState() => _StickyColumnsSliverState<T>();
}

class _StickyColumnsSliverState<T> extends State<StickyColumnsSliver<T>> {
  final _placer = StickyColumnPlacer();

  @override
  Widget build(BuildContext context) {
    final byId = {for (final item in widget.items) widget.idOf(item): item};
    final (left, right) = _placer.place(
      byId.keys.toList(),
      estimate: (id) => widget.estimateHeight(byId[id] as T),
      layout: widget.layout,
      spacing: widget.mainAxisSpacing,
    );

    Widget column(List<String> ids) => SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => KeyedSubtree(
              key: ValueKey<String>(ids[i]),
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.mainAxisSpacing),
                child: widget.itemBuilder(context, byId[ids[i]] as T),
              ),
            ),
            childCount: ids.length,
            // Keeps each tile's state when items above it come or go.
            findChildIndexCallback: (key) {
              final i = ids.indexOf((key as ValueKey<String>).value);
              return i < 0 ? null : i;
            },
          ),
        );

    return SliverCrossAxisGroup(
      slivers: [
        SliverCrossAxisExpanded(flex: 1, sliver: column(left)),
        SliverConstrainedCrossAxis(
          maxExtent: widget.crossAxisSpacing,
          sliver: const SliverToBoxAdapter(),
        ),
        SliverCrossAxisExpanded(flex: 1, sliver: column(right)),
      ],
    );
  }
}
