// Braim Web, Phase 6: the shelf, a book's contents with reordering and Add
// chapter, the reader and the page editor. See docs/braim-web-plan.md, 9.4.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/book.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
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

/// A page of [book] with one paragraph of [text].
Note _page(
  String id,
  String title,
  String kind,
  int order, {
  String book = 'novel',
  String text = '',
}) => Note(
  id: id,
  title: title,
  bookId: book,
  bookPageKind: kind,
  bookOrder: order,
  blocks: [
    NoteBlock(
      type: NoteBlockType.text,
      text: jsonEncode([
        {'insert': '$text\n'},
      ]),
    ),
  ],
);

void main() {
  late Directory root;
  late AppState state;
  late BraimWebServer server;
  late WebSessionStore sessions;
  late String token;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_books_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

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
    await StorageService.instance.save(
      AppData(
        notes: [
          _page('contents', 'Contents', BookPageKind.contents, 0),
          _page('intro', 'Introduction', BookPageKind.intro, 1, text: 'Hello.'),
          _page('ded', 'For M', BookPageKind.dedication, 2, text: 'For M.'),
          _page('ch1', 'Chapter I', BookPageKind.chapter, 3, text: 'It began.'),
          _page(
            'ch2',
            'Chapter II',
            BookPageKind.chapter,
            4,
            text: 'It ended.',
          ),
          _page('sketch', 'Villain sketch', BookPageKind.note, 0),
          _page('old1', 'Old chapter', BookPageKind.chapter, 1, book: 'old'),
          _page('gone1', 'Gone chapter', BookPageKind.chapter, 1, book: 'gone'),
        ],
        spaces: const [],
        cards: const [],
        books: [
          Book(
            id: 'novel',
            title: 'Novel',
            author: 'A. Writer',
            description: 'A story.',
            coverPath: '/x/cover.jpg',
            fontFamily: 'EB Garamond',
          ),
          Book(id: 'old', title: 'Shelved', archived: true),
          Book(id: 'gone', title: 'Binned', deletedAt: DateTime(2026, 9, 1)),
        ],
      ),
    );
    state = AppState();
    await state.init();
    sessions = WebSessionStore(
      File('${root.path}/${WebSessionStore.fileName}'),
    );
    server =
        BraimWebServer(
            state: state,
            sessions: sessions,
            assets: WebAssets(load: _loadFromDisk),
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

  Future<Response> send(String method, String path, {Object? json}) =>
      Future.sync(
        () => server.handler(
          Request(
            method,
            Uri.parse('http://$_host$path'),
            headers: {
              'host': _host,
              'cookie': 'braim_session=$token',
              'x-braim-csrf': csrfTokenFor(token),
              if (json != null) 'content-type': 'application/json',
            },
            body: json == null ? null : jsonEncode(json),
            context: {kConnectionInfoKey: _Conn()},
          ),
        ),
      );

  Future<Response> post(String path, [Object? json]) =>
      send('POST', path, json: json ?? const {});

  /// A page's HTML with the escaped slashes put back, for readable checks.
  Future<String> page(String path) async {
    final r = await send('GET', path);
    expect(r.statusCode, 200, reason: path);
    return (await r.readAsString()).replaceAll('&#47;', '/');
  }

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  /// The page titles a contents page lists, in order.
  List<String> listed(String html) => [
    for (final m in RegExp(
      r'class="c-title" href="[^"]*">([^<]*)</a>',
    ).allMatches(html))
      m.group(1)!,
  ];

  Future<void> move(String pageId, int delta, {int status = 200}) async {
    final r = await post('/api/books/novel/pages/$pageId/move', {
      'delta': delta,
    });
    expect(r.statusCode, status, reason: '$pageId $delta');
  }

  /// Every page's order is its place: 0, 1, 2… with nothing skipped or doubled.
  void expectConsistentOrder() {
    final orders = [for (final p in state.bookPages('novel')) p.bookOrder];
    expect(orders, List.generate(orders.length, (i) => i));
  }

  test('the shelf shows live books, with their covers', () async {
    final html = await page('/books');
    expect(html, contains('href="/books/novel"'));
    expect(html, contains('<img class="book-cover" src="/img/cover.jpg"'));
    expect(html, contains('2 chapters'));
    expect(html, isNot(contains('Shelved')));
    expect(html, isNot(contains('Binned')));
    expect(html, contains('class="tab current" href="/books"'));
    expect(html, contains('books.css'));
  });

  test(
    'the contents lists the manuscript, not the Contents page or workshop notes',
    () async {
      final html = await page('/books/novel');
      expect(listed(html), [
        'Introduction',
        'For M',
        'Chapter I',
        'Chapter II',
      ]);
      expect(html, isNot(contains('Villain sketch')));
      expect(html, contains('href="/books/novel/pages/ch1/edit"'));
      expect(html, contains('href="/books/novel/read#page-ch1"'));
      expect(html, contains('data-book-add="/api/books/novel/chapters"'));
      // The first page can't go up, nor the last down.
      expect(
        html,
        contains(
          'data-book-move="/api/books/novel/pages/intro/move" data-delta="-1" title="Move up" aria-label="Move up" disabled',
        ),
      );
      expect(
        html,
        contains(
          'data-book-move="/api/books/novel/pages/ch2/move" data-delta="1" title="Move down" aria-label="Move down" disabled',
        ),
      );
      expect(
        html,
        contains(
          'A. Writer · 2 chapters · ${state.bookWordCount('novel')} words',
        ),
      );
    },
  );

  test('reordering keeps every page\'s order consistent', () async {
    await move('ch1', -1);
    expect(state.bookPages('novel').map((p) => p.id), [
      'contents',
      'intro',
      'ch1',
      'ded',
      'ch2',
    ]);
    expectConsistentOrder();
    await move('intro', 1);
    await move('intro', 1);
    expect(listed(await page('/books/novel')), [
      'Chapter I',
      'For M',
      'Introduction',
      'Chapter II',
    ]);
    expectConsistentOrder();
    // The Contents page stays first, and the ends stay put.
    expect(state.bookPages('novel').first.id, 'contents');
    await move('ch1', -1, status: 400);
    await move('ch2', 1, status: 400);
    await move('ch2', 2, status: 400);
    await move('contents', 1, status: 404);
    await move('sketch', -1, status: 404);
    expectConsistentOrder();
  });

  test(
    'pages being edited elsewhere are not moved from under the editor',
    () async {
      state.acquireEditLease('ded', kPhoneLease);
      await move('ch1', -1, status: 409); // ded would move down
      await move('intro', 1, status: 409);
      await move('ch2', -1); // ded keeps its place
      expect(state.noteById('ded')!.bookOrder, 2);
    },
  );

  test('a new chapter is named with the next Roman numeral', () async {
    final r = await post('/api/books/novel/chapters');
    expect(r.statusCode, 201);
    final b = await json(r);
    final chapter = state.noteById(b['id'] as String)!;
    expect(chapter.title, 'Chapter III');
    expect(chapter.bookPageKind, BookPageKind.chapter);
    expect(state.bookPages('novel').last.id, chapter.id);
    expect(b['edit'], '/books/novel/pages/${chapter.id}/edit');
    expectConsistentOrder();
  });

  test(
    'the reader runs every page in order, in the book\'s typeface',
    () async {
      final html = await page('/books/novel/read');
      final order = [
        for (final m in RegExp(r'id="page-([^"]+)"').allMatches(html))
          m.group(1),
      ];
      expect(order, ['intro', 'ded', 'ch1', 'ch2']);
      expect(html, contains('<h2 class="page-heading">Chapter I</h2>'));
      // A dedication is quiet matter: no heading.
      expect(html, contains('<section class="book-page quiet" id="page-ded">'));
      expect(html, isNot(contains('<h2 class="page-heading">For M</h2>')));
      expect(html, contains('<p>For M.</p>'));
      expect(html, contains('--serif:&quot;EB Garamond&quot;'));
      expect(html, isNot(contains('Villain sketch')));
    },
  );

  test('archived and deleted books answer 404 everywhere', () async {
    for (final id in ['old', 'gone', 'nope']) {
      expect((await send('GET', '/books/$id')).statusCode, 404, reason: id);
      expect((await send('GET', '/books/$id/read')).statusCode, 404);
      expect((await post('/api/books/$id/chapters')).statusCode, 404);
    }
    expect((await send('GET', '/books/old/pages/old1/edit')).statusCode, 404);
    expect((await send('GET', '/notes/old1')).statusCode, 404);
    expect((await send('GET', '/notes/gone1')).statusCode, 404);
    expect(
      (await post('/api/books/gone/pages/gone1/move', {
        'delta': -1,
      })).statusCode,
      404,
    );
  });

  test('workshop notes never appear', () async {
    expect((await send('GET', '/notes/sketch')).statusCode, 404);
    expect((await send('GET', '/notes/sketch/edit')).statusCode, 404);
    expect(
      (await send('GET', '/books/novel/pages/sketch/edit')).statusCode,
      404,
    );
    expect(await page('/books/novel'), isNot(contains('sketch')));
  });

  test('a page from another book is not this book\'s', () async {
    expect((await send('GET', '/books/novel/pages/old1/edit')).statusCode, 404);
    expect(
      (await post('/api/books/novel/pages/old1/move', {'delta': 1})).statusCode,
      404,
    );
  });

  test('the Contents page opens as the book\'s contents', () async {
    final r = await send('GET', '/notes/contents');
    expect(r.statusCode, 302);
    expect(r.headers['location'], '/books/novel');
    expect((await send('GET', '/notes/contents/edit')).statusCode, 302);
    expect(
      (await send('GET', '/books/novel/pages/contents/edit')).statusCode,
      404,
    );
  });

  test('a book page reads in its book and edits there', () async {
    final html = await page('/notes/ch1');
    expect(html, contains('<a href="/books/novel">In Novel</a>'));
    expect(html, contains('<a class="close-box" href="/books/novel"'));
    expect(html, contains('href="/books/novel/read#page-ch1"'));
    expect(html, contains('data-edit="/books/novel/pages/ch1/edit"'));
    expect(html, contains('class="tab current" href="/books"'));

    final editor = await page('/books/novel/pages/ch1/edit');
    expect(editor, contains('&quot;view&quot;:&quot;/books/novel&quot;'));
    expect(editor, contains('--serif:&quot;EB Garamond&quot;'));
    // No Delete: deleting a page is permanent, so it stays on the phone.
    expect(editor, isNot(contains('data-action="delete"')));
  });
}
