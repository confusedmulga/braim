import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import 'archive_safety.dart';

/// The shareable circuit file (`.braim`): one circuit — every note, its place
/// in the tree, its look, and its images — packed so another phone's Braim can
/// import it exactly as it was.
///
/// The file is a zip:
/// - `manifest.json`: `{format, version, source, title, noteCount, exportedAt}`
/// - `circuit.json`: `{rootId, notes: [...]}`, the notes as Note JSON limited
///   to [_noteKeys], image blocks pointing at `images/<name>`
/// - `images/<name>`: the note images
///
/// Only what makes up the circuit travels. A folder, reminders, pins, book and
/// journal data, history and annotations stay on the sender's phone, and the
/// importer ignores them even if a file carries them.
class CircuitFile {
  CircuitFile._();

  static const format = 'braim-circuit';

  /// The newest version this build reads (and the one it writes).
  static const version = 1;
  static const extension = 'braim';

  /// The type it's shared as. Its own, not the generic octet-stream, which
  /// messengers show (and may save) as a ".bin" file.
  static const mimeType = 'application/vnd.braim.circuit';

  // Limits for a file received from someone else.
  static const maxFileBytes = 200 * 1024 * 1024;
  static const maxImageBytes = 30 * 1024 * 1024;
  static const maxJsonBytes = 20 * 1024 * 1024;
  static const maxNotes = 5000;
}

/// Whether a received file is a circuit: its type or name says so, or it is a
/// zip (a shared Markdown or text file never is). The contents decide in the
/// end, as messengers sometimes rename a file or drop its type on the way;
/// the import itself then checks it properly.
Future<bool> looksLikeCircuitFile(String path, {String? mimeType}) async {
  if (mimeType == CircuitFile.mimeType ||
      path.toLowerCase().endsWith('.${CircuitFile.extension}')) {
    return true;
  }
  try {
    final file = File(path);
    if (!await file.exists()) return false;
    final head = await file.openRead(0, 4).expand((b) => b).toList();
    // A zip starts with its local-file signature: P, K, 3, 4.
    return head.length == 4 &&
        head[0] == 0x50 &&
        head[1] == 0x4B &&
        head[2] == 0x03 &&
        head[3] == 0x04;
  } catch (_) {
    return false;
  }
}

/// Why a file couldn't be imported.
enum CircuitFileProblem {
  /// Not a zip, or a zip that isn't a Braim circuit.
  notACircuit,

  /// Made by a newer Braim, in a format this build doesn't know yet.
  newerVersion,

  /// A Braim circuit, but broken or tampered with.
  damaged,

  /// Over the size or note-count limits.
  tooLarge,
}

class CircuitFileException implements Exception {
  const CircuitFileException(this.problem);
  final CircuitFileProblem problem;

  @override
  String toString() => 'CircuitFileException(${problem.name})';
}

/// A circuit file that has been read and checked, ready to import.
class CircuitBundle {
  CircuitBundle._({
    required this.title,
    required this.source,
    required this.rootId,
    required this.notes,
    required this.images,
  });

  /// The first note's title, for the "already have it" question.
  final String title;

  /// The id of the original circuit this file is a copy of.
  final String source;

  /// The first note's id in [notes] (still the sender's ids).
  final String rootId;

  /// The notes as checked, whitelisted JSON maps.
  final List<Map<String, dynamic>> notes;

  /// Image bytes by the plain file name the notes refer to.
  final Map<String, List<int>> images;

  int get noteCount => notes.length;
}

/// The Note JSON keys a circuit file carries; everything else is left behind.
const _noteKeys = {
  'id',
  'title',
  'blocks',
  'colorValue',
  'tags',
  'fontScale',
  'checkedToBottom',
  'markdown',
  'circuitId',
  'circuitParentId',
  'circuitOrder',
  'circuitShowInFeed',
  'circuitPlaceholder',
  'circuitPlaceholderFor',
  'circuitLayout',
  'createdAt',
  'updatedAt',
};

const _blockKeys = {
  'id',
  'type',
  'text',
  'imagePath',
  'url',
  'linkTitle',
  'linkImage',
  'linkSite',
  'linkFetched',
};

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'heic',
  'heif',
  'bmp',
};

const _layouts = {'ltr', 'ttb', 'radial'};

Map<String, dynamic> _only(Map source, Set<String> keys) => {
      for (final e in source.entries)
        if (e.key is String && keys.contains(e.key)) e.key as String: e.value,
    };

// ---- Export ---------------------------------------------------------------

/// Packs a circuit into the bytes of a `.braim` file. [root] is the first
/// note and [nodes] every live note of the circuit (the root included).
/// [source] identifies the original circuit. [images] holds the bytes of the
/// notes' image files by path; an image missing from it is left out.
/// Synchronous and self-contained, so it can run in a background isolate.
List<int> encodeCircuitFile({
  required Note root,
  required List<Note> nodes,
  required String source,
  required Map<String, List<int>> images,
  DateTime? now,
}) {
  final archive = Archive();
  final namesByPath = <String, String>{};
  final notes = <Map<String, dynamic>>[];

  for (final n in nodes) {
    final json = _only(n.toJson(), _noteKeys);
    final blocks = <Map<String, dynamic>>[];
    for (final b in n.blocks) {
      final block = _only(b.toJson(), _blockKeys);
      if (b.isImage && b.imagePath.isNotEmpty) {
        var name = namesByPath[b.imagePath];
        if (name == null) {
          final bytes = images[b.imagePath];
          if (bytes != null) {
            name = '${namesByPath.length + 1}.${_extensionOf(b.imagePath)}';
            namesByPath[b.imagePath] = name;
            archive.addFile(ArchiveFile('images/$name', bytes.length, bytes));
          }
        }
        // An image that couldn't be read leaves an empty block behind, which
        // every view already skips.
        block['imagePath'] = name == null ? '' : 'images/$name';
      }
      blocks.add(block);
    }
    json['blocks'] = blocks;
    notes.add(json);
  }

  final manifest = {
    'format': CircuitFile.format,
    'version': CircuitFile.version,
    'source': source,
    'title': root.title,
    'noteCount': notes.length,
    'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
  };
  final circuit = {'rootId': root.id, 'notes': notes};
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final circuitBytes = utf8.encode(jsonEncode(circuit));
  archive
    ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes))
    ..addFile(ArchiveFile('circuit.json', circuitBytes.length, circuitBytes));
  return ZipEncoder().encode(archive);
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[\\/]'));
  if (dot <= slash) return 'jpg';
  final ext = path.substring(dot + 1).toLowerCase();
  return _imageExtensions.contains(ext) ? ext : 'jpg';
}

// ---- Import: read and check ------------------------------------------------

/// Reads and checks a `.braim` file received from someone else. Throws
/// [CircuitFileException] when it can't be imported; never throws anything
/// else. The result's notes still carry the sender's ids — see
/// [materializeCircuit].
CircuitBundle decodeCircuitFile(List<int> bytes) {
  if (bytes.length > CircuitFile.maxFileBytes) {
    throw const CircuitFileException(CircuitFileProblem.tooLarge);
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const CircuitFileException(CircuitFileProblem.notACircuit);
  }
  try {
    return _decode(archive);
  } on CircuitFileException {
    rethrow;
  } catch (_) {
    // Anything unexpected (a wrong type deep in a note, a bad zip entry) means
    // the file isn't what it claims to be.
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }
}

CircuitBundle _decode(Archive archive) {
  ArchiveFile? entry(String name) {
    for (final f in archive) {
      if (f.isFile && f.name == name) return f;
    }
    return null;
  }

  Map<String, dynamic> readJson(ArchiveFile f) {
    if (f.size > CircuitFile.maxJsonBytes) {
      throw const CircuitFileException(CircuitFileProblem.tooLarge);
    }
    final content = f.content as List<int>;
    if (content.length > CircuitFile.maxJsonBytes) {
      throw const CircuitFileException(CircuitFileProblem.tooLarge);
    }
    final decoded = jsonDecode(utf8.decode(content));
    if (decoded is! Map<String, dynamic>) {
      throw const CircuitFileException(CircuitFileProblem.damaged);
    }
    return decoded;
  }

  // The manifest says what this is; without it it isn't one of ours.
  final manifestEntry = entry('manifest.json');
  if (manifestEntry == null) {
    throw const CircuitFileException(CircuitFileProblem.notACircuit);
  }
  final Map<String, dynamic> manifest;
  try {
    manifest = readJson(manifestEntry);
  } on CircuitFileException {
    rethrow;
  } catch (_) {
    throw const CircuitFileException(CircuitFileProblem.notACircuit);
  }
  if (manifest['format'] != CircuitFile.format) {
    throw const CircuitFileException(CircuitFileProblem.notACircuit);
  }
  final version = manifest['version'];
  if (version is! int || version < 1) {
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }
  if (version > CircuitFile.version) {
    throw const CircuitFileException(CircuitFileProblem.newerVersion);
  }

  final circuitEntry = entry('circuit.json');
  if (circuitEntry == null) {
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }
  final circuit = readJson(circuitEntry);
  final rootId = circuit['rootId'];
  final rawNotes = circuit['notes'];
  if (rootId is! String || rootId.isEmpty || rawNotes is! List) {
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }
  if (rawNotes.isEmpty) {
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }
  if (rawNotes.length > CircuitFile.maxNotes) {
    throw const CircuitFileException(CircuitFileProblem.tooLarge);
  }

  final notes = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final raw in rawNotes) {
    if (raw is! Map) {
      throw const CircuitFileException(CircuitFileProblem.damaged);
    }
    final json = _only(raw, _noteKeys);
    final id = json['id'];
    if (id is! String || id.isEmpty || !ids.add(id)) {
      throw const CircuitFileException(CircuitFileProblem.damaged);
    }
    final blocks = json['blocks'];
    json['blocks'] = blocks is List
        ? [
            for (final b in blocks)
              if (b is Map) _only(b, _blockKeys)
          ]
        : <Map<String, dynamic>>[];
    // Parse it once as a note: a wrong type anywhere fails here, as damaged,
    // rather than later in the middle of the import.
    Note.fromJson(Map<String, dynamic>.of(json));
    notes.add(json);
  }
  if (!ids.contains(rootId)) {
    throw const CircuitFileException(CircuitFileProblem.damaged);
  }

  // Images: plain names under images/, known types, within limits. Anything
  // else in the zip is ignored.
  final images = <String, List<int>>{};
  var total = 0;
  for (final f in archive) {
    if (!f.isFile) continue;
    final name = safeEntryFileName(f.name, folder: 'images/');
    if (name == null) continue;
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    if (!_imageExtensions.contains(ext)) continue;
    if (f.size > CircuitFile.maxImageBytes) {
      throw const CircuitFileException(CircuitFileProblem.tooLarge);
    }
    final content = f.content as List<int>;
    total += content.length;
    if (content.length > CircuitFile.maxImageBytes ||
        total > CircuitFile.maxFileBytes) {
      throw const CircuitFileException(CircuitFileProblem.tooLarge);
    }
    images[name] = content;
  }

  final title = manifest['title'];
  final source = manifest['source'];
  return CircuitBundle._(
    title: title is String ? title : '',
    source: source is String && source.isNotEmpty ? source : rootId,
    rootId: rootId,
    notes: notes,
    images: images,
  );
}

// ---- Import: fresh notes for this library ----------------------------------

const _uuid = Uuid();

/// Turns a checked [bundle] into new notes for this library: every note gets
/// a new id (and every reference to one is rewritten), images are stored
/// through [saveImage] (given a plain file name and its bytes, it returns the
/// stored path), and the tree is repaired — a node whose parent is missing, or
/// that sits in a loop, is placed under the first note. Returns the notes,
/// the first note first, with its [Note.circuitSource] set.
Future<List<Note>> materializeCircuit(
  CircuitBundle bundle, {
  required Future<String> Function(String name, List<int> bytes) saveImage,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final newIds = {for (final n in bundle.notes) n['id'] as String: _uuid.v4()};
  final rootId = newIds[bundle.rootId]!;
  final savedImages = <String, String>{};

  Future<String> imagePathFor(String filePath) async {
    // Only an image carried in the file can be used: a path to the sender's
    // own storage (or anywhere else) is never followed.
    if (!filePath.startsWith('images/')) return '';
    final name = filePath.substring('images/'.length);
    final bytes = bundle.images[name];
    if (bytes == null) return '';
    return savedImages[name] ??= await saveImage(name, bytes);
  }

  final notes = <Note>[];
  for (final source in bundle.notes) {
    final json = Map<String, dynamic>.of(source);
    final oldId = json['id'] as String;
    json['id'] = newIds[oldId];
    json['circuitId'] = rootId;
    final isRoot = oldId == bundle.rootId;
    // The first note is always a real note, never a stand-in.
    if (isRoot) json.remove('circuitPlaceholder');
    final parent = json['circuitParentId'];
    json['circuitParentId'] = isRoot
        ? null
        : (parent is String ? newIds[parent] : null) ?? rootId;
    final standsFor = json['circuitPlaceholderFor'];
    json['circuitPlaceholderFor'] =
        standsFor is String ? newIds[standsFor] : null;
    if (!_layouts.contains(json['circuitLayout'])) json.remove('circuitLayout');
    json['updatedAt'] = at.toIso8601String();

    final blocks = <Map<String, dynamic>>[];
    for (final b in json['blocks'] as List) {
      final block = Map<String, dynamic>.of(b as Map<String, dynamic>);
      if (block['type'] == 'image') {
        final p = block['imagePath'];
        block['imagePath'] = p is String ? await imagePathFor(p) : '';
      }
      blocks.add(block);
    }
    json['blocks'] = blocks;

    final note = Note.fromJson(json);
    if (isRoot) {
      note.circuitSource = bundle.source;
      notes.insert(0, note);
    } else {
      notes.add(note);
    }
  }
  _repairTree(notes, rootId);
  return notes;
}

/// Makes [notes] one tree under [rootId]: a node whose parent is missing or
/// which sits in a parent loop goes under the root, and each sibling list is
/// numbered 0..n-1 in its saved order.
void _repairTree(List<Note> notes, String rootId) {
  final byId = {for (final n in notes) n.id: n};
  for (final n in notes) {
    if (n.id == rootId) continue;
    final seen = <String>{n.id};
    var cur = byId[n.circuitParentId];
    var ok = cur != null;
    while (ok && cur!.id != rootId) {
      if (!seen.add(cur.id)) {
        ok = false;
        break;
      }
      cur = byId[cur.circuitParentId];
      ok = cur != null;
    }
    if (!ok) n.circuitParentId = rootId;
  }
  final byParent = <String, List<Note>>{};
  for (final n in notes) {
    if (n.id == rootId) continue;
    byParent.putIfAbsent(n.circuitParentId!, () => []).add(n);
  }
  for (final siblings in byParent.values) {
    final saved = [for (var i = 0; i < siblings.length; i++) (i, siblings[i])]
      ..sort((a, b) {
        final c = a.$2.circuitOrder.compareTo(b.$2.circuitOrder);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    for (var i = 0; i < saved.length; i++) {
      saved[i].$2.circuitOrder = i;
    }
  }
}
