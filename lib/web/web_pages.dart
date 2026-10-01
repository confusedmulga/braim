// Braim Web page builders. Each returns finished HTML; strings come from the
// app's localizations and pass through [esc]. See docs/braim-web-plan.md,
// section 8.

import 'dart:convert';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../models/note_block.dart';
import '../models/tweet_card.dart';
import '../services/note_markdown.dart';
import '../state/app_state.dart';
import 'web_api.dart';
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
      'pattern="[0-9]*" '
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
    bool editor = false,
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
<div class="bar-end">
<form class="search" action="/search" method="get" role="search">
<input type="search" name="q" value="${esc(query)}" placeholder="${esc(l10n.webSearch)}" aria-label="${esc(l10n.webSearch)}">
</form>
<span class="dot" id="conn" role="status" title="${esc(l10n.webConnected)}" aria-label="${esc(l10n.webConnected)}"></span>
<button type="button" class="plain" data-action="logout">${esc(l10n.webLogOut)}</button>
</div>
</header>
<p class="banner" id="banner" hidden data-offline="${esc(l10n.webOffline)}" data-deleted="${esc(l10n.webDeletedOnPhone)}"></p>
<main${view.attrs.isEmpty ? '' : ' ${view.attrs}'}>${view.main}</main>''';
    return htmlPage(
      assets: assets,
      title: view.title,
      body: body,
      csrf: csrf,
      styles: editor ? const ['vendor/quill.core.css', 'editor.css'] : const [],
      scripts: editor ? const ['vendor/quill.js', 'editor.js'] : const [],
    );
  }

  // ---- Notes feed -----------------------------------------------------------

  WebView feed() {
    final notes = state.webFeedNotes;
    final out = StringBuffer('<div class="title-row"><h1 class="page-title">')
      ..write(esc(l10n.webTabNotes))
      ..write('</h1><div class="actions">')
      ..write(
        '<a class="button tonal" href="/notes/new?kind=markdown">'
        '${esc(l10n.webNewMarkdown)}</a>',
      )
      ..write('<a class="button" href="/notes/new">${esc(l10n.webNewNote)}</a>')
      ..write('</div></div>');
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
      meta.write(_pin());
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
    final tint = _tintStyle(n.colorValue);
    final out =
        StringBuffer(
          _navRow(_back('/', l10n.webTabNotes), _editHref('/notes', n.id)),
        )..write(
          '<article class="note sheet${tint.isEmpty ? '' : ' tinted'}"$tint>',
        );
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
    if (n.tags.isNotEmpty) {
      out.write('<p class="note-meta">');
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
    final api = '/api/notes/${Uri.encodeComponent(n.id)}';
    return (
      title: display,
      main: out.toString(),
      attrs:
          'data-watch="${esc('$api/meta')}" data-check="${esc('$api/check')}" '
          'data-edit="${esc(_editHref('/notes', n.id))}" '
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
        interactive: true,
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
    bool interactive = false,
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
              interactive: interactive,
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
    final out = StringBuffer('<div class="title-row"><h1 class="page-title">')
      ..write(esc(l10n.webTabSparks))
      ..write('</h1>')
      ..write(
        '<form class="add-link" id="add-link">'
        '<input type="url" name="url" required '
        'placeholder="${esc(l10n.webAddLinkHint)}" '
        'aria-label="${esc(l10n.webAddLinkHint)}">'
        '<button type="submit" class="primary">${esc(l10n.webAddLink)}'
        '</button></form></div>',
      );
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
      out.write('<p class="card-meta">${_pin()}</p>');
    }
    out.write('</div></a>');
    return out.toString();
  }

  WebView spark(TweetCard c) {
    final out = StringBuffer(
      _navRow(_back('/sparks', l10n.webTabSparks), _editHref('/sparks', c.id)),
    )..write('<article class="spark-page sheet">');
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
        ..write(blocksHtml(c.blocks, interactive: true))
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
    final api = '/api/sparks/${Uri.encodeComponent(c.id)}';
    return (
      title: sparkTitle(c),
      main: out.toString(),
      attrs:
          'data-watch="${esc('$api/meta')}" data-check="${esc('$api/check')}" '
          'data-edit="${esc(_editHref('/sparks', c.id))}" '
          'data-updated="${c.updatedAt.millisecondsSinceEpoch}"',
    );
  }

  // ---- Editors ------------------------------------------------------------------

  /// The editor for a note: one rich editor per text block (images and link
  /// cards stay as they are, between them), or the Markdown source. [n] is
  /// null for a note not written yet, which is only added on its first save
  /// with something in it.
  WebView noteEditor(Note? n, {bool markdown = false}) {
    final isMarkdown = n?.markdown ?? markdown;
    final id = n?.id;
    final view = id == null ? '/' : '/notes/${Uri.encodeComponent(id)}';
    final canDelete = n != null && !n.inCircuit && n.bookId == null;
    return _editor(
      item: 'note',
      kind: isMarkdown ? 'markdown' : 'rich',
      id: id,
      base: n?.updatedAt,
      view: view,
      title: n?.title ?? '',
      blocks: n?.blocks ?? const [],
      deleteLabel: canDelete ? l10n.webDeleteNote : null,
      pageTitle: (n?.title.trim().isNotEmpty ?? false)
          ? n!.title.trim()
          : (isMarkdown ? l10n.webNewMarkdown : l10n.webNewNote),
    );
  }

  /// The editor for a spark's title and its own note.
  WebView sparkEditor(TweetCard c) {
    final view = '/sparks/${Uri.encodeComponent(c.id)}';
    return _editor(
      item: 'spark',
      kind: 'rich',
      id: c.id,
      base: c.updatedAt,
      view: view,
      title: c.noteTitle,
      blocks: c.blocks,
      deleteLabel: l10n.deleteCard,
      pageTitle: sparkTitle(c),
    );
  }

  WebView _editor({
    required String item,
    required String kind,
    required String? id,
    required DateTime? base,
    required String view,
    required String title,
    required List<NoteBlock> blocks,
    required String? deleteLabel,
    required String pageTitle,
  }) {
    final config = jsonEncode({
      'item': item,
      'kind': kind,
      'id': id,
      'base': base?.millisecondsSinceEpoch,
      'api': item == 'note' ? '/api/notes' : '/api/sparks',
      'view': view,
      'list': item == 'note' ? '/' : '/sparks',
      'strings': {
        'saving': l10n.webSaving,
        'saved': l10n.webSaved,
        'failed': l10n.webSaveFailed,
        'changed': l10n.webChangedOnPhone,
        'reload': l10n.webReload,
        'keep': l10n.webKeepEditing,
        'copy': l10n.webCopyText,
        'copied': l10n.copied,
        'tryAgain': l10n.webTryAgain,
        'deleteConfirm': l10n.deleteItemsConfirm(1),
        'linkPrompt': l10n.linkUrlHint,
      },
    });
    // Saving is automatic, so the bar needs only the save state and Done.
    final out = StringBuffer('<div class="nav-row edit-bar">')
      ..write(
        '<span class="save-state" id="save-state" aria-live="polite">'
        '</span><button type="button" class="primary" data-action="done">'
        '${esc(l10n.done)}</button></div>',
      )
      ..write(
        '<div class="edit-banner" id="edit-banner" hidden><span></span>'
        '<div class="edit-banner-actions"></div></div>',
      )
      ..write(
        '<article class="sheet editor" id="editor" '
        'data-config="${esc(config)}">',
      );
    if (kind == 'rich') out.write(_toolbar());
    out.write(
      '<input class="title-input" id="title-input" type="text" '
      'value="${esc(title)}" placeholder="${esc(l10n.addATitle)}" '
      'aria-label="${esc(l10n.addATitle)}"'
      '${kind == 'markdown' ? ' hidden' : ''}>',
    );
    if (kind == 'markdown') {
      final source = blocks.where((b) => b.isText).firstOrNull?.text ?? '';
      out
        ..write(
          '<div class="segmented md-mode">'
          '<button type="button" class="current" data-mode="write">'
          '${esc(l10n.webMarkdownSource)}</button>'
          '<button type="button" data-mode="preview">'
          '${esc(l10n.webPreview)}</button></div>',
        )
        ..write(
          '<textarea class="md-source" id="md-source" spellcheck="true" '
          'aria-label="${esc(l10n.webMarkdownSource)}">${esc(source)}'
          '</textarea>',
        )
        ..write(
          '<div class="note-body markdown md-preview" id="md-preview" '
          'hidden></div>',
        );
    } else {
      var anyText = false;
      for (final b in blocks) {
        if (b.isText) {
          anyText = true;
          out.write(
            '<div class="rich" data-block-id="${esc(b.id)}" '
            'data-delta="${esc(editorDelta(b.text))}"></div>',
          );
        } else if (b.isImage && b.imagePath.isNotEmpty) {
          out.write(
            '<figure class="note-img"><img src="'
            '${esc(_imgHref(b.imagePath))}" alt="" loading="lazy"></figure>',
          );
        } else if (b.isLink) {
          out.write(_linkCard(b));
        }
      }
      // Nothing to write in yet (a new note, a spark without a note): one
      // empty editor, saved as a new text block.
      if (!anyText) {
        out.write(
          '<div class="rich" data-delta="${esc(editorDelta(''))}">'
          '</div>',
        );
      }
    }
    out.write('</article>');
    if (deleteLabel != null) {
      out.write(
        '<p class="danger-row"><button type="button" class="danger" '
        'data-action="delete">${esc(deleteLabel)}</button></p>',
      );
    }
    return (title: pageTitle, main: out.toString(), attrs: 'data-edit-page');
  }

  /// The formatting bar, mirroring the phone's: paragraph style, inline
  /// marks, highlight and link, lists, quote, indent and alignment.
  String _toolbar() {
    String button(
      String format,
      String? value,
      String label,
      String icon, {
      String cls = '',
    }) =>
        '<button type="button" class="tool$cls" data-format="$format"'
        '${value == null ? '' : ' data-value="$value"'} '
        'title="${esc(label)}" aria-label="${esc(label)}">$icon</button>';
    const sep = '<span class="tool-sep" aria-hidden="true"></span>';
    return '<div class="toolbar" role="toolbar">'
        '${button('header', '', l10n.body, esc(l10n.body), cls: ' text')}'
        '${button('header', '1', l10n.heading, esc(l10n.heading), cls: ' text')}'
        '${button('header', '2', l10n.webSubheading, esc(l10n.subHeading), cls: ' text')}'
        '$sep'
        '${button('bold', null, l10n.bold, '<b>B</b>')}'
        '${button('italic', null, l10n.italic, '<i>I</i>')}'
        '${button('underline', null, l10n.underline, '<u>U</u>')}'
        '${button('strike', null, l10n.strikethrough, '<s>S</s>')}'
        '${button('highlight', null, l10n.highlight, _icon(_iconHighlight))}'
        '${button('link', null, l10n.hyperlink, _icon(_iconLink))}'
        '$sep'
        '${button('list', 'bullet', l10n.bulletList, _icon(_iconBullets))}'
        '${button('list', 'ordered', l10n.numberedList, _icon(_iconNumbers))}'
        '${button('list', 'unchecked', l10n.checklist, _icon(_iconChecklist))}'
        '${button('blockquote', null, l10n.quote, _icon(_iconQuote))}'
        '$sep'
        '${button('indent', '-1', l10n.indentDecrease, _icon(_iconOutdent))}'
        '${button('indent', '+1', l10n.indentIncrease, _icon(_iconIndent))}'
        '${button('align', '', l10n.alignLeft, _icon(_iconAlignLeft))}'
        '${button('align', 'center', l10n.alignCenter, _icon(_iconAlignCenter))}'
        '${button('align', 'right', l10n.alignRight, _icon(_iconAlignRight))}'
        '</div>';
  }

  static String _icon(String paths) =>
      '<svg viewBox="0 0 18 18" aria-hidden="true" fill="none" '
      'stroke="currentColor" stroke-width="1.6" stroke-linecap="round" '
      'stroke-linejoin="round">$paths</svg>';

  static const _iconHighlight =
      '<path d="M11.5 2.5l4 4-7 7H4.5v-4z"/><path d="M3 16h12"/>';
  static const _iconLink =
      '<path d="M7.5 10.5l3-3"/><path d="M8.5 5.5l1.2-1.2a3 3 0 0 1 4.2 4.2'
      'L12.5 9.7"/><path d="M9.5 12.5l-1.2 1.2a3 3 0 0 1-4.2-4.2L5.5 8.3"/>';
  static const _iconBullets =
      '<circle cx="3.5" cy="5" r=".9" fill="currentColor"/>'
      '<circle cx="3.5" cy="9" r=".9" fill="currentColor"/>'
      '<circle cx="3.5" cy="13" r=".9" fill="currentColor"/>'
      '<path d="M7 5h8M7 9h8M7 13h8"/>';
  static const _iconNumbers =
      '<path d="M2.5 3.5h1.5v3.5M2.5 7h3M2.5 10.5h2.4l-2.4 3h2.6"/>'
      '<path d="M8 5h7M8 9h7M8 13h7"/>';
  static const _iconChecklist =
      '<rect x="2" y="3" width="4.5" height="4.5" rx="1"/>'
      '<path d="M2.8 12.2l1.2 1.2 2-2.4"/><path d="M9 5.3h6.5M9 12.3h6.5"/>';
  static const _iconQuote =
      '<path d="M4 7.5h3v3.5H4zM4 7.5c0-2 1-3 3-3.5M11 7.5h3v3.5h-3z'
      'M11 7.5c0-2 1-3 3-3.5"/>';
  static const _iconOutdent =
      '<path d="M8 4h7M8 9h7M3 14h12"/><path d="M5 6.5L2.5 9 5 11.5"/>';
  static const _iconIndent =
      '<path d="M8 4h7M8 9h7M3 14h12"/><path d="M2.5 6.5L5 9l-2.5 2.5"/>';
  static const _iconAlignLeft = '<path d="M3 4h12M3 8h8M3 12h12M3 16h8"/>';
  static const _iconAlignCenter = '<path d="M3 4h12M5 8h8M3 12h12M5 16h8"/>';
  static const _iconAlignRight = '<path d="M3 4h12M7 8h8M3 12h12M7 16h8"/>';

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

  /// The row above a note or spark: its back button, and Edit.
  String _navRow(String back, String editHref) =>
      '<div class="nav-row">$back<a class="button tonal" '
      'href="${esc(editHref)}">${esc(l10n.editAction)}</a></div>';

  static String _editHref(String base, String id) =>
      '$base/${Uri.encodeComponent(id)}/edit';

  /// The back button above a note or spark: a chevron and the list's name.
  static String _back(String href, String label) =>
      '<a class="back" href="$href"><svg viewBox="0 0 10 16" aria-hidden="true">'
      '<path d="M8.5 1.5 2 8l6.5 6.5" fill="none" stroke="currentColor" '
      'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
      '</svg>${esc(label)}</a>';

  /// A small pushpin, for pinned notes and sparks.
  String _pin() =>
      '<svg class="pin" viewBox="0 0 12 12" role="img" '
      'aria-label="${esc(l10n.webPinned)}"><title>${esc(l10n.webPinned)}'
      '</title><circle cx="6" cy="4" r="3.2"/><path d="M5.2 6.6h1.6L6 11.6z"/>'
      '</svg>';

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
    return ' style="--note:${hex(r, g, b)};'
        '--note-dark:${hex(dark(r, 0x1E), dark(g, 0x20), dark(b, 0x28))}"';
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
