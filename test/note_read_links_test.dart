import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:braim/l10n/gen/app_localizations.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/screens/card_detail_screen.dart';
import 'package:braim/screens/note_editor_screen.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// Records every URL the app asks to open instead of opening it.
class _FakeLauncher extends UrlLauncherPlatform {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late Directory root;
  late _FakeLauncher launcher;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_links_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  const link = {'link': 'https://example.com'};

  /// A rich-text body whose one text block is [ops] (a Quill delta).
  List<NoteBlock> body(List<Map<String, Object>> ops) =>
      [NoteBlock(type: NoteBlockType.text, text: jsonEncode(ops))];

  final linkLine = [
    {'insert': 'Visit '},
    {'insert': 'Example', 'attributes': link},
    {'insert': ' today\n'},
  ];

  /// Like [pump], but builds the screen from the booted state — so it can be
  /// handed the state's own live objects, as the app does.
  Future<AppState> pumpWith(
      WidgetTester tester, Widget Function(AppState) screen,
      {List<Note> notes = const [], List<TweetCard> cards = const []}) async {
    for (final name in ['keepy_data.json', 'keepy_data.bak']) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await tester.runAsync(() => StorageService.instance.save(
        AppData(notes: notes, spaces: const [], cards: cards)));
    final state = AppState();
    await tester.runAsync(state.init);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FlutterQuillLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen(state),
      ),
    ));
    await tester.pumpAndSettle();
    return state;
  }

  /// Boots an [AppState] holding [notes] and [cards], then shows [screen].
  Future<AppState> pump(WidgetTester tester, Widget screen,
          {List<Note> notes = const [], List<TweetCard> cards = const []}) =>
      pumpWith(tester, (_) => screen, notes: notes, cards: cards);

  Future<void> close(WidgetTester tester, AppState state) async {
    // Unmount so the screen's autosave timer is cancelled.
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  Future<void> tapExample(WidgetTester tester) async {
    await tester.tapOnText(find.textRange.ofSubstring('Example'));
    await tester.pumpAndSettle();
  }

  group('note read view', () {
    testWidgets('a hyperlink in a plain line opens', (tester) async {
      final note = Note(title: 'Links', blocks: body(linkLine));
      final state = await pump(
          tester, NoteEditorScreen(note: note, isNew: false),
          notes: [note]);
      await tapExample(tester);
      expect(launcher.launched, ['https://example.com']);
      await close(tester, state);
    });

    testWidgets('a hyperlink in a checklist item opens', (tester) async {
      final note = Note(
          title: 'Links',
          blocks: body([
            {'insert': 'Book on '},
            {'insert': 'Example', 'attributes': link},
            {
              'insert': '\n',
              'attributes': {'list': 'unchecked'},
            },
          ]));
      final state = await pump(
          tester, NoteEditorScreen(note: note, isNew: false),
          notes: [note]);
      await tapExample(tester);
      expect(launcher.launched, ['https://example.com']);
      await close(tester, state);
    });

    testWidgets('edit, save with the check button, then the link opens',
        (tester) async {
      final note = Note(title: 'Links', blocks: body(linkLine));
      final state = await pump(tester,
          NoteEditorScreen(note: note, isNew: false, startEditing: true),
          notes: [note]);
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      await tapExample(tester);
      expect(launcher.launched, ['https://example.com']);
      await close(tester, state);
    });
  });

  group('spark read view', () {
    // The reported bug: a spark's note flattened its body to plain text when
    // read, so a hyperlink added in the editor stopped being a link.
    testWidgets('a hyperlink in the spark\'s note opens', (tester) async {
      final card = TweetCard(
          url: 'https://example.org/post',
          fetched: true,
          noteTitle: 'My take',
          blocks: body(linkLine));
      final state =
          await pump(tester, CardDetailScreen(card: card), cards: [card]);
      await tapExample(tester);
      expect(launcher.launched, ['https://example.com']);
      await close(tester, state);
    });

    testWidgets('a checklist item in the spark\'s note ticks and saves',
        (tester) async {
      final card = TweetCard(
          url: 'https://example.org/post',
          fetched: true,
          blocks: body([
            {'insert': 'Read it'},
            {
              'insert': '\n',
              'attributes': {'list': 'unchecked'},
            },
          ]));
      final state =
          await pump(tester, CardDetailScreen(card: card), cards: [card]);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);
      final saved = state.cardById(card.id)!;
      expect(saved.blocks.single.text, contains('"checked"'));
      await close(tester, state);
    });
  });

  group('review fixes', () {
    testWidgets('a pasted-link card opens its link from the read view',
        (tester) async {
      final note = Note(title: 'Card', blocks: [
        NoteBlock(
            type: NoteBlockType.link,
            url: 'https://example.com/card',
            linkTitle: 'Example card'),
      ]);
      final state = await pump(
          tester, NoteEditorScreen(note: note, isNew: false),
          notes: [note]);
      await tester.tap(find.text('Example card'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://example.com/card']);
      await close(tester, state);
    });

    testWidgets('following [[links]] back to an open note returns to it',
        (tester) async {
      // Two open screens on one note overwrite each other's edits, so going
      // Alpha -> [[Beta]] -> [[Alpha]] must land back on the first Alpha.
      final alpha = Note(title: 'Alpha', blocks: body([
        {'insert': 'see [[Beta]]\n'},
      ]));
      final beta = Note(title: 'Beta', blocks: body([
        {'insert': 'back to [[Alpha]]\n'},
      ]));
      final state = await pump(
          tester, NoteEditorScreen(note: alpha, isNew: false),
          notes: [alpha, beta]);

      await tester.tapOnText(find.textRange.ofSubstring('Beta').first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen, skipOffstage: false),
          findsNWidgets(2));

      await tester.tapOnText(find.textRange.ofSubstring('Alpha').first);
      await tester.pumpAndSettle();
      final open = find.byType(NoteEditorScreen, skipOffstage: false);
      expect(open, findsOneWidget);
      expect(tester.widget<NoteEditorScreen>(open).note.id, alpha.id);
      await close(tester, state);
    });

    testWidgets('a fetched YouTube title survives editing the spark',
        (tester) async {
      final card = TweetCard(
          url: 'https://www.youtube.com/watch?v=VTLnDqjfRZQ', fetched: true);
      final oembed = http.Response(
          '{"title":"How X works","author_name":"Channel",'
          '"thumbnail_url":"https://i.ytimg.com/vi/VTLnDqjfRZQ/hqdefault.jpg"}',
          200);
      late AppState state;
      await http.runWithClient(() async {
        // Opened with the state's own card, exactly as the feed opens it.
        state = await pumpWith(
            tester, (s) => CardDetailScreen(card: s.cardById(card.id)!),
            cards: [card]);
      }, () => MockClient((_) async => oembed));
      expect(state.cardById(card.id)!.noteTitle, 'How X works');

      // Edit the spark's note and save: the title field must carry the
      // fetched title, not the empty one it opened with.
      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();
      expect(state.cardById(card.id)!.noteTitle, 'How X works');
      await close(tester, state);
    });
  });
}
