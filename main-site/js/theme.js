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

  /* Mode preference and mode are different things. The preference is what the
     person chose and can be "time"; the mode is what the document is in and
     is only ever light or dark. */

  var MODE_PREFERENCES = ['light', 'dark', 'time'];

  /* The daylight window. Duplicated in the pre-paint script in index.html's
     head, which has to resolve this before first paint and cannot import
     anything. Change both together. */
  var LIGHT_FROM_HOUR = 9;
  var LIGHT_UNTIL_HOUR = 18;

  function getModePreference() {
    var v = null;
    try { v = localStorage.getItem(STORAGE_KEY_MODE); } catch (e) {}
    return MODE_PREFERENCES.indexOf(v) !== -1 ? v : 'light';
  }

  function isDaylightHours(now) {
    var hour = (now || new Date()).getHours();
    return hour >= LIGHT_FROM_HOUR && hour < LIGHT_UNTIL_HOUR;
  }

  function resolveMode(preference) {
    if (preference === 'time') return isDaylightHours() ? 'light' : 'dark';
    return preference === 'dark' ? 'dark' : 'light';
  }

  // The mode the document is in right now, resolved. What the theme button
  // icon and anything else reading the active mode wants.
  function getStoredMode() {
    return resolveMode(getModePreference());
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

  function applyMode(preference) {
    var chosen = MODE_PREFERENCES.indexOf(preference) !== -1 ? preference : 'light';
    var resolved = resolveMode(chosen);

    document.documentElement.setAttribute('data-mode', resolved);
    document.documentElement.setAttribute('data-mode-preference', chosen);
    try { localStorage.setItem(STORAGE_KEY_MODE, chosen); } catch (e) {}

    scheduleModeCheck();

    return resolved;
  }

  /* Keeping the time based mode honest while the page stays open. */

  var modeTimer = null;
  var watchingVisibility = false;

  // Milliseconds until the next 09:00 or 18:00, whichever comes first.
  function msUntilNextBoundary(now) {
    now = now || new Date();
    var next = new Date(now);
    next.setMinutes(0, 0, 0);

    var hour = now.getHours();
    if (hour < LIGHT_FROM_HOUR) {
      next.setHours(LIGHT_FROM_HOUR);
    } else if (hour < LIGHT_UNTIL_HOUR) {
      next.setHours(LIGHT_UNTIL_HOUR);
    } else {
      next.setDate(next.getDate() + 1);
      next.setHours(LIGHT_FROM_HOUR);
    }

    // A second of slack, so a timer that fires a fraction early does not land
    // back in the hour it just left and reschedule itself in a tight loop.
    return Math.max(1000, next.getTime() - now.getTime() + 1000);
  }

  function scheduleModeCheck() {
    if (modeTimer !== null) {
      clearTimeout(modeTimer);
      modeTimer = null;
    }

    if (getModePreference() !== 'time') return;

    modeTimer = setTimeout(function () {
      modeTimer = null;
      refreshTimeMode();
    }, msUntilNextBoundary());

    if (!watchingVisibility && typeof document !== 'undefined') {
      watchingVisibility = true;
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') refreshTimeMode();
      });
    }
  }

  function refreshTimeMode() {
    if (getModePreference() !== 'time') return;

    var resolved = resolveMode('time');
    var current = document.documentElement.getAttribute('data-mode');

    if (resolved !== current) {
      document.documentElement.setAttribute('data-mode', resolved);
      document.dispatchEvent(
        new CustomEvent('uwu:modechange', {
          detail: { mode: resolved, preference: 'time' },
        })
      );
    }

    scheduleModeCheck();
  }

  function initTheme() {
    migrateLegacyTheme();
    applyColorTheme(getStoredColorTheme());
    // The preference, not the resolved mode. Passing the resolved one would
    // quietly rewrite a stored "time" into "dark" the first evening.
    applyMode(getModePreference());
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

    // A tab left open across 09:00 or 18:00 re-resolves itself; redraw the
    // modal so the note and pressed state stay in step with the change.
    document.addEventListener('uwu:modechange', syncThemeModalState);
  }

  function syncThemeModalState() {
    var activeTheme = getStoredColorTheme();
    var activePreference = getModePreference();
    var resolvedMode = getStoredMode();
    document.querySelectorAll('#swatchGrid .swatch').forEach(function (el) {
      var on = el.dataset.themeId === activeTheme;
      el.classList.toggle('active', on);
      el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    document.querySelectorAll('#modeToggle .mode-btn').forEach(function (el) {
      var on = el.dataset.mode === activePreference;
      el.classList.toggle('active', on);
      el.setAttribute('aria-pressed', on ? 'true' : 'false');
    });

    var note = document.getElementById('modeNote');
    if (note) {
      note.hidden = activePreference !== 'time';
      if (activePreference === 'time') {
        note.textContent = 'Following the clock. Currently ' + resolvedMode + '.';
      }
    }

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
  window.MODE_PREFERENCES = MODE_PREFERENCES;
  window.LIGHT_FROM_HOUR = LIGHT_FROM_HOUR;
  window.LIGHT_UNTIL_HOUR = LIGHT_UNTIL_HOUR;
  window.getModePreference = getModePreference;
  window.isDaylightHours = isDaylightHours;
  window.resolveMode = resolveMode;
  window.refreshTimeMode = refreshTimeMode;
  window.initTheme = initTheme;
})();
