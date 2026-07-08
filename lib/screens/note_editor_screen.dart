import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_bubble.dart';
import '../widgets/glass_morph.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_background.dart';
import '../widgets/note_body_editor.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.isNew,
  });

  final Note note;
  final bool isNew;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late Note _note;
  late TextEditingController _titleCtrl;
  final _editorKey = GlobalKey<NoteBodyEditorState>();
  final _activeController = ValueNotifier<QuillController?>(null);

  /// True once the open animation has finished. Heavy children (Quill editors,
  /// backdrop blurs, the bottom island) mount only then, so the opening stays
  /// smooth; a static lookalike body is shown during the transition.
  bool _settled = false;
  bool _settleHooked = false;

  /// True while collapsing back into the feed: the frosted backdrop blur is
  /// dropped for the collapse so the shrinking glass stays perfectly paced.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleCtrl = TextEditingController(text: _note.title);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settleHooked) return;
    _settleHooked = true;
    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (animation == null || animation.isCompleted) {
      _settled = true;
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(onStatus);
        if (mounted) setState(() => _settled = true);
      }
    }

    animation.addStatusListener(onStatus);
    // Fallback in case the route animation never reports completion.
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted && !_settled) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _activeController.dispose();
    super.dispose();
  }

  /// Writes the live editors back into [_note] (cheap, synchronous).
  void _collect() {
    _note.title = _titleCtrl.text;
    _editorKey.currentState?.sync();
  }

  /// Persists after the close animation so the JSON encode + file write + feed
  /// rebuild don't jank the pop transition.
  void _persistLater(AppState state, {bool delete = false}) {
    Future.delayed(const Duration(milliseconds: 380), () async {
      if (delete) {
        await state.deleteNote(_note.id);
        return;
      }
      if (_note.isEmpty) {
        if (!widget.isNew) await state.deleteNote(_note.id);
        return;
      }
      await state.upsertNote(_note);
    });
  }

  void _close() {
    final state = context.read<AppState>();
    _collect();
    // A brand-new note that has content doesn't belong back in the + button
    // it morphed out of — slide the sheet down instead so it doesn't read
    // as the note being discarded.
    if (widget.isNew && !_note.isEmpty) GlassMorph.slideCloseOf(context);
    setState(() => _closing = true);
    Navigator.of(context).pop();
    _persistLater(state);
  }

  /// Copies the whole note (title + text) to the clipboard for sharing.
  void _copyNote() {
    _collect();
    final buffer = StringBuffer();
    if (_note.title.trim().isNotEmpty) buffer.writeln(_note.title.trim());
    final body = _note.textPreview;
    if (body.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(body);
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.noteCopied)),
    );
  }

  Future<void> _pickSpace() async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: _note.spaceId);
    if (selected == null) return;
    setState(() => _note.spaceId = selected == '__none__' ? null : selected);
  }

  Future<void> _pickTheme() async {
    final selected = await showNoteBackgroundPicker(
      context,
      current: _note.backgroundAsset,
    );
    if (selected == null) return;
    setState(() =>
        _note.backgroundAsset = selected == '__none__' ? null : selected);
  }

  Future<void> _pickColor() async {
    final selected =
        await showNoteColorPicker(context, current: _note.colorValue);
    if (selected == null) return; // dismissed
    setState(() =>
        _note.colorValue = selected == NoteColors.none ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final space = state.spaceById(_note.spaceId);
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final routeAnim =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: NoteBackground(
        asset: _note.backgroundAsset,
        color: NoteColors.resolve(_note.colorValue),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: AppPalette.inkPrimary,
            // Status-bar clock/battery must stay readable over the sheet:
            // dark icons on the light sheet, light icons on the dark one.
            systemOverlayStyle: (AppPalette.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: GlassBubble(
                icon: Icons.chevron_left_rounded,
                tooltip: context.t.back,
                iconColor: AppPalette.inkPrimary,
                glassColor: const Color(0x14000000),
                iconSize: 28,
                shadow: false,
                onTap: _close,
              ),
            ),
            actions: [
              IconButton(
                tooltip: context.t.copyNote,
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: _copyNote,
              ),
              if (!widget.isNew)
                IconButton(
                  tooltip: _note.archived ? context.t.unarchive : context.t.archive,
                  icon: Icon(_note.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined),
                  onPressed: () {
                    _note.archived = !_note.archived;
                    _close();
                  },
                ),
              if (!widget.isNew)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    final state = context.read<AppState>();
                    setState(() => _closing = true);
                    Navigator.of(context).pop();
                    _persistLater(state, delete: true);
                  },
                ),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: EdgeInsets.fromLTRB(18, topInset + 6, 18, 200),
                children: [
                  if (space != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_rounded,
                                  size: 13, color: AppPalette.inkSecondary),
                              const SizedBox(width: 6),
                              Text(space.name,
                                  style: TextStyle(
                                      color: AppPalette.inkSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _Entrance(
                    animation: routeAnim,
                    interval: const Interval(0.30, 0.72, curve: Curves.easeOut),
                    blur: true,
                    child: TextField(
                      controller: _titleCtrl,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.inkPrimary,
                      ),
                      maxLines: null,
                      // The field grows with its text; without this, the
                      // app-wide bouncy physics let the title rubber-band
                      // on its own instead of scrolling with the note.
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      decoration: InputDecoration(
                        hintText: context.t.title,
                        hintStyle: TextStyle(
                          color:
                              AppPalette.inkSecondary.withValues(alpha: 0.6),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Entrance(
                    animation: routeAnim,
                    interval: const Interval(0.42, 0.92, curve: Curves.easeOut),
                    child: _settled
                        ? NoteBodyEditor(
                            key: _editorKey,
                            blocks: _note.blocks,
                            activeController: _activeController,
                            onLight: true,
                            onRemoveImagePath: (path) => context
                                .read<AppState>()
                                .refreshAfterImageRemoval(path),
                          )
                        : _StaticBody(note: _note),
                  ),
                ],
              ),
              if (_settled && !_closing) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ProgressiveBlur(height: topInset + 10, fromTop: true),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ProgressiveBlur(height: 170, fromTop: false),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: EditorBottomBar(
                    activeController: _activeController,
                    onAddPhotos: () => _editorKey.currentState?.addPhotos(),
                    onPickSpace: _pickSpace,
                    onPickTheme: _pickTheme,
                    onPickColor: _pickColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Staged content reveal driven by the route animation: the child drifts up a
/// few pixels while fading in; [blur] additionally sharpens it from a subtle
/// blur (used for the title). Renders the bare child once the route settles,
/// so there is zero steady-state cost.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.interval,
    required this.child,
    this.blur = false,
  });

  final Animation<double> animation;
  final Interval interval;
  final Widget child;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        if (animation.isCompleted) return child;
        final v = interval.transform(animation.value.clamp(0.0, 1.0));
        Widget w = Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - v)),
            child: child,
          ),
        );
        if (blur && v < 0.999) {
          final sigma = 2.2 * (1 - v);
          w = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: w,
          );
        }
        return w;
      },
    );
  }
}

/// A cheap, static lookalike of the note body shown while the open animation
/// runs — mirrors the editor's text style and image layout so the swap to the
/// real Quill editors is invisible.
class _StaticBody extends StatelessWidget {
  const _StaticBody({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final b in note.blocks) {
      if (b.isImage && b.imagePath.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(b.imagePath),
                fit: BoxFit.cover, width: double.infinity, cacheWidth: 1440),
          ),
        ));
      } else if (b.isText) {
        final plain = richToPlain(b.text);
        if (plain.isEmpty) continue;
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            plain,
            style: TextStyle(
              fontSize: 16.5,
              height: 1.4,
              color: AppPalette.inkPrimary,
            ),
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
