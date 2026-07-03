import 'package:flutter/material.dart';

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
  });

  final TweetCard card;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: GlassEdge(
          borderRadius: 22,
          blur: 0,
          fill: AppPalette.cardFill,
          padding: EdgeInsets.all(card.isTweet ? 14 : 12),
          shadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          child: card.isTweet
              ? _tweetBody()
              : (card.noteTitle.trim().isNotEmpty
                  ? _titledLinkBody()
                  : _linkBody()),
        ),
      ),
    );
  }

  // ---- Tweet: the original full layout -----------------------------------

  Widget _tweetBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            card.text,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
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

  Widget _titledLinkBody() {
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
                    style: const TextStyle(
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
                      style: const TextStyle(
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
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            _closeButton(),
          ],
        ),
        const SizedBox(height: 8),
        _urlRow(),
      ],
    );
  }

  // ---- Plain link, no title: preview layout, halved ----------------------

  Widget _linkBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        if (card.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            card.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
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

  Widget _header() {
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
                    : (card.siteName.isNotEmpty ? card.siteName : 'Link'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppPalette.inkPrimary,
                ),
              ),
              if (card.authorHandle.isNotEmpty)
                Text(
                  card.authorHandle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.inkSecondary,
                  ),
                ),
            ],
          ),
        ),
        _closeButton(),
      ],
    );
  }

  Widget _closeButton() {
    return IconButton(
      icon: const Icon(Icons.close_rounded,
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
        if (!card.fetched)
          const Padding(
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
            style: const TextStyle(
              fontSize: 12,
              color: AppPalette.inkSecondary,
            ),
          ),
        ),
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
