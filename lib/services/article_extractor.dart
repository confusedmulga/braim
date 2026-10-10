import 'dart:convert';

import 'package:html/dom.dart' as dom;

/// Reader-mode extraction: pulls the main article text out of a web page so
/// a shared link can be read entirely inside its card, offline.
///
/// A simplified Readability: strip the page chrome, score every text block's
/// container by how much prose it holds, then walk the winning container in
/// document order collecting headings, paragraphs, lists and quotes.
class ArticleExtractor {
  ArticleExtractor._();

  /// Tags that are never part of an article body.
  static const _chromeTags = {
    'script', 'style', 'noscript', 'iframe', 'svg', 'form', 'nav',
    'header', 'footer', 'aside', 'button', 'input', 'select', 'textarea',
    'video', 'audio', 'canvas', 'figure', 'figcaption', 'sup',
  };

  /// class/id fragments that mark boilerplate containers.
  static final _chromeHint = RegExp(
      r'comment|sidebar|footer|masthead|menu|nav|share|social|sponsor|'
      r'related|promo|banner|cookie|subscribe|newsletter|breadcrumb|toc|'
      r'infobox|edit|reference|catlinks|paywall',
      caseSensitive: false);

  /// Blocks collected from the winning container, in document order.
  static const _bodyTags = {
    'h1', 'h2', 'h3', 'h4', 'p', 'li', 'blockquote', 'pre',
  };

  /// schema.org's `"isAccessibleForFree": false` as raw text, for a JSON-LD
  /// block too malformed to parse.
  static final _notFreeJson = RegExp(
      r'''["']isAccessibleForFree["']\s*:\s*["']?false["']?''',
      caseSensitive: false);

  /// Whether [doc] marks its article as for paying subscribers, the way
  /// publishers tell search engines: schema.org `isAccessibleForFree: false`
  /// (in JSON-LD, anywhere in it, including a paywalled `hasPart`, or in
  /// microdata), or an `article:content_tier` of `locked` or `metered`. A
  /// metered article is treated as paywalled too: Braim can't know which of
  /// the reader's free articles it would be using up. Must run before the
  /// scripts are stripped.
  static bool isPaywalled(dom.Document doc) {
    bool notFree(Object? v) =>
        v == false || (v is String && v.trim().toLowerCase() == 'false');

    bool search(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == 'isAccessibleForFree' && notFree(entry.value)) {
            return true;
          }
          if (search(entry.value)) return true;
        }
      } else if (node is List) {
        for (final item in node) {
          if (search(item)) return true;
        }
      }
      return false;
    }

    for (final script
        in doc.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        if (search(jsonDecode(script.text))) return true;
      } catch (_) {
        if (_notFreeJson.hasMatch(script.text)) return true;
      }
    }
    for (final el in doc.querySelectorAll('[itemprop="isAccessibleForFree"]')) {
      if (notFree(el.attributes['content'] ?? el.text)) return true;
    }
    final tier = doc.querySelector('meta[property="article:content_tier"]') ??
        doc.querySelector('meta[name="article:content_tier"]');
    final value = tier?.attributes['content']?.trim().toLowerCase();
    return value == 'locked' || value == 'metered';
  }

  /// Hard cap so a very long page can't bloat the data file.
  static const _maxChars = 80000;

  /// Returns the article as plain text (paragraphs separated by blank
  /// lines), or null when the page doesn't look like an article.
  static String? extract(dom.Document doc) {
    final body = doc.body;
    if (body == null) return null;
    // A publisher's subscriber-only article: don't lift text a paywall hides.
    if (isPaywalled(doc)) return null;

    // 1. Drop chrome outright so it can't score or leak into the text.
    for (final el in body.querySelectorAll(_chromeTags.join(','))) {
      el.remove();
    }
    for (final el in body.querySelectorAll('[hidden],[aria-hidden="true"]')) {
      el.remove();
    }

    // 2. Score each paragraph's parent (and half to the grandparent) by how
    //    much prose it carries. The densest container wins.
    final scores = <dom.Element, double>{};
    for (final p in body.querySelectorAll('p')) {
      final text = p.text.trim();
      if (text.length < 25) continue;
      final score = 1 +
          ','.allMatches(text).length +
          '。'.allMatches(text).length +
          (text.length / 100).clamp(0, 3);
      final parent = p.parent;
      if (parent == null || _isChrome(parent)) continue;
      scores[parent] = (scores[parent] ?? 0) + score;
      final grand = parent.parent;
      if (grand != null && !_isChrome(grand)) {
        scores[grand] = (scores[grand] ?? 0) + score / 2;
      }
    }
    if (scores.isEmpty) return null;
    final top =
        (scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    // 3. Collect the winner's blocks in document order.
    final parts = <String>[];
    var length = 0;
    for (final el in top.querySelectorAll(_bodyTags.join(','))) {
      if (_inChrome(el, stopAt: top)) continue;
      // A block nested in another collected block (p inside li) would double.
      if (_bodyTags.contains(el.parent?.localName)) continue;
      var text = el.text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      if (text.isEmpty) continue;
      final isHeading = el.localName!.startsWith('h');
      if (!isHeading && text.length < 15) continue;
      if (el.localName == 'li') text = '• $text';
      parts.add(text);
      length += text.length;
      if (length > _maxChars) break;
    }

    final article = parts.join('\n\n').trim();
    // Too short = probably a shop page, video page, login wall… not prose.
    if (article.length < 400) return null;
    return article;
  }

  static bool _isChrome(dom.Element el) {
    final hint = '${el.className} ${el.id}';
    return hint.isNotEmpty && _chromeHint.hasMatch(hint);
  }

  /// Whether any ancestor between [el] and [stopAt] looks like boilerplate.
  static bool _inChrome(dom.Element el, {required dom.Element stopAt}) {
    var node = el.parent;
    while (node != null && node != stopAt) {
      if (_isChrome(node)) return true;
      node = node.parent;
    }
    return false;
  }
}
