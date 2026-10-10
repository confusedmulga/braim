import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/widgets/sticky_columns.dart';
import 'package:braim/widgets/tweet_card_widget.dart';

void main() {
  group('StickyColumnPlacer', () {
    test('first placement balances by estimated height', () {
      final heights = {'a': 300.0, 'b': 100.0, 'c': 100.0, 'd': 100.0};
      final (left, right) = StickyColumnPlacer().place(
          heights.keys.toList(),
          estimate: (id) => heights[id]!,
          layout: 'recent');
      // a (300) fills the left; b, c, d stack on the right until it's taller.
      expect(left, ['a']);
      expect(right, ['b', 'c', 'd']);
    });

    test('a tile that changes height never moves the others across', () {
      final heights = {'a': 100.0, 'b': 100.0, 'c': 100.0, 'd': 100.0};
      final placer = StickyColumnPlacer();
      final before = placer.place(heights.keys.toList(),
          estimate: (id) => heights[id]!, layout: 'recent');

      // A preview arrives for "a" and it grows a lot. A masonry grid would
      // now re-pack c and d into the right column.
      heights['a'] = 600;
      final after = placer.place(heights.keys.toList(),
          estimate: (id) => heights[id]!, layout: 'recent');
      expect(after.$1, before.$1);
      expect(after.$2, before.$2);
      expect(after.$1, ['a', 'c']);
    });

    test('a new spark goes to the shorter column; the rest stay put', () {
      final heights = {'a': 400.0, 'b': 100.0, 'c': 100.0};
      final placer = StickyColumnPlacer();
      final (left0, right0) = placer.place(['a', 'b', 'c'],
          estimate: (id) => heights[id]!, layout: 'recent');
      expect(left0, ['a']);
      expect(right0, ['b', 'c']);

      // Saved just now, so it is first in the feed.
      heights['new'] = 100;
      final (left, right) = placer.place(['new', 'a', 'b', 'c'],
          estimate: (id) => heights[id]!, layout: 'recent');
      expect(left, ['new', 'a']);
      expect(right, ['b', 'c']);
    });

    test('a re-sort or a pin balances afresh', () {
      final heights = {'a': 100.0, 'b': 100.0, 'c': 100.0, 'd': 100.0};
      final placer = StickyColumnPlacer();
      placer.place(heights.keys.toList(),
          estimate: (id) => heights[id]!, layout: 'recent');
      heights['a'] = 600;
      final (left, right) = placer.place(heights.keys.toList(),
          estimate: (id) => heights[id]!, layout: 'recent|pinned:d');
      expect(left, ['a']);
      expect(right, ['b', 'c', 'd']);
    });

    test('a spark that leaves and comes back is placed afresh', () {
      final heights = {'a': 100.0, 'b': 100.0, 'c': 100.0};
      final placer = StickyColumnPlacer();
      placer.place(['a', 'b', 'c'],
          estimate: (id) => heights[id]!, layout: 'recent');
      // b is archived, then restored after a has grown.
      placer.place(['a', 'c'], estimate: (id) => heights[id]!, layout: 'recent');
      heights['a'] = 500;
      final (left, right) = placer.place(['a', 'b', 'c'],
          estimate: (id) => heights[id]!, layout: 'recent');
      expect(left, ['a', 'c']); // c kept its column
      expect(right, ['b']); // b re-placed beside the tall a
    });
  });

  testWidgets('the sliver shows both columns side by side', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          StickyColumnsSliver<String>(
            items: const ['one', 'two', 'three'],
            idOf: (s) => s,
            estimateHeight: (_) => 50,
            layout: 'x',
            itemBuilder: (_, s) => SizedBox(height: 50, child: Text(s)),
          ),
        ]),
      ),
    ));
    final one = tester.getTopLeft(find.text('one'));
    final two = tester.getTopLeft(find.text('two'));
    final three = tester.getTopLeft(find.text('three'));
    expect(two.dx, greaterThan(one.dx)); // second column
    expect(two.dy, one.dy);
    expect(three.dx, one.dx); // back in the first column, below "one"
    expect(three.dy, greaterThan(one.dy));
  });

  testWidgets('a preview picture that fails to load keeps its space',
      (tester) async {
    // Tests can't reach the network, so every picture fails here.
    final card = TweetCard(url: 'https://example.com/post')
      ..fetched = true
      ..siteName = 'Example'
      ..imageUrl = 'https://example.com/picture.jpg';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 170,
            child: CompactCardTile(card: card, onTap: () {}),
          ),
        ),
      ),
    ));
    final loading = tester.getSize(find.byType(CompactCardTile)).height;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.getSize(find.byType(CompactCardTile)).height, loading);
  });
}
