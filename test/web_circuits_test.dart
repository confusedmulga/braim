// Braim Web, Phase 5: the Circuits list, the map and its node actions, and
// the circuit controls on a note's page. See docs/braim-web-plan.md, 9.3.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shelf/shelf.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/circuit_layout.dart';
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

/// A branch of [circuit] under [parent].
Note _node(
  String id,
  String title, {
  String circuit = 'trip',
  required String parent,
  int order = 0,
  bool placeholder = false,
  bool markdown = false,
}) => Note(
  id: id,
  title: title,
  markdown: markdown,
  circuitId: circuit,
  circuitParentId: parent,
  circuitOrder: order,
  circuitPlaceholder: placeholder,
  blocks: [
    NoteBlock(type: NoteBlockType.text, text: markdown ? '# $title\n' : ''),
  ],
);

void main() {
  late Directory root;
  late AppState state;
  late BraimWebServer server;
  late WebSessionStore sessions;
  late String token;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_web_circuits_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDownAll(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  // Trip
  // ├─ Flights (a)
  // │  ├─ Compare fares (a1)
  // │  └─ Book by Friday (a2)
  // ├─ Stay (b, Markdown)
  // └─ Placeholder #1 (slot)
  //    └─ Museum (c)
  // Vault, in the Crypt
  // └─ Secret branch (v1)
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
            id: 'trip',
            title: 'Trip',
            circuitId: 'trip',
            createdAt: DateTime(2026, 9, 1),
          ),
          _node('a', 'Flights', parent: 'trip'),
          _node('a1', 'Compare fares', parent: 'a'),
          _node('a2', 'Book by Friday', parent: 'a', order: 1),
          _node('b', 'Stay', parent: 'trip', order: 1, markdown: true),
          _node(
            'slot',
            'Placeholder #1',
            parent: 'trip',
            order: 2,
            placeholder: true,
          ),
          _node('c', 'Museum', parent: 'slot'),
          Note(
            id: 'vault',
            title: 'Vault',
            circuitId: 'vault',
            spaceId: kCryptSpaceId,
          ),
          _node('v1', 'Secret branch', circuit: 'vault', parent: 'vault'),
          Note(
            id: 'plain',
            title: 'Plain',
            blocks: [NoteBlock(type: NoteBlockType.text, text: 'hello')],
          ),
        ],
        spaces: const [],
        cards: const [],
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

  Note note(String id) => state.noteById(id)!;

  group('the Circuits list', () {
    test('lists the circuits the web may show, each opening its map', () async {
      final html = await page('/circuits');
      expect(html, contains('href="/circuits/trip"'));
      expect(html, contains('Trip'));
      expect(html, isNot(contains('Vault')));
      expect(html, contains('id="new-circuit"'));
      expect(html, contains('class="tab current" href="/circuits"'));
    });

    test('a new circuit starts with its first note, titled', () async {
      final r = await post('/api/circuits', {'title': '  Book club '});
      expect(r.statusCode, 201);
      final b = await json(r);
      final created = note(b['id'] as String);
      expect(created.isCircuitRoot, isTrue);
      expect(created.title, 'Book club');
      expect(b['edit'], '/notes/${created.id}/edit');
      expect((await post('/api/circuits', {'title': ' '})).statusCode, 400);
    });
  });

  group('the map', () {
    /// The rectangles the page drew, by node id.
    Map<String, Rect> drawnRects(String html) => {
      for (final m in RegExp(
        r'data-node="([^"]+)" style="left:([\d.]+)px;top:([\d.]+)px;'
        r'width:([\d.]+)px;height:([\d.]+)px"',
      ).allMatches(html))
        m.group(1)!: Rect.fromLTWH(
          double.parse(m.group(2)!),
          double.parse(m.group(3)!),
          double.parse(m.group(4)!),
          double.parse(m.group(5)!),
        ),
    };

    /// Each drawn branch as its start and end points.
    Set<(Offset, Offset)> drawnEdges(String html) {
      final out = <(Offset, Offset)>{};
      for (final m in RegExp(r'<path d="([^"]+)"').allMatches(html)) {
        final n = RegExp(r'-?[\d.]+')
            .allMatches(m.group(1)!)
            .map((x) => double.parse(x.group(0)!))
            .toList();
        out.add((Offset(n[0], n[1]), Offset(n[n.length - 2], n[n.length - 1])));
      }
      return out;
    }

    Offset round(Offset o) => Offset(
      (o.dx * 10).roundToDouble() / 10,
      (o.dy * 10).roundToDouble() / 10,
    );

    for (final mode in CircuitLayoutMode.values) {
      test('nodes and branches match layoutCircuit, ${mode.name}', () async {
        await state.setCircuitLayout('trip', mode.name);
        final html = await page('/circuits/trip');
        final expected = layoutCircuit(
          rootId: 'trip',
          children: const {
            'trip': ['a', 'b', 'slot'],
            'a': ['a1', 'a2'],
            'slot': ['c'],
          },
          mode: mode,
        );
        final rects = drawnRects(html);
        expect(rects.keys.toSet(), expected.rects.keys.toSet());
        expected.rects.forEach((id, r) {
          expect(rects[id]!.left, closeTo(r.left, 0.05), reason: id);
          expect(rects[id]!.top, closeTo(r.top, 0.05), reason: id);
          expect(rects[id]!.width, closeTo(r.width, 0.05));
        });
        final ends = <(Offset, Offset)>{
          for (final (p, c) in expected.edges)
            switch (mode) {
              CircuitLayoutMode.ltr => (
                round(
                  Offset(
                    expected.rects[p]!.right,
                    expected.rects[p]!.center.dy,
                  ),
                ),
                round(
                  Offset(expected.rects[c]!.left, expected.rects[c]!.center.dy),
                ),
              ),
              CircuitLayoutMode.ttb => (
                round(
                  Offset(
                    expected.rects[p]!.center.dx,
                    expected.rects[p]!.bottom,
                  ),
                ),
                round(
                  Offset(expected.rects[c]!.center.dx, expected.rects[c]!.top),
                ),
              ),
              CircuitLayoutMode.radial => (
                round(expected.rects[p]!.center),
                round(expected.rects[c]!.center),
              ),
            },
        };
        expect(expected.edges, hasLength(6));
        expect(drawnEdges(html), ends);
        expect(html, contains('data-layout="${mode.name}" class="current"'));
      });
    }

    test('placeholders show on the map but never open as notes', () async {
      final html = await page('/circuits/trip');
      expect(
        html,
        contains('<button type="button" class="node-open" data-menu="slot">'),
      );
      expect(html, isNot(contains('href="/notes/slot"')));
      expect(html, isNot(contains('data-add="slot"')));
      expect(html, contains('href="/notes/c"'));
      expect((await send('GET', '/notes/slot')).statusCode, 404);
      expect((await send('GET', '/notes/slot/edit')).statusCode, 404);
    });

    test('a circuit whose first note is hidden has no map', () async {
      expect((await send('GET', '/circuits/vault')).statusCode, 404);
      expect((await send('GET', '/circuits/v1')).statusCode, 404);
      expect(
        (await send('GET', '/api/circuits/nodes/v1/menu')).statusCode,
        404,
      );
      expect((await post('/api/circuits/nodes/v1/child')).statusCode, 404);
      expect(
        (await post('/api/circuits/vault/layout', {'mode': 'ttb'})).statusCode,
        404,
      );
      // Only a first note has a map.
      expect((await send('GET', '/circuits/a')).statusCode, 404);
      expect((await send('GET', '/circuits/plain')).statusCode, 404);
    });

    test('?focus marks a node of this circuit, and nothing else', () async {
      expect(
        await page('/circuits/trip?focus=a1'),
        contains('class="node focus" data-node="a1"'),
      );
      final other = await page('/circuits/trip?focus=v1');
      expect(other, contains('data-focus=""'));
      expect(other, isNot(contains(' focus"')));
    });

    test('the layout switch is saved on the first note', () async {
      expect(
        (await post('/api/circuits/trip/layout', {
          'mode': 'radial',
        })).statusCode,
        200,
      );
      expect(note('trip').circuitLayout, 'radial');
      expect(
        (await post('/api/circuits/trip/layout', {
          'mode': 'spiral',
        })).statusCode,
        400,
      );
      expect(
        (await post('/api/circuits/a/layout', {'mode': 'ttb'})).statusCode,
        404,
      );
    });
  });

  group('node actions', () {
    test('add under and next to make "Note #N" notes in place', () async {
      var r = await post('/api/circuits/nodes/a/child');
      expect(r.statusCode, 201);
      final child = note((await json(r))['id'] as String);
      expect(child.title, 'Note #1');
      expect(child.circuitParentId, 'a');
      expect(state.circuitChildren('a').last.id, child.id);

      r = await post('/api/circuits/nodes/a/sibling', {'markdown': true});
      final b = await json(r);
      final sib = note(b['id'] as String);
      expect(sib.title, 'Note #2');
      expect(sib.markdown, isTrue);
      expect(sib.markdownSource, '# Note #2\n');
      expect(state.circuitChildren('trip').map((n) => n.id).toList(), [
        'a',
        sib.id,
        'b',
        'slot',
      ]);
      expect(b['edit'], '/notes/${sib.id}/edit');
      expect(b['map'], '/circuits/trip?focus=${sib.id}');

      // Next to the first note means under it.
      r = await post('/api/circuits/nodes/trip/sibling');
      expect(note((await json(r))['id'] as String).circuitParentId, 'trip');

      expect((await post('/api/circuits/nodes/slot/child')).statusCode, 400);
      expect((await post('/api/circuits/nodes/plain/child')).statusCode, 404);
    });

    test('delete only this note leaves the next "Placeholder #N"', () async {
      final r = await post('/api/circuits/nodes/a/delete', {
        'mode': 'keepSlot',
        'count': 2,
      });
      expect(r.statusCode, 200);
      expect(note('a').deletedAt, isNotNull);
      final kids = state.circuitChildren('trip');
      final slot = kids.first;
      expect(slot.circuitPlaceholder, isTrue);
      expect(slot.title, 'Placeholder #2');
      expect(state.circuitChildren(slot.id).map((n) => n.id), ['a1', 'a2']);
    });

    test('delete all trashes the branch and its notes as one group', () async {
      final r = await post('/api/circuits/nodes/a/delete', {
        'mode': 'all',
        'count': 2,
      });
      expect(r.statusCode, 200);
      final group = note('a').trashGroupId;
      expect(group, isNotNull);
      for (final id in ['a', 'a1', 'a2']) {
        expect(note(id).deletedAt, isNotNull, reason: id);
        expect(note(id).trashGroupId, group, reason: id);
      }
      expect(note('b').deletedAt, isNull);
    });

    test(
      'a delete decided on an older map, or the wrong way, is refused',
      () async {
        var r = await post('/api/circuits/nodes/a/delete', {
          'mode': 'all',
          'count': 1,
        });
        expect(r.statusCode, 409);
        expect((await json(r))['error'], 'changed');
        r = await post('/api/circuits/nodes/a1/delete', {
          'mode': 'keepSlot',
          'count': 0,
        });
        expect(r.statusCode, 400);
        r = await post('/api/circuits/nodes/trip/delete', {
          'mode': 'keepSlot',
          'count': 6,
        });
        expect(r.statusCode, 400);
        expect(
          (await post('/api/circuits/nodes/slot/delete', {
            'mode': 'all',
            'count': 1,
          })).statusCode,
          400,
        );
        expect(note('a').deletedAt, isNull);
      },
    );

    test(
      'deleting the first note takes the circuit and goes to the list',
      () async {
        final r = await post('/api/circuits/nodes/trip/delete', {
          'mode': 'all',
          'count': 6,
        });
        expect(r.statusCode, 200);
        expect((await json(r))['go'], '/circuits');
        for (final id in ['trip', 'a', 'a1', 'b', 'c']) {
          expect(note(id).deletedAt, isNotNull, reason: id);
        }
        expect((await send('GET', '/circuits/trip')).statusCode, 404);
      },
    );

    test('a note being edited elsewhere is not renamed or deleted', () async {
      state.acquireEditLease('a1', kPhoneLease);
      var r = await post('/api/circuits/nodes/a1/rename', {'title': 'Fares'});
      expect(r.statusCode, 409);
      expect((await json(r))['by'], 'phone');
      r = await post('/api/circuits/nodes/a/delete', {
        'mode': 'all',
        'count': 2,
      });
      expect(r.statusCode, 409);
      expect(note('a1').deletedAt, isNull);
      // Leaving a placeholder doesn't touch the note being edited.
      r = await post('/api/circuits/nodes/a/delete', {
        'mode': 'keepSlot',
        'count': 2,
      });
      expect(r.statusCode, 200);
    });

    test('rename and move', () async {
      expect(
        (await post('/api/circuits/nodes/a/rename', {
          'title': ' Air ',
        })).statusCode,
        200,
      );
      expect(note('a').title, 'Air');
      expect(
        (await post('/api/circuits/nodes/a/rename', {'title': ''})).statusCode,
        400,
      );
      expect(
        (await post('/api/circuits/nodes/slot/rename', {
          'title': 'x',
        })).statusCode,
        400,
      );

      expect(
        (await post('/api/circuits/nodes/a/move', {'delta': 1})).statusCode,
        200,
      );
      expect(state.circuitChildren('trip').map((n) => n.id), [
        'b',
        'a',
        'slot',
      ]);
      expect(
        (await post('/api/circuits/nodes/a/move', {'delta': 2})).statusCode,
        400,
      );
      expect(
        (await post('/api/circuits/nodes/trip/move', {'delta': 1})).statusCode,
        400,
      );
    });

    test('a placeholder is written into or removed', () async {
      var r = await post('/api/circuits/nodes/slot/write-placeholder', {
        'markdown': true,
      });
      expect(r.statusCode, 200);
      final slot = note('slot');
      expect(slot.circuitPlaceholder, isFalse);
      expect(slot.title, 'Note #1');
      expect(slot.markdown, isTrue);
      expect((await json(r))['edit'], '/notes/slot/edit');
      expect((await send('GET', '/notes/slot')).statusCode, 200);

      // Now an ordinary note: it can't be "removed" as a placeholder.
      expect(
        (await post('/api/circuits/nodes/slot/remove-placeholder')).statusCode,
        400,
      );
    });

    test('removing a placeholder lifts its notes into its place', () async {
      final r = await post('/api/circuits/nodes/slot/remove-placeholder');
      expect(r.statusCode, 200);
      expect(state.noteById('slot'), isNull);
      expect(state.circuitChildren('trip').map((n) => n.id), ['a', 'b', 'c']);
    });
  });

  group('node menus', () {
    test(
      'a branch: the add items, the moves it can make, and both deletes',
      () async {
        final m = await json(await send('GET', '/api/circuits/nodes/a/menu'));
        expect(m['title'], 'Flights');
        expect(m['open'], '/notes/a');
        final items = (m['items'] as List).cast<Map<String, dynamic>>();
        final actions = [for (final i in items) i['action']];
        expect(
          actions,
          containsAllInOrder([
            'open',
            'rename',
            'sibling',
            'child',
            'child',
            'move',
            'move',
            'delete',
          ]),
        );
        final moves = items.where((i) => i['action'] == 'move').toList();
        expect(moves.first['disabled'], isTrue); // already first
        expect(moves.last['disabled'], isNull);
        final delete = m['delete'] as Map<String, dynamic>;
        expect(delete['count'], 2);
        expect(delete['body'], 'It has 2 notes under it.');
        expect(
          [for (final c in delete['choices'] as List) c['mode']],
          ['keepSlot', 'all'],
        );
        expect((delete['choices'] as List).last['label'], 'Delete all 3');
      },
    );

    test('a leaf asks once; the first note offers no moves', () async {
      final leaf = await json(await send('GET', '/api/circuits/nodes/a2/menu'));
      expect(
        [for (final c in leaf['delete']['choices'] as List) c['mode']],
        ['all'],
      );

      final first = await json(
        await send('GET', '/api/circuits/nodes/trip/menu'),
      );
      final actions = [for (final i in first['items'] as List) i['action']];
      expect(actions, isNot(contains('sibling')));
      expect(actions, isNot(contains('move')));
      expect((first['items'] as List).last['label'], 'Delete circuit');
      expect(
        first['delete']['text'],
        'Delete circuit "Trip" and all its 6 notes?',
      );
    });

    test('a placeholder offers writing a note there, or removing it', () async {
      final m = await json(await send('GET', '/api/circuits/nodes/slot/menu'));
      expect(
        [for (final i in m['items'] as List) i['action'] ?? '-'],
        ['write', 'write', '-', 'remove'],
      );
      expect(m.containsKey('open'), isFalse);
    });
  });

  group('a circuit note page', () {
    test('shows its path, the map and the two adds', () async {
      final html = await page('/notes/a1');
      expect(html, contains('<a href="/notes/trip">Trip</a>'));
      expect(html, contains('<a href="/notes/a">Flights</a>'));
      expect(html, contains('href="/circuits/trip?focus=a1"'));
      expect(
        html,
        contains('data-circuit-add="/api/circuits/nodes/a1/sibling"'),
      );
      expect(html, contains('data-circuit-add="/api/circuits/nodes/a1/child"'));
      expect(html, contains('class="tab current" href="/circuits"'));
      // A placeholder on the path is named, not linked.
      expect(await page('/notes/c'), contains('<span>Placeholder #1</span>'));
    });

    test(
      'the first note adds only under itself; a plain note has no bar',
      () async {
        final first = await page('/notes/trip');
        expect(
          first,
          contains('data-circuit-add="/api/circuits/nodes/trip/child"'),
        );
        expect(first, isNot(contains('/sibling')));
        expect(await page('/notes/plain'), isNot(contains('circuit-bar')));
      },
    );
  });
}
