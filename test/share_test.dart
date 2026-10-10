import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/services/shared_text.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

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
  group('SharedText', () {
    test('a bare link is a link with no caption', () {
      final s = SharedText.parse('  https://news.example.com/story?id=7 ');
      expect(s.isLink, isTrue);
      expect(s.url, 'https://news.example.com/story?id=7');
      expect(s.caption, isEmpty);
    });

    test('a headline shared with its link is still a link', () {
      // How news apps and feeds share an article.
      for (final (shared, caption) in [
        ('Rain sets records across the coast\nhttps://news.example.com/a',
            'Rain sets records across the coast'),
        ('Rain sets records - Example News https://news.example.com/a',
            'Rain sets records - Example News'),
        ('https://news.example.com/a\n\nRain sets records',
            'Rain sets records'),
        ('Worth a read (https://news.example.com/a).', 'Worth a read'),
      ]) {
        final s = SharedText.parse(shared);
        expect(s.isLink, isTrue, reason: shared);
        expect(s.url, 'https://news.example.com/a', reason: shared);
        expect(s.caption, caption, reason: shared);
      }
    });

    test('writing that mentions a link stays a note', () {
      final long = '${'A thought I had while reading this. ' * 10}'
          'https://news.example.com/a';
      expect(SharedText.parse(long).isLink, isFalse);
      expect(SharedText.parse(long).caption, long);

      final lines = 'one\ntwo\nthree\nfour\nfive\nhttps://x.example.com';
      expect(SharedText.parse(lines).isLink, isFalse);

      final two = 'Compare https://a.example.com and https://b.example.com';
      expect(SharedText.parse(two).isLink, isFalse);
    });

    test('plain text is a note; nothing is nothing', () {
      expect(SharedText.parse('Buy milk').isLink, isFalse);
      expect(SharedText.parse('Buy milk').caption, 'Buy milk');
      expect(SharedText.parse('   ').caption, isEmpty);
    });
  });

  group('importing a share', () {
    late Directory root;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('braim_share_test');
      Directory('${root.path}/tmp').createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProvider(root.path);
    });

    tearDownAll(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    setUp(() {
      for (final name in ['keepy_data.json', 'keepy_data.bak']) {
        final f = File('${root.path}/$name');
        if (f.existsSync()) f.deleteSync();
      }
    });

    /// Starts the app with [records] waiting in the share inbox, as the
    /// popup leaves them. Previews can't be fetched in a test.
    Future<AppState> importing(List<Map<String, dynamic>> records) async {
      for (final r in records) {
        await StorageService.instance.saveShareInbox(r);
      }
      final state = AppState();
      await http.runWithClient(state.init,
          () => MockClient((_) async => http.Response('', 404)));
      await state.flushNow();
      return state;
    }

    test('a link keeps the title and note typed in the popup', () async {
      final state = await importing([
        {
          'url': 'https://news.example.com/a',
          'title': 'Rain sets records',
          'body': 'Ask about the insurance.',
          'spaceId': null,
        },
      ]);
      final card = state.cards.single;
      expect(card.url, 'https://news.example.com/a');
      expect(card.noteTitle, 'Rain sets records');
      expect(jsonEncode(card.blocks.map((b) => b.toJson()).toList()),
          contains('Ask about the insurance.'));
      expect(state.notes, isEmpty); // a spark, not a note
      state.dispose();
    });

    test('shared text becomes the note body, with an optional title',
        () async {
      final state = await importing([
        {'noteText': 'Milk, eggs, bread', 'title': 'Groceries'},
        {'noteText': 'An untitled thought'},
      ]);
      final titled = state.notes.firstWhere((n) => n.title == 'Groceries');
      expect(titled.textPreview, contains('Milk, eggs, bread'));
      expect(state.notes.any((n) => n.textPreview.contains('untitled')),
          isTrue);
      state.dispose();
    });

    test('a share saved by the old popup still imports', () async {
      final state = await importing([
        {'url': 'https://old.example.com/x', 'spaceId': null},
        {'noteText': '# Heading\nSome text', 'spaceId': null},
      ]);
      expect(state.cards.single.noteTitle, isEmpty);
      expect(state.notes.single.title, 'Heading');
      state.dispose();
    });
  });
}
