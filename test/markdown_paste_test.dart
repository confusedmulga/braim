import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/screens/circuit_map_screen.dart';
import 'package:braim/services/note_markdown.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/widgets/note_body_editor.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// A reply as an AI chat's Copy button gives it.
const _reply = '''### Weekend plan

Here's a **simple** plan with *a little* of everything:

1. **Saturday**
   - Morning: hike the `ridge trail`
   - Evening: dinner at [Lumen](https://example.com/lumen)

2. **Sunday**
   - [ ] Pack the car
   - [x] Book the cabin

> Keep it ***light***.

---

| Day | Plan |
| --- | --- |
| Sat | Hike |

```
**not bold** - not a bullet
```
#### Notes
Bring \\*snacks\\*.''';

void main() {
  List<RichLine> lines(String md) => richToStyledLines(markdownToDeltaJson(md));

  group('AI-style Markdown becomes note formatting', () {
    late List<RichLine> out;
    setUpAll(() => out = lines(_reply));

    RichLine line(String text) => out.firstWhere((l) => l.text == text,
        orElse: () => throw StateError('no line "$text" in '
            '${out.map((l) => l.text).toList()}'));

    test('headings: ### is a sub-heading, #### a bold line', () {
      expect(line('Weekend plan').header, 2);
      final notes = line('Notes');
      expect(notes.header, 0);
      expect(notes.runs.single.bold, isTrue);
    });

    test('bold, italic, both, links; code keeps its text', () {
      final intro =
          line('Here\'s a simple plan with a little of everything:');
      expect(intro.runs.firstWhere((r) => r.text == 'simple').bold, isTrue);
      expect(intro.runs.firstWhere((r) => r.text == 'a little').italic, isTrue);
      final hike = line('Morning: hike the ridge trail');
      expect(hike.kind, RichLineKind.bullet);
      final dinner = line('Evening: dinner at Lumen');
      expect(dinner.runs.firstWhere((r) => r.text == 'Lumen').link,
          'https://example.com/lumen');
      final light = line('Keep it light.');
      expect(light.quote, isTrue);
      final both = light.runs.firstWhere((r) => r.text == 'light');
      expect(both.bold && both.italic, isTrue);
    });

    test('lists nest by indentation; loose items stay one list', () {
      final sat = line('Saturday');
      expect(sat.kind, RichLineKind.ordered);
      expect(sat.indent, 0);
      expect(line('Morning: hike the ridge trail').indent, 1);
      expect(line('Sunday').kind, RichLineKind.ordered);
      expect(line('Pack the car').kind, RichLineKind.uncheckedItem);
      expect(line('Book the cabin').kind, RichLineKind.checkedItem);
      expect(line('Book the cabin').indent, 1);
      // No empty line between "Evening…" and "Sunday".
      final i = out.indexWhere((l) => l.text == 'Sunday');
      expect(out[i - 1].text, 'Evening: dinner at Lumen');
    });

    test('a table is a line per row; a rule and the fences go', () {
      expect(line('Day  ·  Plan').runs.every((r) => r.bold), isTrue);
      expect(line('Sat  ·  Hike').runs.any((r) => r.bold), isFalse);
      final all = out.map((l) => l.text).join('\n');
      expect(all, isNot(contains('---')));
      expect(all, isNot(contains('```')));
      expect(all, isNot(contains('###')));
      // Inside a code fence, Markdown is text.
      expect(line('**not bold** - not a bullet').kind, RichLineKind.plain);
      // An escaped star is a star.
      expect(line('Bring *snacks*.').runs.any((r) => r.italic), isFalse);
    });

    test('no runs of empty lines', () {
      for (var i = 1; i < out.length; i++) {
        expect(out[i].text.isEmpty && out[i - 1].text.isEmpty, isFalse,
            reason: 'two empty lines at $i');
      }
    });
  });

  test('looksLikeMarkdown: Markdown yes, plain words no', () {
    for (final md in [
      '**Note:** bring water',
      '- one\n- two',
      '1. first',
      '## Title',
      '> quoted',
      'Run `npm test` first',
      'See [docs](https://x.io)',
      '```\ncode\n```',
    ]) {
      expect(looksLikeMarkdown(md), isTrue, reason: md);
    }
    for (final plain in [
      'Buy milk and eggs',
      '5 * 3 = 15',
      'Meet at 10.30, room #4',
      '-5 degrees outside',
      '',
    ]) {
      expect(looksLikeMarkdown(plain), isFalse, reason: plain);
    }
  });

  group('pasting into a note', () {
    late Directory root;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('braim_md_paste_test');
      Directory('${root.path}/tmp').createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProvider(root.path);
    });

    tearDownAll(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<QuillController> pumpEditor(
        WidgetTester tester, String clipboard) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      });
      final state = AppState();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteBodyEditor(
              blocks: [
                NoteBlock(
                    type: NoteBlockType.text,
                    text: jsonEncode([
                      {'insert': 'Before \n'}
                    ])),
              ],
              activeController: ValueNotifier(null),
            ),
          ),
        ),
      ));
      final c =
          tester.widget<QuillEditor>(find.byType(QuillEditor).first).controller;
      c.updateSelection(
          const TextSelection.collapsed(offset: 7), ChangeSource.local);
      return c;
    }

    testWidgets('an AI reply lands formatted', (tester) async {
      final c = await pumpEditor(
          tester, '## Plan\n\n- **Pack** the car\n- Leave at 9');
      // ignore: experimental_member_use
      expect(await tester.runAsync(c.clipboardPaste), isTrue);
      final shown = richToStyledLines(jsonEncode(c.document.toDelta().toJson()));
      expect(shown.map((l) => l.text).join('|'),
          'Before Plan||Pack the car|Leave at 9');
      expect(shown.firstWhere((l) => l.text == 'Pack the car').kind,
          RichLineKind.bullet);
      expect(
          shown
              .firstWhere((l) => l.text == 'Pack the car')
              .runs
              .first
              .bold,
          isTrue);
      expect(c.document.toPlainText(), isNot(contains('**')));
    });

    testWidgets('one formatted line stays in its sentence', (tester) async {
      final c = await pumpEditor(tester, 'a **bold** idea');
      // ignore: experimental_member_use
      expect(await tester.runAsync(c.clipboardPaste), isTrue);
      expect(c.document.toPlainText(), 'Before a bold idea\n');
      expect(c.selection, const TextSelection.collapsed(offset: 18));
    });
  });

  group('Circuit preferences', () {
    late Directory root;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('braim_circuit_pref_test');
      Directory('${root.path}/tmp').createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProvider(root.path);
    });

    tearDownAll(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets("the map's + adds the kind of note chosen in Settings",
        (tester) async {
      final state = AppState();
      await tester.runAsync(state.init);
      late Note first;
      await tester.runAsync(() async {
        first = state.newCircuitRootDraft()..title = 'Trip';
        await state.ensureCircuitRootSaved(first);
        await state.upsertNote(first);
        await state.setCircuitPlusMarkdown(true);
      });
      // Kept with the library, like every setting.
      await tester.runAsync(state.flushNow);
      final saved = await tester.runAsync(StorageService.instance.load);
      expect(saved!.circuitPlusCreates, 'markdown');

      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...FlutterQuillLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: CircuitMapScreen(circuitId: first.id),
        ),
      ));
      // The map keeps a gentle highlight going, so frames are pumped rather
      // than waiting for it to settle.
      Future<void> frames() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await frames();
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await frames();
      final child = state.circuitChildren(first.id).single;
      expect(child.markdown, isTrue);

      await tester.pumpWidget(const SizedBox());
      // The save the tap started does real file work under the test's clock:
      // let both move until it's done, then flush.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.runAsync(state.flushNow);
      state.dispose();
    });
  });
}
