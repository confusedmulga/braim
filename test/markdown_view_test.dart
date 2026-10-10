import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/widgets/markdown_view.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget view) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));

  /// Every block of text currently built.
  int builtBlocks(WidgetTester tester) => find
      .byWidgetPredicate((w) => w is RichText && w.text is TextSpan)
      .evaluate()
      .length;

  testWidgets('renders headings, prose and code as before', (tester) async {
    await show(
        tester,
        const MarkdownView('# Title\n\nSome **bold** words\nwrapped onto a '
            'second line.\n\n```dart\nvoid main() {}\n```\n\n- [ ] a task'));
    expect(find.textContaining('Title'), findsWidgets);
    // A hard-wrapped paragraph flows as one, the way GitHub renders it.
    expect(find.textContaining('words wrapped onto a second line.'),
        findsOneWidget);
    expect(find.textContaining('void main() {}'), findsOneWidget);
    expect(find.textContaining('a task'), findsOneWidget);
  });

  testWidgets('a rebuild with the same source does not parse it again',
      (tester) async {
    const source = '# Notes\n\nOne paragraph.\n\nAnother one.';
    final before = MarkdownView.debugParses;
    await show(tester, const MarkdownView(source));
    expect(MarkdownView.debugParses, before + 1);

    // The note screen rebuilds on every change anywhere in the app.
    for (var i = 0; i < 5; i++) {
      await show(tester, const MarkdownView(source));
    }
    expect(MarkdownView.debugParses, before + 1);

    await show(tester, const MarkdownView('$source\n\nA third.'));
    expect(MarkdownView.debugParses, before + 2);
  });

  testWidgets('a long document builds only what is on screen',
      (tester) async {
    final source = List.generate(
            1500, (i) => '## Section $i\n\nParagraph $i of a long import.')
        .join('\n\n');
    await tester.runAsync(() async {
      await show(tester, MarkdownView(source));
      // Big enough to parse in the background; wait for it.
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    expect(find.textContaining('Section 0'), findsOneWidget);
    // 3000 blocks in the document; a screenful (plus a little) is built.
    expect(builtBlocks(tester), lessThan(60));

    await tester.drag(find.byType(MarkdownView), const Offset(0, -3000));
    await tester.pump();
    expect(find.textContaining('Section 0'), findsNothing);
    expect(builtBlocks(tester), lessThan(60));
  });

  testWidgets('a large source shows a spinner while it parses',
      (tester) async {
    final source = 'word ' * (MarkdownView.backgroundParseChars ~/ 4);
    await show(tester, MarkdownView(source));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('word word'), findsOneWidget);
  });

  testWidgets('a [[wiki-link]] is tappable', (tester) async {
    String? opened;
    await show(
        tester,
        MarkdownView('See [[Trip plan]] for details.',
            onWikiTap: (title) => opened = title));
    await tester.tapOnText(find.textRange.ofSubstring('Trip plan'));
    expect(opened, 'Trip plan');
  });
}
