import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';

import 'package:braim/models/note.dart';
import 'package:braim/services/circuit_file.dart';

/// A zip entry the way a crafted file writes it: [declaredSize] is what its
/// headers claim, whatever [data] inflates to.
class _Entry {
  _Entry(this.name, this.data, this.method, this.declaredSize, this.crc,
      {this.link = false});
  final String name;
  final List<int> data;
  final int method;
  final int declaredSize;
  final int crc;

  /// Marked as a Unix symbolic link.
  final bool link;
  int offset = 0;
}

List<int> _deflatedZeros(int total) {
  final out = BytesBuilder(copy: false);
  final sink = ByteConversionSink.withCallback(out.add);
  final enc = ZLibEncoder(raw: true, level: 9).startChunkedConversion(sink);
  final chunk = Uint8List(1 << 20);
  for (var i = 0; i < total ~/ chunk.length; i++) {
    enc.add(chunk);
  }
  enc.close();
  return out.takeBytes();
}

List<int> _zip(List<_Entry> entries) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  for (final e in entries) {
    e.offset = b.length;
    final name = utf8.encode(e.name);
    u32(0x04034b50);
    u16(20);
    u16(0);
    u16(e.method);
    u16(0);
    u16(0);
    u32(e.crc);
    u32(e.data.length);
    u32(e.declaredSize);
    u16(name.length);
    u16(0);
    b.add(name);
    b.add(e.data);
  }
  final cdStart = b.length;
  for (final e in entries) {
    final name = utf8.encode(e.name);
    u32(0x02014b50);
    u16(e.link ? (3 << 8) | 20 : 20); // made by: Unix for a link
    u16(20);
    u16(0);
    u16(e.method);
    u16(0);
    u16(0);
    u32(e.crc);
    u32(e.data.length);
    u32(e.declaredSize);
    u16(name.length);
    u16(0);
    u16(0);
    u16(0);
    u16(0);
    u32(e.link ? 0xA1FF << 16 : 0); // external attributes: the file mode
    u32(e.offset);
    b.add(name);
  }
  final cdLen = b.length - cdStart;
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(entries.length);
  u16(entries.length);
  u32(cdLen);
  u32(cdStart);
  u16(0);
  return b.takeBytes();
}

_Entry _stored(String name, String text) {
  final d = utf8.encode(text);
  return _Entry(name, d, 0, d.length, getCrc32(d));
}

void main() {
  test('an image that inflates far past its declared size is refused early',
      () {
    // Declares 10 bytes; inflates to 300 MB.
    const inflated = 300 * 1024 * 1024;
    final file = _zip([
      _stored('manifest.json',
          jsonEncode({'format': 'braim-circuit', 'version': 1, 'title': 'x'})),
      _stored(
          'circuit.json',
          jsonEncode({
            'rootId': 'r',
            'notes': [
              {'id': 'r', 'title': 'x', 'blocks': []},
            ],
          })),
      _Entry('images/1.png', _deflatedZeros(inflated), 8, 10, 0),
    ]);
    final before = ProcessInfo.currentRss;
    expect(
      () => decodeCircuitFile(file),
      throwsA(isA<CircuitFileException>()
          .having((e) => e.problem, 'problem', CircuitFileProblem.tooLarge)),
    );
    // Stopped at the 30 MB image limit, not after inflating all 300 MB.
    expect(ProcessInfo.maxRss - before, lessThan(150 * 1024 * 1024));
  });

  test('an entry marked as a link is never inflated', () {
    const inflated = 300 * 1024 * 1024;
    final file = _zip([
      _stored('manifest.json',
          jsonEncode({'format': 'braim-circuit', 'version': 1, 'title': 'x'})),
      _stored(
          'circuit.json',
          jsonEncode({
            'rootId': 'r',
            'notes': [
              {'id': 'r', 'title': 'x', 'blocks': []},
            ],
          })),
      _Entry('images/1.png', _deflatedZeros(inflated), 8, 10, 0, link: true),
    ]);
    final before = ProcessInfo.currentRss;
    try {
      decodeCircuitFile(file);
    } on CircuitFileException {
      // Refusing it is fine too; inflating it isn't.
    }
    expect(ProcessInfo.maxRss - before, lessThan(150 * 1024 * 1024));
  });

  test('a received text size is kept to what the editor allows', () {
    for (final raw in [-5, 0, 1e6, double.infinity, double.nan, 'big']) {
      final n = Note.fromJson({'id': 'n', 'title': 't', 'fontScale': raw});
      expect(n.fontScale, inInclusiveRange(0.8, 1.6), reason: '$raw');
    }
    expect(Note.fromJson({'id': 'n', 'fontScale': 1.2}).fontScale, 1.2);
  });
}
