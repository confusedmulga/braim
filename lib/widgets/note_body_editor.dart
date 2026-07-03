import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/note_block.dart';
import '../services/image_service.dart';
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
    _quillCtrls.putIfAbsent(b.id, () => _controllerFor(b));
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
    if (_blocks.isEmpty || _blocks.last.isImage) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final block in _blocks) _buildBlock(block)],
    );
  }

  Widget _buildBlock(NoteBlock block) {
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
          placeholder: 'Write something…',
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
  TextStyle base(double size, FontWeight w) =>
      TextStyle(fontSize: size, height: 1.4, color: text, fontWeight: w);
  const hs = HorizontalSpacing(0, 0);
  const vs = VerticalSpacing(6, 0);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
        base(16.5, FontWeight.w400), hs, vs, const VerticalSpacing(0, 0), null),
    h1: DefaultTextBlockStyle(base(26, FontWeight.w800), hs,
        const VerticalSpacing(10, 0), const VerticalSpacing(0, 0), null),
    h2: DefaultTextBlockStyle(base(21, FontWeight.w700), hs,
        const VerticalSpacing(8, 0), const VerticalSpacing(0, 0), null),
    placeHolder: DefaultTextBlockStyle(
      TextStyle(fontSize: 16.5, height: 1.4, color: placeholder),
      hs,
      vs,
      const VerticalSpacing(0, 0),
      null,
    ),
  );
}

/// On-light colours for the white floating island.
const _islandPrimary = Color(0xFF202126);
const _islandSecondary = Color(0xFF6B6C77);

/// The standalone floating editor island: a white, frosted, faintly refractive
/// panel holding the format controls, add-photos and move-to-cortex actions.
class EditorBottomBar extends StatelessWidget {
  const EditorBottomBar({
    super.key,
    required this.activeController,
    required this.onAddPhotos,
    required this.onPickSpace,
    this.onPickTheme,
  });

  final ValueNotifier<QuillController?> activeController;
  final VoidCallback onAddPhotos;
  final VoidCallback onPickSpace;

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
                    tooltip: 'Add photos',
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        color: _islandPrimary),
                    onPressed: onAddPhotos,
                  ),
                  if (onPickTheme != null)
                    IconButton(
                      tooltip: 'Background',
                      icon: const Icon(Icons.wallpaper_rounded,
                          color: _islandPrimary),
                      onPressed: onPickTheme,
                    ),
                  IconButton(
                    tooltip: 'Cortex',
                    icon: const Icon(Icons.folder_outlined,
                        color: _islandPrimary),
                    onPressed: onPickSpace,
                  ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                      'Saved automatically',
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
        settings: const LiquidGlassSettings(
          glassColor: Color(0xCCFFFFFF),
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
    final activeFill = onLight
        ? Colors.black.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.20);
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
                'Tap a line to format text',
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

            void toggle(Attribute attr) {
              final on = attrs.containsKey(attr.key);
              c.formatSelection(on ? Attribute.clone(attr, null) : attr);
            }

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TextChip(
                    label: 'Heading',
                    active: headerVal == 1,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(headerVal == 1
                        ? Attribute.clone(Attribute.header, null)
                        : Attribute.h1),
                  ),
                  _TextChip(
                    label: 'Sub',
                    active: headerVal == 2,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(headerVal == 2
                        ? Attribute.clone(Attribute.header, null)
                        : Attribute.h2),
                  ),
                  _TextChip(
                    label: 'Body',
                    active: headerVal == null,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () =>
                        c.formatSelection(Attribute.clone(Attribute.header, null)),
                  ),
                  _vsep(sepColor),
                  _IconToggle(
                      icon: Icons.format_bold_rounded,
                      active: bold,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.bold)),
                  _IconToggle(
                      icon: Icons.format_italic_rounded,
                      active: italic,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.italic)),
                  _IconToggle(
                      icon: Icons.format_underlined_rounded,
                      active: underline,
                      primary: primary,
                      secondary: secondary,
                      activeFill: activeFill,
                      onTap: () => toggle(Attribute.underline)),
                  _IconToggle(
                    icon: Icons.highlight_rounded,
                    active: highlight,
                    primary: primary,
                    secondary: secondary,
                    activeFill: activeFill,
                    onTap: () => c.formatSelection(highlight
                        ? Attribute.clone(Attribute.background, null)
                        : Attribute.clone(Attribute.background, '#FFE082')),
                  ),
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
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color primary;
  final Color secondary;
  final Color activeFill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
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
      ),
    );
  }
}
