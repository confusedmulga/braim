// Braim Web's editor: one Quill per text block of a note or spark (images and
// link cards stay as they are), or a Markdown source box. Saves as you type,
// holds the item's edit lease while open, and never overwrites a change made
// on the phone. See docs/braim-web-plan.md, sections 9 and 11.
(function () {
  'use strict';

  var root = document.getElementById('editor');
  if (!root) return;
  var cfg = JSON.parse(root.getAttribute('data-config'));
  var S = cfg.strings;
  var meta = document.querySelector('meta[name="braim-csrf"]');
  var csrf = meta ? meta.getAttribute('content') : '';

  // Braim's formats, as the phone's editor stores them.
  var FORMATS = ['bold', 'italic', 'underline', 'strike', 'link', 'background',
    'color', 'header', 'blockquote', 'list', 'indent', 'align'];
  // A highlight is this background and ink together (note_body_editor.dart).
  var HL_BG = '#FFE082';
  var HL_INK = '#202124';

  var titleInput = document.getElementById('title-input');
  var stateEl = document.getElementById('save-state');
  var banner = document.getElementById('edit-banner');
  var mdSource = document.getElementById('md-source');
  var mdPreview = document.getElementById('md-preview');
  var tagsInput = document.getElementById('tags-input');
  var swatches = document.getElementById('swatches');
  var MAX_IMAGE = 10 * 1024 * 1024;

  var id = cfg.id;
  var base = cfg.base;
  var editors = [];
  var active = null;
  var dirty = false;
  var saving = null;
  var again = false;
  var locked = false;
  var conflicted = false;
  var navigating = false;
  var timer = null;

  function req(method, url, body, keepalive) {
    return fetch(url, {
      method: method,
      credentials: 'same-origin',
      keepalive: !!keepalive,
      headers: { 'Content-Type': 'application/json', 'X-Braim-CSRF': csrf },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
  }

  function itemUrl(suffix) {
    return cfg.api + '/' + encodeURIComponent(id) + (suffix || '');
  }

  function setState(text) { if (stateEl) stateEl.textContent = text || ''; }

  // ---- Banner --------------------------------------------------------------------

  function showBanner(text, actions) {
    banner.querySelector('span').textContent = text;
    var box = banner.querySelector('.edit-banner-actions');
    box.textContent = '';
    (actions || []).forEach(function (a) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = a[0];
      b.addEventListener('click', a[1]);
      box.appendChild(b);
    });
    banner.hidden = false;
  }

  function hideBanner() { banner.hidden = true; }

  function plainText() {
    var parts = [titleInput.value];
    if (cfg.kind === 'markdown') parts.push(mdSource.value);
    editors.forEach(function (e) { parts.push(e.quill.getText()); });
    return parts.filter(function (p) { return p.trim(); }).join('\n\n');
  }

  // navigator.clipboard needs a secure page, which plain HTTP isn't.
  function copyText() {
    var area = document.createElement('textarea');
    area.value = plainText();
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try { document.execCommand('copy'); setState(S.copied); } catch (e) { /* nothing more to try */ }
    document.body.removeChild(area);
  }

  function setLocked(on) {
    locked = on;
    editors.forEach(function (e) { e.quill.enable(!on); });
    titleInput.readOnly = on;
    if (tagsInput) tagsInput.readOnly = on;
    if (mdSource) mdSource.readOnly = on;
    root.classList.toggle('locked', on);
  }

  // Someone else is editing: read-only until they finish.
  function lock(message) {
    setLocked(true);
    showBanner(message, [[S.tryAgain, function () { location.reload(); }]]);
  }

  // The item changed since this page loaded: never overwrite it.
  function conflict(message) {
    conflicted = true;
    clearTimeout(timer);
    showBanner(message || S.changed, [
      [S.reload, function () { location.reload(); }],
      [S.copy, copyText]
    ]);
  }

  // ---- Saving ----------------------------------------------------------------------

  function isEmpty() {
    if (cfg.kind === 'markdown') return !mdSource.value.trim();
    if (titleInput.value.trim()) return false;
    return editors.every(function (e) { return !e.quill.getText().trim(); });
  }

  function blocks(withIds) {
    return editors.map(function (e) {
      var b = { delta: e.quill.getContents().ops };
      if (withIds && e.blockId) b.id = e.blockId;
      return b;
    });
  }

  // The note's tags and colour, when the page offers them.
  function withProps(b) {
    if (!cfg.props) return b;
    b.tags = [tagsInput.value];
    var on = swatches.querySelector('[aria-checked="true"]');
    var c = on ? on.getAttribute('data-color') : '';
    b.color = c ? Number(c) : null;
    return b;
  }

  function body() {
    if (!id) {
      return withProps(cfg.kind === 'markdown'
        ? { kind: 'markdown', source: mdSource.value }
        : { kind: 'rich', title: titleInput.value, blocks: blocks(false) });
    }
    if (cfg.kind === 'markdown') return withProps({ baseUpdatedAt: base, source: mdSource.value });
    return withProps({ baseUpdatedAt: base, title: titleInput.value, blocks: blocks(true) });
  }

  // The window and the tab say what the note is called once it has a title
  // (a Markdown note's is its first heading).
  function retitle() {
    var t = titleInput.value.trim();
    if (cfg.kind === 'markdown') {
      var m = /^\s*#\s+(.+)$/m.exec(mdSource.value);
      t = m ? m[1].trim() : '';
    }
    if (!t) return;
    var span = root.querySelector('.window-title > span');
    if (span) span.textContent = t;
    document.title = t;
  }

  function created(newId) {
    id = newId;
    var edit = (cfg.item === 'note' ? '/notes/' : '/sparks/') + encodeURIComponent(id);
    cfg.view = edit;
    history.replaceState(null, '', edit + '/edit');
    takeLease();
  }

  function adoptBlockIds(ids) {
    if (!ids || ids.length !== editors.length) return;
    editors.forEach(function (e, i) { e.blockId = ids[i]; });
  }

  // Saves now. Resolves true when saved (or nothing needed saving).
  function save(leaving) {
    clearTimeout(timer);
    if (locked || conflicted) return Promise.resolve(false);
    if (saving) { again = true; return saving; }
    if (!dirty) return Promise.resolve(true);
    // A note isn't created until it has something in it; an emptied Markdown
    // note is deleted only when you leave it, not while you retype it.
    if (isEmpty() && (!id || (cfg.kind === 'markdown' && !leaving))) {
      return Promise.resolve(true);
    }
    dirty = false;
    setState(S.saving);
    saving = req(id ? 'PUT' : 'POST', id ? itemUrl() : cfg.api, body())
      .then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (b) {
          if (res.status === 401) { location.replace('/pair'); return false; }
          if (res.status === 409 && b.error === 'leased') { lock(b.message); return false; }
          if (res.status === 409) { conflict(b.message); return false; }
          if (!res.ok) throw new Error(String(res.status));
          if (b.deleted) { navigating = true; location.replace(cfg.list); return false; }
          if (!id && b.id) created(b.id);
          if (b.updatedAt) base = b.updatedAt;
          adoptBlockIds(b.blockIds);
          retitle();
          setState(S.saved);
          return true;
        });
      })
      .catch(function () {
        dirty = true;
        setState(S.failed);
        return false;
      })
      .then(function (ok) {
        saving = null;
        if (again) { again = false; return save(leaving); }
        return ok;
      });
    return saving;
  }

  function changed() {
    if (locked || conflicted) return;
    dirty = true;
    setState('');
    clearTimeout(timer);
    timer = setTimeout(save, 1500);
  }

  function leave() {
    navigating = true;
    save(true).then(function (ok) {
      navigating = ok;
      if (ok) location.href = id ? cfg.view : cfg.list;
    });
  }

  // ---- The edit lease ----------------------------------------------------------------

  function takeLease() {
    if (!id) return;
    req('POST', itemUrl('/lease')).then(function (res) {
      if (res.status === 409) res.json().then(function (b) { lock(b.message); });
    }).catch(function () {});
  }

  setInterval(function () { if (id && !locked && !conflicted) takeLease(); }, 20000);
  window.addEventListener('pagehide', function () {
    if (id) req('DELETE', itemUrl('/lease'), undefined, true).catch(function () {});
  });
  window.addEventListener('beforeunload', function (e) {
    if (navigating) return;
    if ((dirty && !isEmpty()) || saving) { e.preventDefault(); e.returnValue = ''; }
  });

  // A change on the phone while this page is open (app.js relays it).
  document.addEventListener('braim:changed', function () {
    if (!id || saving || conflicted || locked) return;
    fetch(itemUrl('/meta'), { credentials: 'same-origin' }).then(function (res) {
      if (res.status === 404) {
        var deleted = document.getElementById('banner');
        setLocked(true);
        showBanner(deleted ? deleted.getAttribute('data-deleted') : S.changed);
        return null;
      }
      return res.ok ? res.json() : null;
    }).then(function (m) {
      if (!m || saving || m.updatedAt === base) return;
      showBanner(S.changed, [
        [S.reload, function () { location.reload(); }],
        [S.keep, hideBanner]
      ]);
    }).catch(function () {});
  });

  // ---- Rich text ---------------------------------------------------------------------

  function setUpRich() {
    root.querySelectorAll('.rich').forEach(function (el) {
      var q = new window.Quill(el, {
        formats: FORMATS,
        modules: { toolbar: false, history: { userOnly: true } }
      });
      q.setContents(JSON.parse(el.getAttribute('data-delta')), 'silent');
      q.history.clear();
      var entry = { quill: q, blockId: el.getAttribute('data-block-id') };
      q.on('text-change', function (d, old, source) { if (source === 'user') changed(); });
      q.on('selection-change', function (range) {
        if (range) { active = q; syncToolbar(); }
      });
      q.on('editor-change', function () { if (active === q) syncToolbar(); });
      editors.push(entry);
    });
    active = editors.length ? editors[0].quill : null;

    var bar = root.querySelector('.toolbar');
    // Keep the text selection when a tool is pressed.
    bar.addEventListener('mousedown', function (e) {
      if (e.target.closest('.tool')) e.preventDefault();
    });
    bar.addEventListener('click', function (e) {
      var b = e.target.closest('.tool');
      if (!b || locked || !active || !b.hasAttribute('data-format')) return;
      apply(b.getAttribute('data-format'), b.getAttribute('data-value'));
    });
  }

  function apply(f, v) {
    var q = active;
    if (!q.getSelection()) q.focus();
    var cur = q.getFormat();
    if (f === 'highlight') {
      var on = !!cur.background;
      q.format('background', on ? false : HL_BG, 'user');
      q.format('color', on ? false : HL_INK, 'user');
    } else if (f === 'link') {
      if (cur.link) {
        q.format('link', false, 'user');
      } else {
        var url = (window.prompt(S.linkPrompt, 'https://') || '').trim();
        if (/^(https?:\/\/|mailto:)\S+$/i.test(url)) q.format('link', url, 'user');
      }
    } else if (f === 'header') {
      q.format('header', v ? Number(v) : false, 'user');
    } else if (f === 'list') {
      var isOn = cur.list === v || (v === 'unchecked' && cur.list === 'checked');
      q.format('list', isOn ? false : v, 'user');
    } else if (f === 'indent') {
      q.format('indent', v, 'user');
    } else if (f === 'align') {
      q.format('align', v || false, 'user');
    } else {
      q.format(f, !cur[f], 'user');
    }
    syncToolbar();
  }

  function syncToolbar() {
    if (!active) return;
    var sel = active.getSelection();
    var cur = sel ? active.getFormat(sel) : {};
    root.querySelectorAll('.tool[data-format]').forEach(function (b) {
      var f = b.getAttribute('data-format');
      var v = b.getAttribute('data-value');
      var on;
      if (f === 'highlight') on = !!cur.background;
      else if (f === 'header') on = String(cur.header || '') === v;
      else if (f === 'list') on = cur.list === v || (v === 'unchecked' && cur.list === 'checked');
      else if (f === 'align') on = (cur.align || '') === v;
      else if (f === 'indent') on = false;
      else on = !!cur[f];
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }

  // ---- Tags, colour and photos ----------------------------------------------------------

  function setUpProps() {
    if (!cfg.props) return;
    tagsInput.addEventListener('input', changed);
    swatches.addEventListener('click', function (e) {
      var b = e.target.closest('.swatch');
      if (!b || locked) return;
      swatches.querySelectorAll('.swatch').forEach(function (o) {
        o.setAttribute('aria-checked', o === b ? 'true' : 'false');
      });
      changed();
    });
  }

  // Saves what is typed, then sends [files] one by one, then reloads to show
  // them in place (the server adds a line to write on after each).
  function uploadImages(files) {
    if (!id || locked || conflicted) return;
    var list = Array.prototype.slice.call(files);
    var fits = list.filter(function (f) { return f.size <= MAX_IMAGE; });
    if (fits.length < list.length) setState(S.imageTooBig);
    if (!fits.length) return;
    save().then(function (ok) {
      if (!ok) return;
      setState(S.saving);
      var added = 0;
      var chain = Promise.resolve(true);
      fits.forEach(function (f) {
        chain = chain.then(function (going) {
          if (!going) return false;
          return fetch(itemUrl('/images'), {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': f.type || 'application/octet-stream', 'X-Braim-CSRF': csrf },
            body: f
          }).then(function (res) {
            if (res.ok) { added++; return true; }
            return res.json().catch(function () { return {}; }).then(function (b) {
              if (res.status === 401) location.replace('/pair');
              else if (res.status === 413) setState(S.imageTooBig);
              else if (b.error === 'leased') lock(b.message);
              else setState(b.message || S.failed);
              return false;
            });
          });
        });
      });
      chain.catch(function () { setState(S.failed); }).then(function () {
        if (added) { navigating = true; location.reload(); }
      });
    });
  }

  function removeImage(blockId) {
    if (!id || locked || conflicted) return;
    save().then(function (ok) {
      if (!ok) return;
      req('DELETE', itemUrl('/images/' + encodeURIComponent(blockId))).then(function (res) {
        if (res.ok) { navigating = true; location.reload(); return; }
        return res.json().catch(function () { return {}; }).then(function (b) {
          if (b.error === 'leased') lock(b.message);
          else setState(S.failed);
        });
      }).catch(function () { setState(S.failed); });
    });
  }

  function setUpImages() {
    var input = document.getElementById('image-input');
    var tool = root.querySelector('[data-action="add-image"]');
    if (input && tool) {
      tool.addEventListener('click', function () { if (!locked) input.click(); });
      input.addEventListener('change', function () {
        uploadImages(input.files);
        input.value = '';
      });
    }
    root.addEventListener('click', function (e) {
      var b = e.target.closest('[data-remove-image]');
      if (b) removeImage(b.getAttribute('data-remove-image'));
    });
  }

  // ---- Markdown ------------------------------------------------------------------------

  function setUpMarkdown() {
    mdSource.addEventListener('input', changed);
    root.querySelectorAll('.md-mode button').forEach(function (b) {
      b.addEventListener('click', function () {
        var preview = b.getAttribute('data-mode') === 'preview';
        root.querySelectorAll('.md-mode button').forEach(function (o) {
          o.classList.toggle('current', o === b);
        });
        mdSource.hidden = preview;
        mdPreview.hidden = !preview;
        if (!preview) { mdSource.focus(); return; }
        req('POST', '/api/markdown/preview', { source: mdSource.value })
          .then(function (res) { return res.ok ? res.json() : null; })
          .then(function (b2) { if (b2) mdPreview.innerHTML = b2.html; })
          .catch(function () {});
      });
    });
  }

  // ---- Start ------------------------------------------------------------------------------

  if (cfg.kind === 'markdown') setUpMarkdown();
  else setUpRich();
  setUpProps();
  setUpImages();
  titleInput.addEventListener('input', changed);
  takeLease();

  document.querySelectorAll('[data-action="done"]').forEach(function (b) {
    b.addEventListener('click', leave);
  });
  document.querySelectorAll('[data-action="delete"]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!id || locked) return;
      var ask = window.braim
        ? window.braim.dialog({ text: S.deleteConfirm, choices: [{ label: b.textContent, danger: true }] })
        : Promise.resolve(window.confirm(S.deleteConfirm));
      ask.then(function (ok) {
        if (!ok) return;
        clearTimeout(timer);
        dirty = false;
        req('DELETE', itemUrl()).then(function (res) {
          if (res.ok) { navigating = true; location.replace(cfg.list); return; }
          return res.json().then(function (b2) { if (b2.error === 'leased') lock(b2.message); });
        }).catch(function () { setState(S.failed); });
      });
    });
  });

  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
      e.preventDefault();
      dirty = dirty || !id;
      save();
    } else if (e.key === 'Escape' && !e.defaultPrevented) {
      leave();
    }
  });

  if (cfg.kind === 'markdown') mdSource.focus();
  else if (!titleInput.value && editors.length) titleInput.focus();
})();
