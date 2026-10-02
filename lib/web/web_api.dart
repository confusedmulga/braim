// Braim Web's JSON API for editing: notes, Markdown notes, sparks, circuits
// and books, their edit leases and checklist ticks. Every change goes through AppState on the
// live objects, so the phone, the database and backups see it at once. See
// docs/braim-web-plan.md, sections 7.3, 9 and 11.

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../l10n/l10n.dart';
import '../models/book.dart';
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

  // ---- Circuits (section 9.3) ----------------------------------------------------

  /// A circuit's first note, if the web may show its map.
  Note? circuitRoot(String id) {
    final n = state.noteById(id);
    return n != null && n.isCircuitRoot && state.isWebVisibleNote(n) ? n : null;
  }

  /// A live note of a circuit whose map the web may show. Placeholders count:
  /// they are drawn on the map, though they never open as notes.
  Note? circuitNode(String id) {
    final n = state.noteById(id);
    if (n == null || n.deletedAt != null || !n.inCircuit) return null;
    final root = state.circuitRootOf(n);
    if (root == null || circuitRoot(root.id) == null) return null;
    if (!n.circuitPlaceholder && !state.isWebVisibleNote(n)) return null;
    return n;
  }

  /// A node's name as the map and its dialogs show it.
  String nodeTitle(Note n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    return n.isCircuitRoot ? l10n.untitledCircuit : l10n.untitledNote;
  }

  String _noteTitle(int n) => l10n.circuitNoteTitle(n);

  static Response _ok() => jsonResponse(200, {'ok': true});

  /// Where a new or changed circuit note can be opened: its editor, or the
  /// map focused on it.
  static Map<String, Object> _places(Note n) => {
    'id': n.id,
    'edit': '/notes/${Uri.encodeComponent(n.id)}/edit',
    'map':
        '/circuits/${Uri.encodeComponent(n.circuitId ?? n.id)}'
        '?focus=${Uri.encodeComponent(n.id)}',
  };

  /// [id] and every live note below it.
  List<Note> _subtree(String id) {
    final self = state.noteById(id);
    final out = <Note>[?self];
    final stack = [id];
    final seen = <String>{id};
    while (stack.isNotEmpty) {
      for (final c in state.circuitChildren(stack.removeLast())) {
        if (!seen.add(c.id)) continue;
        out.add(c);
        stack.add(c.id);
      }
    }
    return out;
  }

  /// The number a delete dialog quotes: a circuit's notes, or the notes below
  /// a branch. A delete sent with a different number was decided on a
  /// circuit that has changed since.
  int _deleteCount(Note n) => n.isCircuitRoot
      ? state.circuitNodes(n.id).where((m) => !m.circuitPlaceholder).length
      : state.circuitDescendantCount(n.id);

  /// `POST /api/circuits`: a new circuit whose first note is titled `title`.
  Future<Response> createCircuit(Request request) async {
    final title = (await _body(request))?['title'];
    if (title is! String) return _bad();
    if (title.trim().isEmpty) return _bad('empty');
    final root = state.newCircuitRootDraft()..title = title.trim();
    await state.ensureCircuitRootSaved(root);
    return jsonResponse(201, _places(root));
  }

  /// `POST /api/circuits/nodes/<id>/child` and `.../sibling`: a new "Note #N"
  /// under [id] or right after it. On the first note, both add a child.
  Future<Response> addCircuitNote(
    Request request,
    String id, {
    required bool under,
  }) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (node.circuitPlaceholder) return _bad('placeholder');
    final body = await _body(request);
    if (body == null) return _bad();
    final markdown = body['markdown'] == true;
    final created = under || node.isCircuitRoot
        ? await state.addCircuitChild(
            id,
            markdown: markdown,
            noteTitle: _noteTitle,
          )
        : await state.addCircuitSibling(
            id,
            markdown: markdown,
            noteTitle: _noteTitle,
          );
    return jsonResponse(201, _places(created));
  }

  /// `POST /api/circuits/nodes/<id>/rename`. Refused while someone else is
  /// editing the note, since their editor would put the old title back.
  Future<Response> renameCircuitNode(
    Request request,
    String id,
    String sessionId,
  ) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (node.circuitPlaceholder) return _bad('placeholder');
    final title = (await _body(request))?['title'];
    if (title is! String) return _bad();
    if (title.trim().isEmpty) return _bad('empty');
    final conflict = _leaseConflict(id, webLeaseHolder(sessionId));
    if (conflict != null) return conflict;
    await state.renameCircuitNode(id, title.trim());
    return _ok();
  }

  /// `POST /api/circuits/nodes/<id>/move`: up (-1) or down (1) among its
  /// siblings.
  Future<Response> moveCircuitNode(Request request, String id) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (node.isCircuitRoot) return _bad('root');
    final delta = (await _body(request))?['delta'];
    if (delta is! int || (delta != -1 && delta != 1)) return _bad();
    await state.moveCircuitNode(id, delta);
    return _ok();
  }

  /// `POST /api/circuits/nodes/<id>/delete`, by the phone's rules: the first
  /// note takes the whole circuit; a branch with notes below it goes with
  /// them (`all`) or leaves a placeholder (`keepSlot`); anything else goes
  /// alone. `count` is the number the dialog showed.
  Future<Response> deleteCircuitNode(
    Request request,
    String id,
    String sessionId,
  ) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (node.circuitPlaceholder) return _bad('placeholder');
    final body = await _body(request);
    if (body == null) return _bad();
    final mode = body['mode'];
    final keepSlot = mode == 'keepSlot';
    final canKeepSlot =
        !node.isCircuitRoot && state.circuitDescendantCount(id) > 0;
    if (mode != 'all' && !(keepSlot && canKeepSlot)) return _bad();
    if (body['count'] != _deleteCount(node)) {
      return jsonResponse(409, {
        'error': 'changed',
        'message': l10n.webChangedOnPhone,
      });
    }
    final members = node.isCircuitRoot
        ? state.circuitNodes(id)
        : (keepSlot ? [node] : _subtree(id));
    final holder = webLeaseHolder(sessionId);
    for (final m in members) {
      final conflict = _leaseConflict(m.id, holder);
      if (conflict != null) return conflict;
    }
    if (node.isCircuitRoot) {
      await state.deleteCircuit(id);
    } else if (keepSlot) {
      await state.deleteCircuitNodeKeepSlot(
        id,
        placeholderTitle: l10n.circuitPlaceholderTitle,
      );
    } else {
      await state.deleteCircuitSubtree(id);
    }
    for (final m in members) {
      state.releaseEditLease(m.id, holder);
    }
    return jsonResponse(200, {
      'ok': true,
      if (node.isCircuitRoot) 'go': '/circuits',
    });
  }

  /// `POST /api/circuits/nodes/<id>/write-placeholder`: the placeholder
  /// becomes a new "Note #N" in place, rich or Markdown.
  Future<Response> writePlaceholder(Request request, String id) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (!node.circuitPlaceholder) return _bad('not_placeholder');
    final body = await _body(request);
    if (body == null) return _bad();
    final note = await state.writeIntoPlaceholder(
      id,
      markdown: body['markdown'] == true,
      noteTitle: _noteTitle,
    );
    return jsonResponse(200, _places(note));
  }

  /// `POST /api/circuits/nodes/<id>/remove-placeholder`: the notes under it
  /// move up into its place.
  Future<Response> removePlaceholder(String id) async {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    if (!node.circuitPlaceholder) return _bad('not_placeholder');
    await state.deletePlaceholder(id);
    return _ok();
  }

  /// `POST /api/circuits/<rootId>/layout`: `ltr`, `ttb` or `radial`.
  Future<Response> setCircuitLayout(Request request, String rootId) async {
    if (circuitRoot(rootId) == null) return _notFound();
    final mode = (await _body(request))?['mode'];
    if (mode is! String || !const {'ltr', 'ttb', 'radial'}.contains(mode)) {
      return _bad();
    }
    await state.setCircuitLayout(rootId, mode);
    return _ok();
  }

  /// `GET /api/circuits/nodes/<id>/menu`: what a node's menu offers, with the
  /// texts of its rename and delete dialogs, so the rules and the wording live
  /// here rather than in `map.js`. Each item names an action and, for the
  /// ones that post, the body to send.
  Response circuitNodeMenu(String id) {
    final node = circuitNode(id);
    if (node == null) return _notFound();
    final title = nodeTitle(node);
    final api = '/api/circuits/nodes/${Uri.encodeComponent(id)}';
    Map<String, Object> item(
      String action,
      String label, {
      bool enabled = true,
      bool danger = false,
      Map<String, Object>? send,
    }) => {
      'action': action,
      'label': label,
      if (!enabled) 'disabled': true,
      if (danger) 'danger': true,
      'send': ?send,
    };
    const sep = {'sep': true};

    if (node.circuitPlaceholder) {
      return jsonResponse(200, {
        'title': title,
        'api': api,
        'items': [
          item('write', l10n.circuitSlotWrite, send: {'markdown': false}),
          item(
            'write',
            l10n.circuitSlotWriteMarkdown,
            send: {'markdown': true},
          ),
          sep,
          item('remove', l10n.circuitSlotRemove, danger: true),
        ],
      });
    }

    final root = node.isCircuitRoot;
    final items = <Map<String, Object>>[
      item('open', l10n.circuitOpen),
      item('rename', l10n.circuitRename),
      sep,
      if (!root)
        item('sibling', l10n.circuitAddSibling, send: {'markdown': false}),
      item('child', l10n.circuitAddChild, send: {'markdown': false}),
      item('child', l10n.circuitAddChildMarkdown, send: {'markdown': true}),
    ];
    if (!root) {
      final sibs = state.circuitChildren(node.circuitParentId!);
      final i = sibs.indexWhere((s) => s.id == id);
      items.addAll([
        sep,
        item('move', l10n.circuitMoveUp, enabled: i > 0, send: {'delta': -1}),
        item(
          'move',
          l10n.circuitMoveDown,
          enabled: i >= 0 && i < sibs.length - 1,
          send: {'delta': 1},
        ),
      ]);
    }
    items.addAll([
      sep,
      item(
        'delete',
        root ? l10n.circuitDeleteCircuitAction : l10n.delete,
        danger: true,
      ),
    ]);

    final count = _deleteCount(node);
    final deleteAlone = {'mode': 'all', 'label': l10n.delete, 'danger': true};
    final Map<String, Object> delete = root
        ? {
            'text': l10n.circuitDeleteCircuit(title, count),
            'choices': [deleteAlone],
          }
        : count == 0
        ? {
            'text': l10n.circuitDeleteTitle(title),
            'body': l10n.deleteItemsConfirm(1),
            'choices': [deleteAlone],
          }
        : {
            'text': l10n.circuitDeleteTitle(title),
            'body': l10n.circuitDeleteBody(count),
            'choices': [
              {'mode': 'keepSlot', 'label': l10n.circuitDeleteOnly},
              {
                'mode': 'all',
                'label': l10n.circuitDeleteAll(count + 1),
                'danger': true,
              },
            ],
          };
    return jsonResponse(200, {
      'title': title,
      'api': api,
      'open': '/notes/${Uri.encodeComponent(id)}',
      'items': items,
      'rename': {'title': l10n.circuitRename, 'value': node.title.trim()},
      'delete': {...delete, 'count': count},
    });
  }

  // ---- Books (section 9.4) ---------------------------------------------------------

  /// A live book: on the shelf, not archived or deleted.
  Book? visibleBook(String id) {
    final b = state.bookById(id);
    return b != null && !b.archived && b.deletedAt == null ? b : null;
  }

  /// A page of book [bookId] as the web lists it: a manuscript page the web
  /// may show, other than the book's Contents page (which the contents page
  /// stands in for). Workshop notes are never manuscript pages.
  Note? bookPage(String bookId, String pageId) {
    if (visibleBook(bookId) == null) return null;
    final n = state.noteById(pageId);
    if (n == null ||
        n.bookId != bookId ||
        n.bookPageKind == BookPageKind.contents ||
        !state.isWebVisibleNote(n)) {
      return null;
    }
    return n;
  }

  /// A book page's editor.
  static String bookPageEditHref(Note page) =>
      '/books/${Uri.encodeComponent(page.bookId ?? '')}'
      '/pages/${Uri.encodeComponent(page.id)}/edit';

  /// `POST /api/books/<id>/chapters`: a new "Chapter N" at the end, numbered
  /// as the phone numbers it.
  Future<Response> addChapter(String bookId) async {
    if (visibleBook(bookId) == null) return _notFound();
    final chapter = await state.addBookChapter(bookId);
    return jsonResponse(201, {
      'id': chapter.id,
      'edit': bookPageEditHref(chapter),
    });
  }

  /// `POST /api/books/<id>/pages/<pageId>/move`: one place up (-1) or down
  /// (1) among the pages the contents lists, so the Contents page itself
  /// stays where it is. Moving re-dates every page that changes place, so it
  /// is refused while any of them is being edited elsewhere.
  Future<Response> moveBookPage(
    Request request,
    String bookId,
    String pageId,
    String sessionId,
  ) async {
    final page = bookPage(bookId, pageId);
    if (page == null) return _notFound();
    final delta = (await _body(request))?['delta'];
    if (delta is! int || (delta != -1 && delta != 1)) return _bad();
    final all = state.bookPages(bookId);
    final listed = [
      for (final p in all)
        if (p.bookPageKind != BookPageKind.contents) p,
    ];
    final j = listed.indexOf(page) + delta;
    if (j < 0 || j >= listed.length) return _bad('edge');
    final from = all.indexOf(page);
    final to = all.indexOf(listed[j]);
    final after = List.of(all)
      ..removeAt(from)
      ..insert(to, page);
    final holder = webLeaseHolder(sessionId);
    for (var i = 0; i < after.length; i++) {
      if (after[i].bookOrder == i) continue;
      final conflict = _leaseConflict(after[i].id, holder);
      if (conflict != null) return conflict;
    }
    // `reorderBookPages` takes a list's drop index, which counts the moved
    // page's old slot when moving down.
    await state.reorderBookPages(bookId, from, to > from ? to + 1 : to);
    return _ok();
  }
}
