import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:braim/services/dnd_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// The focus timer's Do Not Disturb touches only what it switched on itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  // The phone's interruption filter, faked at the native channel.
  var filter = 1;
  final sets = <int>[];

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('braim_dnd_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    DndService.debugSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('braim/dnd'), (call) async {
      switch (call.method) {
        case 'hasAccess':
          return true;
        case 'getFilter':
          return filter;
        case 'setFilter':
          final f = (call.arguments as Map)['filter'] as int;
          sets.add(f);
          filter = f;
          return true;
      }
      return null;
    });
  });

  tearDownAll(() {
    DndService.debugSupportedOverride = null;
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    sets.clear();
    final marker = File('${root.path}/focus_dnd.on');
    if (marker.existsSync()) marker.deleteSync();
  });

  test('with the timer\'s DND off, the phone\'s own DND is left alone', () async {
    filter = 2; // the user's own Do Not Disturb (priority)
    await DndService.instance.apply(DndMode.off);
    await DndService.instance.restore();
    expect(sets, isEmpty);
    expect(filter, 2);
  });

  test('ending a session puts back the filter that was on before', () async {
    filter = 2;
    await DndService.instance.apply(DndMode.silence);
    expect(filter, 3);
    await DndService.instance.restore();
    expect(filter, 2);
  });

  test('a session left on by a killed app is undone at the next launch',
      () async {
    filter = 1;
    await DndService.instance.apply(DndMode.focus);
    expect(filter, 2);
    await DndService.instance.restoreIfLeftOn();
    expect(filter, 1);
    // Nothing left to undo after that.
    sets.clear();
    await DndService.instance.restoreIfLeftOn();
    expect(sets, isEmpty);
  });
}
