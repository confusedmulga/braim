import 'package:braim/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled OFL font license loads into the license page', () async {
    registerFontLicenses();
    final fonts = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      final names = entry.packages.where((p) => p.endsWith('(font)'));
      if (names.isEmpty) continue;
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      fonts.addAll(names);
    }
    expect(fonts, {
      'Lora (font)',
      'Caveat (font)',
      'Space Grotesk (font)',
      'EB Garamond (font)',
      'Merriweather (font)',
      'JetBrains Mono (font)',
    });
  });
}
