// Braim Web page builders. Each returns finished HTML; strings come from the
// app's localizations and pass through [esc]. See docs/braim-web-plan.md,
// section 8.

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../models/tweet_card.dart';
import '../services/note_markdown.dart';
import '../state/app_state.dart';
import 'web_assets.dart';
import 'web_html.dart';

/// The main area of a signed-in page. [attrs] go on `<main>` as they are, so
/// they must already be escaped. A list page's main is refetched with
/// `?partial=1` when the library changes; a view page's is watched through
/// its meta URL.
typedef WebView = ({String title, String main, String attrs});

/// The file name of a stored image path, as `/img/<name>` serves it.
String imageName(String path) => path.split(RegExp(r'[\\/]')).last;

/// The pairing form: six single-digit boxes that `app.js` fills, advances and
/// submits to `/api/pair`.
String pairPage(AppLocalizations l10n, WebAssets assets) {
  final digits = StringBuffer();
  for (var i = 0; i < 6; i++) {
    digits.write(
      '<input class="digit" type="text" inputmode="numeric" '
      'maxlength="1" pattern="[0-9]" '
      'autocomplete="${i == 0 ? 'one-time-code' : 'off'}" '
      'aria-label="${esc('${l10n.webCodeLabel} ${i + 1}')}">',
    );
  }
  final body =
      '''
<main class="pair">
<h1>${esc(l10n.webPairTitle)}</h1>
<p class="muted">${esc(l10n.webPairHelp)}</p>
<form id="pair-form" data-offline="${esc(l10n.webOffline)}" novalidate>
<fieldset>
<legend>${esc(l10n.webCodeLabel)}</legend>
<div class="digits">$digits</div>
</fieldset>
<p class="msg" id="pair-msg" role="alert"></p>
<button type="submit" class="primary">${esc(l10n.webPairLink)}</button>
</form>
<p class="muted small">${esc(l10n.webPairNewAddress)}</p>
</main>''';
  return htmlPage(
    assets: assets,
    title: l10n.webPairTitle,
    body: body,
    bodyClass: 'bare',
  );
}

/// A plain error page: a heading and a link home. Never a stack trace.
String errorPage(AppLocalizations l10n, WebAssets assets, String message) {
  final body =
      '''
<main class="narrow error">
<h1>${esc(message)}</h1>
<p><a href="/">${esc(l10n.appTitle)}</a></p>
</main>''';
  return htmlPage(
    assets: assets,
    title: message,
    body: body,
    bodyClass: 'bare',
  );
}

/// The signed-in pages, built from the live library.
class WebPages {
  WebPages({required this.l10n, required this.assets, required this.state});

  final AppLocalizations l10n;
  final WebAssets assets;
  final AppState state;

  /// Rendered note bodies and card snippets, keyed by the content they were
  /// built from, so an unchanged note is not converted again.
  final _cache = _Lru(400);

  /// A whole signed-in page around [view]: the top bar with its tabs, search
  /// box, connection dot and Log out, the banner `app.js` fills, and main.
  String page(
    WebView view, {
    required String csrf,
    String tab = '',
    String query = '',
  }) {
    String tabLink(String key, String href, String label) {
      final current = key == tab;
      return '<a class="tab${current ? ' current' : ''}" href="$href"'
          '${current ? ' aria-current="page"' : ''}>${esc(label)}</a>';
    }

    final body =
        '''
<header class="bar">
<a class="brand" href="/">${esc(l10n.appTitle)}</a>
<nav class="tabs">${tabLink('notes', '/', l10n.webTabNotes)}${tabLink('sparks', '/sparks', l10n.webTabSparks)}</nav>
<form class="search" action="/search" method="get" role="search">
<input type="search" name="q" value="${esc(query)}" placeholder="${esc(l10n.webSearch)}" aria-label="${esc(l10n.webSearch)}">
</form>
<span class="dot" id="conn" role="status" title="${esc(l10n.webConnected)}" aria-label="${esc(l10n.webConnected)}"></span>
<button type="button" class="quiet" data-action="logout">${esc(l10n.webLogOut)}</button>
</header>
<p class="banner" id="banner" hidden data-offline="${esc(l10n.webOffline)}" data-deleted="${esc(l10n.webDeletedOnPhone)}"></p>
<main${view.attrs.isEmpty ? '' : ' ${view.attrs}'}>${view.main}</main>''';
    return htmlPage(
      assets: assets,
      title: view.title,
      body: body,
      csrf: csrf,
      bodyAttrs: 'data-font="${esc(state.noteBodyFont)}"',
    );
  }

  // ---- Notes feed -----------------------------------------------------------

  WebView feed() {
    final notes = state.webFeedNotes;
    final out = StringBuffer('<h1 class="page-title">')
      ..write(esc(l10n.webTabNotes))
      ..write('</h1>');
    if (notes.isEmpty) {
      out.write('<p class="empty">${esc(l10n.webFeedEmpty)}</p>');
    } else {
      out.write('<div class="feed">');
      for (final n in notes) {
        out.write(_noteCard(n));
      }
      out.write('</div>');
    }
    return (title: l10n.webTabNotes, main: out.toString(), attrs: 'data-list');
  }

  String _noteCard(Note n) {
    final title = n.title.trim();
    final circuit = n.isCircuitRoot;
    final snippet = _snippet(n, title);
    final tint = _tintStyle(n.colorValue);
    final out = StringBuffer(
      '<a class="card${tint.isEmpty ? '' : ' tinted'}'
      '${circuit ? ' circuit' : ''}" href="${esc(_noteHref(n))}"$tint>',
    );
    final thumb = n.thumbnailPath;
    if (thumb != null) {
      out.write(
        '<img class="thumb" src="${esc(_imgHref(thumb))}" alt="" '
        'loading="lazy">',
      );
    }
    out.write('<div class="card-body">');
    if (circuit) {
      out.write('<p class="kicker">${esc(l10n.circuitLabel)}</p>');
    }
    if (title.isNotEmpty || circuit) {
      out.write(
        '<h2 class="card-title">'
        '${esc(title.isEmpty ? l10n.untitledCircuit : title)}</h2>',
      );
    }
    if (snippet.isNotEmpty) {
      out.write('<p class="snippet">${esc(snippet)}</p>');
    } else if (title.isEmpty && !circuit) {
      out.write('<p class="snippet muted">${esc(l10n.emptyNote)}</p>');
    }
    final meta = StringBuffer();
    if (n.pinned) {
      meta.write(
        '<span class="pin" title="${esc(l10n.webPinned)}" '
        'aria-label="${esc(l10n.webPinned)}">●</span>',
      );
    }
    if (circuit) {
      meta.write(
        '<span>${esc(l10n.circuitNotesCount(state.circuitBranchCount(n.id)))}</span>',
      );
    }
    for (final t in n.tags) {
      meta.write('<span class="tag">#${esc(t)}</span>');
    }
    if (meta.isNotEmpty) out.write('<p class="card-meta">$meta</p>');
    out.write('</div></a>');
    return out.toString();
  }

  /// A few lines of plain text for a feed card.
  String _snippet(Note n, String title) =>
      _cache.putIfAbsent('snippet:${_signature(n)}', () {
        final text = n.markdown
            ? markdownPlainPreview(n.markdownSource, skipTitle: title)
            : n.textPreview;
        final t = text.trim();
        return t.length > 320 ? '${t.substring(0, 320)}…' : t;
      });

  // ---- A note ----------------------------------------------------------------

  WebView note(Note n) {
    final out = StringBuffer('<article class="note">');
    final path = n.isCircuitNode ? state.circuitPath(n.id) : const <Note>[];
    if (path.length > 1) {
      out.write('<nav class="crumbs">');
      for (var i = 0; i < path.length - 1; i++) {
        final p = path[i];
        final name = p.title.trim().isEmpty
            ? l10n.untitledNote
            : p.title.trim();
        out.write(
          state.isWebVisibleNote(p)
              ? '<a href="${esc(_noteHref(p))}">${esc(name)}</a>'
              : '<span>${esc(name)}</span>',
        );
        out.write('<span class="sep">›</span>');
      }
      out.write('</nav>');
    }
    final title = n.title.trim();
    // A Markdown note's title is its own first heading, drawn by the body.
    if (!n.markdown && title.isNotEmpty) {
      out.write('<h1 class="note-title">${esc(title)}</h1>');
    }
    if (n.tags.isNotEmpty || n.colorValue != null) {
      out.write('<p class="note-meta">');
      if (n.colorValue != null) {
        out.write('<span class="swatch"${_tintStyle(n.colorValue)}></span>');
      }
      for (final t in n.tags) {
        out.write('<span class="tag">#${esc(t)}</span>');
      }
      out.write('</p>');
    }
    out
      ..write(_noteBody(n))
      ..write('</article>');
    final display = title.isNotEmpty
        ? title
        : (n.textPreview.isNotEmpty
              ? n.textPreview.split('\n').first
              : l10n.emptyNote);
    return (
      title: display,
      main: out.toString(),
      attrs:
          'data-watch="${esc('/api/notes/${Uri.encodeComponent(n.id)}/meta')}" '
          'data-updated="${n.updatedAt.millisecondsSinceEpoch}"',
    );
  }

  String _noteBody(Note n) => _cache.putIfAbsent('body:${_signature(n)}', () {
    final scale = n.fontScale.clamp(0.8, 1.6);
    final out = StringBuffer(
      scale == 1.0
          ? '<div class="note-body${n.markdown ? ' markdown' : ''}">'
          : '<div class="note-body${n.markdown ? ' markdown' : ''}" '
                'style="font-size:${scale.toStringAsFixed(2)}em">',
    );
    out.write(
      blocksHtml(
        n.blocks,
        markdown: n.markdown,
        checkedToBottom: n.checkedToBottom,
      ),
    );
    out.write('</div>');
    return out.toString();
  });

  /// A note's (or a spark's) blocks in order: text as HTML, images from
  /// `/img/`, link blocks as small link cards.
  String blocksHtml(
    List<NoteBlock> blocks, {
    bool markdown = false,
    bool checkedToBottom = false,
  }) {
    final out = StringBuffer();
    var markdownDone = false;
    for (var bi = 0; bi < blocks.length; bi++) {
      final b = blocks[bi];
      if (b.isText) {
        if (markdown && !markdownDone) {
          out.write(markdownToSafeHtml(b.text));
          markdownDone = true;
        } else {
          out.write(
            richBlockHtml(
              b.text,
              blockIndex: bi,
              checkedToBottom: checkedToBottom,
            ),
          );
        }
      } else if (b.isImage && b.imagePath.isNotEmpty) {
        out.write(
          '<figure class="note-img"><img src="'
          '${esc(_imgHref(b.imagePath))}" alt="" loading="lazy"></figure>',
        );
      } else if (b.isLink) {
        out.write(_linkCard(b));
      }
    }
    return out.toString();
  }

  String _linkCard(NoteBlock b) {
    final href = safeUrl(b.url);
    final image = safeUrl(b.linkImage);
    final inner = StringBuffer();
    if (image != null && image.startsWith('https:')) {
      inner.write('<img src="${esc(image)}" alt="" loading="lazy">');
    }
    inner
      ..write('<span class="lc-text"><span class="lc-title">')
      ..write(esc(b.linkTitle.isNotEmpty ? b.linkTitle : b.url))
      ..write('</span>');
    if (b.linkSite.isNotEmpty) {
      inner.write('<span class="lc-site">${esc(b.linkSite)}</span>');
    }
    inner.write('</span>');
    return href == null
        ? '<div class="linkcard">$inner</div>'
        : externalLink(href, inner.toString(), cls: 'linkcard');
  }

  // ---- Sparks -----------------------------------------------------------------

  WebView sparks() {
    final cards = state.cards;
    final out = StringBuffer('<h1 class="page-title">')
      ..write(esc(l10n.webTabSparks))
      ..write('</h1>');
    if (cards.isEmpty) {
      out.write('<p class="empty">${esc(l10n.webSparksEmpty)}</p>');
    } else {
      out.write('<div class="feed sparks">');
      for (final c in cards) {
        out.write(_sparkCard(c));
      }
      out.write('</div>');
    }
    return (title: l10n.webTabSparks, main: out.toString(), attrs: 'data-list');
  }

  static String sparkTitle(TweetCard c) {
    if (c.noteTitle.trim().isNotEmpty) return c.noteTitle.trim();
    if (c.authorName.trim().isNotEmpty) return c.authorName.trim();
    if (c.siteName.trim().isNotEmpty) return c.siteName.trim();
    return c.url;
  }

  String _sparkCard(TweetCard c) {
    final out = StringBuffer(
      '<a class="card spark" href="${esc(_sparkHref(c))}">',
    );
    final cover = _remoteImage(c.coverImageUrl);
    if (cover != null) {
      out.write(
        '<img class="thumb" src="${esc(cover)}" alt="" '
        'loading="lazy" referrerpolicy="no-referrer">',
      );
    }
    out.write('<div class="card-body">');
    if (c.siteName.trim().isNotEmpty) {
      out.write('<p class="kicker">${esc(c.siteName.trim())}</p>');
    }
    out.write('<h2 class="card-title">${esc(sparkTitle(c))}</h2>');
    final text = c.text.trim();
    if (text.isNotEmpty) {
      out.write(
        '<p class="snippet">'
        '${esc(text.length > 320 ? '${text.substring(0, 320)}…' : text)}'
        '</p>',
      );
    }
    if (c.pinned) {
      out.write(
        '<p class="card-meta"><span class="pin" '
        'title="${esc(l10n.webPinned)}" '
        'aria-label="${esc(l10n.webPinned)}">●</span></p>',
      );
    }
    out.write('</div></a>');
    return out.toString();
  }

  WebView spark(TweetCard c) {
    final out = StringBuffer('<article class="spark-page">');
    final cover = _remoteImage(c.coverImageUrl);
    if (cover != null) {
      out.write(
        '<img class="cover" src="${esc(cover)}" alt="" '
        'referrerpolicy="no-referrer">',
      );
    }
    final byline = [
      if (c.siteName.trim().isNotEmpty) c.siteName.trim(),
      if (c.authorHandle.trim().isNotEmpty) c.authorHandle.trim(),
    ];
    if (byline.isNotEmpty) {
      out.write('<p class="kicker">${esc(byline.join(' · '))}</p>');
    }
    out.write('<h1 class="note-title">${esc(sparkTitle(c))}</h1>');
    if (c.noteTitle.trim().isNotEmpty && c.authorName.trim().isNotEmpty) {
      out.write('<p class="muted">${esc(c.authorName.trim())}</p>');
    }
    if (c.text.trim().isNotEmpty) {
      out.write('<div class="scraped">${plainTextHtml(c.text)}</div>');
    }
    final href = safeUrl(c.url);
    out.write('<p class="spark-link">');
    if (href != null) {
      out.write(externalLink(href, esc(l10n.open), cls: 'button'));
    }
    out.write(' <span class="url">${esc(c.url)}</span></p>');
    // The spark's own note, written by the user.
    final hasNote = c.blocks.any(
      (b) => !b.isText || richToPlain(b.text).isNotEmpty,
    );
    if (hasNote) {
      out
        ..write('<section class="spark-note"><div class="note-body">')
        ..write(blocksHtml(c.blocks))
        ..write('</div></section>');
    }
    void section(String label, String text) {
      if (text.trim().isEmpty) return;
      out.write(
        '<section class="scraped"><h2>${esc(label)}</h2>'
        '${plainTextHtml(text)}</section>',
      );
    }

    section(l10n.youtubeDescription, c.videoDescription);
    section(l10n.youtubeTranscript, c.videoTranscript);
    section(l10n.readerSection, c.articleText);
    out.write('</article>');
    return (
      title: sparkTitle(c),
      main: out.toString(),
      attrs:
          'data-watch="${esc('/api/sparks/${Uri.encodeComponent(c.id)}/meta')}" '
          'data-updated="${c.updatedAt.millisecondsSinceEpoch}"',
    );
  }

  // ---- Search -----------------------------------------------------------------

  WebView search(
    String query,
    ({List<Note> notes, List<TweetCard> cards})? found,
  ) {
    final out = StringBuffer('<h1 class="page-title">')
      ..write(esc(query.trim().isEmpty ? l10n.webSearch : query.trim()))
      ..write('</h1>');
    if (found == null) {
      out.write('<p class="empty">${esc(l10n.webSearchPrompt)}</p>');
    } else if (found.notes.isEmpty && found.cards.isEmpty) {
      out.write('<p class="empty">${esc(l10n.noMatches)}</p>');
    } else {
      if (found.notes.isNotEmpty) {
        out.write(
          '<section><h2 class="section-label">'
          '${esc(l10n.webTabNotes)}</h2><ul class="results">',
        );
        for (final n in found.notes) {
          final (title, sub) = _noteResult(n);
          out.write(_result(_noteHref(n), title, sub));
        }
        out.write('</ul></section>');
      }
      if (found.cards.isNotEmpty) {
        out.write(
          '<section><h2 class="section-label">'
          '${esc(l10n.webTabSparks)}</h2><ul class="results">',
        );
        for (final c in found.cards) {
          out.write(
            _result(
              _sparkHref(c),
              sparkTitle(c),
              c.text.isNotEmpty ? c.text : c.url,
            ),
          );
        }
        out.write('</ul></section>');
      }
    }
    return (
      title: query.trim().isEmpty ? l10n.webSearch : query.trim(),
      main: out.toString(),
      attrs: 'data-list',
    );
  }

  /// Title and subtitle as the phone's search list shows them.
  (String, String?) _noteResult(Note n) {
    final title = n.title.trim().isNotEmpty
        ? n.title.trim()
        : (n.textPreview.isNotEmpty ? n.textPreview : l10n.emptyNote);
    if (n.isCircuitNode) {
      final root = state.noteById(n.circuitId!);
      final name = (root == null || root.title.trim().isEmpty)
          ? l10n.untitledCircuit
          : root.title.trim();
      return (title, l10n.circuitIn(name));
    }
    return (
      title,
      n.title.trim().isNotEmpty && n.textPreview.isNotEmpty
          ? n.textPreview
          : null,
    );
  }

  String _result(String href, String title, String? sub) {
    final s = sub?.split('\n').first.trim();
    return '<li><a href="${esc(href)}"><span class="r-title">'
        '${esc(title.split('\n').first)}</span>'
        '${s == null || s.isEmpty ? '' : '<span class="r-sub">${esc(s)}</span>'}'
        '</a></li>';
  }

  // ---- Not on Braim Web ---------------------------------------------------------

  WebView notAvailable(String title) => (
    title: l10n.webNotAvailable,
    main:
        '<div class="narrow"><h1 class="page-title">'
        '${esc(l10n.webNotAvailable)}</h1>'
        '${title.trim().isEmpty ? '' : '<p class="muted">${esc(title.trim())}</p>'}'
        '</div>',
    attrs: '',
  );

  // ---- Helpers ------------------------------------------------------------------

  static String _noteHref(Note n) => '/notes/${Uri.encodeComponent(n.id)}';
  static String _sparkHref(TweetCard c) =>
      '/sparks/${Uri.encodeComponent(c.id)}';
  static String _imgHref(String path) =>
      '/img/${Uri.encodeComponent(imageName(path))}';

  /// A remote image the page may load: https only, as the CSP allows.
  static String? _remoteImage(String url) {
    final u = safeUrl(url.trim());
    return u != null && u.startsWith('https:') ? u : null;
  }

  /// What a note's rendering depends on. String hashes are cached by the VM,
  /// so this stays cheap.
  static String _signature(Note n) =>
      '${n.id}:'
      '${n.updatedAt.millisecondsSinceEpoch}:'
      '${Object.hash(n.title, n.markdown, n.checkedToBottom, n.fontScale, Object.hashAll(n.blocks.map((b) => Object.hash(b.type, b.text, b.imagePath, b.url, b.linkTitle))))}';

  /// A colour tag as CSS custom properties: the swatch for light pages and
  /// the app's dark-mode tint (16% of the swatch over #1E2028) for dark ones.
  static String _tintStyle(int? value) {
    if (value == null) return '';
    final r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF;
    String hex(int r, int g, int b) =>
        '#${[r, g, b].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';
    int dark(int c, int base) => (c * 0.16 + base * 0.84).round();
    return ' style="--tint:${hex(r, g, b)};'
        '--tint-dark:${hex(dark(r, 0x1E), dark(g, 0x20), dark(b, 0x28))}"';
  }
}

/// A small least-recently-used string cache.
class _Lru {
  _Lru(this.capacity);
  final int capacity;
  final _map = <String, String>{}; // insertion-ordered

  String putIfAbsent(String key, String Function() build) {
    final hit = _map.remove(key);
    if (hit != null) {
      _map[key] = hit;
      return hit;
    }
    final value = build();
    _map[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
    return value;
  }
}
