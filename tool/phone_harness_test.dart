// A stand-in phone for exercising remote mode end to end: the real
// PhoneServer over a real AppState whose library lives in SQLite (FFI), the
// same store the phone uses, serving a web build from disk. Pairing and Crypt
// unlocks are approved automatically. A small control server lets a test
// script read the "phone's" library and edit it the way the phone's UI would.
//
//   flutter build web --release --no-web-resources-cdn --pwa-strategy=none
//   HARNESS_PORT=8787 HARNESS_CONTROL=8788 flutter test tool/phone_harness_test.dart
//
// tool/remote_smoke.mjs starts this itself.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:braim/models/note.dart';
import 'package:braim/models/note_block.dart';
import 'package:braim/services/db/db_store.dart';
import 'package:braim/services/phone_server/paired_devices.dart';
import 'package:braim/services/phone_server/phone_server.dart';
import 'package:braim/services/phone_server/web_bundle.dart';
import 'package:braim/services/storage_service.dart';
import 'package:braim/state/app_state.dart';

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  test('phone harness', () async {
    final env = Platform.environment;
    final port = int.parse(env['HARNESS_PORT'] ?? '8787');
    final controlPort = int.parse(env['HARNESS_CONTROL'] ?? '8788');
    final webDir = env['HARNESS_WEB'] ?? 'build/web';

    final root = Directory.systemTemp.createTempSync('braim_phone');
    PathProviderPlatform.instance = _PathProvider(root.path);
    final images = Directory('${root.path}/images')..createSync();
    File('assets/BACK03.jpg').copySync('${images.path}/phone-photo.jpg');

    // The phone's library: the demo library, a photo, and a Crypt note.
    final demo = AppData.fromJson(jsonDecode(
            File('test_data/braim_demo.json').readAsStringSync())
        as Map<String, dynamic>);
    demo.tutorialSeen = true;
    demo.notes.first.blocks.add(NoteBlock(
        type: NoteBlockType.image, imagePath: '${images.path}/phone-photo.jpg'));
    demo.notes.add(Note(
      title: 'Phone crypt secret',
      spaceId: kCryptSpaceId,
      blocks: [NoteBlock(type: NoteBlockType.text, text: 'behind the lock')],
    ));
    await StorageService.instance.save(demo);

    sqfliteFfiInit();
    final state = AppState(
        dbStore: DbStore(
            factory: databaseFactoryFfi, path: '${root.path}/braim.db'));
    await state.init();

    Future<PhoneServer> startServer() async {
      final server = PhoneServer(
        state: state,
        bundle: DirectoryWebBundle(webDir),
        devices: PairedDevices(File('${root.path}/paired.json')),
        imagesDir: images.path,
        approvePairing: (_) async => true,
        approveCrypt: (_) async => true,
        port: port,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await server.start();
      return server;
    }

    var server = await startServer();
    final done = Completer<void>();

    final control = await HttpServer.bind(InternetAddress.loopbackIPv4, controlPort);
    control.listen((req) async {
      final res = req.response..headers.contentType = ContentType.json;
      try {
        switch (req.uri.path) {
          case '/code':
            res.write(jsonEncode({'code': server.newPairingCode()}));
          case '/notes':
            await state.flushNow();
            res.write(jsonEncode([
              for (final n in state.notes)
                {'id': n.id, 'title': n.title, 'text': n.textPreview},
            ]));
          case '/edit':
            final body = jsonDecode(await utf8.decodeStream(req)) as Map;
            final n = state.noteById(body['id'] as String)!;
            n.title = body['title'] as String;
            await state.upsertNote(n);
            await state.flushNow();
            res.write('{"ok":true}');
          case '/restart':
            await server.stop();
            server = await startServer();
            res.write('{"ok":true}');
          case '/stop':
            res.write('{"ok":true}');
            done.complete();
          default:
            res.statusCode = 404;
        }
      } catch (e) {
        res.statusCode = 500;
        res.write(jsonEncode({'error': '$e'}));
      }
      await res.close();
    });
    // ignore: avoid_print
    print('HARNESS READY $port $controlPort');
    await done.future;
    await server.stop();
    await control.close(force: true);
    await state.flushNow();
    state.dispose();
  }, timeout: Timeout.none);
}
