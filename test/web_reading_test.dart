import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/space.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/services/db/db_store.dart';
import 'package:braim/services/library_search.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/web/web_assets.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_security.dart';
import 'package:braim/web/web_server.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

class _Conn implements HttpConnectionInfo {
  @override
  InternetAddress get remoteAddress => InternetAddress('192.168.1.50');
  @override
  int get remotePort => 50123;
  @override
  int get localPort => 8420;
}

Future<ByteData> _loadFromDisk(String key) async =>
    ByteData.sublistView(await File(key).readAsBytes());

const _host = '192.168.1.23:8420';

String _delta(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

NoteBlock _text(String text) =>
    NoteBlock(type: NoteBlockType.text, text: _delta(text));

void main() {
  late Directory root;
  late Directory images;
  late AppState state;
  late BraimWebServer server;
  late String token;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_reading_test');
    images = Directory('${root.path}/images')..createSync();
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  NoteBlock image(String name) {
    File('${images.path}/$name').writeAsBytesSync([0xFF, 0xD8, 0xFF, 1, 2, 3]);
    return NoteBlock(
      type: NoteBlockType.image,
      imagePath: '${images.path}/$name',
    );
  }

  /// A library with something of every kind the web must show or hide.
  AppData library() => AppData(
    notes: [
      Note(
        id: 'visible',
        title: 'Groceries',
        tags: ['home'],
        colorValue: 0xFFFFF1B8,
        blocks: [
          _text(
            'Milk and [[Secret plan]] and [[Old idea]] and [[Shared page]]',
          ),
          image('visible.jpg'),
          NoteBlock(
            type: NoteBlockType.link,
            url: 'https://example.com/article',
            linkTitle: 'An <b>article</b>',
            linkSite: 'example.com',
          ),
        ],
      ),
      Note(
        id: 'md',
        title: 'Readme',
        markdown: true,
        blocks: [
          NoteBlock(
            type: NoteBlockType.text,
            text: '# Readme\n\nSome **markdown** <script>x</script>',
          ),
        ],
      ),
      Note(
        id: 'crypt',
        title: 'Secret plan',
        spaceId: kCryptSpaceId,
        blocks: [_text('hidden words'), image('crypt.jpg')],
      ),
      Note(
        id: 'deleted',
        title: 'Gone note',
        deletedAt: DateTime.now(),
        blocks: [_text('deleted words'), image('deleted.jpg')],
      ),
      Note(
        id: 'archived',
        title: 'Old idea',
        archived: true,
        blocks: [_text('archived words'), image('archived.jpg')],
      ),
      Note(
        id: 'journal',
        title: 'Dear diary',
        journalDate: '2026-09-30',
        blocks: [_text('journal words')],
      ),
      Note(id: 'tagged-other', title: 'Work stuff', tags: ['work']),
    ],
    spaces: [Space(id: 'fold', name: 'Fold')],
    cards: [
      TweetCard(
        id: 'spark',
        url: 'https://example.com/post',
        noteTitle: 'Shared page',
        siteName: 'Example',
        text: 'Hi <script>alert(1)</script>',
        articleText: 'Body <img src=x onerror=alert(2)>',
        videoTranscript: '<iframe src="https://evil.example"></iframe>',
        imageUrl: 'https://example.com/cover.png',
        blocks: [_text('my note on it')],
      ),
      TweetCard(
        id: 'crypt-spark',
        url: 'https://example.com/hidden',
        noteTitle: 'Hidden spark',
        spaceId: kCryptSpaceId,
      ),
    ],
  );

  Future<Response> get(String path, {String? session}) => Future.sync(
    () => server.handler(
      Request(
        'GET',
        Uri.parse('http://$_host$path'),
        headers: {'host': _host, 'cookie': 'braim_session=${session ?? token}'},
        context: {kConnectionInfoKey: _Conn()},
      ),
    ),
  );

  Future<String> body(String path) async {
    final r = await get(path);
    expect(r.statusCode, 200, reason: path);
    return r.readAsString();
  }

  setUp(() async {
    for (final name in [
      'keepy_data.json',
      'keepy_data.bak',
      'keepy_json_ahead',
      WebSessionStore.fileName,
    ]) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
    await StorageService.instance.save(library());
    state = AppState();
    await state.init();
    final sessions = WebSessionStore(
      File('${root.path}/${WebSessionStore.fileName}'),
    );
    server =
        BraimWebServer(
            state: state,
            sessions: sessions,
            assets: WebAssets(load: _loadFromDisk),
            imagesDir: () async => images,
          )
          ..addresses = const ['192.168.1.23']
          ..debugPort = 8420;
    await server.prepare();
    token = (await sessions.create(label: 'test')).token;
  });

  tearDown(() async {
    await server.stop();
    await state.flushNow();
    state.dispose();
  });

  group('pages', () {
    test(
      'the notes feed shows web-visible notes, ignoring the tag filter',
      () async {
        state.setActiveTag('work'); // the phone's own view
        final html = await body('/');
        expect(html, contains('Groceries'));
        expect(html, contains('Work stuff'));
        expect(html, contains('Readme'));
        expect(html, contains('href="&#47;notes&#47;visible"'));
        expect(html, contains('src="&#47;img&#47;visible.jpg"'));
        expect(html, contains('--note:#fff1b8'));
        expect(html, contains('<span class="tag">#home</span>'));
        expect(html, contains('<main data-list>'));
      },
    );

    test('?partial=1 returns only the main area, for live refresh', () async {
      final html = await body('/?partial=1');
      expect(html, startsWith('<article class="window list-window">'));
      expect(html, isNot(contains('<html')));
      expect(html, contains('Groceries'));
      // The desk accessories sit outside main, so a refresh leaves them be.
      expect(html, isNot(contains('desk-row')));
    });

    test(
      'the Notes page has the desk accessories; every page the footer line',
      () async {
        final feed = await body('/');
        expect(feed, contains('<div class="desk-row">'));
        expect(feed, contains('data-clock-time'));
        expect(feed, contains('<canvas data-life'));
        expect(feed, contains('class="sysline"'));
        final sparks = await body('/sparks');
        expect(sparks, isNot(contains('desk-row')));
        expect(sparks, contains('class="sysline"'));
      },
    );

    test(
      'a note page: title, body, images, link cards, watch attributes',
      () async {
        final html = await body('/notes/visible');
        // The title sits in the window's title bar, after any colour label.
        expect(html, contains('<h1 class="window-title"><span>'));
        expect(html, contains('Groceries</span></h1>'));
        expect(html, contains('<p>Milk and '));
        expect(
          html,
          contains('<a class="wiki" href="&#47;link?to=Secret+plan">'),
        );
        expect(html, contains('<img src="&#47;img&#47;visible.jpg"'));
        expect(html, contains('class="linkcard"'));
        expect(html, contains('An &lt;b&gt;article&lt;&#47;b&gt;'));
        final note = state.noteById('visible')!;
        expect(
          html,
          contains('data-watch="&#47;api&#47;notes&#47;visible&#47;meta"'),
        );
        expect(
          html,
          contains('data-updated="${note.updatedAt.millisecondsSinceEpoch}"'),
        );

        final meta = await get('/api/notes/visible/meta');
        expect(jsonDecode(await meta.readAsString()), {
          'updatedAt': note.updatedAt.millisecondsSinceEpoch,
          'leaseHolder': null,
        });
      },
    );

    test('a Markdown note renders sanitised Markdown', () async {
      final html = await body('/notes/md');
      expect(html, contains('<div class="note-body markdown">'));
      expect(html, contains('<h1>Readme</h1>'));
      expect(html, contains('<strong>markdown</strong>'));
      expect(html, isNot(contains('<script>x')));
    });

    test('a note page reflects a change made on the phone', () async {
      final before = await body('/notes/visible');
      expect(before, contains('Milk'));
      final n = state.noteById('visible')!;
      n.blocks.first.text = _delta('Bread');
      await state.upsertNote(n);
      final after = await body('/notes/visible');
      expect(after, contains('Bread'));
      expect(after, isNot(contains('Milk')));
    });

    test('sparks: list and page, with scraped text escaped', () async {
      final list = await body('/sparks');
      expect(list, contains('Shared page'));
      expect(list, isNot(contains('Hidden spark')));
      expect(list, contains('src="https:&#47;&#47;example.com&#47;cover.png"'));

      final html = await body('/sparks/spark');
      expect(html, contains('<h2 class="spark-title">Shared page</h2>'));
      expect(html, contains('Hi &lt;script&gt;alert(1)&lt;&#47;script&gt;'));
      expect(html, contains('&lt;img src=x onerror=alert(2)&gt;'));
      expect(html, contains('&lt;iframe'));
      expect(html, isNot(contains('<script>alert')));
      expect(html, isNot(contains('<img src=x')));
      expect(html, isNot(contains('<iframe')));
      expect(html, contains('my note on it'));
      expect(html, contains('rel="noopener noreferrer" target="_blank"'));

      final meta = await get('/api/sparks/spark/meta');
      expect(meta.statusCode, 200);
    });

    test('search lists notes and sparks; empty queries just prompt', () async {
      final html = await body('/search?q=groceries');
      expect(html, contains('Groceries'));
      expect(html, contains('<main data-list>'));
      final sparks = await body('/search?q=shared');
      expect(sparks, contains('Shared page'));
      expect(
        await body('/search?q='),
        contains('Search your notes and sparks.'),
      );
      expect(await body('/search?q=zzzz-nothing'), contains('No matches'));
    });

    test('/link opens the note or spark a wiki-link names', () async {
      final r = await get('/link?to=groceries');
      expect(r.statusCode, 302);
      expect(r.headers['location'], '/notes/visible');
      final s = await get('/link?to=Shared%20page');
      expect(s.headers['location'], '/sparks/spark');
      final missing = await body('/link?to=Nothing%20by%20this%20name');
      expect(missing, contains('Open this on your phone'));
    });
  });

  group('hidden items never reach the web', () {
    for (final (id, title, words, imageName) in [
      ('crypt', 'Secret plan', 'hidden words', 'crypt.jpg'),
      ('deleted', 'Gone note', 'deleted words', 'deleted.jpg'),
      ('archived', 'Old idea', 'archived words', 'archived.jpg'),
    ]) {
      test(
        '$id: not in the feed, search, /link, its page or its images',
        () async {
          // (The visible note links to these titles itself, so the check is
          // for the hidden note's own link and words.)
          final feed = await body('/');
          expect(feed, isNot(contains('&#47;notes&#47;$id"')));
          expect(feed, isNot(contains('<h2 class="card-title">$title')));
          expect(feed, isNot(contains(words)));

          for (final q in [title, words, id]) {
            final html = await body('/search?q=${Uri.encodeQueryComponent(q)}');
            expect(html, isNot(contains('&#47;notes&#47;$id"')), reason: q);
            expect(
              html,
              isNot(contains('<span class="r-title">$title')),
              reason: q,
            );
          }

          final link = await get('/link?to=${Uri.encodeQueryComponent(title)}');
          expect(link.statusCode, 200); // the same page as a missing title
          final linkHtml = await link.readAsString();
          expect(linkHtml, contains('Open this on your phone'));
          expect(linkHtml, isNot(contains('&#47;notes&#47;$id"')));

          expect((await get('/notes/$id')).statusCode, 404);
          expect((await get('/notes/$id?partial=1')).statusCode, 404);
          expect((await get('/api/notes/$id/meta')).statusCode, 404);
          expect(File('${images.path}/$imageName').existsSync(), isTrue);
          expect((await get('/img/$imageName')).statusCode, 404);
        },
      );
    }

    test('a hidden page looks exactly like a missing one', () async {
      final hidden = await get('/notes/crypt');
      final missing = await get('/notes/no-such-note');
      expect(hidden.statusCode, missing.statusCode);
      expect(await hidden.readAsString(), await missing.readAsString());
    });

    test('journal entries and Crypt sparks stay on the phone', () async {
      expect((await get('/notes/journal')).statusCode, 404);
      expect(await body('/search?q=diary'), isNot(contains('Dear diary')));
      expect((await get('/sparks/crypt-spark')).statusCode, 404);
      expect((await get('/api/sparks/crypt-spark/meta')).statusCode, 404);
    });

    test('a note put in the Crypt on the phone vanishes at once', () async {
      expect((await get('/notes/visible')).statusCode, 200);
      expect((await get('/img/visible.jpg')).statusCode, 200);
      await state.moveNoteToSpace('visible', kCryptSpaceId);
      expect((await get('/notes/visible')).statusCode, 404);
      expect((await get('/img/visible.jpg')).statusCode, 404);
      expect(await body('/'), isNot(contains('Groceries')));
      expect(await body('/search?q=groceries'), isNot(contains('Groceries')));
    });
  });

  group('/img', () {
    test('serves an image a visible note uses, cached for good', () async {
      final r = await get('/img/visible.jpg');
      expect(r.statusCode, 200);
      expect(r.mimeType, 'image/jpeg');
      expect(
        r.headers['cache-control'],
        'private, max-age=31536000, immutable',
      );
      expect(await r.read().expand((b) => b).toList(), [
        0xFF,
        0xD8,
        0xFF,
        1,
        2,
        3,
      ]);
    });

    test('rejects path traversal and names not in webImageNames', () async {
      File('${root.path}/secret.jpg').writeAsBytesSync([1]);
      File('${images.path}/stray.jpg').writeAsBytesSync([1]);
      for (final path in [
        '/img/..%2Fsecret.jpg',
        '/img/..%5Csecret.jpg',
        '/img/%2E%2E%2Fkeepy_data.json',
        '/img/stray.jpg', // in the folder, but no visible note uses it
        '/img/visible.jpg%00.png',
        '/img/.visible.jpg',
        '/img/missing.jpg',
        '/img/',
      ]) {
        final r = await get(path);
        expect(r.statusCode, anyOf(404, 302), reason: path);
        expect(r.mimeType, isNot(startsWith('image/')), reason: path);
      }
      expect(
        (await get('/img/../keepy_data.json')).statusCode,
        anyOf(404, 302),
      );
    });

    test('needs a linked browser', () async {
      final r = await get('/img/visible.jpg', session: 'x' * 43);
      expect(r.statusCode, 302);
    });
  });

  group('searchLibrary', () {
    /// The universal search's merge exactly as it read before the
    /// extraction (lib/widgets/universal_search.dart, build()).
    ({List<String> notes, List<String> cards, List<String> archived}) before(
      AppState state,
      String query,
      List<SearchHit>? hits,
    ) {
      final q = query.toLowerCase().trim();
      final qTag = q.replaceAll('#', '');
      bool noteMatches(Note n) {
        final space = state.spaceById(n.spaceId);
        return n.title.toLowerCase().contains(q) ||
            n.textPreview.toLowerCase().contains(q) ||
            (qTag.isNotEmpty && n.tags.any((t) => t.contains(qTag))) ||
            (space?.name.toLowerCase().contains(q) ?? false);
      }

      bool cardMatches(TweetCard c) {
        return c.text.toLowerCase().contains(q) ||
            c.noteTitle.toLowerCase().contains(q) ||
            c.authorName.toLowerCase().contains(q) ||
            c.authorHandle.toLowerCase().contains(q) ||
            c.url.toLowerCase().contains(q);
      }

      List<T> merge<T>(
        List<T> visible,
        String kind,
        bool Function(T) matches,
        String Function(T) idOf,
      ) {
        if (hits == null) return visible.where(matches).toList();
        final byId = {for (final v in visible) idOf(v): v};
        final out = <T>[];
        final seen = <String>{};
        for (final h in hits) {
          if (h.kind != kind) continue;
          final v = byId[h.id];
          if (v != null && seen.add(h.id)) out.add(v);
        }
        for (final v in visible) {
          if (matches(v) && seen.add(idOf(v))) out.add(v);
        }
        return out;
      }

      return (
        notes: [
          for (final n in merge(
            state.searchableNotes,
            'note',
            noteMatches,
            (n) => n.id,
          ))
            n.id,
        ],
        cards: [
          for (final c in merge(
            state.searchableCards,
            'card',
            cardMatches,
            (c) => c.id,
          ))
            c.id,
        ],
        archived: [
          for (final n in merge(
            state.archivedNotes,
            'note',
            noteMatches,
            (n) => n.id,
          ))
            n.id,
          for (final c in merge(
            state.archivedCards,
            'card',
            cardMatches,
            (c) => c.id,
          ))
            c.id,
        ],
      );
    }

    test(
      'returns what the phone widget showed before the extraction',
      () async {
        final queries = [
          '',
          'milk',
          'GROCERIES',
          '#home',
          'home',
          'example',
          'old',
          'shared',
          'words',
          'fold',
          'zzz',
          '  readme  ',
        ];
        final hitSets = <List<SearchHit>?>[
          null,
          [],
          [
            (id: 'tagged-other', kind: 'note'),
            (id: 'crypt', kind: 'note'), // never surfaces
            (id: 'spark', kind: 'card'),
            (id: 'archived', kind: 'note'),
            (id: 'visible', kind: 'note'),
            (id: 'visible', kind: 'note'), // duplicates collapse
          ],
        ];
        for (final query in queries) {
          for (final hits in hitSets) {
            final q = query.toLowerCase().trim();
            final now = matchLibrary(state, q, hits);
            final then = before(state, query, hits);
            final reason = '"$query" with $hits';
            expect(
              [for (final n in now.notes) n.id],
              then.notes,
              reason: reason,
            );
            expect(
              [for (final c in now.cards) c.id],
              then.cards,
              reason: reason,
            );
            expect(
              [
                for (final n in now.archivedNotes) n.id,
                for (final c in now.archivedCards) c.id,
              ],
              then.archived,
              reason: reason,
            );
          }
        }

        // The async entry point the web uses agrees too.
        final found = await searchLibrary(state, 'Milk');
        expect([
          for (final n in found.notes) n.id,
        ], before(state, 'Milk', await state.searchIndex('milk')).notes);
      },
    );
  });
}
