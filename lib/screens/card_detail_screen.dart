import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart' show richToPlain;

import '../models/tweet_card.dart';
import '../services/wiki_links.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_route.dart';
import '../widgets/bubble_button.dart';
import '../widgets/expand_from_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_bubble.dart';
import '../widgets/move_to_space_sheet.dart';
import '../widgets/note_body_editor.dart';
import '../widgets/note_links_section.dart';
import 'note_editor_screen.dart';

/// Opens a saved card/tweet/link as a note: the fetched preview and the link
/// (with copy) are pinned at the top, with an editable note body below.
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.card});

  final TweetCard card;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  late TweetCard _card;
  late TextEditingController _titleCtrl;
  final _titleFocus = FocusNode();
  final _editorKey = GlobalKey<NoteBodyEditorState>();

  /// Moves the caret up into the title (Backspace on an empty first body line).
  void _focusTitle() {
    _titleFocus.requestFocus();
    _titleCtrl.selection =
        TextSelection.collapsed(offset: _titleCtrl.text.length);
  }
  final _activeController = ValueNotifier<QuillController?>(null);

  // Heavy children (Quill, edge blurs, bottom island) mount only after the
  // open morph settles; a static body is shown during the transition.
  bool _settled = false;
  bool _settleHooked = false;
  bool _closing = false;

  /// Live save while writing (see the note editor's autosave).
  Timer? _autosave;
  String _savedFingerprint = '';

  String _fingerprint() => jsonEncode([
        _card.noteTitle,
        _card.spaceId,
        for (final b in _card.blocks) b.toJson(),
      ]);

  /// A card opens as something to read; the compose button starts the note
  /// attached to it, growing the editor out of itself.
  bool _editing = false;
  bool get _readOnly => !_editing;

  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  void _startEditing() {
    setState(() => _editing = true);
    _expand.forward(from: 0);
  }

  void _finishEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    _collect();
    final state = context.read<AppState>();
    setState(() => _editing = false);
    _savedFingerprint = _fingerprint();
    state.updateCard(_card);
  }

  void _autosaveTick() {
    if (_closing || _readOnly || !mounted) return;
    _collect();
    final fp = _fingerprint();
    if (fp == _savedFingerprint) return;
    _savedFingerprint = fp;
    context.read<AppState>().updateCard(_card);
  }

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _titleCtrl = TextEditingController(text: _card.noteTitle);
    _savedFingerprint = _fingerprint();
    _autosave = Timer.periodic(
        const Duration(seconds: 3), (_) => _autosaveTick());
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
    _autosave?.cancel();
    _expand.dispose();
    _titleCtrl.dispose();
    _titleFocus.dispose();
    _activeController.dispose();
    super.dispose();
  }

  void _collect() {
    _card.noteTitle = _titleCtrl.text;
    _editorKey.currentState?.sync();
  }

  void _close() {
    // Reading changed nothing — leave without rewriting the card.
    if (_readOnly) {
      Navigator.of(context).pop();
      return;
    }
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

  // ---- Wiki-links ---------------------------------------------------------

  /// The card's user-authored text (title + note body), scanned for outgoing
  /// `[[links]]`.
  String _cardScanText() {
    final buffer = StringBuffer(_card.noteTitle);
    for (final b in _card.blocks) {
      if (!b.isText) continue;
      final plain = richToPlain(b.text);
      if (plain.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(plain);
    }
    return buffer.toString();
  }

  Future<void> _openRef(LinkRef ref) async {
    final state = context.read<AppState>();
    _editorKey.currentState?.sync();
    _card.noteTitle = _titleCtrl.text;
    state.updateCard(_card);
    if (!mounted) return;
    if (ref.kind == LinkKind.card) {
      final card = state.cardById(ref.id);
      if (card != null) {
        await Navigator.of(context)
            .push(bouncyRoute(CardDetailScreen(card: card)));
      }
      return;
    }
    final note = state.noteById(ref.id);
    if (note != null) {
      await Navigator.of(context)
          .push(bouncyRoute(NoteEditorScreen(note: note, isNew: false)));
    }
  }

  Future<void> _createAndOpenLinkedNote(String title) async {
    final state = context.read<AppState>();
    _editorKey.currentState?.sync();
    _card.noteTitle = _titleCtrl.text;
    state.updateCard(_card);
    final created = await state.createLinkedNote(title);
    if (!mounted) return;
    await Navigator.of(context)
        .push(bouncyRoute(NoteEditorScreen(note: created, isNew: true)));
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final Widget topActions = BubblePill(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: context.t.refreshPreview,
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => context.read<AppState>().refreshCard(_card.id),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
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
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ColoredBox(
        color: AppPalette.sheet,
        // Status-bar clock/battery must stay readable over the sheet: dark
        // icons on the light sheet, light icons on the dark one.
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: (AppPalette.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              ListView(
                // A little breathing room between the pinned back button and
                // the card title below it.
                padding: EdgeInsets.fromLTRB(18, topInset + 24, 18, 200),
                children: [
                  _CardPreview(card: _card),
                  const SizedBox(height: 10),
                  _LinkBar(
                      url: _card.url, onOpen: _openLink, onCopy: _copyLink),
                  if (_card.articleText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ArticleReader(text: _card.articleText),
                  ],
                  const SizedBox(height: 16),
                  if (_readOnly) ...[
                    if (_card.noteTitle.trim().isNotEmpty)
                      Text(
                        _card.noteTitle,
                        style: TextStyle(
                          fontFamily: kNoteHeadingFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.inkPrimary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    _CardNoteBody(card: _card),
                  ] else ...[
                    TextField(
                      controller: _titleCtrl,
                      focusNode: _titleFocus,
                      style: TextStyle(
                        fontFamily: kNoteHeadingFont,
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
                          color:
                              AppPalette.inkSecondary.withValues(alpha: 0.6),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ExpandFromButton(
                      animation: _expand,
                      child: _settled
                          ? NoteBodyEditor(
                              key: _editorKey,
                              blocks: _card.blocks,
                              activeController: _activeController,
                              onLight: true,
                              onBackspaceAtStart: _focusTitle,
                              onRemoveImagePath: (path) => context
                                  .read<AppState>()
                                  .refreshAfterImageRemoval(path),
                            )
                          : _CardNoteBody(card: _card),
                    ),
                  ],
                  // The card's place in the graph: outgoing [[links]] and the
                  // notes, journal entries and cards that mention it.
                  NoteLinksSection(
                    selfId: _card.id,
                    title: _card.noteTitle,
                    scanText: _cardScanText(),
                    onOpen: _openRef,
                    onCreateOpen: _createAndOpenLinkedNote,
                  ),
                ],
              ),
              if (_settled && !_closing) ...[
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Scrim confined to the status bar so the clock/battery stay
                  // readable over whatever scrolls beneath; the card content
                  // itself stays fully visible under the toolbar.
                  child: TopScrimFade(
                      height: MediaQuery.of(context).padding.top + 8),
                ),
                if (!_readOnly)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SlideUpFromButton(
                      animation: _expand,
                      child: EditorBottomBar(
                        activeController: _activeController,
                        onAddPhotos: () =>
                            _editorKey.currentState?.addPhotos(),
                        onPickSpace: _pickSpace,
                      ),
                    ),
                  ),
                // Same compose button as the feed: it starts (and finishes)
                // the note attached to this card.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  right: 18,
                  bottom: (_editing ? 148 : 18) +
                      MediaQuery.of(context).padding.bottom,
                  child: BubbleButton(
                    icon: _editing ? Icons.check_rounded : Icons.edit_rounded,
                    tooltip:
                        _editing ? context.t.save : context.t.editAction,
                    onTap: _editing ? _finishEditing : _startEditing,
                  ),
                ),
              ],
              // The back button + actions, pinned at the standard chrome spot.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        FrostedBackButton(onTap: _close),
                        const Spacer(),
                        topActions,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// The user's own note on a card, rendered as plain text for reading (and
/// during the open morph, before the editors mount).
class _CardNoteBody extends StatelessWidget {
  const _CardNoteBody({required this.card});

  final TweetCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in card.blocks)
          if (b.isText && richToPlain(b.text).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                richToPlain(b.text),
                style: TextStyle(
                  fontFamily: activeBodyFont,
                  fontSize: 21,
                  height: 1.35,
                  color: AppPalette.inkPrimary,
                ),
              ),
            ),
      ],
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

/// The page's captured article text, readable in place (no browser needed).
/// Collapsible so a long read doesn't bury the user's own note below it.
class _ArticleReader extends StatefulWidget {
  const _ArticleReader({required this.text});
  final String text;

  @override
  State<_ArticleReader> createState() => _ArticleReaderState();
}

class _ArticleReaderState extends State<_ArticleReader> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      blur: 0,
      color: Colors.black.withValues(alpha: 0.05),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.chrome_reader_mode_outlined,
                      size: 18, color: AppPalette.inkSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.t.readerSection,
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkSecondary)),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: AppPalette.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectionArea(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.55,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
            ),
        ],
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
