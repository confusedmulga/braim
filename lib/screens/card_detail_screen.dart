import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart' show richToPlain;

import '../models/tweet_card.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/glass_bubble.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_body_editor.dart';

/// Opens a saved card/tweet/link as a note: the fetched preview and the link
/// (with copy) are pinned at the top, with an editable note body below.
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card});

  final TweetCard card;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  late TweetCard _card;
  late TextEditingController _titleCtrl;
  final _editorKey = GlobalKey<NoteBodyEditorState>();
  final _activeController = ValueNotifier<QuillController?>(null);

  // Heavy children (Quill, edge blurs, bottom island) mount only after the
  // open morph settles; a static body is shown during the transition.
  bool _settled = false;
  bool _settleHooked = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _titleCtrl = TextEditingController(text: _card.noteTitle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settleHooked) return;
    _settleHooked = true;
    final animation = ModalRoute.of(context)?.animation;
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

  void _collect() {
    _card.noteTitle = _titleCtrl.text;
    _editorKey.currentState?.sync();
  }

  void _close() {
    final state = context.read<AppState>();
    _collect();
    setState(() => _closing = true);
    Navigator.of(context).pop();
    // Persist after the close animation so the write can't jank it.
    Future.delayed(const Duration(milliseconds: 380), () {
      state.updateCard(_card);
    });
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(_card.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.couldNotOpenLink)),
        );
      }
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _card.url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t.linkCopied)),
    );
  }

  Future<void> _pickSpace() async {
    final selected =
        await showMoveToSpaceSheet(context, currentSpaceId: _card.spaceId);
    if (selected == null) return;
    setState(() => _card.spaceId = selected == '__none__' ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ColoredBox(
        color: AppPalette.sheet,
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
                tooltip: context.t.refreshPreview,
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context.read<AppState>().refreshCard(_card.id),
              ),
              IconButton(
                tooltip: context.t.deleteCard,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  final state = context.read<AppState>();
                  setState(() => _closing = true);
                  Navigator.of(context).pop();
                  Future.delayed(const Duration(milliseconds: 380), () {
                    state.deleteCard(_card.id);
                  });
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: EdgeInsets.fromLTRB(18, topInset + 6, 18, 200),
                children: [
                  _CardPreview(card: _card),
                  const SizedBox(height: 10),
                  _LinkBar(
                      url: _card.url, onOpen: _openLink, onCopy: _copyLink),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleCtrl,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary,
                    ),
                    maxLines: null,
                    // Grows with text; keeps the title from rubber-banding
                    // independently under the bouncy scroll physics.
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    decoration: InputDecoration(
                      hintText: context.t.addATitle,
                      hintStyle: TextStyle(
                        color: AppPalette.inkSecondary.withValues(alpha: 0.6),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_settled)
                    NoteBodyEditor(
                      key: _editorKey,
                      blocks: _card.blocks,
                      activeController: _activeController,
                      onLight: true,
                      onRemoveImagePath: (path) => context
                          .read<AppState>()
                          .refreshAfterImageRemoval(path),
                    )
                  else
                    // Static lookalike of the body during the open morph.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final b in _card.blocks)
                          if (b.isText && richToPlain(b.text).isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                richToPlain(b.text),
                                style: TextStyle(
                                  fontSize: 16.5,
                                  height: 1.4,
                                  color: AppPalette.inkPrimary,
                                ),
                              ),
                            ),
                      ],
                    ),
                ],
              ),
              if (_settled && !_closing) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Fewer blur bands: each one is a live BackdropFilter that
                  // resamples the content on every scroll frame.
                  child: ProgressiveBlur(
                      height: topInset + 10, fromTop: true, bands: 4),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  // The island covers most of this zone; a shorter, coarser
                  // fade reads the same and filters far fewer pixels.
                  child:
                      ProgressiveBlur(height: 130, fromTop: false, bands: 4),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: EditorBottomBar(
                    activeController: _activeController,
                    onAddPhotos: () => _editorKey.currentState?.addPhotos(),
                    onPickSpace: _pickSpace,
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

/// Read-only preview of the fetched tweet/link.
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.card});
  final TweetCard card;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      // The sheet behind is opaque: a backdrop blur here is invisible and
      // costs a full compositing layer during the open/close morph.
      blur: 0,
      color: Colors.black.withValues(alpha: 0.05),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _avatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.authorName.isNotEmpty
                          ? card.authorName
                          : (card.siteName.isNotEmpty
                              ? card.siteName
                              : context.t.linkFallback),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    if (card.authorHandle.isNotEmpty)
                      Text(card.authorHandle,
                          style: TextStyle(
                              fontSize: 12, color: AppPalette.inkSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (card.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              card.text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.4,
                color: AppPalette.inkPrimary,
              ),
            ),
          ],
          if (card.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                card.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                // Matches the feed tiles' cacheWidth, so this is a cache hit
                // (no fresh full-res decode mid-morph).
                cacheWidth: 900,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar() {
    const size = 38.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.07),
      ),
      child: Icon(
        card.isTweet ? Icons.alternate_email_rounded : Icons.link_rounded,
        size: 18,
        color: AppPalette.inkSecondary,
      ),
    );
    if (card.avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        card.avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 120,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        },
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// The source link with open and copy buttons.
class _LinkBar extends StatelessWidget {
  const _LinkBar(
      {required this.url, required this.onOpen, required this.onCopy});
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 16,
      blur: 0,
      color: Colors.black.withValues(alpha: 0.05),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          Icon(Icons.link_rounded,
              size: 18, color: AppPalette.inkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, color: AppPalette.inkSecondary),
            ),
          ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(context.t.open),
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.inkPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(context.t.copy),
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.inkPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }
}
