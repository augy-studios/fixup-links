/* Theme system: 7 brand colour swatches + light/dark mode.
   Default is always light + classic (#ccffcc), regardless of OS preference.
   Once the user picks something, it is persisted. */
'use strict';

(function () {
  var APP_KEY = 'uwufix';

  var COLOR_THEMES = [
    { id: 'classic', label: 'Classic', hex: '#ccffcc' },
    { id: 'not-green-1', label: 'Not green 1', hex: '#ffcccc' },
    { id: 'not-green-2', label: 'Not green 2', hex: '#ccccff' },
    { id: 'not-green-3', label: 'Not green 3', hex: '#ffffcc' },
    { id: 'not-green-4', label: 'Not green 4', hex: '#ffccff' },
    { id: 'not-green-5', label: 'Not green 5', hex: '#ccffff' },
    { id: 'really-light-green', label: 'Really really light green', hex: '#ffffff' },
  ];

  var STORAGE_KEY_COLOR = APP_KEY + '.colorTheme';
  var STORAGE_KEY_MODE = APP_KEY + '.mode';

  // Pre-v22 key, single axis, different ids. Mapped once then dropped.
  var LEGACY_KEY = 'uwufix_theme';
  var LEGACY_MAP = {
    classic: 'classic',
    notgreen1: 'not-green-1',
    notgreen2: 'not-green-2',
    notgreen3: 'not-green-3',
    notgreen4: 'not-green-4',
    notgreen5: 'not-green-5',
    white: 'really-light-green',
  };

  function migrateLegacyTheme() {
    try {
      var legacy = localStorage.getItem(LEGACY_KEY);
      if (!legacy) return;
      if (!localStorage.getItem(STORAGE_KEY_COLOR) && LEGACY_MAP[legacy]) {
        localStorage.setItem(STORAGE_KEY_COLOR, LEGACY_MAP[legacy]);
      }
      localStorage.removeItem(LEGACY_KEY);
    } catch (e) {
      /* storage unavailable, fall back to defaults */
    }
  }

  function hexToRgb(hex) {
    var n = parseInt(hex.replace('#', ''), 16);
    return ((n >> 16) & 255) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255);
  }

  function getStoredColorTheme() {
    try {
      return localStorage.getItem(STORAGE_KEY_COLOR) || 'classic';
    } catch (e) {
      return 'classic';
    }
  }

  function getStoredMode() {
    try {
      return localStorage.getItem(STORAGE_KEY_MODE) || 'light';
    } catch (e) {
      return 'light';
    }
  }

  function applyColorTheme(id) {
    var theme = COLOR_THEMES.filter(function (t) { return t.id === id; })[0] || COLOR_THEMES[0];
    document.documentElement.setAttribute('data-color-theme', theme.id);
    document.documentElement.style.setProperty('--brand', theme.hex);
    document.documentElement.style.setProperty('--brand-rgb', hexToRgb(theme.hex));
    try { localStorage.setItem(STORAGE_KEY_COLOR, theme.id); } catch (e) {}
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', theme.hex);
    return theme;
  }

  function applyMode(mode) {
    var resolved = mode === 'dark' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-mode', resolved);
    try { localStorage.setItem(STORAGE_KEY_MODE, resolved); } catch (e) {}
    return resolved;
  }

  function initTheme() {
    migrateLegacyTheme();
    applyColorTheme(getStoredColorTheme());
    applyMode(getStoredMode());
  }

  /* ---- modal wiring ---- */

  function buildThemeModal() {
    var grid = document.getElementById('swatchGrid');
    if (!grid) return;

    grid.innerHTML = COLOR_THEMES.map(function (t) {
      return '<button class="swatch" data-theme-id="' + t.id + '" style="--swatch-color:' + t.hex + '" type="button" aria-label="' + t.label + '">' +
        '<span class="swatch-dot"></span>' +
        '<span class="swatch-label">' + t.label + '</span>' +
        '</button>';
    }).join('');

    syncThemeModalState();

    grid.addEventListener('click', function (e) {
      var btn = e.target.closest('[data-theme-id]');
      if (!btn) return;
      applyColorTheme(btn.dataset.themeId);
      syncThemeModalState();
    });

    document.getElementById('modeToggle').addEventListener('click', function (e) {
      var btn = e.target.closest('[data-mode]');
      if (!btn) return;
      applyMode(btn.dataset.mode);
      syncThemeModalState();
    });
  }

  function syncThemeModalState() {
    var activeTheme = getStoredColorTheme();
    var activeMode = getStoredMode();
    document.querySelectorAll('#swatchGrid .swatch').forEach(function (el) {
      var on = el.dataset.themeId === activeTheme;
      el.classList.toggle('active', on);
      el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    document.querySelectorAll('#modeToggle .mode-btn').forEach(function (el) {
      var on = el.dataset.mode === activeMode;
      el.classList.toggle('active', on);
      el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    updateThemeButtonIcon();
  }

  function updateThemeButtonIcon() {
    var span = document.querySelector('#themeBtn [data-icon]');
    if (!span) return;
    span.setAttribute('data-icon', getStoredMode() === 'dark' ? 'moon' : 'sun');
    window.hydrateIcons(document.getElementById('themeBtn'));
  }

  function wireModals() {
    document.querySelectorAll('[data-close-modal]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        window.closeModal(btn.dataset.closeModal);
      });
    });
    document.querySelectorAll('.modal-backdrop').forEach(function (backdrop) {
      backdrop.addEventListener('click', function (e) {
        if (e.target === backdrop) window.closeModal(backdrop.id);
      });
    });
    var themeBtn = document.getElementById('themeBtn');
    if (themeBtn) {
      themeBtn.addEventListener('click', function () { window.openModal('themeModal'); });
    }
  }

  // Attributes are already set by the pre-paint script in <head>; this
  // re-applies them so the inline --brand and theme-color meta stay in sync.
  initTheme();

  document.addEventListener('DOMContentLoaded', function () {
    window.hydrateIcons();
    updateThemeButtonIcon();
    buildThemeModal();
    wireModals();
  });

  window.COLOR_THEMES = COLOR_THEMES;
  window.applyColorTheme = applyColorTheme;
  window.applyMode = applyMode;
  window.getStoredColorTheme = getStoredColorTheme;
  window.getStoredMode = getStoredMode;
  window.initTheme = initTheme;
})();
