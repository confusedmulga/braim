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
      .then(function (html) { if (html !== null && html !== undefined) main.innerHTML = html; })
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
    if (!main) return;
    if (main.hasAttribute('data-list')) refreshList();
    else if (main.hasAttribute('data-watch')) checkView();
  }

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
  document.querySelectorAll('[data-action="logout"]').forEach(setUpLogout);

  if (csrf) {
    connect();
    setInterval(ping, 5 * 60 * 1000);
    document.addEventListener('visibilitychange', ping);
  }

  var search = document.querySelector('.search input');
  document.addEventListener('keydown', function (e) {
    if (e.key !== '/' || !search || e.ctrlKey || e.metaKey || e.altKey) return;
    var t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    e.preventDefault();
    search.focus();
    search.select();
  });
})();
