import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/widgets/frosted_chrome.dart';
import 'package:braim/widgets/scrolling_title.dart';

const _style = TextStyle(fontSize: 17.5);
const _long = 'A very long circuit title that could never fit in the top bar';

Widget _inBox(String text, {double width = 160}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 50,
            child: ScrollingTitle(text, style: _style),
          ),
        ),
      ),
    );

ScrollController _ctrl(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .controller!;

void main() {
  testWidgets('a title that fits sits still and centred', (tester) async {
    await tester.pumpWidget(_inBox('Trip', width: 300));
    expect(find.byType(SingleChildScrollView), findsNothing);
    final title = tester.getCenter(find.text('Trip'));
    final box = tester.getCenter(find.byType(ScrollingTitle));
    expect(title.dx, moreOrLessEquals(box.dx, epsilon: 0.5));
  });

  testWidgets('a long title rests, then drifts slowly toward its end',
      (tester) async {
    await tester.pumpWidget(_inBox(_long));
    await tester.pump(); // post-frame start
    final ctrl = _ctrl(tester);
    expect(ctrl.position.maxScrollExtent, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 1500)); // still resting
    expect(ctrl.offset, 0);

    await tester.pump(const Duration(milliseconds: 200)); // drift begins
    await tester.pump(const Duration(seconds: 1));
    // ~28 px/s — moving, but slowly.
    expect(ctrl.offset, greaterThan(10));
    expect(ctrl.offset, lessThan(60));
  });

  testWidgets('it reaches the end, rests, and starts over', (tester) async {
    await tester.pumpWidget(_inBox(_long));
    await tester.pump();
    final ctrl = _ctrl(tester);
    final end = ctrl.position.maxScrollExtent;
    // Rest + the whole drift at 28 px/s, with room to spare.
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(Duration(milliseconds: (end / 28 * 1000).round() + 200));
    expect(ctrl.offset, moreOrLessEquals(end, epsilon: 1));

    await tester.pump(const Duration(milliseconds: 1600)); // rest at the end
    await tester.pumpAndSettle(); // the return to the start
    expect(ctrl.offset, lessThan(end));
  });

  testWidgets('a tap sends the title back to its start', (tester) async {
    await tester.pumpWidget(_inBox(_long));
    await tester.pump();
    final ctrl = _ctrl(tester);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(seconds: 3));
    expect(ctrl.offset, greaterThan(40));

    await tester.tap(find.byType(ScrollingTitle));
    await tester.pump(); // the reset animation starts on this frame
    await tester.pump(const Duration(milliseconds: 400));
    expect(ctrl.offset, 0);
  });

  testWidgets('dragging scrolls it by hand, and the drift waits',
      (tester) async {
    await tester.pumpWidget(_inBox(_long));
    await tester.pump();
    final ctrl = _ctrl(tester);

    await tester.drag(find.byType(ScrollingTitle), const Offset(-60, 0));
    await tester.pump();
    final dragged = ctrl.offset;
    // The first ~20 px of a drag only cross the touch slop.
    expect(dragged, greaterThan(30));

    // Well past the normal rest: no drift while the hand-scroll holds.
    await tester.pump(const Duration(milliseconds: 2500));
    expect(ctrl.offset, moreOrLessEquals(dragged, epsilon: 0.5));

    // Dragging the other way scrolls back.
    await tester.drag(find.byType(ScrollingTitle), const Offset(40, 0));
    await tester.pump();
    expect(ctrl.offset, lessThan(dragged));
  });

  testWidgets('with animations off it never drifts', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _inBox(_long),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(_ctrl(tester).offset, 0);
  });

  testWidgets(
      'the scaffold title sits between the back button and two actions',
      (tester) async {
    Widget action(IconData icon) =>
        FrostedCircleButton(icon: icon, tooltip: 'a', onTap: () {});
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: FrostedScaffold(
        title: _long,
        scrollingTitle: true,
        actions: [action(Icons.hub_rounded), action(Icons.fit_screen_rounded)],
        body: const SizedBox(),
      ),
    ));
    await tester.pump();
    final title = tester.getRect(find.byType(ScrollingTitle));
    final back = tester.getRect(find.byType(FrostedBackButton));
    final firstAction = tester.getRect(find.byIcon(Icons.hub_rounded));
    expect(title.left, greaterThanOrEqualTo(back.right));
    expect(title.right, lessThanOrEqualTo(firstAction.left));
  });
}
