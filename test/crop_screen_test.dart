import 'dart:convert';
import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/screens/crop_screen.dart';

/// A 1×1 PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

void main() {
  late Directory dir;

  setUpAll(() => dir = Directory.systemTemp.createTempSync('braim_crop_test'));

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Opens the cropper for a picture file as the note editor does, and
  /// returns what cropImageFile will hand back.
  Future<Future<String?>> openCropper(WidgetTester tester, String path,
      {double? aspectRatio}) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    late Future<String?> result;
    await tester.runAsync(() async {
      result = cropImageFile(ctx, path, aspectRatio: aspectRatio);
      // Lets the file read finish on the real clock.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    return result;
  }

  bool selected(WidgetTester tester, String label) {
    final box = tester.widget<Container>(find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first);
    return (box.decoration as BoxDecoration).color != Colors.white12;
  }

  testWidgets('opens on Original, and keeping it returns the file untouched',
      (tester) async {
    final file = File('${dir.path}/photo.png')..writeAsBytesSync(_png);
    final result = await openCropper(tester, file.path);

    expect(selected(tester, 'Original'), isTrue);
    expect(find.byType(Crop), findsNothing); // just the picture, uncropped
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    // The result was started on the real clock; read it there too.
    expect(await tester.runAsync(() => result), file.path);
  });

  testWidgets('a crop shape brings up the cropper; Original puts it away',
      (tester) async {
    final file = File('${dir.path}/photo.png')..writeAsBytesSync(_png);
    await openCropper(tester, file.path);

    await tester.tap(find.text('Square'));
    await tester.pump();
    expect(find.byType(Crop), findsOneWidget);
    expect(selected(tester, 'Square'), isTrue);
    expect(selected(tester, 'Original'), isFalse);

    // The cropper sits clear of the screen's edges and the top bar, so a
    // corner handle is never dragged from Android's back-swipe zone.
    final area = tester.getRect(find.byType(Crop));
    final screen = tester.getRect(find.byType(Scaffold).last);
    expect(area.left, greaterThanOrEqualTo(28));
    expect(screen.right - area.right, greaterThanOrEqualTo(28));

    await tester.tap(find.text('Free'));
    await tester.pump();
    expect(selected(tester, 'Free'), isTrue);

    await tester.tap(find.text('Original'));
    await tester.pump();
    expect(find.byType(Crop), findsNothing);
  });

  testWidgets('a book cover still opens on its 2:3 shape', (tester) async {
    final file = File('${dir.path}/cover.png')..writeAsBytesSync(_png);
    await openCropper(tester, file.path, aspectRatio: 2 / 3);
    expect(selected(tester, '2:3'), isTrue);
    expect(selected(tester, 'Original'), isFalse);
    expect(find.byType(Crop), findsOneWidget);
  });
}
