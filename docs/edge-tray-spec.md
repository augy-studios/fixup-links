# Edge tray: spec for building it into a web app or adding it to one

A floating column of icon buttons pinned to the top right of the viewport. An
arrow tab sits beside it. Pressing the tab slides the column off the right edge
of the screen. Only the tab stays visible, flush against the edge, so the tray
can be brought back. The choice is remembered per browser.

Use it for an app's primary navigation and its few global actions (settings,
theme, notifications) when the content should get the full width of the screen:
maps, dashboards, games, readers.

This document is self-contained. The reference implementation below is plain
HTML, CSS and JavaScript with no dependencies. A React adaptation follows it.

---

## 1. Behaviour

| | Open (default) | Collapsed |
|---|---|---|
| Buttons | Visible, a column at the right edge, `--edge` from it | Translated off screen to the right and faded to opacity 0 |
| Tab | Fully rounded pill, left of the buttons, chevron pointing right (→ "push away") | Flush with the right edge of the viewport, flat on its right side with no right border, chevron pointing left (← "pull back") |
| Focus / AT | Buttons reachable | Buttons `inert`: not focusable, not clickable, hidden from assistive tech |
| Tab label | "Hide menu" | "Show menu" |
| `body` class | `tray-open` | none |
| Page | On narrow screens, keeps a strip clear for the tray (§5.1) | Takes the full width; the tab floats over its edge. Only the brand line, level with the tab, steps in to clear it |

- **Motion:** everything runs at one pace, `--tray-time` (340 ms) with
  `--tray-ease` (`cubic-bezier(0.2, 0.8, 0.2, 1)`), so the tray, its buttons,
  its tab and the page move together:
  - **The tray** slides as one transform, off the edge to collapse and back to
    open.
  - **The buttons unroll on open.** Each fades in, slides 12 px back from the
    edge and grows from 85 % scale. Each starts 18 ms after the one above it,
    so the column fills in from top to bottom. **On collapse they go
    together**, fading, shrinking and sliding towards the edge as the tray
    slides away.
  - **The tab** reshapes from pill to edge tab and its chevron turns round, at
    the same pace.
  - **The page** follows: its side padding (§5.1) grows as the tray opens and
    shrinks as it collapses, and the brand line's nudge steps in and out with
    it. Changing the tray's side (§9) animates the same way.
- **Persistence:** the state is written to `localStorage` on every toggle, as
  `"1"` or `"0"`. On load the tray is open unless the stored value is exactly
  `"0"`. If storage throws (private mode, blocked site data), the tray opens and
  the toggle still works for that page view.
- **Click-through:** the fixed container lets clicks through
  (`pointer-events: none`) and only its children take them, so the empty space
  around the tray never blocks the page or map underneath.
- **Hover:** the buttons lift 1 px and switch to a stronger surface.
- **Reduced motion:** with `prefers-reduced-motion: reduce`, transitions run in
  effectively zero time. The state change itself still happens.

## 2. Anatomy

```
viewport right edge ─────────────────────────────┐
                                                  │
 OPEN                       ┌──┐ gap ┌──────┐ edge│
                            │ ›│ 8px │ btn  │ 16px│
                            └──┘     │ btn  │     │
                            tab 24px │ btn  │     │
                                     │ ──── │ ← rule
                                     │ btn  │     │
                                     └──────┘     │
                                                  │
 COLLAPSED                                   ┌──┤
 (tray translated right by                   │ ‹│
  btn + gap + edge)                          └──┤
```

The collapse distance is chosen so the tab's right side lands exactly on the
viewport edge:

```
--tray-shift = button width + gap (8px) + edge inset
```

## 3. Design tokens

Define these on `:root`, or map them to the app's existing tokens. The names
are suggestions; keep whatever the host app already calls these things.

| Token | Purpose | Reference value |
|---|---|---|
| `--glass-btn` | Button size (square) and tab height | `44px`; `40px` at ≤ 480 px wide |
| `--edge` | Inset from the right edge, safe-area aware | `max(16px, calc(env(safe-area-inset-right) + 16px))`; `10px` variant at ≤ 480 px |
| `--tray-top` | Distance from the top, clear of the notch and any top banner | `max(calc(var(--banner-h, 0px) + 14px), calc(env(safe-area-inset-top) + 14px))` |
| `--banner-h` | Height of a sticky top banner, if the app has one (set from JS, §6.3) | `0px` |
| `--tray-time` | Duration of every tray animation, and of the page making room | `0.34s` |
| `--tray-ease` | Their easing | `cubic-bezier(0.2, 0.8, 0.2, 1)` |
| `--surface` | Glass background | light `rgba(255,255,255,.55)` / dark `rgba(255,255,255,.06)` |
| `--surface-strong` | Hover background | light `rgba(255,255,255,.78)` / dark `rgba(255,255,255,.11)` |
| `--surface-border` | 1 px border | light `rgba(255,255,255,.65)` / dark `rgba(255,255,255,.14)` |
| `--shadow` | Drop shadow | light `0 10px 30px rgba(20,40,30,.10)` / dark `0 10px 34px rgba(0,0,0,.5)` |
| `--ink` | Icon colour | the app's text colour |
| `--accent-fill`, `--on-accent` | Selected nav item background and icon colour | the app's brand colour and its contrasting text colour |

The glass look depends on `backdrop-filter`, so the tray needs something behind
it to blur. On a flat page it still reads as a translucent card.

## 4. Markup

```html
<!-- Fixed to the top right. Holds the tray, and anything else that should
     stack under it at that edge. -->
<div class="hud-right">
  <div id="tray" class="tray">
    <button id="trayTab" class="tray-tab" type="button"
            aria-controls="trayButtons" aria-expanded="true" aria-label="Hide menu">
      <!-- Chevron pointing right. Rotated 180° by CSS when collapsed. -->
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
           stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="m9 5 7 7-7 7"/>
      </svg>
    </button>

    <div id="trayButtons" class="tray-buttons">
      <!-- Optional: the app's views, as a vertical tab list. -->
      <nav class="tray-views" role="tablist" aria-label="Views" aria-orientation="vertical">
        <button class="glass-btn" type="button" role="tab" id="tab-home" data-view="home"
                aria-controls="view-home" aria-selected="true"
                aria-label="Home" title="Home"><!-- icon svg --></button>
        <button class="glass-btn" type="button" role="tab" id="tab-search" data-view="search"
                aria-controls="view-search" aria-selected="false" tabindex="-1"
                aria-label="Search" title="Search"><!-- icon svg --></button>
      </nav>

      <span class="tray-rule" aria-hidden="true"></span>

      <!-- Global actions. -->
      <button class="glass-btn" id="settingsBtn" type="button" aria-haspopup="dialog"
              aria-label="Settings" title="Settings"><!-- icon svg --></button>
    </div>
  </div>
</div>
```

Rules:

- The tab comes **before** the buttons in the DOM. It is visually on their left
  and it comes first in tab order.
- Every icon-only button has an `aria-label` and a matching `title`.
- If the app has no views, drop the `<nav>` and the rule and put the action
  buttons straight into `.tray-buttons`.
- The markup ships in the open state (`aria-expanded="true"`, no `collapsed`
  class). The script sets the real state on load (§6.4 covers the first-paint
  flash).

## 5. CSS

```css
/* Fixed top right. Lets clicks through except on its children. */
.hud-right {
  position: fixed;
  z-index: 800;            /* above content, below modals and any top banner */
  top: var(--tray-top);
  right: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  pointer-events: none;
  transition: top 0.2s ease;  /* glides when a top banner comes or goes */
}
.hud-right > * { pointer-events: auto; }

/* The tray: tab + column. Collapsed, the whole thing shifts right until only
   the tab is left, flush with the edge. */
.tray {
  --tray-shift: calc(var(--glass-btn) + 8px + var(--edge));
  display: flex;
  align-items: flex-start;
  gap: 8px;
  transition: transform var(--tray-time) var(--tray-ease);
}
.tray.collapsed { transform: translateX(var(--tray-shift)); }

.tray-tab {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: var(--glass-btn);
  padding: 0;
  border-radius: 12px;
  background: var(--surface);
  backdrop-filter: blur(18px) saturate(150%);
  -webkit-backdrop-filter: blur(18px) saturate(150%);
  border: 1px solid var(--surface-border);
  box-shadow: var(--shadow);
  color: var(--ink);
  cursor: pointer;
  transition: border-radius var(--tray-time) var(--tray-ease);
}
.tray-tab svg { width: 16px; height: 16px; transition: transform var(--tray-time) var(--tray-ease); }
/* At the edge it is a tab: flat on the side the screen cuts off. */
.tray.collapsed .tray-tab { border-radius: 12px 0 0 12px; border-right: none; }
.tray.collapsed .tray-tab svg { transform: rotate(180deg); }

.tray-buttons,
.tray-views {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
}
.tray-buttons { margin-right: var(--edge); }

/* Separates the views from the global actions. */
.tray-rule {
  width: 24px;
  height: 1px;
  margin: 2px 0;
  background: color-mix(in srgb, var(--ink) 25%, transparent);
}

/* The buttons. */
.glass-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: var(--glass-btn);
  height: var(--glass-btn);
  padding: 0;
  border-radius: 14px;
  background: var(--surface);
  backdrop-filter: blur(18px) saturate(150%);
  -webkit-backdrop-filter: blur(18px) saturate(150%);
  border: 1px solid var(--surface-border);
  box-shadow: var(--shadow);
  color: var(--ink);
  cursor: pointer;
  transition: transform 0.15s ease, background 0.15s ease, color 0.15s ease;
}
.glass-btn:hover { transform: translateY(-1px); background: var(--surface-strong); }
.glass-btn svg { width: 22px; height: 22px; }

/* The buttons unroll: each fades in, slides back from the edge and grows, 18 ms after
   the one above it. They move by `translate` and `scale`, leaving `transform` to the
   hover lift, so the list repeats the hover transitions. After .glass-btn, so it wins.
   A <nav> of views is one child here and moves as one step. */
.tray-buttons > * {
  transition:
    opacity calc(var(--tray-time) * 0.8) ease,
    translate var(--tray-time) var(--tray-ease),
    scale var(--tray-time) var(--tray-ease),
    transform 0.15s ease,
    background 0.15s ease,
    color 0.15s ease;
  /* Only opening is staggered: the delay comes from the state being entered. */
  transition-delay: calc(var(--i, 0) * 18ms), calc(var(--i, 0) * 18ms), calc(var(--i, 0) * 18ms), 0s, 0s, 0s;
}
.tray-buttons > :nth-child(2) { --i: 1; }
.tray-buttons > :nth-child(3) { --i: 2; }
.tray-buttons > :nth-child(4) { --i: 3; }
.tray-buttons > :nth-child(5) { --i: 4; }
.tray-buttons > :nth-child(6) { --i: 5; }
.tray-buttons > :nth-child(7) { --i: 6; }
.tray-buttons > :nth-child(8) { --i: 7; }
.tray-buttons > :nth-child(9) { --i: 8; }
.tray-buttons > :nth-child(10) { --i: 9; }
.tray-buttons > :nth-child(11) { --i: 10; }
/* Add more nth-child lines if the tray holds more than eleven items. */
.tray.collapsed .tray-buttons > * {
  opacity: 0;
  translate: 12px 0;   /* towards the edge it leaves by */
  scale: 0.85;
  transition-delay: 0s; /* collapsing, they all go at once */
}

/* The view on screen. */
.glass-btn[aria-selected="true"],
.glass-btn[aria-selected="true"]:hover {
  background: var(--accent-fill);
  color: var(--on-accent);
}

/* Keyboard focus must be visible on glass. Use the app's focus style if it has one. */
.tray-tab:focus-visible,
.glass-btn:focus-visible {
  outline: 2px solid var(--ink);
  outline-offset: 2px;
}

@media (max-width: 480px) {
  :root {
    --glass-btn: 40px;
    --edge: max(10px, calc(env(safe-area-inset-right) + 10px));
  }
}

@media (prefers-reduced-motion: reduce) {
  .hud-right, .tray, .tray-tab, .tray-tab svg, .tray-buttons > *, .glass-btn, main, .brand {
    transition-duration: 0.001ms !important;
    transition-delay: 0s !important;
  }
}
```

### 5.1 Keeping content clear of the tray

The tray floats over the page. On wide screens a centred content column never
reaches it. On narrow screens it would, so the column reserves room while the
tray is open, and only then.

When the tray is collapsed, the column reserves nothing for it. The tab is
small and sits in the page's own side margin, so keeping a strip clear for it
would only leave a blank band down that side of the screen. The content takes
the full width and the tab floats over its edge.

The one exception is the brand line at the top, which sits level with the tab.
The brand line is the app's logo and its name, side by side, and nothing else.
Only that line steps in, just far enough for the tab and a 10px gap, so the tab
never covers the logo or the name; everything below it keeps the full width. On a screen wide enough that the tab is out in the margin, the step is
zero. If the tab would cover something else that is interactive, move that
control rather than reserve the strip.

The padding animates with the tray, so the column narrows as the tray slides
in and widens as it slides out, and the brand line steps in and out with it.

```css
/* Pick the breakpoint where the content column's right edge meets the tray:
   roughly column max-width + 2 × (button + edge + 12px). For a 720px column
   that is about 920px. */
/* Both sides, so changing the tray's side (§9) animates too. */
main, .brand {
  transition: padding-right var(--tray-time) var(--tray-ease),
              padding-left var(--tray-time) var(--tray-ease);
}
@media (max-width: 920px) {
  body.tray-open main { padding-right: calc(var(--glass-btn) + var(--edge) + 12px); }
  /* Collapsed: the brand line alone clears the tab (24px wide) by 10px, less the
     column's own side padding (16px here). */
  body:not(.tray-open) .brand { padding-right: calc(24px + 10px - 16px); }
}
```

Full-bleed surfaces (maps, canvases) do not get the padding. They keep their
own on-screen controls away from the top right:

- Put the surface's own controls top left or bottom right, never top right.
- When fitting a map to bounds, pad the right side by at least
  `button + edge + ~10px` (about 70 px) and the top by enough to clear the
  floating controls.
- Bottom-right controls use `margin-right: var(--edge)` so they line up with the
  tray's column.

## 6. JavaScript

### 6.1 Core

```js
// Namespace the key per app so two apps on one origin don't share it.
const TRAY_KEY = "myapp.trayOpen";

const tray = document.getElementById("tray");
const trayTab = document.getElementById("trayTab");
const trayButtons = document.getElementById("trayButtons");

function setTray(open, { save = true } = {}) {
  tray.classList.toggle("collapsed", !open);
  trayTab.setAttribute("aria-expanded", String(open));
  trayTab.setAttribute("aria-label", open ? "Hide menu" : "Show menu");
  // Off-screen buttons must not take focus or clicks.
  trayButtons.inert = !open;
  document.body.classList.toggle("tray-open", open);
  if (save) {
    try {
      localStorage.setItem(TRAY_KEY, open ? "1" : "0");
    } catch {
      // Remembered for this page view only.
    }
  }
}

function initTray() {
  let open = true;
  try {
    open = localStorage.getItem(TRAY_KEY) !== "0";
  } catch {
    // Open, the default.
  }
  setTray(open, { save: false });
  trayTab.addEventListener("click", () => setTray(tray.classList.contains("collapsed")));
}

initTray();
```

### 6.2 Views as a tab list (optional)

If the tray holds the app's views, it is an ARIA tab list. It uses roving
`tabindex`, and the arrow keys, Home and End move between tabs.

```js
const VIEWS = ["home", "search" /* … in DOM order */];
let view = VIEWS[0];

function showView(name, { focus = false } = {}) {
  if (!VIEWS.includes(name)) return;
  view = name;
  for (const v of VIEWS) {
    const tab = document.getElementById(`tab-${v}`);
    const on = v === name;
    tab.setAttribute("aria-selected", String(on));
    tab.tabIndex = on ? 0 : -1;
    document.getElementById(`view-${v}`).hidden = !on;
  }
  if (focus) document.getElementById(`tab-${name}`).focus();
}

const tabs = document.querySelector(".tray-views");
tabs.addEventListener("click", (e) => {
  const tab = e.target.closest("[data-view]");
  if (tab) showView(tab.dataset.view);
});
// The list runs top to bottom, but left and right work too.
tabs.addEventListener("keydown", (e) => {
  const i = VIEWS.indexOf(view);
  const next = { ArrowUp: i - 1, ArrowLeft: i - 1, ArrowDown: i + 1, ArrowRight: i + 1,
                 Home: 0, End: VIEWS.length - 1 }[e.key];
  if (next == null) return;
  e.preventDefault();
  showView(VIEWS[(next + VIEWS.length) % VIEWS.length], { focus: true });
});
```

Each view panel is `role="tabpanel"` with `aria-labelledby="tab-<name>"`.

### 6.3 Sitting under a sticky top banner (optional)

If the app shows a sticky banner at the top (an update prompt, an offline
notice, a cookie bar), publish its height as `--banner-h` so the tray starts
below it. `--tray-top` already takes it into account, and the `top` transition
makes the tray glide when the banner comes or goes.

```js
const sizer = new ResizeObserver(([entry]) => {
  document.documentElement.style.setProperty("--banner-h", `${entry.target.offsetHeight}px`);
});
// When the banner is shown:   sizer.observe(bannerEl);
// When it is removed:         sizer.disconnect();
//                             document.documentElement.style.setProperty("--banner-h", "0px");
```

Give the banner a higher `z-index` than `.hud-right`. Any full-screen surface
should start at `top: var(--banner-h, 0px)` too.

### 6.4 No flash on load (recommended)

`initTray()` runs after the markup has painted open. For a returning user who
left the tray collapsed, the tray visibly slides shut on load. To avoid that,
apply the stored state before first paint with a tiny inline script in
`<head>`, and suppress transitions for that first frame:

```html
<script>
  try {
    if (localStorage.getItem("myapp.trayOpen") === "0")
      document.documentElement.classList.add("tray-start-collapsed");
  } catch {}
</script>
```

```css
.tray-start-collapsed .tray { transform: translateX(var(--tray-shift)); transition: none; }
.tray-start-collapsed .tray-buttons > * { opacity: 0; translate: 12px 0; scale: 0.85; transition: none; }
.tray-start-collapsed main, .tray-start-collapsed .brand { transition: none; }
.tray-start-collapsed .tray-tab { border-radius: 12px 0 0 12px; border-right: none; }
.tray-start-collapsed .tray-tab svg { transform: rotate(180deg); }
```

Then remove the class in `initTray()` after `setTray(open, { save: false })`,
inside a `requestAnimationFrame`, so later toggles animate as normal.

## 7. React adaptation

The same contract in a React app: state, ARIA and `inert` are driven from one
boolean, and the CSS from §5 is unchanged.

```jsx
const TRAY_KEY = "myapp.trayOpen";

function readOpen() {
  try { return localStorage.getItem(TRAY_KEY) !== "0"; } catch { return true; }
}

export function EdgeTray({ children }) {
  const [open, setOpen] = useState(readOpen);

  useEffect(() => {
    document.body.classList.toggle("tray-open", open);
    try { localStorage.setItem(TRAY_KEY, open ? "1" : "0"); } catch {}
  }, [open]);

  return (
    <div className="hud-right">
      <div className={`tray${open ? "" : " collapsed"}`}>
        <button className="tray-tab" type="button" aria-controls="trayButtons"
                aria-expanded={open} aria-label={open ? "Hide menu" : "Show menu"}
                onClick={() => setOpen((o) => !o)}>
          <ChevronRight aria-hidden="true" />
        </button>
        {/* `inert` is a boolean prop from React 19. On React 18 pass inert={open ? undefined : ""}. */}
        <div id="trayButtons" className="tray-buttons" inert={!open}>
          {children}
        </div>
      </div>
    </div>
  );
}
```

With server rendering, render the open state on the server and read storage in
an effect (or use the §6.4 head script) to avoid a hydration mismatch.

## 8. Retrofitting an existing app

1. **Take stock.** List what currently lives in the app's header or nav: views,
   settings, theme, account, notifications. Anything that is a short label or
   an icon belongs in the tray. Long text links, search fields and anything
   wider than a button do not.
2. **Pick icons** for every item. Each needs an `aria-label` and a `title`,
   because the tray has no visible text.
3. **Map tokens** (§3) to the host app's existing colours, shadows and
   radii rather than adding a second palette. Check light and dark modes.
4. **Add the markup** (§4) as the first child of `<body>`, outside any
   container that has `overflow: hidden` or a `transform`. A transformed
   ancestor makes `position: fixed` resolve against that ancestor instead of
   the viewport.
5. **Move the behaviour.** Wire existing handlers (theme picker, settings
   dialog, router links) to the new buttons. For router-driven apps, the nav
   items can be links (`<a class="glass-btn" aria-current="page">`) instead of
   ARIA tabs. Style `[aria-current="page"]` the way §5 styles
   `[aria-selected="true"]`.
6. **Remove the old header nav**, or keep only the brand line: the app's logo
   and its name, in the page flow above the content. Give it the collapsed
   tab's clearance from §5.1; the rest of the page needs none. Nothing else
   goes in it.
7. **Clear the top right.** Audit everything that is `position: fixed/sticky`
   or absolutely positioned near the top right: toasts, FABs, map controls,
   chat widgets. Move them, or offset them by the tray's footprint. Check the
   `z-index` order: content < tray (800) < top banner < modals and toasts.
8. **Content padding.** Find the breakpoint where the column meets the tray and
   add the `body.tray-open` padding (§5.1).
9. **Banner and safe areas.** If the app has a sticky top bar, wire
   `--banner-h` (§6.3). Make sure the page has
   `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`
   so the `env(safe-area-inset-*)` values are non-zero on notched phones.
10. **Storage key.** Namespace it per app (`<app>.trayOpen`).

## 9. Variants

- **Left edge.** Mirror everything: `.hud-right` becomes `left: 0` with
  `align-items: flex-start`, the tab goes **after** the buttons in the DOM,
  `.tray-buttons` takes `margin-left: var(--edge)`, the shift becomes
  `translateX(calc(-1 * var(--tray-shift)))`, and the collapsed tab is flat on
  the left (`border-radius: 0 12px 12px 0; border-left: none`). Use a
  left-pointing chevron for the open state. Collapsing, the buttons slide
  towards the left edge (`translate: -12px 0`). The content padding (§5.1) moves to
  the left too, and so does the brand line's nudge: collapsed, it takes the
  tab's clearance as `padding-left`, so the tab doesn't cover the logo.
- **More items than fit vertically.** Give `.tray-buttons` a
  `max-height: calc(100dvh - var(--tray-top) - 16px)` and `overflow-y: auto`,
  or group rarely used actions behind one "More" button that opens a menu.
- **Something stacked under the tray.** `.hud-right` is a flex column, so a
  second element (a status pill, a mini-player) can follow `.tray` and will
  sit beneath it at the same edge. Decide whether it collapses with the tray.
  If it does, put it inside `.tray-buttons`.

## 10. Acceptance checklist

- [ ] Tray appears top right, `--edge` from the side, below the notch and below
      any top banner. It moves down and up as the banner comes and goes.
- [ ] Clicking the tab collapses the tray in about 340 ms, the buttons fading,
      shrinking and sliding out together. Only the tab remains, flush with the
      right edge, flat on its right side, chevron pointing left.
- [ ] Clicking it again restores the tray, chevron pointing right, and the
      buttons unroll top to bottom, each a beat after the one above.
- [ ] The page's side padding and the brand line's nudge animate in step with
      the tray, at the same pace, in both directions and when the side changes.
- [ ] The tab's `aria-expanded` and `aria-label` track the state.
- [ ] Collapsed: Tab-key navigation skips every tray button. A screen reader
      does not announce them.
- [ ] Reloading keeps the last state. A returning collapsed user sees no slide
      on load (if §6.4 is used).
- [ ] With storage blocked (private window or site data disabled), the tray
      opens by default, toggles, and throws no errors.
- [ ] Empty space around the tray does not block clicks on the page or map
      beneath it.
- [ ] At phone width (≤ 480 px) buttons are 40 px, the edge is 10 px, and no
      content runs under the open tray. The page does not scroll sideways.
- [ ] Collapsed, the page uses its full width: no blank strip is left down the
      side for the tab, which floats over the page's edge. Only the brand line
      (logo and app name) steps in, so the tab covers neither. The
      column widens as the tray slides out and narrows as it slides back in.
- [ ] Views (if used): arrow keys, Home and End move the selection, only the
      selected tab is in the tab order, and the selected button uses the accent
      fill.
- [ ] Hover lifts the buttons. Keyboard focus is visible on the tab and on
      every button, in light and dark modes.
- [ ] With reduced motion on, the toggle is instant.
- [ ] No other fixed element (toast, widget, map control) overlaps the tray
      in either state.
