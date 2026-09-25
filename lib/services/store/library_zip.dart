import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/note.dart';
import '../../state/app_state.dart' show kCryptSpaceId;
import '../storage_service.dart' show AppData;

/// A whole library as it travels in a backup zip: the data plus its images
/// keyed by file name.
typedef LibraryBundle = ({AppData data, Map<String, Uint8List> images});

/// The phone's backup format (`data.json` + `images/<name>`), read and written
/// in memory — the browser has no files, and a phone backup must restore on
/// the web and a web export on the phone with the existing flows.
class LibraryZip {
  LibraryZip._();

  /// Parses a backup zip. Throws [FormatException] when it isn't one.
  static LibraryBundle decode(Uint8List zipBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw FormatException('Not a zip file: $e');
    }
    String? dataJson;
    final images = <String, Uint8List>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      if (f.name == 'data.json') {
        dataJson = utf8.decode(f.content);
      } else if (f.name.startsWith('images/')) {
        final base = f.name.substring('images/'.length);
        if (base.isEmpty || base.contains('/')) continue;
        images[base] = Uint8List.fromList(f.content);
      }
    }
    if (dataJson == null) {
      throw const FormatException('Not a valid Braim backup (no data.json).');
    }
    final map = jsonDecode(dataJson) as Map<String, dynamic>;
    return (data: AppData.fromJson(map), images: images);
  }

  /// Builds a backup zip the phone's restore accepts.
  static Uint8List encode(AppData data, Map<String, Uint8List> images) {
    final archive = Archive();
    final json = utf8.encode(jsonEncode(data.toJson()));
    archive.addFile(ArchiveFile('data.json', json.length, json));
    images.forEach((name, bytes) {
      archive.addFile(ArchiveFile('images/$name', bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

/// Ids of everything that lives in the Crypt: notes filed there (and circuit
/// branches whose root is), and cards filed there. The Crypt is locked behind
/// the phone's biometrics, so these never reach a browser unasked.
Set<String> cryptEntityIds(AppData data) {
  final notesById = {for (final n in data.notes) n.id: n};
  bool inCrypt(Note n) {
    if (n.spaceId == kCryptSpaceId) return true;
    final root = n.circuitId;
    if (root == null || root == n.id) return false;
    return notesById[root]?.spaceId == kCryptSpaceId;
  }

  return {
    for (final n in data.notes)
      if (inCrypt(n)) n.id,
    for (final c in data.cards)
      if (c.spaceId == kCryptSpaceId) c.id,
  };
}

/// [data] with every Crypt entity removed (see [cryptEntityIds]).
AppData withoutCrypt(AppData data) {
  final crypt = cryptEntityIds(data);
  if (crypt.isEmpty) return data;
  final json = data.settingsToJson();
  return AppData.fromJson(
    json,
    notesOverride: [
      for (final n in data.notes)
        if (!crypt.contains(n.id)) n,
    ],
    cardsOverride: [
      for (final c in data.cards)
        if (!crypt.contains(c.id)) c,
    ],
    booksOverride: data.books,
    impulsesOverride: data.impulses,
    spacesOverride: data.spaces,
  );
}

/// Every image path the library references (note and card blocks, folder
/// thumbnails, book covers, feed backgrounds, journal month covers).
Set<String> referencedImagePaths(AppData data) {
  final out = <String>{};
  void add(String? p) {
    if (p != null && p.isNotEmpty) out.add(p);
  }

  for (final n in data.notes) {
    for (final b in n.blocks) {
      if (b.isImage) add(b.imagePath);
    }
  }
  for (final c in data.cards) {
    for (final b in c.blocks) {
      if (b.isImage) add(b.imagePath);
    }
  }
  for (final s in data.spaces) {
    add(s.thumbnailPath);
  }
  for (final b in data.books) {
    add(b.coverPath);
  }
  add(data.feedBackgroundLight);
  add(data.feedBackgroundDark);
  add(data.feedBackgroundPath);
  data.journalMonthCovers.values.forEach(add);
  return out;
}
