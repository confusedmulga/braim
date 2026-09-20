import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note_block.dart';
import '../screens/crop_screen.dart';
import '../services/image_service.dart';
import '../services/link_preview_service.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'frosted_glass.dart';

/// The highlighter's paint: a light background with a fixed dark ink so
/// highlighted text stays legible in both light and dark themes (the default
/// body ink flips with the theme, the highlight background does not). Shared by
/// the editor toggle and the read-only view.
const String kHighlightBg = '#FFE082';
const String kHighlightInk = '#202124';

/// Adds an https scheme when the user typed a bare host, so "example.com"
/// becomes a working link. A URL that already carries a scheme is left as-is.
String _normalizeLinkUrl(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return u;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(u)) return u;
  return 'https://$u';
}

/// A reusable rich-text + image block editor. It edits the [blocks] list in
/// place; call [NoteBodyEditorState.sync] before persisting. The [activeController]
/// notifier is shared with a [NoteFormatBar] so the toolbar targets the focused
/// line.
class NoteBodyEditor extends StatefulWidget {
  const NoteBodyEditor({
    super.key,
    required this.blocks,
    required this.activeController,
    this.onRemoveImagePath,
    this.onLight = false,
    this.bodyFontFamily,
    this.fontScale = 1.0,
    this.onBackspaceAtStart,
  });

  final List<NoteBlock> blocks;
  final ValueNotifier<QuillController?> activeController;
  final void Function(String path)? onRemoveImagePath;

  /// Called when Backspace is pressed at the very start of an empty first line,
  /// so the screen can move the cursor up into the title (Google Keep style).
  final VoidCallback? onBackspaceAtStart;

  /// Use black text for light (white) backgrounds.
  final bool onLight;

  /// When set (a book page), typeset the whole editor — body and headings —
  /// in this family instead of the handwriting default, so the manuscript
  /// reads in the book's chosen face.
  final String? bodyFontFamily;

  /// A per-note multiplier on every text size (body, headings, lists…), so a
  /// note can be set larger or smaller as a whole.
  final double fontScale;

  @override
  State<NoteBodyEditor> createState() => NoteBodyEditorState();
}

class NoteBodyEditorState extends State<NoteBodyEditor> {
  final Map<String, QuillController> _quillCtrls = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, ScrollController> _scrollCtrls = {};
  final Map<String, StreamSubscription> _docSubs = {};
  final Set<String> _fetchingLinks = {};
  // One debounce timer per block: a scan queued for one block must not cancel a
  // scan already pending for another (typing a URL in one block then a newline
  // in a second within the debounce window would otherwise drop the first).
  final Map<String, Timer> _linkScanTimers = {};

  // ---- @@ / @@@ mention autocomplete --------------------------------------
  /// The trigger just before the caret: `@@Query` links a node, `@@@Query`
  /// mentions a thread/impulse. The picker filters live as [_mentionQuery] grows.
  static final _mentionRe = RegExp(r'(@{2,3})([^@\n]{0,40})$');
  OverlayEntry? _mentionEntry;
  String? _mentionBlockId;
  int _mentionMode = 0; // 0 none, 2 node link, 3 thread/impulse mention
  int _mentionStart = 0; // plain-text offset where the `@@`/`@@@` begins
  int _mentionCaret = 0; // plain-text offset of the caret (end of the query)
  String _mentionQuery = '';

  /// Any http(s) URL embedded in the text (not just a whole-line one), so a
  /// link pasted mid-sentence is caught too. Trailing punctuation is trimmed
  /// when a match is applied. Case-insensitive: keyboards auto-capitalize.
  static final _urlInText = RegExp(r'https?://[^\s]+', caseSensitive: false);

  List<NoteBlock> get _blocks => widget.blocks;

  @override
  void initState() {
    super.initState();
    if (_blocks.isEmpty) {
      _blocks.add(NoteBlock(type: NoteBlockType.text));
    }
    _ensureTrailingText();
    for (final b in _blocks) {
      if (b.isText) _ensure(b);
    }
  }

  @override
  void dispose() {
    for (final t in _linkScanTimers.values) {
      t.cancel();
    }
    _mentionEntry?.remove();
    _mentionEntry = null;
    for (final s in _docSubs.values) {
      s.cancel();
    }
    for (final c in _quillCtrls.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    for (final s in _scrollCtrls.values) {
      s.dispose();
    }
    super.dispose();
  }

  void _ensure(NoteBlock b) {
    _quillCtrls.putIfAbsent(b.id, () {
      final c = _controllerFor(b);
      // Watch for URLs: a paste arrives as one big insert (convert right
      // away); typed URLs convert when Enter finishes the line.
      _docSubs[b.id]?.cancel();
      _docSubs[b.id] = c.document.changes.listen((change) {
        for (final op in change.change.toList()) {
          final data = op.data;
          if (!op.isInsert || data is! String) continue;
          // Count this keystroke toward the "time spent writing" analytic.
          if (mounted) context.read<AppState>().recordTypingActivity();
          if (data.length >= 12 && data.toLowerCase().contains('http')) {
            _scheduleLinkScan(b.id, allowCursorLine: true);
            break;
          }
          if (data.contains('\n')) {
            _scheduleLinkScan(b.id, allowCursorLine: false);
            break;
          }
        }
      });
      // Watch the caret + text for an @@/@@@ mention trigger (fires on both
      // typing and cursor moves, so the picker follows the caret).
      c.addListener(() => _scanMention(b.id));
      return c;
    });
    _scrollCtrls.putIfAbsent(b.id, () => ScrollController());
    _focusNodes.putIfAbsent(b.id, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus) {
          widget.activeController.value = _quillCtrls[b.id];
        }
      });
      return node;
    });
  }

  /// Google Keep-style edits at the start of a line, hooked into the Quill
  /// editor's own key pipeline (so it also catches the soft keyboard's
  /// Backspace). Returns null to let the editor handle the key normally.
  KeyEventResult? _onBlockKey(NoteBlock b, KeyEvent event) {
    if (event is KeyUpEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return null;
    }
    final c = _quillCtrls[b.id];
    if (c == null) return null;
    final sel = c.selection;
    if (!sel.isCollapsed || sel.baseOffset != 0) return null;
    final idx = _blocks.indexWhere((x) => x.id == b.id);
    if (idx < 0) return null;

    // Right after an image (or link) card: delete that block.
    if (idx > 0 && !_blocks[idx - 1].isText) {
      final prev = _blocks[idx - 1];
      sync();
      setState(() => _blocks.removeAt(idx - 1));
      if (prev.isImage && prev.imagePath.isNotEmpty) {
        widget.onRemoveImagePath?.call(prev.imagePath);
      }
      _disposeBlockEditors(prev.id);
      return KeyEventResult.handled;
    }

    // Right after another text block: merge this line up into it, so a blank
    // line (e.g. one left behind by a removed image) erases on Backspace
    // instead of getting stuck.
    if (idx > 0 && _blocks[idx - 1].isText) {
      _mergeTextBlocks(idx, focus: true);
      return KeyEventResult.handled;
    }

    // Empty first line: hand the cursor up to the title.
    final firstText = _blocks.indexWhere((x) => x.isText);
    if (idx == firstText &&
        widget.onBackspaceAtStart != null &&
        c.document.toPlainText().trim().isEmpty) {
      widget.onBackspaceAtStart!();
      return KeyEventResult.handled;
    }
    return null;
  }

  QuillController _controllerFor(NoteBlock b) {
    Document doc;
    final raw = b.text.trim();
    if (raw.startsWith('[')) {
      try {
        doc = Document.fromJson(_readableHighlights(jsonDecode(raw) as List));
      } catch (_) {
        doc = Document()..insert(0, raw);
      }
    } else if (raw.isEmpty) {
      doc = Document();
    } else {
      doc = Document()..insert(0, raw);
    }
    return QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Back-fills a readable dark ink onto highlighted runs saved before the
  /// highlighter paired the two, so older notes aren't light-on-yellow in the
  /// editor. Only touches runs that carry a background but no explicit colour.
  List<dynamic> _readableHighlights(List<dynamic> ops) {
    return [
      for (final op in ops)
        if (op is Map &&
            op['attributes'] is Map &&
            (op['attributes'] as Map)['background'] != null &&
            (op['attributes'] as Map)['color'] == null)
          {
            ...op,
            'attributes': {
              ...(op['attributes'] as Map),
              'color': kHighlightInk,
            },
          }
        else
          op,
    ];
  }

  // ---- Mention autocomplete -------------------------------------------------

  /// Re-checks the text just before the caret for an `@@`/`@@@` trigger and
  /// shows, updates or hides the suggestion popup accordingly.
  void _scanMention(String blockId) {
    if (!mounted) return;
    final c = _quillCtrls[blockId];
    if (c == null) {
      _hideMention();
      return;
    }
    final sel = c.selection;
    if (!sel.isCollapsed || sel.baseOffset < 0) {
      _hideMention();
      return;
    }
    final text = c.document.toPlainText();
    final caret = sel.baseOffset.clamp(0, text.length);
    final before = text.substring(0, caret);
    final m = _mentionRe.firstMatch(before);
    if (m == null) {
      _hideMention();
      return;
    }
    _mentionBlockId = blockId;
    _mentionMode = m.group(1)!.length >= 3 ? 3 : 2;
    _mentionStart = m.start;
    _mentionCaret = caret;
    _mentionQuery = m.group(2)!;
    if (!_hasMentionResults()) {
      _hideMention();
      return;
    }
    if (_mentionEntry == null) {
      _mentionEntry = OverlayEntry(builder: _buildMentionOverlay);
      Overlay.of(context).insert(_mentionEntry!);
    } else {
      _mentionEntry!.markNeedsBuild();
    }
  }

  bool _hasMentionResults() {
    if (_mentionMode == 0) return false;
    final state = context.read<AppState>();
    return _mentionMode == 3
        ? state.searchMentionTargets(_mentionQuery).isNotEmpty
        : state.searchLinkTargets(_mentionQuery).isNotEmpty;
  }

  void _hideMention() {
    _mentionMode = 0;
    _mentionBlockId = null;
    _mentionQuery = '';
    _mentionStart = 0;
    _mentionCaret = 0;
    _mentionEntry?.remove();
    _mentionEntry = null;
  }

  /// Replaces the `@@`/`@@@` trigger + query with [insert] and re-focuses the
  /// block so the keyboard stays up.
  void _applyMention(String insert) {
    final blockId = _mentionBlockId;
    final c = blockId == null ? null : _quillCtrls[blockId];
    if (c == null) {
      _hideMention();
      return;
    }
    final start = _mentionStart;
    final end = _mentionCaret;
    _hideMention();
    // Guard against the document having shrunk since the last scan.
    final maxLen = c.document.length;
    if (end < start || start > maxLen) return;
    final removeLen = (end - start).clamp(0, maxLen - start);
    c.replaceText(start, removeLen, insert,
        TextSelection.collapsed(offset: start + insert.length));
    _focusNodes[blockId]?.requestFocus();
  }

  Widget _buildMentionOverlay(BuildContext ctx) {
    final state = context.read<AppState>();
    final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
    final rows = <Widget>[];
    if (_mentionMode == 3) {
      for (final t in state.searchMentionTargets(_mentionQuery)) {
        rows.add(_mentionRow(
          icon: t.isThread
              ? Icons.check_circle_outline_rounded
              : Icons.bolt_rounded,
          title: t.label,
          subtitle: t.parent,
          onTap: () => _applyMention('[[@${t.label}]] '),
        ));
      }
    } else {
      for (final n in state.searchLinkTargets(_mentionQuery)) {
        final title = n.title.trim();
        rows.add(_mentionRow(
          icon: Icons.description_outlined,
          title: title,
          subtitle: null,
          onTap: () => _applyMention('[[$title]] '),
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final header =
        _mentionMode == 3 ? context.t.mentionThreadHeader : context.t.mentionNodeHeader;
    return Positioned(
      left: 10,
      right: 10,
      // Sit above the keyboard and clear the floating format island below.
      bottom: bottomInset + 170,
      child: Material(
        elevation: 12,
        color: AppPalette.sheet,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          constraints: const BoxConstraints(maxHeight: 244),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(
                  children: [
                    Icon(
                        _mentionMode == 3
                            ? Icons.alternate_email_rounded
                            : Icons.link_rounded,
                        size: 15,
                        color: AppPalette.inkSecondary),
                    const SizedBox(width: 8),
                    Text(header.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary)),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: rows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mentionRow({
    required IconData icon,
    required String title,
    required String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppPalette.scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkPrimary)),
                  if (subtitle != null && subtitle.trim().isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: AppPalette.inkSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureTrailingText() {
    if (_blocks.isEmpty || !_blocks.last.isText) {
      final b = NoteBlock(type: NoteBlockType.text);
      _blocks.add(b);
      _ensure(b);
    }
  }

  /// Writes the live editor contents back into the block models.
  void sync() {
    for (final b in _blocks) {
      if (b.isText) {
        final c = _quillCtrls[b.id];
        if (c != null) b.text = jsonEncode(c.document.toDelta().toJson());
      }
    }
  }

  Future<void> addPhotos() async {
    final picked = await ImageService.pickMultiple();
    if (picked.isEmpty) return;
    // A single photo gets an in-app crop before it lands in the note (backing
    // out keeps it uncropped). A multi-pick is inserted as-is: walking the
    // user through one cropper per image was a chore.
    final paths = List<String>.of(picked);
    if (picked.length == 1 && mounted) {
      final cropped = await cropImageFile(context, picked.single);
      if (cropped != null && cropped != picked.single) {
        paths[0] = cropped;
        unawaited(StorageService.instance.deleteImage(picked.single));
      }
    }
    if (!mounted) return;
    sync();
    setState(() {
      for (final p in paths) {
        _blocks.add(NoteBlock(type: NoteBlockType.image, imagePath: p));
      }
      final trailing = NoteBlock(type: NoteBlockType.text);
      _blocks.add(trailing);
      _ensure(trailing);
    });
  }

  void _removeImage(NoteBlock block) {
    // Remember the blocks the image sat between so we can rejoin them.
    final idx = _blocks.indexWhere((b) => b.id == block.id);
    final prev = idx > 0 ? _blocks[idx - 1] : null;
    final next = idx >= 0 && idx + 1 < _blocks.length ? _blocks[idx + 1] : null;
    setState(() {
      _blocks.removeWhere((b) => b.id == block.id);
      if (_blocks.isEmpty) {
        final b = NoteBlock(type: NoteBlockType.text);
        _blocks.add(b);
        _ensure(b);
      }
    });
    widget.onRemoveImagePath?.call(block.imagePath);
    // If the image left two text blocks touching and one of them is empty,
    // fold the empty line away so it doesn't strand an undeletable blank line
    // (two blocks that both hold text are left alone — that isn't a stray).
    if (prev != null && prev.isText && next != null && next.isText) {
      final p = _blocks.indexOf(prev);
      final n = _blocks.indexOf(next);
      if (p >= 0 && n == p + 1 &&
          (_isTextBlockEmpty(prev) || _isTextBlockEmpty(next))) {
        _mergeTextBlocks(n);
      }
    }
  }

  // ---- Inline hyperlinks ---------------------------------------------------

  void _scheduleLinkScan(String blockId, {required bool allowCursorLine}) {
    _linkScanTimers[blockId]?.cancel();
    _linkScanTimers[blockId] = Timer(const Duration(milliseconds: 350), () {
      _linkScanTimers.remove(blockId);
      if (mounted) _linkifyUrls(blockId, allowCursorLine: allowCursorLine);
    });
  }

  /// Turns every http(s) URL in the block into an inline, tappable, sky-blue
  /// hyperlink (Quill's `link` attribute) rather than a preview card. Runs on a
  /// paste (any URL) and when a line is finished — skipping a URL still under
  /// the caret so one being typed isn't linked mid-word. Formatting keeps the
  /// text length so the caret never moves, and already-linked URLs are skipped
  /// (which also stops this re-firing forever on its own change events).
  void _linkifyUrls(String blockId, {required bool allowCursorLine}) {
    final c = _quillCtrls[blockId];
    if (c == null) return;
    final plain = c.document.toPlainText();
    final cursor = c.selection.baseOffset;
    final delta = c.document.toDelta();
    final sel = c.selection;
    const trailing = '.,;:!?)]}>"\'';
    var applied = false;
    for (final m in _urlInText.allMatches(plain)) {
      var end = m.end;
      while (end > m.start && trailing.contains(plain[end - 1])) {
        end--;
      }
      final start = m.start;
      if (end - start < 8) continue; // "http://x" is the shortest worth linking
      if (!allowCursorLine && cursor > start && cursor < end) continue;
      if (_rangeIsLinked(delta, start, end)) continue;
      c.formatText(start, end - start,
          LinkAttribute(_normalizeLinkUrl(plain.substring(start, end))));
      applied = true;
    }
    // A pure attribute change shouldn't move the caret, but restore it anyway.
    if (applied && c.selection != sel) {
      c.updateSelection(sel, ChangeSource.local);
    }
  }

  /// Whether [start,end) is already fully covered by a non-empty `link`, so
  /// [_linkifyUrls] leaves it alone (and thus doesn't loop on its own change).
  bool _rangeIsLinked(Delta delta, int start, int end) {
    var pos = 0;
    for (final op in delta.toList()) {
      final data = op.data;
      final len = data is String ? data.length : 1;
      if (pos < end && pos + len > start) {
        final link = op.attributes?['link'];
        if (data is! String || link is! String || link.isEmpty) return false;
      }
      pos += len;
      if (pos >= end) break;
    }
    return true;
  }

  /// Quill documents must end with a newline insert.
  Delta _normalized(Delta d) {
    final ops = d.toList();
    if (ops.isEmpty) return Delta()..insert('\n');
    final last = ops.last.data;
    if (last is String && last.endsWith('\n')) return d;
    return d..insert('\n');
  }

  bool _isTextBlockEmpty(NoteBlock b) {
    final c = _quillCtrls[b.id];
    if (c != null) return c.document.toPlainText().trim().isEmpty;
    return b.text.trim().isEmpty;
  }

  /// Joins two block deltas end-to-end, dropping [a]'s single terminating
  /// newline so [b]'s content continues [a]'s last line — a line merge.
  Delta _concatDeltas(Delta a, Delta b) {
    final out = Delta();
    final aOps = a.toList();
    for (var i = 0; i < aOps.length; i++) {
      final op = aOps[i];
      final data = op.data;
      if (i == aOps.length - 1 && data is String && data.endsWith('\n')) {
        final trimmed = data.substring(0, data.length - 1);
        if (trimmed.isNotEmpty) out.insert(trimmed, op.attributes);
      } else {
        out.insert(op.data, op.attributes);
      }
    }
    for (final op in b.toList()) {
      out.insert(op.data, op.attributes);
    }
    return _normalized(out);
  }

  /// Merges the text block at [curIdx] into the text block just before it,
  /// preserving both sides' formatting. Rebuilds the previous block from the
  /// combined delta (the same dispose/recreate path link conversion uses) and,
  /// when [focus], drops the caret at the join. This is what lets a blank line
  /// — e.g. one stranded by a removed image — backspace away like any newline.
  void _mergeTextBlocks(int curIdx, {bool focus = false}) {
    final prevIdx = curIdx - 1;
    if (prevIdx < 0 || curIdx >= _blocks.length) return;
    final prev = _blocks[prevIdx];
    final cur = _blocks[curIdx];
    final prevC = _quillCtrls[prev.id];
    final curC = _quillCtrls[cur.id];
    if (!prev.isText || !cur.isText || prevC == null || curC == null) return;
    // The join sits just before the previous block's terminating newline.
    final caret = prevC.document.length - 1;
    final merged = _concatDeltas(prevC.document.toDelta(), curC.document.toDelta());
    setState(() {
      prev.text = jsonEncode(merged.toJson());
      _disposeBlockEditors(prev.id);
      _blocks.removeAt(curIdx);
      _disposeBlockEditors(cur.id);
      _ensure(prev);
    });
    if (!focus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _quillCtrls[prev.id];
      if (c == null) return;
      final max = c.document.length - 1;
      final off = caret.clamp(0, max < 0 ? 0 : max);
      c.updateSelection(
          TextSelection.collapsed(offset: off), ChangeSource.local);
      _focusNodes[prev.id]?.requestFocus();
    });
  }

  void _disposeBlockEditors(String id) {
    final c = _quillCtrls.remove(id);
    if (widget.activeController.value == c) {
      widget.activeController.value = null;
    }
    _docSubs.remove(id)?.cancel();
    c?.dispose();
    _focusNodes.remove(id)?.dispose();
    _scrollCtrls.remove(id)?.dispose();
  }

  void _fetchLinkPreview(NoteBlock b) {
    if (b.linkFetched || !_fetchingLinks.add(b.id)) return;
    LinkPreviewService.fetchBasicPreview(b.url).then((p) {
      _fetchingLinks.remove(b.id);
      if (!mounted || p == null) return;
      setState(() {
        b.linkTitle = p.title;
        b.linkImage = p.imageUrl;
        b.linkSite = p.siteName;
        b.linkFetched = true;
      });
    });
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Leave the card in place; nothing else to do.
    }
  }

  /// A pasted link as a small horizontal preview card (1500x400-ish ratio).
  Widget _linkCard(NoteBlock block) {
    if (!block.linkFetched) _fetchLinkPreview(block);
    final domain = block.linkSite.isNotEmpty
        ? block.linkSite
        : (Uri.tryParse(block.url)?.host ?? block.url);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _openLink(block.url),
        child: AspectRatio(
          aspectRatio: 1500 / 270,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppPalette.bubbleGlass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.cardOutline),
            ),
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: block.linkImage.isNotEmpty
                      ? Image.network(block.linkImage,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => _linkIconBox())
                      : _linkIconBox(),
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          block.linkTitle.isNotEmpty
                              ? block.linkTitle
                              : block.url,
                          // The slim card fits one title line comfortably.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.inkPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppPalette.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t.dismiss,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: AppPalette.inkSecondary),
                  onPressed: () => setState(() {
                    _blocks.removeWhere((b) => b.id == block.id);
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linkIconBox() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.06),
        child: Icon(Icons.link_rounded, color: AppPalette.inkSecondary),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final block in _blocks) _buildBlock(block)],
    );
  }

  Widget _buildBlock(NoteBlock block) {
    if (block.isLink) return _linkCard(block);
    if (block.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Image.file(File(block.imagePath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // Bound the decode: older notes may hold full-res photos.
                  cacheWidth: 1440),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _removeImage(block),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _ensure(block);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: QuillEditor.basic(
        controller: _quillCtrls[block.id]!,
        focusNode: _focusNodes[block.id]!,
        scrollController: _scrollCtrls[block.id]!,
        config: QuillEditorConfig(
          // Only the lone text block of an empty note gets the hint — the
          // filler blocks around images must stay visually empty.
          placeholder:
              _blocks.length == 1 ? context.t.writeSomething : null,
          scrollable: false,
          expands: false,
          autoFocus: false,
          padding: EdgeInsets.zero,
          customStyles: _quillStyles(
              widget.onLight, widget.bodyFontFamily, widget.fontScale),
          // Backspace at the start of a line: delete a preceding image, or on
          // an empty first line jump up to the title (Google Keep style).
          // ignore: experimental_member_use
          onKeyPressed: (event, node) => _onBlockKey(block, event),
          // A tap on an inline hyperlink opens it (Quill's default only opens on
          // long-press while editing); a tap elsewhere still places the caret.
          onTapUp: (details, getPosition) =>
              _openLinkAtTap(block.id, details, getPosition),
          // Long-press menu: the full address plus Open / Copy / Edit / Remove.
          linkActionPickerDelegate: (ctx, link, node) =>
              _linkMenu(block.id, ctx, link, node),
        ),
      ),
    );
  }

  /// Opens the hyperlink under a tap, if any. Returns true to consume the tap
  /// (so the caret doesn't move onto the link); false lets the editor handle it.
  bool _openLinkAtTap(String blockId, TapUpDetails details,
      TextPosition Function(Offset offset) getPosition) {
    final c = _quillCtrls[blockId];
    if (c == null) return false;
    final link = _linkAtOffset(c, getPosition(details.globalPosition).offset);
    if (link == null || link.isEmpty) return false;
    _openLink(link);
    return true;
  }

  /// The `link` attribute covering document [offset] in [c], or null.
  String? _linkAtOffset(QuillController c, int offset) {
    var pos = 0;
    for (final op in c.document.toDelta().toList()) {
      final data = op.data;
      final len = data is String ? data.length : 1;
      if (offset >= pos && offset < pos + len) {
        final link = op.attributes?['link'];
        return link is String ? link : null;
      }
      pos += len;
    }
    return null;
  }

  /// The long-press menu for an inline hyperlink: the full address at the top,
  /// then Open / Copy / Edit / Remove. Open and Edit are handled here (returning
  /// [LinkMenuAction.none]); Copy and Remove are handed back to Quill.
  Future<LinkMenuAction> _linkMenu(
      String blockId, BuildContext context, String link, Node node) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.sheet,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The pasted address, so the user can read where it points.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.link_rounded,
                      size: 18, color: AppPalette.inkSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(link,
                        style: TextStyle(
                            fontSize: 13.5, height: 1.3, color: kLinkColor)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppPalette.cardOutline),
            _linkMenuItem(ctx, Icons.open_in_new_rounded, context.t.open, 'open'),
            _linkMenuItem(ctx, Icons.copy_rounded, context.t.copy, 'copy'),
            _linkMenuItem(ctx, Icons.edit_outlined, context.t.editLink, 'edit'),
            _linkMenuItem(
                ctx, Icons.link_off_rounded, context.t.removeLink, 'remove',
                danger: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'open':
        await _openLink(link);
        return LinkMenuAction.none;
      case 'copy':
        return LinkMenuAction.copy;
      case 'remove':
        return LinkMenuAction.remove;
      case 'edit':
        await _editLinkNode(blockId, node, link);
        return LinkMenuAction.none;
      default:
        return LinkMenuAction.none;
    }
  }

  Widget _linkMenuItem(
      BuildContext sheetCtx, IconData icon, String label, String value,
      {bool danger = false}) {
    final color = danger ? const Color(0xFFE0567B) : AppPalette.inkPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      onTap: () => Navigator.pop(sheetCtx, value),
    );
  }

  /// Swaps the URL on an existing link run (from the long-press "Edit"): asks for
  /// a new address, then re-applies it across the whole link's range (or clears
  /// it when the field is emptied).
  Future<void> _editLinkNode(String blockId, Node node, String oldLink) async {
    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _LinkDialog(initial: oldLink),
    );
    if (result == null) return;
    final c = _quillCtrls[blockId];
    if (c == null) return;
    final range = getLinkRange(node);
    final len = range.end - range.start;
    if (len <= 0) return;
    if (result.trim().isEmpty) {
      c.formatText(range.start, len, Attribute.clone(Attribute.link, null));
    } else {
      c.formatText(range.start, len, LinkAttribute(_normalizeLinkUrl(result)));
    }
  }
}

/// Text styles for the editor, with distinct heading sizes. [onLight] switches
/// to black text for white backgrounds. When [fontFamily] is given (a book
/// page), the whole editor is typeset in that face at print-like sizes; the
/// default is the handwriting body with Lora headings used elsewhere.
DefaultStyles _quillStyles(bool onLight,
    [String? fontFamily, double scale = 1.0]) {
  final text = onLight ? AppPalette.inkPrimary : AppPalette.textPrimary;
  final placeholder = onLight
      ? AppPalette.inkSecondary.withValues(alpha: 0.7)
      : AppPalette.textSecondary.withValues(alpha: 0.7);
  // A book reads in one consistent face; a note keeps the handwritten body.
  final bookFace = fontFamily != null;
  final bodyFace = fontFamily ?? activeBodyFont;
  final headingFace = fontFamily ?? kNoteHeadingFont;
  // Caveat runs small for its point size, so notes sit a notch larger; the
  // serif book faces are set nearer a real page size. The per-note [scale]
  // grows or shrinks the whole note at once.
  final bodySize = (bookFace ? 18.0 : 21.0) * scale;
  final h1Size = (bookFace ? 24.0 : 26.0) * scale;
  final h2Size = (bookFace ? 20.0 : 21.0) * scale;
  final bodyHeight = bookFace ? 1.5 : 1.35;
  // Quill paints spans directly (no DefaultTextStyle inheritance), so the
  // family must be spelled out here or the editor falls back to Roboto.
  TextStyle body(double size, FontWeight w) => TextStyle(
      fontSize: size,
      height: bodyHeight,
      color: text,
      fontWeight: w,
      fontFamily: bodyFace);
  TextStyle heading(double size, FontWeight w) => TextStyle(
      fontSize: size,
      height: 1.25,
      color: text,
      fontWeight: w,
      fontFamily: headingFace);
  const hs = HorizontalSpacing(0, 0);
  const vs = VerticalSpacing(6, 0);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
        body(bodySize, FontWeight.w400), hs, vs, const VerticalSpacing(0, 0),
        null),
    // Without these, list lines and their bullets/numbers fall back to the
    // theme's (white) text style and vanish on the white sheet.
    lists: DefaultListBlockStyle(
      body(bodySize, FontWeight.w400),
      hs,
      vs,
      const VerticalSpacing(0, 6),
      null,
      null,
    ),
    leading: DefaultTextBlockStyle(
      body(bodySize, FontWeight.w400),
      hs,
      const VerticalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      null,
    ),
    // A quoted block: indented with a soft left rule.
    quote: DefaultTextBlockStyle(
      body(bodySize, FontWeight.w400).copyWith(
          color: text.withValues(alpha: 0.72), fontStyle: FontStyle.italic),
      const HorizontalSpacing(16, 0),
      const VerticalSpacing(6, 6),
      const VerticalSpacing(0, 0),
      BoxDecoration(
        border: Border(
          left: BorderSide(
              color: text.withValues(alpha: 0.28), width: 3),
        ),
      ),
    ),
    h1: DefaultTextBlockStyle(heading(h1Size, FontWeight.w700), hs,
        const VerticalSpacing(10, 0), const VerticalSpacing(0, 0), null),
    h2: DefaultTextBlockStyle(heading(h2Size, FontWeight.w600), hs,
        const VerticalSpacing(8, 0), const VerticalSpacing(0, 0), null),
    // Inline hyperlinks read as sky-blue underlined text in the editor, matching
    // the read view; a tap opens them (see onTapUp above).
    link: TextStyle(
      color: kLinkColor,
      decoration: TextDecoration.underline,
      decorationColor: kLinkColor,
    ),
    placeHolder: DefaultTextBlockStyle(
      TextStyle(
          fontSize: bodySize,
          height: bodyHeight,
          color: placeholder,
          fontFamily: bodyFace),
      hs,
      vs,
      const VerticalSpacing(0, 0),
      null,
    ),
  );
}

// Island ink colours follow the theme.
Color get _islandPrimary => AppPalette.inkPrimary;
Color get _islandSecondary => AppPalette.inkSecondary;

/// The standalone floating editor island: a white, frosted, faintly refractive
/// panel holding the format controls, add-photos and move-to-cortex actions.
class EditorBottomBar extends StatelessWidget {
  const EditorBottomBar({
    super.key,
    required this.activeController,
    required this.onAddPhotos,
    this.onPickSpace,
    this.onPickColor,
    this.onReminder,
    this.reminderSet = false,
    this.onLinkNote,
    this.onFontSize,
  });

  final ValueNotifier<QuillController?> activeController;
  final VoidCallback onAddPhotos;

  /// Opens the per-note text-size control.
  final VoidCallback? onFontSize;

  /// Move-to-cortex; hidden when null (journal entries don't join folders).
  final VoidCallback? onPickSpace;

  /// Opens the combined colour + background menu (note editor only); hidden
  /// when null (book pages, cards).
  final VoidCallback? onPickColor;

  /// Set/clear a reminder for the note; hidden when null (book pages).
  final VoidCallback? onReminder;
  final bool reminderSet;

  /// Insert a `[[link]]` to another note; hidden when null (book pages).
  final VoidCallback? onLinkNote;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: _RefractiveIsland(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoteFormatBar(activeController: activeController, onLight: true),
              Divider(height: 10, color: Colors.black.withValues(alpha: 0.08)),
              Row(
                children: [
                  IconButton(
                    tooltip: context.t.addPhotos,
                    icon: Icon(Icons.add_photo_alternate_outlined,
                        color: _islandPrimary),
                    onPressed: onAddPhotos,
                  ),
                  if (onFontSize != null)
                    IconButton(
                      tooltip: context.t.textSize,
                      icon: Icon(Icons.format_size_rounded,
                          color: _islandPrimary),
                      onPressed: onFontSize,
                    ),
                  if (onPickColor != null)
                    IconButton(
                      tooltip: context.t.noteColor,
                      icon: Icon(Icons.palette_outlined,
                          color: _islandPrimary),
                      onPressed: onPickColor,
                    ),
                  if (onPickSpace != null)
                    IconButton(
                      tooltip: context.t.tabCortex,
                      icon: Icon(Icons.folder_outlined,
                          color: _islandPrimary),
                      onPressed: onPickSpace,
                    ),
                  if (onReminder != null)
                    IconButton(
                      tooltip: context.t.reminder,
                      icon: Icon(
                          reminderSet
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: reminderSet
                              ? AppPalette.scheme.primary
                              : _islandPrimary),
                      onPressed: onReminder,
                    ),
                  if (onLinkNote != null)
                    IconButton(
                      tooltip: context.t.linkToNote,
                      icon: Icon(Icons.link_rounded, color: _islandPrimary),
                      onPressed: onLinkNote,
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, right: 8),
                      child: Text(
                        context.t.savedAutomatically,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: _islandSecondary),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating editor island, rendered with real liquid glass. A white-tinted
/// glass keeps it light (so the dark controls stay legible) over both the white
/// note background and the dark card background.
class _RefractiveIsland extends StatelessWidget {
  const _RefractiveIsland({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // A soft dark shadow behind the island so it reads as floating.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FrostedGlass(
        borderRadius: 28,
        color: AppPalette.islandGlass,
        blur: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

/// Formatting toolbar bound to whichever text block is focused.
class NoteFormatBar extends StatefulWidget {
  const NoteFormatBar({
    super.key,
    required this.activeController,
    this.onLight = false,
  });

  final ValueNotifier<QuillController?> activeController;

  /// Use dark-on-white colours for the light floating island.
  final bool onLight;

  @override
  State<NoteFormatBar> createState() => _NoteFormatBarState();
}

class _NoteFormatBarState extends State<NoteFormatBar> {
  // Held here so the toolbar keeps its horizontal scroll position when it
  // rebuilds on every format toggle — otherwise it would snap back to the
  // start and hide the indent/align controls each time you tap a button.
  final ScrollController _barScroll = ScrollController();

  @override
  void dispose() {
    _barScroll.dispose();
    super.dispose();
  }

  ValueNotifier<QuillController?> get activeController =>
      widget.activeController;
  bool get onLight => widget.onLight;

  /// The "H" button: turn the selected word(s) into a tappable hyperlink, edit
  /// an existing one, or remove it — like Ctrl+K in a word processor. Needs a
  /// selection (there's nothing to link at a bare caret). The dialog owns its
  /// own text controller ([_LinkDialog]) so it's disposed with the route rather
  /// than mid-exit-animation.
  Future<void> _editLink(BuildContext context, QuillController c) async {
    if (c.selection.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.selectTextToLink)),
      );
      return;
    }
    final existing =
        c.getSelectionStyle().attributes[Attribute.link.key]?.value as String?;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _LinkDialog(initial: existing ?? ''),
    );
    if (result == null) return; // cancelled
    if (result.trim().isEmpty) {
      c.formatSelection(Attribute.clone(Attribute.link, null));
    } else {
      c.formatSelection(LinkAttribute(_normalizeLinkUrl(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = onLight ? _islandPrimary : AppPalette.textPrimary;
    final secondary = onLight ? _islandSecondary : AppPalette.textSecondary;
    final activeFill = AppPalette.selFill;
    final sepColor = onLight
        ? Colors.black.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.15);

    return ValueListenableBuilder<QuillController?>(
      valueListenable: activeController,
      builder: (context, c, _) {
        if (c == null) {
          return SizedBox(
            height: 40,
            child: Center(
              child: Text(
                context.t.tapLineToFormat,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ),
          );
        }
        return ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final attrs = c.getSelectionStyle().attributes;
            final headerVal = attrs[Attribute.header.key]?.value;
            final bold = attrs.containsKey(Attribute.bold.key);
            final italic = attrs.containsKey(Attribute.italic.key);
            final underline = attrs.containsKey(Attribute.underline.key);
            final strike = attrs.containsKey(Attribute.strikeThrough.key);
            final highlight = attrs.containsKey(Attribute.background.key);
            final hasLink = attrs.containsKey(Attribute.link.key);
            final quote = attrs.containsKey(Attribute.blockQuote.key);
            final listVal = attrs[Attribute.list.key]?.value;
            final indentRaw = attrs[Attribute.indent.key]?.value;
            final indentLevel = indentRaw is int ? indentRaw : 0;
            final alignVal = attrs[Attribute.align.key]?.value;

            void toggle(Attribute attr) {
              final on = attrs.containsKey(attr.key);
              c.formatSelection(on ? Attribute.clone(attr, null) : attr);
            }

            void toggleList(Attribute attr) {
              c.formatSelection(listVal == attr.value
                  ? Attribute.clone(Attribute.list, null)
                  : attr);
            }

            // Checkbox lists use the `list` key with a checked/unchecked value.
            void toggleCheck() {
              final isCheck = listVal == 'unchecked' || listVal == 'checked';
              c.formatSelection(isCheck
                  ? Attribute.clone(Attribute.list, null)
                  : Attribute.unchecked);
            }

            // Paragraph indent, stepped through Quill's three levels.
            Attribute indentAttr(int level) => switch (level) {
                  1 => Attribute.indentL1,
                  2 => Attribute.indentL2,
                  _ => Attribute.indentL3,
                };
            void indentMore() {
              if (indentLevel >= 3) return;
              c.formatSelection(indentAttr(indentLevel + 1));
            }
            void indentLess() {
              final next = indentLevel - 1;
              c.formatSelection(next <= 0
                  ? Attribute.clone(Attribute.indent, null)
                  : indentAttr(next));
            }

            void setAlign(Attribute attr) {
              c.formatSelection(alignVal == attr.value
                  ? Attribute.clone(Attribute.align, null)
                  : attr);
            }

            return SingleChildScrollView(
              controller: _barScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _IconToggle(
                      tooltip: context.t.undo,
                      icon: Icons.undo_rounded,
                      active: false,
                      primary: primary,
                      secondary: c.hasUndo
                          ? primary
                          : secondary.withValues(alpha: 0.45),
                      activeFill: activeFill,
                      onTap: () {
                        if (c.hasUndo) c.undo();
                      }),
                  _IconToggle(
                      tooltip: context.t.redo,
                      icon: Icons.redo_rounded,
                      active: false,
                      primary: primary,
                      secondary: c.hasRedo
                          ? primary
                          : secondary.withValues(alpha: 0.45),
                      activeFill: activeFill,
                      onTap: () {
                        if (c.hasRedo) c.redo();
                      }),
                  _vsep(sepColor),
                  // Body / Heading / Sub-heading folded into one dropdown.
                  _StyleDropdown(
                    headerVal: headerVal is int ? headerVal : 0,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onSelect: (level) => c.formatSelection(switch (level) {
                      1 => Attribute.h1,
                      2 => Attribute.h2,
                      _ => Attribute.clone(Attribute.header, null),
                    }),
                  ),
                  _vsep(sepColor),
                  _IconToggle(
                      tooltip: context.t.bold,
                      icon: Icons.format_bold_rounded,
                      active: bold,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.bold)),
                  _IconToggle(
                      tooltip: context.t.italic,
                      icon: Icons.format_italic_rounded,
                      active: italic,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.italic)),
                  _IconToggle(
                      tooltip: context.t.underline,
                      icon: Icons.format_underlined_rounded,
                      active: underline,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.underline)),
                  _IconToggle(
                      tooltip: context.t.strikethrough,
                      icon: Icons.format_strikethrough_rounded,
                      active: strike,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.strikeThrough)),
                  _IconToggle(
                    tooltip: context.t.highlight,
                    icon: Icons.highlight_rounded,
                    active: highlight,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    // Highlight pairs a light background with a fixed dark ink
                    // so the text stays readable on it in dark theme too (where
                    // the default body ink is light). Clearing drops both.
                    onTap: () {
                      if (highlight) {
                        c.formatSelection(
                            Attribute.clone(Attribute.background, null));
                        c.formatSelection(
                            Attribute.clone(Attribute.color, null));
                      } else {
                        c.formatSelection(
                            Attribute.clone(Attribute.background, kHighlightBg));
                        c.formatSelection(
                            Attribute.clone(Attribute.color, kHighlightInk));
                      }
                    },
                  ),
                  // Hyperlink: select word(s), tap "H", enter a URL — Word-style.
                  _TextToggle(
                    label: 'H',
                    tooltip: context.t.hyperlink,
                    active: hasLink,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => _editLink(context, c),
                  ),
                  _vsep(sepColor),
                  _IconToggle(
                      tooltip: context.t.bulletList,
                      icon: Icons.format_list_bulleted_rounded,
                      active: listVal == 'bullet',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggleList(Attribute.ul)),
                  _IconToggle(
                      tooltip: context.t.numberedList,
                      icon: Icons.format_list_numbered_rounded,
                      active: listVal == 'ordered',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggleList(Attribute.ol)),
                  _IconToggle(
                      tooltip: context.t.checklist,
                      icon: Icons.checklist_rounded,
                      active: listVal == 'unchecked' || listVal == 'checked',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: toggleCheck),
                  _IconToggle(
                      tooltip: context.t.quote,
                      icon: Icons.format_quote_rounded,
                      active: quote,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.blockQuote)),
                  _vsep(sepColor),
                  _IconToggle(
                      tooltip: context.t.indentDecrease,
                      icon: Icons.format_indent_decrease_rounded,
                      active: false,
                      primary: primary,
                      secondary: indentLevel > 0
                          ? primary
                          : secondary.withValues(alpha: 0.45),
                      activeFill: activeFill,
                      onTap: indentLess),
                  _IconToggle(
                      tooltip: context.t.indentIncrease,
                      icon: Icons.format_indent_increase_rounded,
                      active: false,
                      primary: primary,
                      secondary: indentLevel < 3
                          ? primary
                          : secondary.withValues(alpha: 0.45),
                      activeFill: activeFill,
                      onTap: indentMore),
                  _vsep(sepColor),
                  _IconToggle(
                      tooltip: context.t.alignLeft,
                      icon: Icons.format_align_left_rounded,
                      active: alignVal == null || alignVal == 'left',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => setAlign(Attribute.leftAlignment)),
                  _IconToggle(
                      tooltip: context.t.alignCenter,
                      icon: Icons.format_align_center_rounded,
                      active: alignVal == 'center',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => setAlign(Attribute.centerAlignment)),
                  _IconToggle(
                      tooltip: context.t.alignRight,
                      icon: Icons.format_align_right_rounded,
                      active: alignVal == 'right',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => setAlign(Attribute.rightAlignment)),
                  _IconToggle(
                      tooltip: context.t.justify,
                      icon: Icons.format_align_justify_rounded,
                      active: alignVal == 'justify',
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => setAlign(Attribute.justifyAlignment)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _vsep(Color color) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: color,
      );
}

/// Body / Heading / Sub-heading folded into one dropdown. [headerVal] is 0
/// (body), 1 (heading) or 2 (sub-heading); [onSelect] passes the chosen level.
class _StyleDropdown extends StatelessWidget {
  const _StyleDropdown({
    required this.headerVal,
    required this.onSelect,
    required this.primary,
    required this.secondary,
    required this.activeFill,
  });
  final int headerVal;
  final void Function(int level) onSelect;
  final Color primary;
  final Color secondary;
  final Color activeFill;

  @override
  Widget build(BuildContext context) {
    final active = headerVal == 1 || headerVal == 2;
    final label = headerVal == 1
        ? context.t.heading
        : headerVal == 2
            ? context.t.subHeading
            : context.t.body;
    return PopupMenuButton<int>(
      tooltip: context.t.textStyle,
      onSelected: onSelect,
      color: AppPalette.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 0,
            child: Text(context.t.body,
                style: TextStyle(color: AppPalette.inkPrimary))),
        PopupMenuItem(
            value: 1,
            child: Text(context.t.heading,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.inkPrimary))),
        PopupMenuItem(
            value: 2,
            child: Text(context.t.subHeading,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: active ? activeFill : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? primary : secondary,
                  )),
              Icon(Icons.arrow_drop_down_rounded,
                  size: 20, color: active ? primary : secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.primary,
    required this.secondary,
    required this.activeFill,
    this.tooltip,
  });
  final String? tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color primary;
  final Color secondary;
  final Color activeFill;

  @override
  Widget build(BuildContext context) {
    Widget w = Material(
      color: active ? activeFill : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: active ? primary : secondary),
        ),
      ),
    );
    if (tooltip != null) {
      w = Tooltip(
        message: tooltip!,
        child: Semantics(
            button: true, selected: active, label: tooltip, child: w),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: w,
    );
  }
}

/// The "Add/Edit link" dialog for the "H" button. A StatefulWidget so it owns
/// its [TextEditingController] and disposes it with the route (disposing one
/// straight after `await showDialog` can crash while the dialog animates out).
/// Pops null (cancelled), '' (remove the link), or the entered URL.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial});
  final String initial;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = widget.initial.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: AppPalette.sheet,
      title: Text(hasExisting ? context.t.editLink : context.t.addLink,
          style: TextStyle(color: AppPalette.inkPrimary)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        style: TextStyle(color: AppPalette.inkPrimary),
        decoration: InputDecoration(
          hintText: context.t.linkUrlHint,
          hintStyle: TextStyle(color: AppPalette.inkSecondary),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (hasExisting)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(context.t.removeLink,
                style: const TextStyle(color: Color(0xFFE0567B))),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t.cancel,
              style: TextStyle(color: AppPalette.inkSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(context.t.save,
              style: TextStyle(color: AppPalette.scheme.primary)),
        ),
      ],
    );
  }
}

/// A toolbar toggle that shows a letter instead of an icon (the "H" hyperlink
/// button). Matches [_IconToggle]'s sizing and active/inactive styling.
class _TextToggle extends StatelessWidget {
  const _TextToggle({
    required this.label,
    required this.active,
    required this.onTap,
    required this.primary,
    required this.secondary,
    required this.activeFill,
    this.tooltip,
  });
  final String label;
  final String? tooltip;
  final bool active;
  final VoidCallback onTap;
  final Color primary;
  final Color secondary;
  final Color activeFill;

  @override
  Widget build(BuildContext context) {
    Widget w = Material(
      color: active ? activeFill : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: active ? primary : secondary,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      w = Tooltip(
        message: tooltip!,
        child: Semantics(
            button: true, selected: active, label: tooltip, child: w),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: w,
    );
  }
}
