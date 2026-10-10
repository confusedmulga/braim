import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/space.dart';
import 'package:braim/screens/share_popup.dart';
import 'package:braim/services/storage_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  late Directory root;
  late String shared;
  var closed = false;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_popup_test');
    Directory('${root.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    closed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('braim/share'),
            (call) async {
      if (call.method == 'getSharedText') return shared;
      if (call.method == 'close') closed = true;
      return null;
    });
  });

  /// Shows the popup for [text], with a "Reading" fold to choose.
  Future<void> open(WidgetTester tester, String text) async {
    shared = text;
    await tester.runAsync(() async {
      await StorageService.instance
          .save(AppData(notes: [], spaces: [Space(name: 'Reading')], cards: []));
      await StorageService.instance.drainShareInbox();
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SharePopupScreen(),
    ));
    // Loading reads real files, which only move on the real clock: let it
    // run a little at a time until the spinner gives way to the form.
    for (var i = 0;
        i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Taps ✓ and returns what the popup left in the share inbox.
  Future<Map<String, dynamic>> save(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Save'));
    // The popup writes the share, shows "Saved" briefly, then closes itself.
    // The write moves on the real clock, the pause on the test's: alternate.
    for (var i = 0; i < 60 && !closed; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(closed, isTrue);
    late List<Map<String, dynamic>> records;
    await tester.runAsync(() async {
      records = await StorageService.instance.drainShareInbox();
    });
    return records.single;
  }

  testWidgets('a shared headline + link: spark, headline as its title',
      (tester) async {
    await open(tester,
        'Rain sets records across the coast\nhttps://news.example.com/a');
    expect(find.text('Save to Braim'), findsOneWidget); // not "node"
    expect(find.text('Rain sets records across the coast'), findsOneWidget);

    // Picking a fold only selects it; ✓ saves.
    await tester.tap(find.text('Reading'));
    await tester.pump();
    expect(closed, isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'),
        'Ask about the insurance.');
    final record = await save(tester);
    expect(record['url'], 'https://news.example.com/a');
    expect(record['title'], 'Rain sets records across the coast');
    expect(record['body'], 'Ask about the insurance.');
    expect(record['spaceId'], isNotNull);
    expect(closed, isTrue);
  });

  testWidgets('shared text goes in the body; the title is optional',
      (tester) async {
    await open(tester, 'Milk, eggs, bread');
    expect(find.text('Save node to Braim'), findsOneWidget);
    expect(find.text('Milk, eggs, bread'), findsOneWidget); // in the body
    final record = await save(tester);
    expect(record['noteText'], 'Milk, eggs, bread');
    expect(record.containsKey('title'), isFalse);
    expect(record['spaceId'], isNull); // Home
  });
}
