import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_quill/flutter_quill.dart' show Document;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/models/tweet_card.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';
import 'package:braim/web/web_api.dart';
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

/// A Delta with every format Braim keeps, as Quill 2 writes it.
final _everyFormat = <Map<String, Object>>[
  {
    'insert': 'Bold',
    'attributes': {'bold': true},
  },
  {'insert': ' '},
  {
    'insert': 'italic',
    'attributes': {'italic': true},
  },
  {'insert': ' '},
  {
    'insert': 'under',
    'attributes': {'underline': true},
  },
  {'insert': ' '},
  {
    'insert': 'struck',
    'attributes': {'strike': true},
  },
  {'insert': ' '},
  {
    'insert': 'marked',
    'attributes': {'background': '#FFE082', 'color': '#202124'},
  },
  {'insert': ' '},
  {
    'insert': 'link',
    'attributes': {'link': 'https://example.com/a'},
  },
  {'insert': ' [[Wiki]]\nHeading'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'Sub'},
  {
    'insert': '\n',
    'attributes': {'header': 2},
  },
  {'insert': 'Quoted'},
  {
    'insert': '\n',
    'attributes': {'blockquote': true},
  },
  {'insert': 'Bullet'},
  {
    'insert': '\n',
    'attributes': {'list': 'bullet'},
  },
  {'insert': 'Deeper'},
  {
    'insert': '\n',
    'attributes': {'indent': 1, 'list': 'bullet'},
  },
  {'insert': 'First'},
  {
    'insert': '\n',
    'attributes': {'list': 'ordered'},
  },
  {'insert': 'Done'},
  {
    'insert': '\n',
    'attributes': {'list': 'checked'},
  },
  {'insert': 'To do'},
  {
    'insert': '\n',
    'attributes': {'list': 'unchecked'},
  },
  {'insert': 'Centred'},
  {
    'insert': '\n',
    'attributes': {'align': 'center'},
  },
  {'insert': 'Right'},
  {
    'insert': '\n',
    'attributes': {'align': 'right'},
  },
  {'insert': 'Justified'},
  {
    'insert': '\n',
    'attributes': {'align': 'justify'},
  },
  {'insert': 'Indented'},
  {
    'insert': '\n',
    'attributes': {'indent': 3},
  },
];

void main() {
  group('sanitizeDelta', () {
    test('keeps every format Braim has, exactly as Quill 2 writes it', () {
      expect(sanitizeDelta(_everyFormat), _everyFormat);
    });

    test('strips other formats and embeds, and adds the final newline', () {
      final cleaned = sanitizeDelta([
        {
          'insert': {'image': 'https://evil.example/x.png'},
        },
        {
          'insert': 'text',
          'attributes': {
            'bold': true,
            'font': 'serif',
            'size': 'huge',
            'italic': 'yes',
            'code': true,
            'color': 'red',
            'background': 'javascript:x',
            'link': 'javascript:alert(1)',
            'header': 1, // a line format on text
          },
        },
        {
          'insert': {'video': 'x'},
        },
        {
          'insert': '\n',
          'attributes': {
            'header': 3,
            'list': 'weird',
            'bold': true, // an inline mark on a newline
            'indent': 9,
            'align': 'left',
            'code-block': true,
          },
        },
        {'insert': 'no newline\r\nat the end'},
      ]);
      expect(cleaned, [
        {
          'insert': 'text',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'indent': 3},
        },
        {'insert': 'no newline\nat the end'},
        {'insert': '\n'},
      ]);
      expect(sanitizeDelta([]), [
        {'insert': '\n'},
      ]);
      expect(sanitizeDelta('nope'), isNull);
      expect(sanitizeDelta([1, 2]), isNull);
    });

    test('the editor loads legacy plain text as a Delta', () {
      expect(jsonDecode(editorDelta('line one\nline two')), [
        {'insert': 'line one\nline two\n'},
      ]);
      expect(jsonDecode(editorDelta('')), [
        {'insert': '\n'},
      ]);
    });
  });

  group('the API', () {
    late Directory root;
    late AppState state;
    late BraimWebServer server;
    late WebSessionStore sessions;
    late String token;
    late String sid;
    late DateTime now;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('braim_web_editing_test');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
    });

    tearDownAll(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    String delta(String text) => jsonEncode([
      {'insert': '$text\n'},
    ]);

    NoteBlock text(String id, String body) =>
        NoteBlock(id: id, type: NoteBlockType.text, text: delta(body));

    setUp(() async {
      now = DateTime(2026, 10, 1, 12);
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
              title: 'Shopping',
              blocks: [
                text('b1', 'Milk'),
                NoteBlock(
                  id: 'img',
                  type: NoteBlockType.image,
                  imagePath: '/x/a.jpg',
                ),
                text('b2', 'Eggs'),
              ],
            ),
            Note(
              id: 'list',
              title: 'Todo',
              blocks: [
                NoteBlock(
                  id: 'c1',
                  type: NoteBlockType.text,
                  text: jsonEncode([
                    {'insert': 'One'},
                    {
                      'insert': '\n',
                      'attributes': {'list': 'unchecked'},
                    },
                  ]),
                ),
              ],
            ),
            Note(
              id: 'md',
              markdown: true,
              title: 'Old',
              blocks: [
                NoteBlock(
                  id: 'm1',
                  type: NoteBlockType.text,
                  text: '# Old\n\nbody',
                ),
              ],
            ),
            Note(id: 'root', title: 'Trip')..circuitId = 'root',
            Note(
                id: 'branch',
                title: 'Note #1',
                markdown: true,
                blocks: [
                  NoteBlock(type: NoteBlockType.text, text: 'branch body'),
                ],
              )
              ..circuitId = 'root'
              ..circuitParentId = 'root',
            Note(
              id: 'secret',
              title: 'Hidden',
              spaceId: kCryptSpaceId,
              blocks: [text('s1', 'hidden')],
            ),
          ],
          spaces: const [],
          cards: [
            TweetCard(
              id: 'spark',
              url: 'https://example.com/post',
              blocks: [text('k1', 'my note')],
            ),
            TweetCard(
              id: 'crypt-spark',
              url: 'https://example.com/hidden',
              spaceId: kCryptSpaceId,
            ),
          ],
        ),
      );
      state = AppState()..leaseClock = () => now;
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
      final created = await sessions.create(label: 'test');
      token = created.token;
      sid = created.session.id;
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
      String? session,
    }) {
      final t = session ?? token;
      return Future.sync(
        () => server.handler(
          Request(
            method,
            Uri.parse('http://$_host$path'),
            headers: {
              'host': _host,
              'cookie': 'braim_session=$t',
              'x-braim-csrf': csrfTokenFor(t),
              if (json != null) 'content-type': 'application/json',
            },
            body: json == null ? null : jsonEncode(json),
            context: {kConnectionInfoKey: _Conn()},
          ),
        ),
      );
    }

    Future<Map<String, dynamic>> body(Response r) async =>
        jsonDecode(await r.readAsString()) as Map<String, dynamic>;

    int base(String id) => state.noteById(id)!.updatedAt.millisecondsSinceEpoch;

    test(
      'a save with every format reads back unchanged, on the phone too',
      () async {
        final note = state.noteById('rich')!;
        final r = await send(
          'PUT',
          '/api/notes/rich',
          json: {
            'baseUpdatedAt': base('rich'),
            'title': 'Groceries',
            'blocks': [
              {'id': 'b1', 'delta': _everyFormat},
            ],
          },
        );
        expect(r.statusCode, 200);
        expect(
          identical(state.noteById('rich'), note),
          isTrue,
        ); // the live note
        expect(note.title, 'Groceries');
        expect(jsonDecode(note.blocks[0].text), _everyFormat);
        expect(richToPlain(note.blocks[2].text), 'Eggs'); // untouched
        expect(note.blocks[1].imagePath, '/x/a.jpg');
        expect(
          (await body(r))['updatedAt'],
          note.updatedAt.millisecondsSinceEpoch,
        );

        // The phone's editor (flutter_quill) loads it as it was saved...
        expect(
          Document.fromJson(_everyFormat).toDelta().toJson(),
          _everyFormat,
        );
        // ...and its read view sees every format.
        final lines = richToStyledLines(note.blocks[0].text);
        expect(
          lines[0].runs.map(
            (r) =>
                (r.bold, r.italic, r.underline, r.strike, r.highlight, r.link),
          ),
          containsAll([
            (true, false, false, false, false, null),
            (false, true, false, false, false, null),
            (false, false, true, false, false, null),
            (false, false, false, true, false, null),
            (false, false, false, false, true, null),
            (false, false, false, false, false, 'https://example.com/a'),
          ]),
        );
        expect([for (final l in lines) l.header], containsAllInOrder([1, 2]));
        expect(lines.firstWhere((l) => l.text == 'Quoted').quote, isTrue);
        expect(lines.firstWhere((l) => l.text == 'Deeper').indent, 1);
        expect(
          lines.firstWhere((l) => l.text == 'Done').kind,
          RichLineKind.checkedItem,
        );
        expect(
          lines.firstWhere((l) => l.text == 'To do').kind,
          RichLineKind.uncheckedItem,
        );
        expect(lines.firstWhere((l) => l.text == 'Centred').align, 'center');
        expect(lines.firstWhere((l) => l.text == 'Indented').indent, 3);
      },
    );

    test(
      'a save is cleaned: no other formats, no embeds, a final newline',
      () async {
        final r = await send(
          'PUT',
          '/api/notes/rich',
          json: {
            'baseUpdatedAt': base('rich'),
            'blocks': [
              {
                'id': 'b2',
                'delta': [
                  {
                    'insert': {'image': 'x'},
                  },
                  {
                    'insert': 'Eggs',
                    'attributes': {'font': 'serif', 'bold': true},
                  },
                ],
              },
            ],
          },
        );
        expect(r.statusCode, 200);
        expect(jsonDecode(state.noteById('rich')!.blocks[2].text), [
          {
            'insert': 'Eggs',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ]);
      },
    );

    test('a stale save gets 409; an unknown block gets 400', () async {
      final stale = await send(
        'PUT',
        '/api/notes/rich',
        json: {'baseUpdatedAt': base('rich') - 1, 'blocks': []},
      );
      expect(stale.statusCode, 409);
      expect((await body(stale))['error'], 'changed');
      expect(
        (await body(
          await send(
            'PUT',
            '/api/notes/rich',
            json: {'baseUpdatedAt': base('rich') - 1, 'blocks': []},
          ),
        ))['message'],
        'Changed on your phone',
      );

      for (final blocks in [
        [
          {'id': 'nope', 'delta': []},
        ],
        [
          {'id': 'img', 'delta': []},
        ], // an image block is not text
        [
          {'id': 'b1', 'delta': []},
          {'id': 'b1', 'delta': []},
        ],
        [
          {'id': 'b1', 'delta': 'x'},
        ],
      ]) {
        final r = await send(
          'PUT',
          '/api/notes/rich',
          json: {'baseUpdatedAt': base('rich'), 'blocks': blocks},
        );
        expect(r.statusCode, 400, reason: '$blocks');
      }
      expect(richToPlain(state.noteById('rich')!.blocks[0].text), 'Milk');
    });

    test('a block without an id is added as a new text block', () async {
      final r = await send(
        'PUT',
        '/api/notes/rich',
        json: {
          'baseUpdatedAt': base('rich'),
          'blocks': [
            {
              'delta': [
                {'insert': 'Bread\n'},
              ],
            },
          ],
        },
      );
      expect(r.statusCode, 200);
      final note = state.noteById('rich')!;
      expect(note.blocks, hasLength(4));
      expect(richToPlain(note.blocks.last.text), 'Bread');
      expect((await body(r))['blockIds'], ['b1', 'b2', note.blocks.last.id]);
    });

    test('the phone\'s lease blocks web saves, deletes and ticks', () async {
      expect(state.acquireEditLease('rich', kPhoneLease), isTrue);
      final save = await send(
        'PUT',
        '/api/notes/rich',
        json: {'baseUpdatedAt': base('rich'), 'blocks': []},
      );
      expect(save.statusCode, 409);
      final b = await body(save);
      expect(b['error'], 'leased');
      expect(b['by'], 'phone');
      expect(b['message'], 'Being edited on your phone');
      expect((await send('DELETE', '/api/notes/rich')).statusCode, 409);
      expect((await send('POST', '/api/notes/rich/lease')).statusCode, 409);
      expect(state.noteById('rich')!.deletedAt, isNull);

      expect(state.acquireEditLease('list', kPhoneLease), isTrue);
      final tick = await send(
        'POST',
        '/api/notes/list/check',
        json: {'block': 0, 'line': 0, 'baseUpdatedAt': base('list')},
      );
      expect(tick.statusCode, 409);

      state.releaseEditLease('rich', kPhoneLease);
      expect((await send('POST', '/api/notes/rich/lease')).statusCode, 200);
    });

    test(
      'a web lease keeps the phone and other browsers out until it expires',
      () async {
        expect((await send('POST', '/api/notes/rich/lease')).statusCode, 200);
        expect(state.editLeaseHolder('rich'), webLeaseHolder(sid));
        expect(state.acquireEditLease('rich', kPhoneLease), isFalse);

        final other = await sessions.create(label: 'other');
        final meta = await body(
          await send('GET', '/api/notes/rich/meta', session: other.token),
        );
        expect(meta['leaseHolder'], 'web');
        expect(
          (await body(
            await send('GET', '/api/notes/rich/meta'),
          ))['leaseHolder'],
          'you',
        );
        final blocked = await send(
          'PUT',
          '/api/notes/rich',
          json: {'baseUpdatedAt': base('rich'), 'blocks': []},
          session: other.token,
        );
        expect(blocked.statusCode, 409);
        expect(
          (await body(blocked))['message'],
          'Being edited in another browser',
        );

        // Renewed within 60 seconds it holds; left alone, it lapses.
        now = now.add(const Duration(seconds: 50));
        expect((await send('POST', '/api/notes/rich/lease')).statusCode, 200);
        now = now.add(const Duration(seconds: 59));
        expect(state.acquireEditLease('rich', kPhoneLease), isFalse);
        now = now.add(const Duration(seconds: 1));
        expect(state.editLeaseHolder('rich'), isNull);
        expect(state.acquireEditLease('rich', kPhoneLease), isTrue);
      },
    );

    test('releasing, or logging out, frees the lease', () async {
      await send('POST', '/api/notes/rich/lease');
      expect((await send('DELETE', '/api/notes/rich/lease')).statusCode, 204);
      expect(state.editLeaseHolder('rich'), isNull);

      await send('POST', '/api/notes/rich/lease');
      await server.logOut(sid);
      expect(state.editLeaseHolder('rich'), isNull);
    });

    test('a new note is added only once it has content', () async {
      final count = state.noteCount;
      final empty = await send(
        'POST',
        '/api/notes',
        json: {
          'kind': 'rich',
          'title': '  ',
          'blocks': [
            {
              'delta': [
                {'insert': '\n'},
              ],
            },
          ],
        },
      );
      expect(empty.statusCode, 400);
      expect((await body(empty))['error'], 'empty');
      expect(
        (await send(
          'POST',
          '/api/notes',
          json: {'kind': 'markdown', 'source': '   '},
        )).statusCode,
        400,
      );
      expect(state.noteCount, count);

      final r = await send(
        'POST',
        '/api/notes',
        json: {
          'kind': 'rich',
          'title': 'From the laptop',
          'blocks': [
            {
              'delta': [
                {'insert': 'Hello\n'},
              ],
            },
          ],
        },
      );
      expect(r.statusCode, 201);
      final b = await body(r);
      final note = state.noteById(b['id'] as String)!;
      expect(note.title, 'From the laptop');
      expect(b['blockIds'], [note.blocks.single.id]);
      expect(state.webFeedNotes, contains(note));
      expect(state.noteCount, count + 1);
    });

    test('a Markdown save takes its title from the first heading', () async {
      final r = await send(
        'PUT',
        '/api/notes/md',
        json: {
          'baseUpdatedAt': base('md'),
          'source': '# New title\n\nNew body',
        },
      );
      expect(r.statusCode, 200);
      final note = state.noteById('md')!;
      expect(note.title, 'New title');
      expect(note.markdownSource, '# New title\n\nNew body');
      expect(note.blocks.single.id, 'm1'); // the same block, edited

      final created = await send(
        'POST',
        '/api/notes',
        json: {'kind': 'markdown', 'source': '# Fresh\n\ntext'},
      );
      expect(created.statusCode, 201);
      final fresh = state.noteById((await body(created))['id'] as String)!;
      expect(fresh.markdown, isTrue);
      expect(fresh.title, 'Fresh');
    });

    test(
      'an emptied Markdown note is deleted, unless it is a circuit note',
      () async {
        final gone = await send(
          'PUT',
          '/api/notes/md',
          json: {'baseUpdatedAt': base('md'), 'source': '  '},
        );
        expect((await body(gone))['deleted'], isTrue);
        expect(state.noteById('md')!.deletedAt, isNotNull);

        final kept = await send(
          'PUT',
          '/api/notes/branch',
          json: {'baseUpdatedAt': base('branch'), 'source': ''},
        );
        expect(kept.statusCode, 200);
        expect(state.noteById('branch')!.deletedAt, isNull);
      },
    );

    test(
      'delete moves a plain note to Recently deleted; circuits stay put',
      () async {
        expect((await send('DELETE', '/api/notes/rich')).statusCode, 200);
        expect(state.noteById('rich')!.deletedAt, isNotNull);
        expect((await send('GET', '/notes/rich')).statusCode, 404);
        final branch = await send('DELETE', '/api/notes/branch');
        expect(branch.statusCode, 400);
        expect((await body(branch))['error'], 'not_here');
        expect(state.noteById('branch')!.deletedAt, isNull);
      },
    );

    test('ticking a checklist line from the note page', () async {
      final r = await send(
        'POST',
        '/api/notes/list/check',
        json: {'block': 0, 'line': 0, 'baseUpdatedAt': base('list')},
      );
      expect(r.statusCode, 200);
      final note = state.noteById('list')!;
      expect(
        richToLines(note.blocks[0].text).single.kind,
        RichLineKind.checkedItem,
      );
      expect(
        (await body(r))['updatedAt'],
        note.updatedAt.millisecondsSinceEpoch,
      );
      // A stale page, or a line that isn't a checkbox, changes nothing.
      expect(
        (await send(
          'POST',
          '/api/notes/list/check',
          json: {'block': 0, 'line': 0, 'baseUpdatedAt': 1},
        )).statusCode,
        409,
      );
      expect(
        (await send(
          'POST',
          '/api/notes/rich/check',
          json: {'block': 0, 'line': 0, 'baseUpdatedAt': base('rich')},
        )).statusCode,
        400,
      );
    });

    test('hidden notes cannot be edited, leased or deleted', () async {
      for (final (method, path) in [
        ('PUT', '/api/notes/secret'),
        ('DELETE', '/api/notes/secret'),
        ('POST', '/api/notes/secret/lease'),
        ('POST', '/api/notes/secret/check'),
        ('GET', '/notes/secret/edit'),
      ]) {
        final r = await send(
          method,
          path,
          json: method == 'GET'
              ? null
              : {
                  'baseUpdatedAt': base('secret'),
                  'blocks': [],
                  'block': 0,
                  'line': 0,
                },
        );
        expect(r.statusCode, 404, reason: '$method $path');
      }
      expect(
        richToPlain(state.noteById('secret')!.blocks.single.text),
        'hidden',
      );
    });

    test('the Markdown preview is sanitised', () async {
      final r = await send(
        'POST',
        '/api/markdown/preview',
        json: {'source': '**hi** <script>x</script>'},
      );
      final html = (await body(r))['html'] as String;
      expect(html, contains('<strong>hi</strong>'));
      expect(html, isNot(contains('<script')));
    });

    test('sparks: add from a URL, save, delete', () async {
      final count = state.cardCount;
      final added = await send(
        'POST',
        '/api/sparks',
        json: {'url': 'https://example.org/new'},
      );
      expect(added.statusCode, 201);
      expect(state.cardCount, count + 1);
      final id = (await body(added))['id'] as String;
      expect(state.cardById(id)!.url, 'https://example.org/new');
      expect(
        (await send(
          'POST',
          '/api/sparks',
          json: {'url': 'javascript:alert(1)'},
        )).statusCode,
        400,
      );

      final card = state.cardById('spark')!;
      final saved = await send(
        'PUT',
        '/api/sparks/spark',
        json: {
          'baseUpdatedAt': card.updatedAt.millisecondsSinceEpoch,
          'title': 'Worth reading',
          'blocks': [
            {
              'id': 'k1',
              'delta': [
                {'insert': 'my better note\n'},
              ],
            },
          ],
        },
      );
      expect(saved.statusCode, 200);
      expect(card.noteTitle, 'Worth reading');
      expect(richToPlain(card.blocks.single.text), 'my better note');

      expect((await send('DELETE', '/api/sparks/spark')).statusCode, 200);
      expect(card.deletedAt, isNotNull);
    });

    test('adding the URL of a Crypt spark reveals nothing', () async {
      final r = await send(
        'POST',
        '/api/sparks',
        json: {'url': 'https://example.com/hidden'},
      );
      expect(r.statusCode, 201);
      expect(await body(r), isEmpty);
      expect(
        (await send(
          'PUT',
          '/api/sparks/crypt-spark',
          json: {'baseUpdatedAt': 0, 'blocks': []},
        )).statusCode,
        404,
      );
    });

    test('editor pages', () async {
      final edit = await send('GET', '/notes/rich/edit');
      expect(edit.statusCode, 200);
      final html = await edit.readAsString();
      expect(
        html.replaceAll('&#47;', '/'),
        contains('/assets/vendor/quill.js?v='),
      );
      expect(html, contains('data-block-id="b1"'));
      expect(html, contains('data-block-id="b2"'));
      expect(html, contains('class="note-img"')); // the image stays put
      expect(html, isNot(contains('<script>'))); // config is data, not code

      final md = await (await send('GET', '/notes/md/edit')).readAsString();
      expect(md, contains('id="md-source"'));
      expect(md, contains('# Old'));

      expect((await send('GET', '/notes/new')).statusCode, 200);
      expect((await send('GET', '/notes/new?kind=markdown')).statusCode, 200);
      expect((await send('GET', '/sparks/spark/edit')).statusCode, 200);

      // Quill's files are served from the vendor folder.
      final q = await send('GET', '/assets/vendor/quill.js');
      expect(q.statusCode, 200);
      expect(q.mimeType, 'text/javascript');
    });
  });
}
