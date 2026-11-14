# Claude Code prompt: retrofit time-based mode

Paste this into Claude Code inside the app's repo. The repo already has the
uwuapps theme system with a two-button light/dark toggle. This is a retrofit,
not a rebuild: touch only the theme system files, leave every other file in
the repo alone.

---

Read `uwuapps-theme.md` at the repo root and apply it. It is the source of
truth for every file this task touches. Use the repo root `index.html`'s
`<head>` tag as the template for every other HTML file in the repo, so any
`<meta>` or script ordering you add stays consistent across pages.

Goal: add the time-based mode option described in `uwuapps-theme.md`'s
"Time based mode" section to this app, on top of the light/dark toggle that
already exists. Do not change the brand colour system, the swatch grid, or
any token values. Do not touch app logic outside the theme system.

Do this in order:

1. **Find the theme files.** Locate `js/theme.js`, the theme CSS (either
   `css/theme.css` or the top of `style.css`), `js/icons.js`, `js/ui.js`,
   the file that wires theme buttons (`app.js` or the per-page script if
   there's no shared `app.js`), and every HTML file with a theme modal and
   a pre-paint flash-prevention script in `<head>`.

2. **`js/theme.js`.** Diff the current file against the `js/theme.js` block
   in `uwuapps-theme.md` section 2. Keep `APP_KEY`, `COLOR_THEMES`, and
   `applyColorTheme` exactly as they already are in this repo. Add:
   - `MODE_PREFERENCES`, `LIGHT_FROM_HOUR`, `LIGHT_UNTIL_HOUR`
   - `getModePreference()`, `isDaylightHours()`, `resolveMode()`
   - Change `getStoredMode()` to resolve through `resolveMode(getModePreference())`
     instead of reading localStorage directly
   - Change `applyMode()` to take a preference (`light`/`dark`/`time`),
     resolve it, write both `data-mode` and `data-mode-preference` to the
     document, store the preference (not the resolved value) in
     localStorage, and call `scheduleModeCheck()`
   - Add `scheduleModeCheck()`, `msUntilNextBoundary()`, and
     `refreshTimeMode()` exactly as specified, including the
     `visibilitychange` listener and the `uwu:modechange` custom event
   - Update `initTheme()` to call `applyMode(getModePreference())`, not
     `applyMode(getStoredMode())`

3. **Theme CSS.** Diff the current `.mode-toggle` and `.mode-btn` rules
   against `uwuapps-theme.md`. Change `.mode-toggle` from `display: flex` to
   the two-column grid shown there, and add `.mode-btn-wide` and
   `.mode-note`. Leave every other rule untouched.

4. **`js/icons.js`.** Add the `clock` icon if it isn't already there.

5. **Every HTML file with a theme modal.** Add the third mode button
   (`data-mode="time"`, class `mode-btn mode-btn-wide`) and the
   `<p class="mode-note" id="modeNote" hidden></p>` element, in the same
   place `uwuapps-theme.md` section 5 shows them. If the modal markup is
   duplicated across multiple pages rather than shared, update every copy,
   using the root page as the template for the others.

6. **Pre-paint flash script.** If this app already has the optional
   flash-prevention script from section 7, update it in every `<head>` that
   has one to resolve `time` and set `data-mode-preference`, matching the
   updated script in `uwuapps-theme.md`. If the app doesn't have this script
   yet, don't add it as part of this task, it's a separate concern.

7. **Wiring file (`app.js` or equivalent).** Update the theme modal wiring
   to import `getModePreference`, compute `activePreference` and
   `resolvedMode` in `syncThemeModalState()`, set `aria-pressed` on the mode
   buttons, show/hide and fill in `#modeNote`, and listen for
   `uwu:modechange` to re-sync the modal when a tab crosses a boundary while
   open.

8. **Verify.** Confirm:
   - The app still defaults to light + the existing default swatch for a
     fresh profile, clock preference untouched
   - Picking "Time-based" and reloading keeps that button pressed, not
     "Dark", even in the evening
   - `data-mode` in the DOM is never anything but `light` or `dark`
   - No console errors from the new event listener or timer on pages that
     don't have a `#modeNote` element (guard with the existing `if (note)`
     check)
   - Existing swatch and light/dark behaviour is unchanged for anyone who
     hasn't picked "Time-based"

Work through one file type at a time (theme.js, then CSS, then icons, then
HTML, then wiring) and show a summary of what changed in each before moving
to the next, rather than editing everything silently and reporting at the
end.