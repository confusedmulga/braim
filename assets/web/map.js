// Braim Web: the circuit map. The server draws the canvas; this pans and zooms
// it and runs each node's menu through the circuit API. Needs app.js.
(function () {
  'use strict';

  var main = document.querySelector('main[data-map]');
  var braim = window.braim;
  if (!main || !braim) return;

  var MIN = 0.15;
  var MAX = 2.5;
  var view = { x: 0, y: 0, s: 1 };
  var map, port, canvas;
  var S = {};
  var menu = null;

  function bind() {
    map = document.getElementById('map');
    port = document.getElementById('map-view');
    canvas = document.getElementById('map-canvas');
    S = JSON.parse(map.getAttribute('data-strings') || '{}');
  }

  function apply() {
    canvas.style.transform =
      'translate(' + view.x + 'px,' + view.y + 'px) scale(' + view.s + ')';
  }

  function clamp(s) { return Math.min(MAX, Math.max(MIN, s)); }

  // Zooms to [s], keeping the canvas point under (px, py) where it is.
  function zoomAt(px, py, s) {
    s = clamp(s);
    view.x = px - (px - view.x) * s / view.s;
    view.y = py - (py - view.y) * s / view.s;
    view.s = s;
    apply();
  }

  // Fits the nodes and their + buttons (not the canvas's empty margins),
  // never above full size.
  function fit() {
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    canvas.querySelectorAll('.node, .node-plus').forEach(function (n) {
      x0 = Math.min(x0, n.offsetLeft);
      y0 = Math.min(y0, n.offsetTop);
      x1 = Math.max(x1, n.offsetLeft + n.offsetWidth);
      y1 = Math.max(y1, n.offsetTop + n.offsetHeight);
    });
    if (x0 === Infinity) return;
    var w = port.clientWidth, h = port.clientHeight, pad = 32;
    var s = clamp(Math.min(1, (w - 2 * pad) / (x1 - x0), (h - 2 * pad) / (y1 - y0)));
    view = {
      s: s,
      x: (w - (x1 - x0) * s) / 2 - x0 * s,
      y: (h - (y1 - y0) * s) / 2 - y0 * s
    };
    apply();
  }

  function centre(node) {
    if (!node) return;
    view = {
      s: 1,
      x: port.clientWidth / 2 - (node.offsetLeft + node.offsetWidth / 2),
      y: port.clientHeight / 2 - (node.offsetTop + node.offsetHeight / 2)
    };
    apply();
  }

  function focusNode() {
    return canvas.querySelector('.node.focus') || canvas.querySelector('.node.root');
  }

  function inMap(e) { return port && port.contains(e.target); }

  // ---- Pan with a drag, zoom with the wheel, a pinch or the keys --------------

  var pointers = {};
  var drag = null, pinch = null, moved = false;

  function point(e) {
    var r = port.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  function pair() {
    var ids = Object.keys(pointers);
    var a = pointers[ids[0]], b = pointers[ids[1]];
    return {
      d: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)),
      m: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }
    };
  }

  main.addEventListener('pointerdown', function (e) {
    if (!inMap(e) || (e.pointerType === 'mouse' && e.button !== 0)) return;
    pointers[e.pointerId] = point(e);
    var count = Object.keys(pointers).length;
    if (count === 1) {
      drag = { id: e.pointerId, p: pointers[e.pointerId], x: view.x, y: view.y };
      moved = false;
    } else if (count === 2) {
      var p = pair();
      pinch = { d: p.d, m: p.m, s: view.s, x: view.x, y: view.y };
      drag = null;
      moved = true;
    }
  });

  main.addEventListener('pointermove', function (e) {
    if (!(e.pointerId in pointers)) return;
    var at = pointers[e.pointerId] = point(e);
    if (pinch && Object.keys(pointers).length > 1) {
      var p = pair();
      var s = clamp(pinch.s * p.d / pinch.d);
      view.x = p.m.x - (pinch.m.x - pinch.x) * s / pinch.s;
      view.y = p.m.y - (pinch.m.y - pinch.y) * s / pinch.s;
      view.s = s;
      apply();
    } else if (drag && drag.id === e.pointerId) {
      var dx = at.x - drag.p.x, dy = at.y - drag.p.y;
      if (!moved && Math.abs(dx) + Math.abs(dy) > 5) {
        moved = true;
        port.classList.add('dragging');
        try { port.setPointerCapture(e.pointerId); } catch (_) { /* gone */ }
      }
      if (moved) {
        view.x = drag.x + dx;
        view.y = drag.y + dy;
        apply();
      }
    }
  });

  function lift(e) {
    delete pointers[e.pointerId];
    var left = Object.keys(pointers).length;
    if (left < 2) pinch = null;
    if (!left) {
      drag = null;
      if (port) port.classList.remove('dragging');
    }
  }
  main.addEventListener('pointerup', lift);
  main.addEventListener('pointercancel', lift);

  // A drag that ends over a node must not open it.
  main.addEventListener('click', function (e) {
    if (moved && inMap(e)) {
      e.preventDefault();
      e.stopPropagation();
    }
    moved = false;
  }, true);
  main.addEventListener('dragstart', function (e) { if (inMap(e)) e.preventDefault(); });

  // A mouse wheel or a pinch (which arrives with ctrlKey) zooms; a trackpad's
  // two-finger scroll pans.
  main.addEventListener('wheel', function (e) {
    if (!inMap(e)) return;
    e.preventDefault();
    var lines = e.deltaMode !== 0;
    if (e.ctrlKey || lines || (e.deltaX === 0 && Math.abs(e.deltaY) >= 50)) {
      var p = point(e);
      var dy = lines ? e.deltaY * 40 : e.deltaY;
      zoomAt(p.x, p.y, view.s * Math.exp(-dy * (e.ctrlKey ? 0.01 : 0.002)));
    } else {
      view.x -= e.deltaX;
      view.y -= e.deltaY;
      apply();
    }
  }, { passive: false });

  main.addEventListener('keydown', function (e) {
    if (e.target !== port || e.ctrlKey || e.metaKey || e.altKey) return;
    var cx = port.clientWidth / 2, cy = port.clientHeight / 2;
    var pan = { ArrowLeft: [60, 0], ArrowRight: [-60, 0], ArrowUp: [0, 60], ArrowDown: [0, -60] }[e.key];
    if (pan) {
      view.x += pan[0];
      view.y += pan[1];
      apply();
    } else if (e.key === '+' || e.key === '=') zoomAt(cx, cy, view.s * 1.25);
    else if (e.key === '-' || e.key === '_') zoomAt(cx, cy, view.s / 1.25);
    else if (e.key === '0') fit();
    else return;
    e.preventDefault();
  });

  // ---- Buttons --------------------------------------------------------------------

  function nodeApi(id) { return '/api/circuits/nodes/' + encodeURIComponent(id); }

  main.addEventListener('click', function (e) {
    var b = e.target.closest('button');
    if (!b || !main.contains(b)) return;
    if (b.hasAttribute('data-view')) {
      if (b.getAttribute('data-view') === 'fit') fit();
      else centre(focusNode());
    } else if (b.hasAttribute('data-layout')) {
      send(map.getAttribute('data-layout-api'), { mode: b.getAttribute('data-layout') }, fit);
    } else if (b.hasAttribute('data-add')) {
      send(nodeApi(b.getAttribute('data-add')) + '/child', { markdown: false });
    } else if (b.hasAttribute('data-menu')) {
      openMenu(b.getAttribute('data-menu'), b);
    }
  });

  function offline() { braim.banner(braim.text('offline')); }

  // Posts a change. A new note opens in its editor and a deleted circuit
  // goes back to the list; anything else redraws the map, then runs [then].
  function send(url, data, then) {
    braim.post(url, data).then(function (res) {
      if (res.status === 401) { location.replace('/pair'); return; }
      return res.json().catch(function () { return {}; }).then(function (b) {
        if (!res.ok) {
          braim.banner(b.message || S.failed);
          refresh();
        } else if (b.go || b.edit) {
          location.href = b.go || b.edit;
        } else {
          refresh(then);
        }
      });
    }).catch(offline);
  }

  // ---- A node's menu --------------------------------------------------------------

  function closeMenu() {
    if (menu) menu.remove();
    menu = null;
  }

  document.addEventListener('pointerdown', function (e) {
    if (menu && !menu.contains(e.target)) closeMenu();
  }, true);

  document.addEventListener('keydown', function (e) {
    if (!menu) return;
    if (e.key === 'Escape') {
      closeMenu();
      e.preventDefault();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      var items = Array.prototype.slice.call(menu.querySelectorAll('button:not([disabled])'));
      var i = items.indexOf(document.activeElement) + (e.key === 'ArrowDown' ? 1 : -1);
      if (items.length) items[(i + items.length) % items.length].focus();
      e.preventDefault();
    }
  });

  function openMenu(id, anchor) {
    fetch(nodeApi(id) + '/menu', { credentials: 'same-origin' })
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (m) {
        if (!m) { refresh(); return; }
        closeMenu();
        menu = document.createElement('div');
        menu.className = 'menu-panel node-menu';
        menu.setAttribute('role', 'menu');
        var head = document.createElement('p');
        head.className = 'menu-head';
        head.textContent = m.title;
        menu.appendChild(head);
        m.items.forEach(function (it) {
          if (it.sep) { menu.appendChild(document.createElement('hr')); return; }
          var b = document.createElement('button');
          b.type = 'button';
          b.setAttribute('role', 'menuitem');
          b.textContent = it.label;
          if (it.danger) b.className = 'danger';
          b.disabled = !!it.disabled;
          b.addEventListener('click', function () { closeMenu(); run(m, it); });
          menu.appendChild(b);
        });
        document.body.appendChild(menu);
        var r = anchor.getBoundingClientRect();
        var top = r.bottom + 4;
        if (top + menu.offsetHeight > innerHeight - 8) top = Math.max(8, r.top - menu.offsetHeight - 4);
        menu.style.left = Math.max(8, Math.min(r.left, innerWidth - menu.offsetWidth - 16)) + 'px';
        menu.style.top = top + 'px';
        var first = menu.querySelector('button:not([disabled])');
        if (first) first.focus();
      })
      .catch(offline);
  }

  var paths = {
    sibling: '/sibling',
    child: '/child',
    move: '/move',
    write: '/write-placeholder',
    remove: '/remove-placeholder'
  };

  function run(m, it) {
    if (it.action === 'open') {
      location.href = m.open;
    } else if (it.action === 'rename') {
      braim.dialog({
        title: m.title,
        text: m.rename.title,
        input: true,
        value: m.rename.value,
        choices: [{ label: S.save, primary: true }]
      }).then(function (v) {
        if (v && v.trim()) send(m.api + '/rename', { title: v.trim() });
      });
    } else if (it.action === 'delete') {
      var d = m['delete'];
      braim.dialog({
        title: m.title,
        text: d.text,
        body: d.body,
        choices: d.choices.map(function (c) {
          return { label: c.label, value: c.mode, danger: c.danger };
        })
      }).then(function (mode) {
        if (mode) send(m.api + '/delete', { mode: mode, count: d.count });
      });
    } else if (paths[it.action]) {
      send(m.api + paths[it.action], it.send || {});
    }
  }

  // ---- Redrawing, keeping the view --------------------------------------------------

  function refresh(then) {
    fetch(location.pathname + '?partial=1', { credentials: 'same-origin' })
      .then(function (res) {
        if (res.status === 401) { location.replace('/pair'); return null; }
        if (res.status === 404) { braim.banner(braim.text('deleted')); return null; }
        return res.ok ? res.text() : null;
      })
      .then(function (html) {
        if (html === null || html === undefined) return;
        closeMenu();
        main.innerHTML = html;
        bind();
        apply();
        if (then) then();
      })
      .catch(function () {});
  }

  document.addEventListener('braim:changed', function () { refresh(); });

  bind();
  var focus = canvas.querySelector('.node.focus');
  if (focus) {
    centre(focus);
    focus.classList.add('flash');
  } else {
    fit();
  }
})();
