import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note.dart' show richToPlain;

import '../models/tweet_card.dart';
import '../services/note_markdown.dart';
import '../services/note_pdf.dart';
import '../services/wiki_links.dart';
import '../services/youtube_service.dart';
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
import 'note_open.dart';

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

  /// True while the YouTube description/transcript is being scraped on open.
  bool _ytLoading = false;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _titleCtrl = TextEditingController(text: _card.noteTitle);
    _savedFingerprint = _fingerprint();
    _autosave = Timer.periodic(
        const Duration(seconds: 3), (_) => _autosaveTick());
    // A YouTube spark scrapes its description + transcript the first time it's
    // opened; thereafter the stored copy shows instantly. A persistently-blocked
    // video stops auto-scraping after a few tries (Retry still forces it).
    if (_card.shouldAutoFetchYouTube) {
      _loadYouTube();
    }
  }

  Future<void> _loadYouTube({bool force = false}) async {
    setState(() => _ytLoading = true);
    try {
      await context.read<AppState>().fetchYouTubeDetails(_card.id, force: force);
    } catch (_) {
      // Best-effort; the sections just stay empty.
    }
    if (mounted) setState(() => _ytLoading = false);
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

  /// Adjusts the card note's text size (a per-card multiplier).
  void _pickFontSize() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          void set(double v) {
            _collect();
            setState(() => _card.fontScale = v.clamp(0.8, 1.6));
            setSheet(() {});
            context.read<AppState>().updateCard(_card);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                decoration: BoxDecoration(
                  color: AppPalette.sheet,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t.textSize,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.inkPrimary)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _sizeButton('A', 15, () => set(_card.fontScale - 0.1)),
                        const SizedBox(width: 12),
                        _sizeButton('A', 26, () => set(_card.fontScale + 0.1)),
                        const Spacer(),
                        Text('${(_card.fontScale * 100).round()}%',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.inkSecondary)),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: () => set(1.0),
                            child: Text(context.t.resetSize)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sizeButton(String label, double size, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.cardOutline),
          ),
          child: Text(label,
              style: TextStyle(fontSize: size, color: AppPalette.inkPrimary)),
        ),
      );

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

  /// The 3-dots overflow menu: share as Markdown, refresh preview, archive,
  /// delete.
  void _showCardMenu() {
    final state = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _cardMenuTile(sheetCtx, Icons.ios_share_rounded,
                    context.t.share, _shareMarkdown),
                _cardMenuTile(sheetCtx, Icons.picture_as_pdf_outlined,
                    context.t.exportAsPdf, _exportPdf),
                _cardMenuTile(sheetCtx, Icons.refresh_rounded,
                    context.t.refreshPreview, () => state.refreshCard(_card.id)),
                _cardMenuTile(
                  sheetCtx,
                  _card.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  _card.archived ? context.t.unarchive : context.t.archive,
                  () => state.setCardArchived(_card.id, !_card.archived),
                ),
                _cardMenuTile(
                  sheetCtx,
                  Icons.delete_outline_rounded,
                  context.t.deleteCard,
                  () {
                    setState(() => _closing = true);
                    Navigator.of(context).pop();
                    Future.delayed(const Duration(milliseconds: 380),
                        () => state.deleteCard(_card.id));
                  },
                  danger: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardMenuTile(BuildContext sheetCtx, IconData icon, String label,
      VoidCallback onTap,
      {bool danger = false}) {
    final tint = danger ? const Color(0xFFE0567B) : null;
    return ListTile(
      leading: Icon(icon, color: tint ?? AppPalette.inkSecondary),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: tint ?? AppPalette.inkPrimary)),
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );
  }

  String _fileBase() {
    final title =
        _card.noteTitle.trim().isNotEmpty ? _card.noteTitle.trim() : 'spark';
    final base = title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    return base.isEmpty ? 'spark' : base;
  }

  Future<void> _shareMarkdown() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final md = cardToMarkdown(_card);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_fileBase()}.md');
      await file.writeAsString(md);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.shareFailed)));
      }
    }
  }

  /// Renders the spark (via its Markdown form) to a PDF and shares it.
  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await NotePdf.fromMarkdown(cardToMarkdown(_card),
          title: _card.noteTitle.trim());
      await Printing.sharePdf(bytes: bytes, filename: '${_fileBase()}.pdf');
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(context.t.exportFailed)));
      }
    }
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
      await Navigator.of(context).push(bouncyRoute(noteScreen(note)));
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
          tooltip: context.t.moreOptions,
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: _showCardMenu,
        ),
      ],
    );
    return PopScope(
      // While viewing (the default), let the back gesture pop directly so
      // Android's predictive-back peek can play; only intercept while editing,
      // where _close() collects and persists the edits before popping.
      canPop: _readOnly,
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
                  if (YouTubeService.isYouTube(_card.url)) ...[
                    const SizedBox(height: 10),
                    _YouTubeSections(
                      card: _card,
                      loading: _ytLoading,
                      onRetry: () => _loadYouTube(force: true),
                    ),
                  ],
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
                          fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w700,
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
                              fontScale: _card.fontScale,
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
                        onFontSize: _pickFontSize,
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
          if (card.coverImageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                card.coverImageUrl,
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

/// The Description + Transcript panels for a YouTube spark, scraped so the video
/// doesn't have to be opened. Sections that came back empty are simply omitted.
class _YouTubeSections extends StatelessWidget {
  const _YouTubeSections(
      {required this.card, required this.loading, required this.onRetry});

  final TweetCard card;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final description = card.videoDescription.trim().isNotEmpty
        ? card.videoDescription.trim()
        : card.text.trim(); // fall back to the OG blurb if scrape came up dry
    final transcript = card.videoTranscript.trim();

    if (loading && description.isEmpty && transcript.isEmpty) {
      return _panel(
        Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(context.t.youtubeFetching,
              style: TextStyle(color: AppPalette.inkSecondary)),
        ]),
      );
    }

    final sections = <Widget>[];
    if (description.isNotEmpty) {
      sections.add(_ExpandableSection(
        icon: Icons.notes_rounded,
        title: context.t.youtubeDescription,
        body: description,
        initiallyExpanded: true,
      ));
    }
    if (transcript.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 10));
      sections.add(_ExpandableSection(
        icon: Icons.subject_rounded,
        title: context.t.youtubeTranscript,
        body: transcript,
        initiallyExpanded: false,
      ));
    }
    if (sections.isEmpty) {
      return _panel(
        Row(children: [
          Icon(Icons.smart_display_outlined,
              size: 18, color: AppPalette.inkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(context.t.youtubeUnavailable,
                style: TextStyle(color: AppPalette.inkSecondary)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: loading ? null : onRetry,
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.t.retry),
            style: TextButton.styleFrom(
                foregroundColor: AppPalette.inkPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ]),
      );
    }
    return Column(children: sections);
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.surfaceGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: child,
      );
}

/// A tap-to-expand titled panel holding long, selectable text (description or
/// transcript). The transcript starts collapsed since it can run long.
class _ExpandableSection extends StatefulWidget {
  const _ExpandableSection({
    required this.icon,
    required this.title,
    required this.body,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool initiallyExpanded;

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(widget.icon, size: 18, color: AppPalette.inkPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppPalette.inkPrimary)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: context.t.copy,
                  icon: Icon(Icons.copy_rounded,
                      size: 17, color: AppPalette.inkSecondary),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.body));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.t.copied)));
                  },
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded,
                      color: AppPalette.inkSecondary),
                ),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SelectableText(
                widget.body,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppPalette.inkSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
