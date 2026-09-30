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

  var pairForm = document.getElementById('pair-form');
  if (pairForm) setUpPairing(pairForm);
  document.querySelectorAll('[data-action="logout"]').forEach(setUpLogout);
})();
