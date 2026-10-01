// Braim Web's JSON API for editing: notes, Markdown notes and sparks, their
// edit leases and checklist ticks. Every change goes through AppState on the
// live objects, so the phone, the database and backups see it at once. See
// docs/braim-web-plan.md, sections 7.3, 9 and 11.

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../models/tweet_card.dart';
import '../services/note_markdown.dart';
import '../state/app_state.dart';
import 'web_html.dart';
import 'web_security.dart';

/// A JSON response.
Response jsonResponse(
  int status,
  Map<String, Object?> body, {
  Map<String, Object>? headers,
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

// ---- Delta sanitising (section 9.1) -------------------------------------------

/// Inline marks Braim stores, with the values each may take.
const _inlineFlags = {'bold', 'italic', 'underline', 'strike'};

/// Line formats; Quill keeps them on the newline that ends the line.
const _lineFormats = {'header', 'blockquote', 'list', 'indent', 'align'};

final _hexColour = RegExp(r'^#[0-9a-fA-F]{6}$');

Object? _cleanAttribute(String key, Object? value) {
  if (_inlineFlags.contains(key)) return value == true ? true : null;
  switch (key) {
    case 'link':
      if (value is! String) return null;
      return safeUrl(value);
    case 'background':
    case 'color':
      return value is String && _hexColour.hasMatch(value) ? value : null;
    case 'header':
      return value == 1 || value == 2 ? value : null;
    case 'blockquote':
      return value == true ? true : null;
    case 'list':
      return const {'bullet', 'ordered', 'checked', 'unchecked'}.contains(value)
          ? value
          : null;
    case 'indent':
      // The phone shows three levels; deeper indents keep the deepest.
      if (value is! num) return null;
      final i = value.toInt();
      return i < 1 ? null : (i > 3 ? 3 : i);
    case 'align':
      return const {'center', 'right', 'justify'}.contains(value)
          ? value
          : null;
  }
  return null; // not one of Braim's formats
}

/// [ops] reduced to what Braim's phone editor can show: text inserts only
/// (images and other embeds are dropped), the format allowlist on every op,
/// line formats only on newlines and inline marks only on text, and a final
/// newline, which `flutter_quill` requires. Null when [ops] isn't a list of
/// ops.
List<Map<String, Object>>? sanitizeDelta(Object? ops) {
  if (ops is! List) return null;
  final out = <Map<String, Object>>[];
  for (final op in ops) {
    if (op is! Map) return null;
    final insert = op['insert'];
    if (insert is! String) continue; // an embed
    final text = insert.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.isEmpty) continue;
    final attrs = <String, Object>{};
    final raw = op['attributes'];
    final onlyNewlines = text.replaceAll('\n', '').isEmpty;
    if (raw is Map) {
      for (final e in raw.entries) {
        final key = e.key;
        if (key is! String) continue;
        // Line formats live on newlines, inline marks on text.
        if (_lineFormats.contains(key) != onlyNewlines) continue;
        final value = _cleanAttribute(key, e.value);
        if (value != null) attrs[key] = value;
      }
    }
    out.add({'insert': text, if (attrs.isNotEmpty) 'attributes': attrs});
  }
  final last = out.isEmpty ? null : out.last['insert'] as String;
  if (last == null || !last.endsWith('\n')) out.add({'insert': '\n'});
  return out;
}

/// A text block as the web editor loads it: its Delta, cleaned, or legacy
/// plain text turned into one.
String editorDelta(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('[')) {
    try {
      final ops = sanitizeDelta(jsonDecode(trimmed));
      if (ops != null) return jsonEncode(ops);
    } on FormatException {
      // Not a Delta after all: plain text.
    }
  }
  return jsonEncode([
    {'insert': raw.endsWith('\n') ? raw : '$raw\n'},
  ]);
}

// ---- Handlers -------------------------------------------------------------------

/// How long a browser's edit lease lasts unless renewed. The editor renews it
/// every 20 seconds.
const webLeaseTtl = Duration(seconds: 60);

/// The lease holder name for a browser session.
String webLeaseHolder(String sessionId) => 'web:$sessionId';

class WebApi {
  WebApi({required this.state, required this.l10n});

  final AppState state;
  final AppLocalizations l10n;

  /// The live note [id] if the web may show it, else null.
  Note? visibleNote(String id) {
    final n = state.noteById(id);
    return n != null && state.isWebVisibleNote(n) ? n : null;
  }

  /// The live spark [id] if it is in the Sparks feed's population.
  TweetCard? visibleSpark(String id) {
    final c = state.cardById(id);
    if (c == null) return null;
    for (final s in state.searchableCards) {
      if (identical(s, c)) return c;
    }
    return null;
  }

  static Response _bad([String error = 'bad_request']) =>
      jsonResponse(400, {'error': error});

  static Response _notFound() => jsonResponse(404, {'error': 'not_found'});

  /// Reads a JSON object body, or null when it isn't one.
  static Future<Map<String, Object?>?> _body(Request request) async {
    if (request.mimeType != 'application/json') return null;
    try {
      final decoded = jsonDecode(await readBodyLimited(request));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// The 409 to answer when someone other than [holder] is editing [id].
  Response? _leaseConflict(String id, String holder) {
    final current = state.editLeaseHolder(id);
    if (current == null || current == holder) return null;
    final phone = current == kPhoneLease;
    return jsonResponse(409, {
      'error': 'leased',
      'by': phone ? 'phone' : 'web',
      'message': phone ? l10n.webEditingOnPhone : l10n.webEditingElsewhere,
    });
  }

  /// The 409 to answer when the item changed since the page loaded it.
  Response? _versionConflict(DateTime updatedAt, Object? base) {
    if (base is int && base == updatedAt.millisecondsSinceEpoch) return null;
    return jsonResponse(409, {
      'error': 'changed',
      'message': l10n.webChangedOnPhone,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    });
  }

  /// Who holds [id]'s lease, as [sessionId]'s page should show it.
  String? leaseHolderFor(String id, String sessionId) {
    final h = state.editLeaseHolder(id);
    if (h == null) return null;
    if (h == kPhoneLease) return 'phone';
    return h == webLeaseHolder(sessionId) ? 'you' : 'web';
  }

  // ---- Leases ---------------------------------------------------------------------

  Response takeLease(String id, String sessionId) {
    final holder = webLeaseHolder(sessionId);
    final conflict = _leaseConflict(id, holder);
    if (conflict != null) return conflict;
    state.acquireEditLease(id, holder, ttl: webLeaseTtl);
    return jsonResponse(200, {'ok': true, 'ttl': webLeaseTtl.inSeconds});
  }

  Response releaseLease(String id, String sessionId) {
    state.releaseEditLease(id, webLeaseHolder(sessionId));
    return Response(204);
  }

  // ---- Notes ------------------------------------------------------------------------

  /// `POST /api/notes`: a new note. Like the phone, nothing is added until
  /// there is something in it.
  Future<Response> createNote(Request request) async {
    final body = await _body(request);
    if (body == null) return _bad();
    if (body['kind'] == 'markdown') {
      final source = body['source'];
      if (source is! String) return _bad();
      if (source.trim().isEmpty) return _bad('empty');
      final note = await state.addMarkdownNode(source);
      return _created(note);
    }
    final title = body['title'];
    final blocks = body['blocks'];
    if ((title != null && title is! String) || blocks is! List) return _bad();
    final newBlocks = <NoteBlock>[];
    for (final b in blocks) {
      final ops = sanitizeDelta(b is Map ? b['delta'] : null);
      if (ops == null) return _bad();
      newBlocks.add(NoteBlock(type: NoteBlockType.text, text: jsonEncode(ops)));
    }
    if (newBlocks.isEmpty) {
      newBlocks.add(
        NoteBlock(
          type: NoteBlockType.text,
          text: jsonEncode(sanitizeDelta([])),
        ),
      );
    }
    final note = Note(title: (title as String?) ?? '', blocks: newBlocks);
    if (note.isEmpty) return _bad('empty');
    await state.upsertNote(note);
    return _created(note);
  }

  Response _created(Note note) => jsonResponse(201, {
    'id': note.id,
    'updatedAt': note.updatedAt.millisecondsSinceEpoch,
    'blockIds': [
      for (final b in note.blocks)
        if (b.isText) b.id,
    ],
  });

  /// `PUT /api/notes/<id>`: saves a rich note's title and text blocks, or a
  /// Markdown note's source.
  Future<Response> saveNote(
    Request request,
    String id,
    String sessionId,
  ) async {
    final note = visibleNote(id);
    if (note == null) return _notFound();
    final body = await _body(request);
    if (body == null) return _bad();
    final conflict =
        _leaseConflict(id, webLeaseHolder(sessionId)) ??
        _versionConflict(note.updatedAt, body['baseUpdatedAt']);
    if (conflict != null) return conflict;

    if (note.markdown) {
      final source = body['source'];
      if (source is! String) return _bad();
      return _saveMarkdown(note, source);
    }

    final title = body['title'];
    if (title != null && title is! String) return _bad();
    final edits = _textEdits(note.blocks, body['blocks']);
    if (edits == null) return _bad('unknown_block');
    for (final (block, text) in edits.updates) {
      block.text = text;
    }
    note.blocks.addAll(edits.added);
    if (title is String) note.title = title;
    await state.upsertNote(note);
    return _saved(note.updatedAt, note.blocks);
  }

  /// The Markdown screen's save: the source is the note's one text block and
  /// its first heading the title. Emptied, it is deleted, except a circuit
  /// note others hang off (Circuits guide, section 9).
  Future<Response> _saveMarkdown(Note note, String source) async {
    if (source.trim().isEmpty &&
        !(note.isCircuitNode ||
            (note.isCircuitRoot &&
                state.circuitChildren(note.id).isNotEmpty))) {
      await state.deleteNote(note.id);
      return jsonResponse(200, {'deleted': true});
    }
    final block = note.blocks.where((b) => b.isText).firstOrNull;
    if (block == null) {
      note.blocks.add(NoteBlock(type: NoteBlockType.text, text: source));
    } else {
      block.text = source;
    }
    note
      ..markdown = true
      ..title = markdownTitle(source);
    await state.upsertNote(note);
    return _saved(note.updatedAt, note.blocks);
  }

  Response _saved(DateTime updatedAt, List<NoteBlock> blocks) =>
      jsonResponse(200, {
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'blockIds': [
          for (final b in blocks)
            if (b.isText) b.id,
        ],
      });

  /// Validates a save's `blocks`: each names an existing text block of
  /// [blocks] by `id`, at most once, or has no id and becomes a new text block
  /// at the end. Null for an unknown or repeated id, or a malformed Delta.
  ({List<(NoteBlock, String)> updates, List<NoteBlock> added})? _textEdits(
    List<NoteBlock> blocks,
    Object? sent,
  ) {
    if (sent is! List) return null;
    final byId = {
      for (final b in blocks)
        if (b.isText) b.id: b,
    };
    final seen = <String>{};
    final updates = <(NoteBlock, String)>[];
    final added = <NoteBlock>[];
    for (final item in sent) {
      if (item is! Map) return null;
      final ops = sanitizeDelta(item['delta']);
      if (ops == null) return null;
      final text = jsonEncode(ops);
      final blockId = item['id'];
      if (blockId == null) {
        added.add(NoteBlock(type: NoteBlockType.text, text: text));
        continue;
      }
      final block = blockId is String ? byId[blockId] : null;
      if (block == null || !seen.add(block.id)) return null;
      updates.add((block, text));
    }
    return (updates: updates, added: added);
  }

  /// `DELETE /api/notes/<id>`: moves a plain note to Recently deleted.
  /// Circuit notes delete through the map's rules (section 9.3); book pages
  /// stay phone-only, since deleting one is permanent.
  Future<Response> deleteNote(String id, String sessionId) async {
    final note = visibleNote(id);
    if (note == null) return _notFound();
    final conflict = _leaseConflict(id, webLeaseHolder(sessionId));
    if (conflict != null) return conflict;
    if (note.inCircuit || note.bookId != null) return _bad('not_here');
    await state.deleteNote(id);
    state.releaseEditLease(id, webLeaseHolder(sessionId));
    return jsonResponse(200, {'ok': true});
  }

  /// `POST /api/notes/<id>/check`: ticks or unticks one checklist line.
  Future<Response> checkLine(Request request, String id, String sessionId) =>
      _check(request, id, sessionId, note: visibleNote(id));

  Future<Response> _check(
    Request request,
    String id,
    String sessionId, {
    Note? note,
    TweetCard? card,
  }) async {
    final blocks = note?.blocks ?? card?.blocks;
    final updatedAt = note?.updatedAt ?? card?.updatedAt;
    if (blocks == null || updatedAt == null) return _notFound();
    if (note != null && note.markdown) return _bad();
    final body = await _body(request);
    if (body == null) return _bad();
    final conflict =
        _leaseConflict(id, webLeaseHolder(sessionId)) ??
        _versionConflict(updatedAt, body['baseUpdatedAt']);
    if (conflict != null) return conflict;
    final bi = body['block'];
    final line = body['line'];
    if (bi is! int || line is! int || bi < 0 || bi >= blocks.length) {
      return _bad();
    }
    final block = blocks[bi];
    if (!block.isText) return _bad();
    final updated = toggleChecklistLine(block.text, line);
    if (updated == block.text) return _bad('not_a_checkbox');
    block.text = updated;
    if (note != null) {
      await state.upsertNote(note);
      return jsonResponse(200, {
        'updatedAt': note.updatedAt.millisecondsSinceEpoch,
      });
    }
    await state.updateCard(card!);
    return jsonResponse(200, {
      'updatedAt': card.updatedAt.millisecondsSinceEpoch,
    });
  }

  /// `POST /api/markdown/preview`: the sanitised HTML the note page would show.
  Future<Response> markdownPreview(Request request) async {
    final body = await _body(request);
    final source = body?['source'];
    if (source is! String) return _bad();
    return jsonResponse(200, {'html': markdownToSafeHtml(source)});
  }

  // ---- Sparks ---------------------------------------------------------------------------

  /// `POST /api/sparks`: saves a link as a spark. The phone fetches its
  /// preview; the page updates through the event stream.
  Future<Response> addSpark(Request request) async {
    final body = await _body(request);
    final url = body?['url'];
    if (url is! String) return _bad();
    final safe = safeUrl(url.trim());
    if (safe == null || safe.toLowerCase().startsWith('mailto:')) {
      return _bad('bad_url');
    }
    final card = await state.addCardFromUrl(safe);
    // An existing spark kept in the Crypt stays out of sight.
    return jsonResponse(201, {
      if (visibleSpark(card.id) != null) 'id': card.id,
    });
  }

  /// `PUT /api/sparks/<id>`: saves a spark's title and its own note.
  Future<Response> saveSpark(
    Request request,
    String id,
    String sessionId,
  ) async {
    final card = visibleSpark(id);
    if (card == null) return _notFound();
    final body = await _body(request);
    if (body == null) return _bad();
    final conflict =
        _leaseConflict(id, webLeaseHolder(sessionId)) ??
        _versionConflict(card.updatedAt, body['baseUpdatedAt']);
    if (conflict != null) return conflict;
    final title = body['title'];
    if (title != null && title is! String) return _bad();
    final edits = _textEdits(card.blocks, body['blocks']);
    if (edits == null) return _bad('unknown_block');
    for (final (block, text) in edits.updates) {
      block.text = text;
    }
    card.blocks.addAll(edits.added);
    if (title is String) card.noteTitle = title;
    await state.updateCard(card);
    return _saved(card.updatedAt, card.blocks);
  }

  /// `DELETE /api/sparks/<id>`: moves a spark to Recently deleted.
  Future<Response> deleteSpark(String id, String sessionId) async {
    if (visibleSpark(id) == null) return _notFound();
    final conflict = _leaseConflict(id, webLeaseHolder(sessionId));
    if (conflict != null) return conflict;
    await state.deleteCard(id);
    state.releaseEditLease(id, webLeaseHolder(sessionId));
    return jsonResponse(200, {'ok': true});
  }

  /// `POST /api/sparks/<id>/check`: ticks a line in a spark's own note.
  Future<Response> checkSparkLine(
    Request request,
    String id,
    String sessionId,
  ) => _check(request, id, sessionId, card: visibleSpark(id));
}
