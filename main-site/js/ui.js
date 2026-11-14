/* Shared UI helpers: icon hydration and modal show/hide. */
'use strict';

(function () {
  // Safe to call repeatedly; re-renders when data-icon changes.
  function hydrateIcons(root) {
    (root || document).querySelectorAll('[data-icon]').forEach(function (el) {
      var name = el.dataset.icon;
      if (el.dataset.iconRendered === name) return;
      el.innerHTML = window.icon(name);
      el.dataset.iconRendered = name;
    });
  }

  // Windows open and close. History and Share history are places of their own, so each change
  // is a pagechange for the tours (js/tour.js).
  function openModal(id) {
    const m = document.getElementById(id);
    const was = m.classList.contains('hidden');
    m.classList.remove('hidden');
    document.body.classList.add('modal-open');
    if (was) dispatchEvent(new CustomEvent('pagechange'));
  }

  function closeModal(id) {
    const m = document.getElementById(id);
    if (!m) return;
    const was = !m.classList.contains('hidden');
    m.classList.add('hidden');
    if (!document.querySelector('.modal-backdrop:not(.hidden)')) {
      document.body.classList.remove('modal-open');
    }
    if (was) dispatchEvent(new CustomEvent('pagechange'));
  }

  window.hydrateIcons = hydrateIcons;
  window.openModal = openModal;
  window.closeModal = closeModal;
})();
