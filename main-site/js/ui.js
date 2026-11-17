/* Shared UI helpers: icon hydration and modal show/hide. */
'use strict';

(function () {
  // Safe to call repeatedly; re-renders when data-icon changes.
  function hydrateIcons(root) {
    let searchRoot = root;
    if (!searchRoot) {
      searchRoot = document;
    }
    searchRoot.querySelectorAll('[data-icon]').forEach(function (element) {
      var name = element.dataset.icon;
      if (element.dataset.iconRendered === name) {
        return;
      }
      element.innerHTML = window.icon(name);
      element.dataset.iconRendered = name;
    });
  }

  // Windows open and close. History and Share history are places of their own, so each change
  // is a pagechange for the tours (js/tour.js).
  function openModal(id) {
    const modal = document.getElementById(id);
    const wasHidden = modal.classList.contains('hidden');
    modal.classList.remove('hidden');
    document.body.classList.add('modal-open');
    if (wasHidden) {
      dispatchEvent(new CustomEvent('pagechange'));
    }
  }

  function closeModal(id) {
    const modal = document.getElementById(id);
    if (!modal) {
      return;
    }
    const wasOpen = !modal.classList.contains('hidden');
    modal.classList.add('hidden');
    if (!document.querySelector('.modal-backdrop:not(.hidden)')) {
      document.body.classList.remove('modal-open');
    }
    if (wasOpen) {
      dispatchEvent(new CustomEvent('pagechange'));
    }
  }

  window.hydrateIcons = hydrateIcons;
  window.openModal = openModal;
  window.closeModal = closeModal;
})();
