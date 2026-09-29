import 'package:braim/main.dart';
import 'package:braim/models/book.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      'Inter (font)',
      'Nunito (font)',
    });
  });

  test('every book face has the OFL license its ePub export embeds', () async {
    for (final family in [...BookFonts.all, 'unknown-falls-back']) {
      final text = await rootBundle.loadString(BookFonts.licenseAsset(family));
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'),
          reason: family);
    }
    expect(BookFonts.licenseAsset('EB Garamond'),
        'assets/fonts/OFL-EBGaramond.txt');
  });
}
