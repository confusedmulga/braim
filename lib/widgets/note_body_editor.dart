import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/note_block.dart';
import '../services/image_service.dart';
import '../services/link_preview_service.dart';
import '../theme/app_theme.dart';

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
  });

  final List<NoteBlock> blocks;
  final ValueNotifier<QuillController?> activeController;
  final void Function(String path)? onRemoveImagePath;

  /// Use black text for light (white) backgrounds.
  final bool onLight;

  @override
  State<NoteBodyEditor> createState() => NoteBodyEditorState();
}

class NoteBodyEditorState extends State<NoteBodyEditor> {
  final Map<String, QuillController> _quillCtrls = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, ScrollController> _scrollCtrls = {};
  final Map<String, StreamSubscription> _docSubs = {};
  final Set<String> _fetchingLinks = {};
  Timer? _linkScanTimer;

  /// A line that is nothing but a URL, as left behind by a paste.
  /// Case-insensitive: keyboards auto-capitalize a typed "Https://…".
  static final _urlLine = RegExp(r'^https?://\S+$', caseSensitive: false);

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
    _linkScanTimer?.cancel();
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

  QuillController _controllerFor(NoteBlock b) {
    Document doc;
    final raw = b.text.trim();
    if (raw.startsWith('[')) {
      try {
        doc = Document.fromJson(jsonDecode(raw) as List);
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
    final paths = await ImageService.pickMultiple();
    if (paths.isEmpty) return;
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
    setState(() {
      _blocks.removeWhere((b) => b.id == block.id);
      if (_blocks.isEmpty) {
        final b = NoteBlock(type: NoteBlockType.text);
        _blocks.add(b);
        _ensure(b);
      }
    });
    widget.onRemoveImagePath?.call(block.imagePath);
  }

  // ---- Pasted-link cards ---------------------------------------------------

  void _scheduleLinkScan(String blockId, {required bool allowCursorLine}) {
    _linkScanTimer?.cancel();
    _linkScanTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _scanForPastedLink(blockId, allowCursorLine: allowCursorLine);
      }
    });
  }

  /// Finds a line that is exactly a URL and turns it into a link block,
  /// splitting the text block around it. Unless [allowCursorLine] (paste),
  /// the line the cursor is on is left alone so a URL mid-typing survives.
  void _scanForPastedLink(String blockId, {required bool allowCursorLine}) {
    final idx = _blocks.indexWhere((b) => b.id == blockId);
    final c = _quillCtrls[blockId];
    if (idx < 0 || c == null) return;
    final plain = c.document.toPlainText();
    final cursor = c.selection.baseOffset;
    var lineStart = 0;
    for (final line in plain.split('\n')) {
      final lineEnd = lineStart + line.length;
      final url = line.trim();
      final cursorHere = cursor >= lineStart && cursor <= lineEnd;
      if (url.length > 11 &&
          _urlLine.hasMatch(url) &&
          (allowCursorLine || !cursorHere)) {
        _convertUrlLine(idx, _blocks[idx], c, lineStart, line.length, url);
        return;
      }
      lineStart = lineEnd + 1;
    }
  }

  void _convertUrlLine(int idx, NoteBlock block, QuillController c, int start,
      int lineLen, String url) {
    final full = c.document.toDelta();
    final docLen = c.document.length;
    final before = start > 0 ? full.slice(0, start) : Delta();
    final afterStart = start + lineLen + 1;
    final after = afterStart < docLen ? full.slice(afterStart) : Delta();

    final linkBlock = NoteBlock(type: NoteBlockType.link, url: url);
    setState(() {
      block.text = jsonEncode(_normalized(before).toJson());
      _disposeBlockEditors(block.id);
      _ensure(block);

      _blocks.insert(idx + 1, linkBlock);
      if (_hasContent(after)) {
        final tail = NoteBlock(
            type: NoteBlockType.text,
            text: jsonEncode(_normalized(after).toJson()));
        _blocks.insert(idx + 2, tail);
        _ensure(tail);
      }
      _ensureTrailingText();
    });
    _fetchLinkPreview(linkBlock);
  }

  /// Quill documents must end with a newline insert.
  Delta _normalized(Delta d) {
    final ops = d.toList();
    if (ops.isEmpty) return Delta()..insert('\n');
    final last = ops.last.data;
    if (last is String && last.endsWith('\n')) return d;
    return d..insert('\n');
  }

  bool _hasContent(Delta d) {
    for (final op in d.toList()) {
      final data = op.data;
      if (data is String) {
        if (data.replaceAll('\n', '').trim().isNotEmpty) return true;
      } else if (data != null) {
        return true;
      }
    }
    return false;
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
          customStyles: _quillStyles(widget.onLight),
        ),
      ),
    );
  }
}

/// Text styles for the editor, with distinct heading sizes. [onLight] switches
/// to black text for white backgrounds.
DefaultStyles _quillStyles(bool onLight) {
  final text = onLight ? AppPalette.inkPrimary : AppPalette.textPrimary;
  final placeholder = onLight
      ? AppPalette.inkSecondary.withValues(alpha: 0.7)
      : AppPalette.textSecondary.withValues(alpha: 0.7);
  // Quill paints spans directly (no DefaultTextStyle inheritance), so the
  // family must be spelled out here or the editor falls back to Roboto.
  TextStyle base(double size, FontWeight w) => TextStyle(
      fontSize: size,
      height: 1.4,
      color: text,
      fontWeight: w,
      fontFamily: 'SpaceGrotesk');
  const hs = HorizontalSpacing(0, 0);
  const vs = VerticalSpacing(6, 0);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
        base(16.5, FontWeight.w400), hs, vs, const VerticalSpacing(0, 0), null),
    // Without these, list lines and their bullets/numbers fall back to the
    // theme's (white) text style and vanish on the white sheet.
    lists: DefaultListBlockStyle(
      base(16.5, FontWeight.w400),
      hs,
      vs,
      const VerticalSpacing(0, 6),
      null,
      null,
    ),
    leading: DefaultTextBlockStyle(
      base(16.5, FontWeight.w400),
      hs,
      const VerticalSpacing(0, 0),
      const VerticalSpacing(0, 0),
      null,
    ),
    h1: DefaultTextBlockStyle(base(26, FontWeight.w800), hs,
        const VerticalSpacing(10, 0), const VerticalSpacing(0, 0), null),
    h2: DefaultTextBlockStyle(base(21, FontWeight.w700), hs,
        const VerticalSpacing(8, 0), const VerticalSpacing(0, 0), null),
    placeHolder: DefaultTextBlockStyle(
      TextStyle(
          fontSize: 16.5,
          height: 1.4,
          color: placeholder,
          fontFamily: 'SpaceGrotesk'),
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
    this.onPickTheme,
    this.onPickColor,
  });

  final ValueNotifier<QuillController?> activeController;
  final VoidCallback onAddPhotos;

  /// Move-to-cortex; hidden when null (journal entries don't join folders).
  final VoidCallback? onPickSpace;
  final VoidCallback? onPickColor;

  /// When provided (note editor only), shows a button to change the note's
  /// background between the add-photos and move-to-cortex buttons.
  final VoidCallback? onPickTheme;

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
                  if (onPickColor != null)
                    IconButton(
                      tooltip: context.t.noteColor,
                      icon: Icon(Icons.palette_outlined,
                          color: _islandPrimary),
                      onPressed: onPickColor,
                    ),
                  if (onPickTheme != null)
                    IconButton(
                      tooltip: context.t.background,
                      icon: Icon(Icons.wallpaper_rounded,
                          color: _islandPrimary),
                      onPressed: onPickTheme,
                    ),
                  if (onPickSpace != null)
                    IconButton(
                      tooltip: context.t.tabCortex,
                      icon: Icon(Icons.folder_outlined,
                          color: _islandPrimary),
                      onPressed: onPickSpace,
                    ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      context.t.savedAutomatically,
                      style: TextStyle(fontSize: 12, color: _islandSecondary),
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
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 28),
        settings: LiquidGlassSettings(
          glassColor: AppPalette.islandGlass,
          blur: 14,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

/// Formatting toolbar bound to whichever text block is focused.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({
    super.key,
    required this.activeController,
    this.onLight = false,
  });

  final ValueNotifier<QuillController?> activeController;

  /// Use dark-on-white colours for the light floating island.
  final bool onLight;

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
            final highlight = attrs.containsKey(Attribute.background.key);
            final listVal = attrs[Attribute.list.key]?.value;

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

            return SingleChildScrollView(
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
                  _TextChip(
                    label: context.t.heading,
                    active: headerVal == 1,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(headerVal == 1
                        ? Attribute.clone(Attribute.header, null)
                        : Attribute.h1),
                  ),
                  _TextChip(
                    label: context.t.subHeading,
                    active: headerVal == 2,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(headerVal == 2
                        ? Attribute.clone(Attribute.header, null)
                        : Attribute.h2),
                  ),
                  _TextChip(
                    label: context.t.body,
                    active: headerVal == null,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () =>
                        c.formatSelection(Attribute.clone(Attribute.header, null)),
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
                    tooltip: context.t.highlight,
                    icon: Icons.highlight_rounded,
                    active: highlight,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(highlight
                        ? Attribute.clone(Attribute.background, null)
                        : Attribute.clone(Attribute.background, '#FFE082')),
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

class _TextChip extends StatelessWidget {
  const _TextChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.primary,
    required this.secondary,
    required this.activeFill,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color primary;
  final Color secondary;
  final Color activeFill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? activeFill : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? primary : secondary,
              ),
            ),
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
