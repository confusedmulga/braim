import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/services/dictionary.dart';
import 'package:braim/widgets/dictionary_popup.dart';

void main() {
  late Directory root;

  setUpAll(() async {
    sqfliteFfiInit();
    root = Directory.systemTemp.createTempSync('braim_dictionary_popup_test');
    Dictionary.instance = Dictionary(
      factory: databaseFactoryFfi,
      directory: () async => root,
      loadAsset: () async => ByteData.sublistView(
          await File(Dictionary.assetPath).readAsBytes()),
    );
    // Unpack once, outside the tests' fake clock.
    await Dictionary.instance.define('warm');
  });

  tearDownAll(() async {
    await Dictionary.instance.close();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Lets the real database answer, then shows what it said.
  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<BuildContext> pumpPage(WidgetTester tester) async {
    // A phone's screen.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          page = context;
          return const SizedBox.expand();
        }),
      ),
    ));
    return page;
  }

  testWidgets('Define: the meaning in a card; a synonym looks itself up',
      (tester) async {
    final page = await pumpPage(tester);
    showDefinition(page, 'Happiest,');
    await settle(tester, find.text('adjective'));

    // "happiest" isn't a headword; its base is.
    expect(find.text('happy'), findsOneWidget);
    expect(find.text('enjoying or showing or marked by joy or pleasure'),
        findsOneWidget);
    expect(find.text('“a happy smile”'), findsOneWidget);

    await tester.ensureVisible(find.text('glad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('glad'));
    await settle(tester, find.byTooltip('Back'));
    expect(find.text('glad'), findsWidgets);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, find.text('happy'));
    expect(find.text('happy'), findsOneWidget);

    // A tap outside the card closes it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('happy'), findsNothing);
  });

  testWidgets('Define: a word it doesn’t know says so', (tester) async {
    final page = await pumpPage(tester);
    showDefinition(page, 'qwzxv');
    await settle(tester, find.textContaining('No definition'));
    expect(find.text('No definition found for “qwzxv”.'),
        findsOneWidget);
  });

  testWidgets('the search popup groups definitions, synonyms and meanings',
      (tester) async {
    final page = await pumpPage(tester);
    showDictionarySearch(page);
    await tester.pumpAndSettle();
    expect(find.textContaining('describe a meaning'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'happy');
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester, find.text('SYNONYMS'));
    expect(find.text('DEFINITIONS'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('blissful'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('blissful'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fear of great heights');
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester, find.textContaining('acrophobia'));
    expect(find.text('WORDS FOR THIS MEANING'), findsOneWidget);
    expect(find.text('DEFINITIONS'), findsNothing);
    // Its words, then its word class.
    expect(find.textContaining('acrophobia'), findsOneWidget);

    // A word in the results becomes the search.
    await tester.tap(find.textContaining('acrophobia'));
    await settle(tester, find.text('DEFINITIONS'));
    expect(find.text('acrophobia'), findsWidgets);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'acrophobia');
  });

  testWidgets('Define joins a selection menu after Copy, for a word only',
      (tester) async {
    final page = await pumpPage(tester);
    final copy = ContextMenuButtonItem(
        type: ContextMenuButtonType.copy, onPressed: () {});
    final selectAll = ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll, onPressed: () {});
    final items = withDefine(page, [copy, selectAll], 'serendipity', () {});
    expect(items.map((i) => i.label), [null, 'Define', null]);
    expect(
        withDefine(page, [copy, selectAll],
            'a whole sentence that is far too long to define', () {}),
        [copy, selectAll]);
  });
}
