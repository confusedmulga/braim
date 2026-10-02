// Braim Web: the small script every page loads. No framework, no build step.
(function () {
  'use strict';

  var csrfMeta = document.querySelector('meta[name="braim-csrf"]');
  var csrf = csrfMeta ? csrfMeta.getAttribute('content') : '';

  function post(url, data) {
    return fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', 'X-Braim-CSRF': csrf },
      body: JSON.stringify(data || {})
    });
  }

  // ---- Pairing --------------------------------------------------------------

  function setUpPairing(form) {
    var boxes = Array.prototype.slice.call(form.querySelectorAll('.digit'));
    var msg = document.getElementById('pair-msg');
    var busy = false;

    function code() {
      return boxes.map(function (b) { return b.value; }).join('');
    }

    function fill(digits, from) {
      for (var i = 0; i < digits.length && from + i < boxes.length; i++) {
        boxes[from + i].value = digits[i];
      }
      var next = Math.min(from + digits.length, boxes.length - 1);
      boxes[next].focus();
      if (code().length === boxes.length) submit();
    }

    function clear() {
      boxes.forEach(function (b) { b.value = ''; });
      boxes[0].focus();
    }

    function submit() {
      var c = code();
      if (busy || !/^[0-9]{6}$/.test(c)) return;
      busy = true;
      msg.textContent = '';
      post('/api/pair', { code: c })
        .then(function (res) {
          if (res.ok) {
            location.replace('/');
            return;
          }
          return res.json().then(function (body) {
            msg.textContent = (body && body.message) || '';
            clear();
          });
        })
        .catch(function () {
          msg.textContent = form.getAttribute('data-offline') || '';
        })
        .then(function () { busy = false; });
    }

    boxes.forEach(function (box, i) {
      // Typing into a filled box replaces its digit.
      box.addEventListener('focus', function () { box.select(); });
      box.addEventListener('input', function () {
        var digits = box.value.replace(/[^0-9]/g, '');
        box.value = '';
        if (digits) fill(digits.split(''), i);
      });
      box.addEventListener('keydown', function (e) {
        if (e.key === 'Backspace' && !box.value && i > 0) {
          boxes[i - 1].value = '';
          boxes[i - 1].focus();
          e.preventDefault();
        } else if (e.key === 'ArrowLeft' && i > 0) {
          boxes[i - 1].focus();
        } else if (e.key === 'ArrowRight' && i < boxes.length - 1) {
          boxes[i + 1].focus();
        }
      });
      box.addEventListener('paste', function (e) {
        var text = (e.clipboardData || window.clipboardData).getData('text');
        var digits = (text || '').replace(/[^0-9]/g, '');
        if (!digits) return;
        e.preventDefault();
        fill(digits.split(''), i);
      });
    });

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      submit();
    });
    boxes[0].focus();
  }

  // ---- Log out ---------------------------------------------------------------

  function setUpLogout(button) {
    button.addEventListener('click', function () {
      button.disabled = true;
      post('/api/logout')
        .catch(function () {})
        .then(function () { location.replace('/pair'); });
    });
  }

  // ---- Live updates ------------------------------------------------------------
  // One event stream per tab. On a change, a list page refetches its own main
  // area; a view page checks its item and reloads only if it changed.

  var main = document.querySelector('main');
  var banner = document.getElementById('banner');
  var dot = document.getElementById('conn');

  function showBanner(text) {
    if (!banner) return;
    banner.textContent = text || '';
    banner.hidden = !text;
  }

  function withPartial(url) {
    return url + (url.indexOf('?') < 0 ? '?' : '&') + 'partial=1';
  }

  function refreshList() {
    fetch(withPartial(location.pathname + location.search),
      { credentials: 'same-origin' })
      .then(function (res) {
        if (res.status === 401) { location.replace('/pair'); return null; }
        return res.ok ? res.text() : null;
      })
      .then(function (html) {
        if (html === null || html === undefined) return;
        // Keep a half-typed link or title, and its focus, across the swap.
        var kept = {};
        var active = document.activeElement;
        var focused = active && active.form && active.form.id ? active.form.id : null;
        main.querySelectorAll('form[id] input[name]').forEach(function (i) {
          kept[i.form.id + ' ' + i.name] = i.value;
        });
        main.innerHTML = html;
        main.querySelectorAll('form[id] input[name]').forEach(function (i) {
          var v = kept[i.form.id + ' ' + i.name];
          if (v) i.value = v;
          if (i.form.id === focused) i.focus();
        });
      })
      .catch(function () {});
  }

  function checkView() {
    var url = main.getAttribute('data-watch');
    fetch(url, { credentials: 'same-origin' })
      .then(function (res) {
        if (res.status === 401) { location.replace('/pair'); return null; }
        if (res.status === 404) {
          showBanner(banner.getAttribute('data-deleted'));
          return null;
        }
        return res.ok ? res.json() : null;
      })
      .then(function (meta) {
        if (meta && String(meta.updatedAt) !== main.getAttribute('data-updated')) {
          location.reload();
        }
      })
      .catch(function () {});
  }

  function onChanged() {
    // Edit pages decide for themselves (editor.js); they never reload.
    document.dispatchEvent(new CustomEvent('braim:changed'));
    if (!main) return;
    if (main.hasAttribute('data-list')) refreshList();
    else if (main.hasAttribute('data-watch')) checkView();
  }

  // ---- Ticking a checklist on a note or spark page ----------------------------

  function setUpTicks() {
    var url = main && main.getAttribute('data-check');
    if (!url) return;
    main.addEventListener('change', function (e) {
      var box = e.target;
      if (!box.matches('input[type=checkbox][data-line]')) return;
      box.disabled = true;
      post(url, {
        block: Number(box.getAttribute('data-block')),
        line: Number(box.getAttribute('data-line')),
        baseUpdatedAt: Number(main.getAttribute('data-updated'))
      }).then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (b) {
          if (res.ok) {
            main.setAttribute('data-updated', String(b.updatedAt));
            var li = box.closest('li');
            if (li) li.classList.toggle('done', box.checked);
            return;
          }
          if (res.status === 401) { location.replace('/pair'); return; }
          box.checked = !box.checked;
          showBanner(b.message || '');
        });
      }).catch(function () {
        box.checked = !box.checked;
        showBanner(banner.getAttribute('data-offline'));
      }).then(function () { box.disabled = false; });
    });
  }

  // ---- Adding a spark or a circuit ----------------------------------------------
  // Listened for on the document: a list page's live refresh replaces its forms.

  function offline() { showBanner(banner.getAttribute('data-offline')); }

  // Posts [data] to [url] and hands the reply's JSON to [then], with a banner
  // for a failure. [button] is disabled meanwhile.
  function act(url, data, button, then) {
    if (button) button.disabled = true;
    return post(url, data).then(function (res) {
      if (res.status === 401) { location.replace('/pair'); return; }
      return res.json().catch(function () { return {}; }).then(function (body) {
        if (res.ok) then(body);
        else showBanner(body.message || banner.getAttribute('data-failed'));
      });
    }).catch(offline).then(function () { if (button) button.disabled = false; });
  }

  document.addEventListener('submit', function (e) {
    var form = e.target;
    var input = form.querySelector('input');
    if (form.id === 'add-link') {
      e.preventDefault();
      act('/api/sparks', { url: input.value.trim() }, form.querySelector('button'),
        function () { input.value = ''; refreshList(); });
    } else if (form.id === 'new-circuit') {
      e.preventDefault();
      if (!input.value.trim()) return;
      act('/api/circuits', { title: input.value.trim() }, form.querySelector('button'),
        function (body) { location.href = body.edit; });
    }
  });

  // A circuit note's "+ Next to this note" and "+ Under this note" show the
  // new note on the map; a book's Add chapter opens the new chapter; a page's
  // up and down arrows redraw the contents.
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-circuit-add], [data-book-add], [data-book-move]');
    if (!b) return;
    if (b.hasAttribute('data-circuit-add')) {
      act(b.getAttribute('data-circuit-add'), { markdown: false }, b,
        function (body) { location.href = body.map; });
    } else if (b.hasAttribute('data-book-add')) {
      act(b.getAttribute('data-book-add'), {}, b,
        function (body) { location.href = body.edit; });
    } else {
      act(b.getAttribute('data-book-move'), { delta: Number(b.getAttribute('data-delta')) }, b,
        refreshList);
    }
  });

  // ---- Dialogs: a window on the desk, as the old system drew them --------------
  // o: {title, text, body, input, value, choices: [{label, value, primary,
  // danger}]}. Resolves with the chosen value (the typed text, for an input
  // dialog), or null for Cancel and Esc.

  function dialog(o) {
    return new Promise(function (resolve) {
      var opener = document.activeElement;
      var back = document.createElement('div');
      back.className = 'modal';
      back.innerHTML = '<div class="window dialog" role="dialog" aria-modal="true" ' +
        'aria-labelledby="dialog-title"><header class="titlebar"><h1 class="window-title" ' +
        'id="dialog-title"><span></span></h1></header><div class="window-body"></div></div>';
      back.querySelector('.window-title span').textContent = o.title || document.title;
      var body = back.querySelector('.window-body');
      function para(cls, text) {
        if (!text) return;
        var p = document.createElement('p');
        p.className = cls;
        p.textContent = text;
        body.appendChild(p);
      }
      para('alert-text', o.text);
      para('alert-body', o.body);
      var input = null;
      if (o.input) {
        input = document.createElement('input');
        input.type = 'text';
        input.className = 'dialog-input';
        input.maxLength = 200;
        input.value = o.value || '';
        body.appendChild(input);
      }
      var row = document.createElement('p');
      row.className = 'alert-actions';
      body.appendChild(row);

      function close(value) {
        document.removeEventListener('keydown', onKey, true);
        back.remove();
        if (opener && opener.focus) opener.focus();
        resolve(value);
      }
      function addButton(label, cls, value) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = cls;
        b.textContent = label;
        b.addEventListener('click', function () {
          close(value === null ? null : (input ? input.value : value));
        });
        row.appendChild(b);
        return b;
      }
      var cancel = addButton(banner ? banner.getAttribute('data-cancel') : 'Cancel', '', null);
      var last = cancel;
      (o.choices || []).forEach(function (c) {
        last = addButton(c.label, c.danger ? 'danger' : (c.primary ? 'primary' : ''),
          c.value === undefined ? true : c.value);
      });

      function onKey(e) {
        if (e.key === 'Escape') {
          e.preventDefault();
          close(null);
        } else if (e.key === 'Enter' && e.target === input) {
          e.preventDefault();
          last.click();
        } else if (e.key === 'Tab') {
          // Keep the focus inside the dialog.
          var stops = back.querySelectorAll('input, button');
          var first = stops[0];
          var end = stops[stops.length - 1];
          if (e.shiftKey && document.activeElement === first) { e.preventDefault(); end.focus(); }
          else if (!e.shiftKey && document.activeElement === end) { e.preventDefault(); first.focus(); }
        }
      }
      document.addEventListener('keydown', onKey, true);
      back.addEventListener('mousedown', function (e) { if (e.target === back) close(null); });
      document.body.appendChild(back);
      if (input) { input.focus(); input.select(); } else cancel.focus();
    });
  }

  // For map.js and editor.js.
  window.braim = {
    post: post,
    dialog: dialog,
    banner: showBanner,
    text: function (key) { return banner ? banner.getAttribute('data-' + key) || '' : ''; }
  };

  var source = null;
  var lastConnected = Date.now();
  var offlineTimer = null;

  function connected(on) {
    if (dot) dot.classList.toggle('on', on);
    if (on) {
      lastConnected = Date.now();
      if (banner && banner.textContent === banner.getAttribute('data-offline')) {
        showBanner('');
      }
    }
  }

  function watchOffline() {
    if (offlineTimer) return;
    offlineTimer = setInterval(function () {
      if (dot && dot.classList.contains('on')) return;
      if (Date.now() - lastConnected >= 60000) {
        showBanner(banner.getAttribute('data-offline'));
      }
    }, 5000);
  }

  function connect() {
    if (!window.EventSource || !dot) return;
    source = new EventSource('/api/events');
    source.addEventListener('open', function () { connected(true); });
    source.addEventListener('changed', onChanged);
    source.addEventListener('error', function () {
      connected(false);
      watchOffline();
      if (source.readyState !== EventSource.CLOSED) return; // it retries itself
      // Refused outright: logged out on the phone, or the server went away.
      post('/api/ping')
        .then(function (res) {
          if (res.status === 401) location.replace('/pair');
          else setTimeout(connect, 5000);
        })
        .catch(function () { setTimeout(connect, 5000); });
    });
  }

  // While someone is looking at the tab, Braim Web stays on (30-minute auto-off).
  function ping() {
    if (document.visibilityState === 'visible') post('/api/ping').catch(function () {});
  }

  // ---- Start ---------------------------------------------------------------------

  var pairForm = document.getElementById('pair-form');
  if (pairForm) setUpPairing(pairForm);
  setUpTicks();
  document.querySelectorAll('[data-action="logout"]').forEach(setUpLogout);

  if (csrf) {
    connect();
    setInterval(ping, 5 * 60 * 1000);
    document.addEventListener('visibilitychange', ping);
  }

  // Keys: "/" searches, "e" edits the open note or spark.
  var search = document.querySelector('.search input');

  // ---- The File menu: a <details>, closed by a click elsewhere or Esc --------
  var menu = document.querySelector('details.menu');
  if (menu) {
    document.addEventListener('click', function (e) {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape' || !menu.open) return;
      e.preventDefault();
      menu.open = false;
      menu.querySelector('summary').focus();
    });
    var find = menu.querySelector('[data-action="find"]');
    if (find) {
      find.addEventListener('click', function () {
        menu.open = false;
        if (search) { search.focus(); search.select(); }
      });
    }
  }
  // File > Add a link and File > New circuit.
  var field = { '#add': '#add-link input', '#new': '#new-circuit input' }[location.hash];
  if (field && document.querySelector(field)) document.querySelector(field).focus();
  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    var t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    var edit = main && main.getAttribute('data-edit');
    if (e.key === '/' && search) {
      e.preventDefault();
      search.focus();
      search.select();
    } else if ((e.key === 'e' || e.key === 'E') && edit) {
      e.preventDefault();
      location.href = edit;
    }
  });
})();
