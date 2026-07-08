import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/tweet_card.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// A saved link/tweet rendered as a compact feed card.
///
/// Tweets keep the full layout (avatar, text, media). Plain links are compact:
/// if the user titled the card, the title + a caption snippet lead; otherwise
/// a trimmed version of the link preview is shown.
class TweetCardWidget extends StatelessWidget {
  const TweetCardWidget({
    super.key,
    required this.card,
    required this.onTap,
    required this.onDelete,
    this.onLongPress,
    this.folderName,
  });

  final TweetCard card;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;

  /// Name of the cortex folder this card lives in, shown as a small chip.
  final String? folderName;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: FlatCard(
          borderRadius: 22,
          padding: EdgeInsets.all(card.isTweet ? 14 : 12),
          child: card.isTweet
              ? _tweetBody(context)
              : (card.noteTitle.trim().isNotEmpty
                  ? _titledLinkBody(context)
                  : _linkBody(context)),
        ),
      ),
    );
  }

  // ---- Tweet: the original full layout -----------------------------------

  Widget _tweetBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            card.text,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: AppPalette.inkPrimary,
            ),
          ),
        ],
        if (card.imageUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          _media(height: 170),
        ],
        const SizedBox(height: 10),
        _urlRow(),
      ],
    );
  }

  // ---- Plain link, user titled it: title + caption snippet ---------------

  Widget _titledLinkBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.noteTitle.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary,
                    ),
                  ),
                  if (card.text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      card.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: AppPalette.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (card.imageUrl.isNotEmpty) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  card.imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  // Same cacheWidth as the detail preview: one shared decode.
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            _closeButton(context),
          ],
        ),
        const SizedBox(height: 8),
        _urlRow(),
      ],
    );
  }

  // ---- Plain link, no title: preview layout, halved ----------------------

  Widget _linkBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            card.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: AppPalette.inkPrimary,
            ),
          ),
        ],
        if (card.imageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          _media(height: 96),
        ],
        const SizedBox(height: 8),
        _urlRow(),
      ],
    );
  }

  // ---- Shared pieces ------------------------------------------------------

  Widget _header(BuildContext context) {
    return Row(
      children: [
        _Avatar(card: card),
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
                Text(
                  card.authorHandle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.inkSecondary,
                  ),
                ),
            ],
          ),
        ),
        _closeButton(context),
      ],
    );
  }

  Widget _closeButton(BuildContext context) {
    return IconButton(
      tooltip: context.t.deleteCard,
      icon: Icon(Icons.close_rounded,
          size: 18, color: AppPalette.inkSecondary),
      onPressed: onDelete,
      splashRadius: 18,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _media({required double height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        card.imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        cacheWidth: 900,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            alignment: Alignment.center,
            color: Colors.black.withValues(alpha: 0.05),
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        },
      ),
    );
  }

  Widget _urlRow() {
    return Row(
      children: [
        if (card.pinned)
          Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.push_pin_rounded,
                size: 13, color: AppPalette.inkSecondary),
          ),
        if (!card.fetched)
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppPalette.inkSecondary,
              ),
            ),
          ),
        Expanded(
          child: Text(
            _displayUrl(card.url),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.inkSecondary,
            ),
          ),
        ),
        if (folderName != null && folderName!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_rounded,
                    size: 11, color: AppPalette.inkSecondary),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    folderName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: AppPalette.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _displayUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '') + uri.path;
    } catch (_) {
      return url;
    }
  }
}

/// A compact "block" tile for the cards feed's Blocks view: a small masonry
/// tile like the notes on the home feed.
class CompactCardTile extends StatelessWidget {
  const CompactCardTile({
    super.key,
    required this.card,
    required this.onTap,
    this.onLongPress,
    this.folderName,
  });

  final TweetCard card;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? folderName;

  String _title(AppLocalizations t) {
    if (card.noteTitle.trim().isNotEmpty) return card.noteTitle.trim();
    if (card.authorName.isNotEmpty) return card.authorName;
    if (card.siteName.isNotEmpty) return card.siteName;
    return t.linkFallback;
  }

  String get _host {
    try {
      return Uri.parse(card.url).host.replaceFirst('www.', '');
    } catch (_) {
      return card.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: FlatCard(
          borderRadius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (card.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16.5)),
                  child: Image.network(
                    card.imageUrl,
                    height: 86,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: 900,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          card.isTweet
                              ? Icons.alternate_email_rounded
                              : Icons.link_rounded,
                          size: 13,
                          color: AppPalette.inkSecondary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _title(context.t),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.inkPrimary,
                            ),
                          ),
                        ),
                        if (card.pinned)
                          Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin_rounded,
                                size: 12, color: AppPalette.inkSecondary),
                          ),
                      ],
                    ),
                    if (card.text.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        card.text,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppPalette.inkSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppPalette.inkSecondary,
                            ),
                          ),
                        ),
                        if (folderName != null &&
                            folderName!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.folder_rounded,
                              size: 10, color: AppPalette.inkSecondary),
                          const SizedBox(width: 3),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 60),
                            child: Text(
                              folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppPalette.inkSecondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular author avatar with a graceful icon fallback.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.card});
  final TweetCard card;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
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
        // unavatar serves the image only to a browser-like user-agent.
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
