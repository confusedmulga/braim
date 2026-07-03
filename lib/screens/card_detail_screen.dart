import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

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

  // Defer the expensive edge blurs until the open morph has settled.
  bool _showEdgeBlur = false;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _titleCtrl = TextEditingController(text: _card.noteTitle);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _showEdgeBlur = true);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _activeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _card.noteTitle = _titleCtrl.text;
    _editorKey.currentState?.sync();
    await context.read<AppState>().updateCard(_card);
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _card.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied')),
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
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        await _save();
        if (mounted) nav.pop();
      },
      child: FrostedWhiteBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: AppPalette.inkPrimary,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: GlassBubble(
                icon: Icons.chevron_left_rounded,
                iconColor: AppPalette.inkPrimary,
                glassColor: const Color(0x14000000),
                iconSize: 28,
                shadow: false,
                onTap: () async {
                  final nav = Navigator.of(context);
                  await _save();
                  if (mounted) nav.pop();
                },
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh preview',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context.read<AppState>().refreshCard(_card.id),
              ),
              IconButton(
                tooltip: 'Delete card',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await context.read<AppState>().deleteCard(_card.id);
                  if (mounted) nav.pop();
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
                  _LinkBar(url: _card.url, onCopy: _copyLink),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleCtrl,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.inkPrimary,
                    ),
                    maxLines: null,
                    // Grows with text; keeps the title from rubber-banding
                    // independently under the bouncy scroll physics.
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    decoration: InputDecoration(
                      hintText: 'Add a title',
                      hintStyle: TextStyle(
                        color: AppPalette.inkSecondary.withValues(alpha: 0.6),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  NoteBodyEditor(
                    key: _editorKey,
                    blocks: _card.blocks,
                    activeController: _activeController,
                    onLight: true,
                    onRemoveImagePath: (path) =>
                        context.read<AppState>().refreshAfterImageRemoval(path),
                  ),
                ],
              ),
              if (_showEdgeBlur) ...[
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
              ],
              Align(
                alignment: Alignment.bottomCenter,
                child: EditorBottomBar(
                  activeController: _activeController,
                  onAddPhotos: () => _editorKey.currentState?.addPhotos(),
                  onPickSpace: _pickSpace,
                ),
              ),
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
                          : (card.siteName.isNotEmpty ? card.siteName : 'Link'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary,
                      ),
                    ),
                    if (card.authorHandle.isNotEmpty)
                      Text(card.authorHandle,
                          style: const TextStyle(
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
              style: const TextStyle(
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

/// The source link with a copy button.
class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.url, required this.onCopy});
  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 16,
      color: Colors.black.withValues(alpha: 0.05),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const Icon(Icons.link_rounded,
              size: 18, color: AppPalette.inkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppPalette.inkSecondary),
            ),
          ),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
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
