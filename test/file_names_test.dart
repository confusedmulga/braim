import 'package:flutter_test/flutter_test.dart';

import 'package:braim/services/file_names.dart';

void main() {
  group('safeFileBase', () {
    test('keeps a plain title, joining words with the separator', () {
      expect(safeFileBase('Plan a trip', fallback: 'x'), 'Plan-a-trip');
      expect(safeFileBase('Plan a trip', fallback: 'x', separator: ' '),
          'Plan a trip');
    });

    test('keeps titles in non-Latin scripts', () {
      // These used to become "" — a hidden ".md" file.
      expect(safeFileBase('यात्रा योजना', fallback: 'x'), 'यात्रा-योजना');
      expect(safeFileBase('旅行', fallback: 'x'), '旅行');
      expect(safeFileBase('Café ✈️', fallback: 'x'), 'Café-✈️');
    });

    test('drops only characters file systems reject', () {
      expect(safeFileBase('a/b\\c:d*e?f"g<h>i|j', fallback: 'x'), 'abcdefghij');
      expect(safeFileBase('tab\there', fallback: 'x'), 'tab-here');
      expect(safeFileBase('a / b', fallback: 'x'), 'a-b');
    });

    test('never starts with a dot, so the file is never hidden', () {
      expect(safeFileBase('.hidden', fallback: 'x'), 'hidden');
      expect(safeFileBase('...', fallback: 'x'), 'x');
    });

    test('falls back when nothing usable is left', () {
      expect(safeFileBase('', fallback: 'note'), 'note');
      expect(safeFileBase('   ', fallback: 'note'), 'note');
      expect(safeFileBase('///', fallback: 'circuit'), 'circuit');
    });

    test('caps long titles at 80 characters without splitting an emoji', () {
      final out = safeFileBase('${'a' * 79}😀😀', fallback: 'x');
      expect(out.runes.length, 80);
      expect(out.endsWith('😀'), isTrue);
    });
  });
}
