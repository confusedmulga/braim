import 'dart:io' show ZLibCodec;
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The plain file name an archive entry may be written as inside [folder]
/// (for example `images/`), or null when the entry isn't one to write.
///
/// Zips get passed between people — a backup someone sent, a shared circuit —
/// so an entry's name is untrusted input. A name like `images/../data.json`
/// would otherwise land outside the folder and overwrite app files (a "zip
/// slip"). Only a single path segment is accepted: no separators, not `.` or
/// `..`, no control characters, and a sane length.
String? safeEntryFileName(String entryName, {required String folder}) {
  if (!entryName.startsWith(folder)) return null;
  final name = entryName.substring(folder.length);
  if (name.isEmpty || name.length > 255) return null;
  if (name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\\')) return null;
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) return null;
  return name;
}

/// Reads a zip's list of entries without inflating any of them.
///
/// The archive package's ZipDecoder inflates every entry marked as a Unix
/// symbolic link while it reads the list (to learn where the link points),
/// past any size limit: a crafted file can mark its "zip bomb" as a link.
/// This reads the same list but leaves each entry to [inflateEntry], and
/// leaves links out altogether: nothing Braim writes contains one.
Archive readZipEntries(InputStream input) {
  final directory = ZipDirectory()..read(input);
  final archive = Archive();
  for (final header in directory.fileHeaders) {
    final file = header.file;
    if (file == null) continue;
    final mode = header.externalFileAttributes >> 16;
    final link = header.versionMadeBy >> 8 == 3 && (mode & 0xf000) == 0xa000;
    final name = file.filename;
    final folder = name.endsWith('/') || name.endsWith(r'\');
    if (link || folder || archive.find(name) != null) continue;
    archive.add(ArchiveFile.file(name, file.uncompressedSize, file)
      ..compression = file.compressionMethod
      ..mode = mode);
  }
  return archive;
}

/// Thrown by [inflateEntry] once an entry inflates past its limit.
class EntryTooLarge implements Exception {
  const EntryTooLarge();
}

/// Inflates [f] a chunk at a time into [onChunk], stopping with
/// [EntryTooLarge] once more than [max] bytes have come out.
///
/// A zip entry's declared size is untrusted (a "zip bomb" declares a few
/// bytes and inflates to gigabytes), and the archive package inflates a whole
/// entry into memory before handing any of it on, so the counting is done
/// here, as the bytes come out.
void inflateEntry(
    ArchiveFile f, int max, void Function(List<int> chunk) onChunk) {
  var total = 0;
  void take(List<int> chunk) {
    total += chunk.length;
    if (total > max) throw const EntryTooLarge();
    onChunk(chunk);
  }

  final raw = f.rawContent;
  if (raw == null) {
    // Already in memory (an archive built here): its length is real.
    take(f.readBytes() ?? Uint8List(0));
    return;
  }
  final input = raw.getStream(decompress: false);
  // The entry's own stream: put it back where it was, as the archive package
  // does, so the entry can be read again.
  final start = input.position;
  List<int> next() => input.readBytes(min(1 << 16, input.length)).toUint8List();
  try {
    switch (f.compression) {
      case CompressionType.deflate:
        final inflater =
            ZLibCodec(raw: true).decoder.startChunkedConversion(_Chunks(take));
        while (!input.isEOS) {
          inflater.add(next());
        }
        inflater.close();
      case CompressionType.bzip2:
        throw const FormatException('Unsupported compression');
      case CompressionType.none || null:
        while (!input.isEOS) {
          take(next());
        }
    }
  } finally {
    input.setPosition(start);
  }
}

class _Chunks implements Sink<List<int>> {
  _Chunks(this._take);
  final void Function(List<int>) _take;

  @override
  void add(List<int> chunk) => _take(chunk);

  @override
  void close() {}
}
