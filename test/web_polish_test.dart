// Braim Web, Phase 8: photos from the computer into a note and out again,
// tags and colour from the editor, and Print. See docs/braim-web-plan.md.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/book.dart';
import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/theme/app_theme.dart' show NoteColors;
import 'package:braim/web/web_api.dart';
import 'package:braim/web/web_assets.dart';
import 'package:braim/web/web_auth.dart';
import 'package:braim/web/web_pages.dart' show imageName;
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

/// The first bytes of a PNG, then filler: enough for the server's check.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  ...List.filled(64, 7),
]);

String _delta(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  late Directory root;
  late AppState state;
  late BraimWebServer server;
  late WebSessionStore sessions;
  late String token;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_polish_test');
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
          Note(
            id: 'rich',
            title: 'Trip',
            tags: ['travel'],
            blocks: [
              NoteBlock(id: 't1', type: NoteBlockType.text, text: _delta('Hi')),
            ],
          ),
          Note(
            id: 'md',
            markdown: true,
            title: 'Readme',
            blocks: [
              NoteBlock(type: NoteBlockType.text, text: '# Readme\n\nbody'),
            ],
          ),
          Note(
            id: 'page',
            title: 'Chapter I',
            bookId: 'book',
            bookPageKind: BookPageKind.chapter,
            bookOrder: 1,
            blocks: [NoteBlock(type: NoteBlockType.text, text: _delta('x'))],
          ),
        ],
        spaces: const [],
        cards: const [],
        books: [Book(id: 'book', title: 'Book')],
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

  Future<Response> send(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    String type = 'image/png',
    Map<String, String> headers = const {},
  }) => Future.sync(
    () => server.handler(
      Request(
        method,
        Uri.parse('http://$_host$path'),
        headers: {
          'host': _host,
          'cookie': 'braim_session=$token',
          'x-braim-csrf': csrfTokenFor(token),
          if (json != null) 'content-type': 'application/json',
          if (bytes != null) 'content-type': type,
          ...headers,
        },
        body: json != null ? jsonEncode(json) : bytes,
        context: {kConnectionInfoKey: _Conn()},
      ),
    ),
  );

  Future<String> page(String path) async {
    final r = await send('GET', path);
    expect(r.statusCode, 200, reason: path);
    return (await r.readAsString()).replaceAll('&#47;', '/');
  }

  Future<Map<String, dynamic>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  Note note(String id) => state.noteById(id)!;

  int base(String id) => note(id).updatedAt.millisecondsSinceEpoch;

  group('photos', () {
    test(
      'an upload lands at the end of the note, with a line after it',
      () async {
        final r = await send('POST', '/api/notes/rich/images', bytes: _png);
        expect(r.statusCode, 200);
        final blocks = note('rich').blocks;
        expect(blocks, hasLength(3));
        expect(blocks[1].isImage, isTrue);
        expect(blocks[1].imagePath, endsWith('.png'));
        expect(blocks[2].isText, isTrue);
        expect(File(blocks[1].imagePath).readAsBytesSync(), _png);
        expect((await json(r))['updatedAt'], base('rich'));
        // The browser may now load it.
        final name = imageName(blocks[1].imagePath);
        expect((await send('GET', '/img/$name')).statusCode, 200);
      },
    );

    test('only real images are taken, and only into rich notes', () async {
      var r = await send(
        'POST',
        '/api/notes/rich/images',
        bytes: utf8.encode('<svg onload="x">'),
        type: 'image/svg+xml',
      );
      expect(r.statusCode, 400);
      expect((await json(r))['message'], 'Use a JPEG, PNG, GIF or WebP image.');
      r = await send('POST', '/api/notes/md/images', bytes: _png);
      expect(r.statusCode, 400);
      expect(note('rich').blocks, hasLength(1));
    });

    test('an image over 10 MB is refused', () async {
      // Sent without a length, so the server has to count as it reads.
      final chunk = Uint8List(1024 * 1024);
      final r = await server.handler(
        Request(
          'POST',
          Uri.parse('http://$_host/api/notes/rich/images'),
          headers: {
            'host': _host,
            'cookie': 'braim_session=$token',
            'x-braim-csrf': csrfTokenFor(token),
            'content-type': 'image/png',
          },
          body: Stream<List<int>>.fromIterable([
            _png,
            for (var i = 0; i < 10; i++) chunk,
          ]),
          context: {kConnectionInfoKey: _Conn()},
        ),
      );
      expect(r.statusCode, 413);
      expect(note('rich').blocks, hasLength(1));
      // A body that declares its size is turned away before it is read.
      expect(
        bodyLimitFor(Request('POST', Uri.parse('http://x/api/notes/a/images'))),
        kWebMaxImageBytes,
      );
      expect(
        bodyLimitFor(Request('PUT', Uri.parse('http://x/api/notes/a'))),
        kWebMaxBodyBytes,
      );
    });

    test('not while the note is being edited on the phone', () async {
      state.acquireEditLease('rich', kPhoneLease);
      final r = await send('POST', '/api/notes/rich/images', bytes: _png);
      expect(r.statusCode, 409);
    });

    test(
      'removing a photo deletes its file and folds the empty line',
      () async {
        await send('POST', '/api/notes/rich/images', bytes: _png);
        final image = note('rich').blocks[1];
        final r = await send('DELETE', '/api/notes/rich/images/${image.id}');
        expect(r.statusCode, 200);
        final blocks = note('rich').blocks;
        expect(blocks, hasLength(1));
        expect(blocks.single.id, 't1');
        expect(File(image.imagePath).existsSync(), isFalse);
        expect(
          (await send(
            'DELETE',
            '/api/notes/rich/images/${image.id}',
          )).statusCode,
          404,
        );
      },
    );

    test('the editor offers photos on a saved rich note only', () async {
      final rich = await page('/notes/rich/edit');
      expect(rich, contains('data-action="add-image"'));
      expect(rich, contains('id="image-input"'));
      expect(await page('/notes/md/edit'), isNot(contains('add-image')));
      expect(await page('/notes/new'), isNot(contains('add-image')));
    });
  });

  group('tags and colour', () {
    test('a save carries them, cleaned as the phone cleans tags', () async {
      final sun = NoteColors.swatches.first;
      final r = await send(
        'PUT',
        '/api/notes/rich',
        json: {
          'baseUpdatedAt': base('rich'),
          'title': 'Trip',
          'blocks': [
            {'id': 't1', 'delta': jsonDecode(_delta('Hi'))},
          ],
          'tags': ['#Idea, todo  #idea Work'],
          'color': sun,
        },
      );
      expect(r.statusCode, 200);
      expect(note('rich').tags, ['idea', 'todo', 'work']);
      expect(note('rich').colorValue, sun);
    });

    test(
      'left out, they stay; null clears the colour; odd ones are refused',
      () async {
        note('rich').colorValue = NoteColors.swatches[2];
        var r = await send(
          'PUT',
          '/api/notes/md',
          json: {'baseUpdatedAt': base('md'), 'source': '# Readme\n\nmore'},
        );
        expect(r.statusCode, 200);
        r = await send(
          'PUT',
          '/api/notes/rich',
          json: {
            'baseUpdatedAt': base('rich'),
            'blocks': <Object>[],
            'color': null,
          },
        );
        expect(r.statusCode, 200);
        expect(note('rich').colorValue, isNull);
        expect(note('rich').tags, ['travel']);
        for (final bad in [
          {'color': 0xFF123456},
          {'color': 'red'},
          {'tags': 'idea'},
          {
            'tags': [1],
          },
        ]) {
          r = await send(
            'PUT',
            '/api/notes/rich',
            json: {'baseUpdatedAt': base('rich'), 'blocks': <Object>[], ...bad},
          );
          expect(r.statusCode, 400, reason: '$bad');
        }
      },
    );

    test('a new note can start with them', () async {
      final r = await send(
        'POST',
        '/api/notes',
        json: {
          'kind': 'markdown',
          'source': '# Plan',
          'tags': ['later'],
          'color': NoteColors.swatches[3],
        },
      );
      expect(r.statusCode, 201);
      final created = note((await json(r))['id'] as String);
      expect(created.tags, ['later']);
      expect(created.colorValue, NoteColors.swatches[3]);
    });

    test(
      'the editor shows them; a book page keeps them on the phone',
      () async {
        note('rich').colorValue = NoteColors.swatches[1];
        final html = await page('/notes/rich/edit');
        expect(
          html,
          contains(
            'id="tags-input" type="text" autocomplete="off" value="travel"',
          ),
        );
        expect(
          html,
          contains(
            'data-color="${NoteColors.swatches[1]}" aria-checked="true"',
          ),
        );
        expect(html, contains('data-color="" aria-checked="false"'));
        expect(
          await page('/books/book/pages/page/edit'),
          isNot(contains('tags-input')),
        );
      },
    );
  });

  test(
    'a link the server refuses says why, not "check the connection"',
    () async {
      for (final url in [
        'ftp://example.com/x',
        'mailto:a@b.c',
        'javascript:alert(1)',
      ]) {
        final r = await send('POST', '/api/sparks', json: {'url': url});
        expect(r.statusCode, 400, reason: url);
        final b = await json(r);
        expect(b['error'], 'bad_url');
        expect(b['message'], startsWith("That isn't a web link."));
      }
    },
  );

  test('the File menu can print the page', () async {
    expect(await page('/'), contains('data-action="print"'));
  });

  test('image types are read from the bytes', () {
    expect(WebApi.imageExtension([0xFF, 0xD8, 0xFF, 0xE0]), '.jpg');
    expect(WebApi.imageExtension(_png), '.png');
    expect(WebApi.imageExtension(utf8.encode('GIF89a...')), '.gif');
    expect(WebApi.imageExtension(utf8.encode('RIFF1234WEBPVP8 ')), '.webp');
    expect(WebApi.imageExtension(utf8.encode('<html>')), isNull);
    expect(WebApi.imageExtension(const []), isNull);
  });
}
