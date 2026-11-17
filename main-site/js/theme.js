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
      if (!legacy) {
        return;
      }
      if (!localStorage.getItem(STORAGE_KEY_COLOR) && LEGACY_MAP[legacy]) {
        localStorage.setItem(STORAGE_KEY_COLOR, LEGACY_MAP[legacy]);
      }
      localStorage.removeItem(LEGACY_KEY);
    } catch (error) {
      /* storage unavailable, fall back to defaults */
    }
  }

  // "#ccffcc" -> "204, 255, 204", for the --brand-rgb custom property.
  function hexToRgb(hex) {
    var colorNumber = parseInt(hex.replace('#', ''), 16);
    var red = (colorNumber >> 16) & 255;
    var green = (colorNumber >> 8) & 255;
    var blue = colorNumber & 255;
    return red + ', ' + green + ', ' + blue;
  }

  function getStoredColorTheme() {
    try {
      var storedColorTheme = localStorage.getItem(STORAGE_KEY_COLOR);
      if (!storedColorTheme) {
        return 'classic';
      }
      return storedColorTheme;
    } catch (error) {
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
    var storedPreference = null;
    try {
      storedPreference = localStorage.getItem(STORAGE_KEY_MODE);
    } catch (error) {
      // Storage unavailable: the default below.
    }
    if (MODE_PREFERENCES.indexOf(storedPreference) !== -1) {
      return storedPreference;
    }
    return 'light';
  }

  function isDaylightHours(now) {
    var time = now;
    if (!time) {
      time = new Date();
    }
    var hour = time.getHours();
    return hour >= LIGHT_FROM_HOUR && hour < LIGHT_UNTIL_HOUR;
  }

  function resolveMode(preference) {
    if (preference === 'time') {
      if (isDaylightHours()) {
        return 'light';
      }
      return 'dark';
    }
    if (preference === 'dark') {
      return 'dark';
    }
    return 'light';
  }

  // The mode the document is in right now, resolved. What the theme button
  // icon and anything else reading the active mode wants.
  function getStoredMode() {
    return resolveMode(getModePreference());
  }

  function applyColorTheme(id) {
    var theme = COLOR_THEMES.filter(function (colorTheme) {
      return colorTheme.id === id;
    })[0];
    if (!theme) {
      theme = COLOR_THEMES[0];
    }
    document.documentElement.setAttribute('data-color-theme', theme.id);
    document.documentElement.style.setProperty('--brand', theme.hex);
    document.documentElement.style.setProperty('--brand-rgb', hexToRgb(theme.hex));
    try {
      localStorage.setItem(STORAGE_KEY_COLOR, theme.id);
    } catch (error) {
      // Storage unavailable: applied for this page view only.
    }
    var themeColorMeta = document.querySelector('meta[name="theme-color"]');
    if (themeColorMeta) {
      themeColorMeta.setAttribute('content', theme.hex);
    }
    return theme;
  }

  function applyMode(preference) {
    var chosen = 'light';
    if (MODE_PREFERENCES.indexOf(preference) !== -1) {
      chosen = preference;
    }
    var resolved = resolveMode(chosen);

    document.documentElement.setAttribute('data-mode', resolved);
    document.documentElement.setAttribute('data-mode-preference', chosen);
    try {
      localStorage.setItem(STORAGE_KEY_MODE, chosen);
    } catch (error) {
      // Storage unavailable: applied for this page view only.
    }

    scheduleModeCheck();

    return resolved;
  }

  /* Keeping the time based mode honest while the page stays open. */

  var modeTimer = null;
  var watchingVisibility = false;

  // Milliseconds until the next 09:00 or 18:00, whichever comes first.
  function millisecondsUntilNextBoundary(now) {
    if (!now) {
      now = new Date();
    }
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

    if (getModePreference() !== 'time') {
      return;
    }

    modeTimer = setTimeout(function () {
      modeTimer = null;
      refreshTimeMode();
    }, millisecondsUntilNextBoundary());

    if (!watchingVisibility && typeof document !== 'undefined') {
      watchingVisibility = true;
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') {
          refreshTimeMode();
        }
      });
    }
  }

  function refreshTimeMode() {
    if (getModePreference() !== 'time') {
      return;
    }

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

  /** Fills the theme window with one swatch per colour and wires up its swatches and mode buttons. */
  function buildThemeModal() {
    var grid = document.getElementById('swatchGrid');
    if (!grid) {
      return;
    }

    var swatchesHtml = '';
    for (var themeIndex = 0; themeIndex < COLOR_THEMES.length; themeIndex++) {
      var colorTheme = COLOR_THEMES[themeIndex];
      swatchesHtml += '<button class="swatch" data-theme-id="' + colorTheme.id + '" style="--swatch-color:' + colorTheme.hex + '" type="button" aria-label="' + colorTheme.label + '">' +
        '<span class="swatch-dot"></span>' +
        '<span class="swatch-label">' + colorTheme.label + '</span>' +
        '</button>';
    }
    grid.innerHTML = swatchesHtml;

    syncThemeModalState();

    grid.addEventListener('click', function (event) {
      var swatchButton = event.target.closest('[data-theme-id]');
      if (!swatchButton) {
        return;
      }
      applyColorTheme(swatchButton.dataset.themeId);
      syncThemeModalState();
    });

    document.getElementById('modeToggle').addEventListener('click', function (event) {
      var modeButton = event.target.closest('[data-mode]');
      if (!modeButton) {
        return;
      }
      applyMode(modeButton.dataset.mode);
      syncThemeModalState();
    });

    // A tab left open across 09:00 or 18:00 re-resolves itself; redraw the
    // modal so the note and pressed state stay in step with the change.
    document.addEventListener('uwu:modechange', syncThemeModalState);
  }

  /** Marks the chosen swatch and mode as pressed, shows the clock note, and updates the theme button. */
  function syncThemeModalState() {
    var activeTheme = getStoredColorTheme();
    var activePreference = getModePreference();
    var resolvedMode = getStoredMode();
    document.querySelectorAll('#swatchGrid .swatch').forEach(function (element) {
      var isActive = element.dataset.themeId === activeTheme;
      element.classList.toggle('active', isActive);
      element.setAttribute('aria-pressed', String(isActive));
    });
    document.querySelectorAll('#modeToggle .mode-btn').forEach(function (element) {
      var isActive = element.dataset.mode === activePreference;
      element.classList.toggle('active', isActive);
      element.setAttribute('aria-pressed', String(isActive));
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
    var iconSpan = document.querySelector('#themeBtn [data-icon]');
    if (!iconSpan) {
      return;
    }
    var iconName = 'sun';
    if (getStoredMode() === 'dark') {
      iconName = 'moon';
    }
    iconSpan.setAttribute('data-icon', iconName);
    window.hydrateIcons(document.getElementById('themeBtn'));
  }

  function wireModals() {
    document.querySelectorAll('[data-close-modal]').forEach(function (closeButton) {
      closeButton.addEventListener('click', function () {
        window.closeModal(closeButton.dataset.closeModal);
      });
    });
    document.querySelectorAll('.modal-backdrop').forEach(function (backdrop) {
      backdrop.addEventListener('click', function (event) {
        if (event.target === backdrop) {
          window.closeModal(backdrop.id);
        }
      });
    });
    var themeButton = document.getElementById('themeBtn');
    if (themeButton) {
      themeButton.addEventListener('click', function () {
        window.openModal('themeModal');
      });
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
