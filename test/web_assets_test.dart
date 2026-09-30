import 'package:flutter_test/flutter_test.dart';

import 'package:braim/web/web_assets.dart';

// Loads through the real Flutter bundle (rootBundle), so this fails if
// pubspec.yaml stops listing assets/web/ or a font the site serves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the site\'s files and fonts are in the app bundle', () async {
    final assets = WebAssets();
    await assets.preload();
    for (final name in WebAssets.files.keys) {
      expect(
        assets.url(name),
        matches(RegExp('^/assets/$name\\?v=[0-9a-f]{10}\$')),
      );
      final r = assets.asset(name)!;
      expect(r.contentLength, greaterThan(0));
    }
    for (final name in WebAssets.fonts) {
      final r = await assets.font(name);
      expect(r, isNotNull, reason: name);
      expect(r!.contentLength, greaterThan(1000), reason: name);
    }
    expect(assets.asset('nope.js'), isNull);
    expect(await assets.font('nope.ttf'), isNull);
  });
}
