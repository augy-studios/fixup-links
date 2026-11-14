# Page tours: spec for building first-visit tutorials into a web app

A short guided tour over a page, shown the first time someone opens that page.
The page dims, one thing on it is lit, and a hand-drawn chalk arrow runs to it
from a line saying what it does. **Next** moves to the next thing, **Skip** ends
the tour. Every page in the app has its own tour. The one for the start page
also serves as the welcome the first time the app is opened. Settings can replay
any of them.

Use it for apps with several pages, each with a few controls that aren't
obvious at first sight. It isn't meant for long onboarding flows or forms: a
tour is three to five steps, each one line about one real thing on the page.

This document is self-contained. The reference implementation below is plain
HTML, CSS and JavaScript with no dependencies.

---

## 1. Behaviour

| | |
|---|---|
| When | The first time each page is shown, once its content has drawn. Never again on its own after it ends, whether by **Done** or **Skip**. |
| What | A spotlight on one element at a time, a chalk arrow to it, one line of text, step dots, **Next** (or **Done** on the last step) and **Skip**. |
| Where it ends | On the page it began on. A tour started from another page (a replay from Settings) switches to its page first and switches back at the end. |
| Replays | Settings has a **Show me around** section with one button per page. Replaying doesn't change what's been seen. |
| Not shown | Over a page someone reached by a link (a deep link came for that thing, not a tour); while a dialog or other window is open over the page; on a page with no tour; when none of its steps' elements are there. |

- **One tour per page, one at a time.** A tour never starts while another is
  showing. Switching pages during a tour (the tour does this itself on a
  replay) doesn't start that page's tour.
- **The welcome.** The first time the app is opened, the start page's tour
  runs. Its last steps go beyond the page, to the app's navigation and to
  Settings, so it also teaches how to reach the other pages and replay tours.
  If the app opens on a different page, the welcome switches to the start
  page, runs, then returns. That page's own tour then follows straight on, as
  it is now being seen for the first time.
- **Steps that aren't there are left out.** Each step names its element by a
  CSS selector (a list of alternatives is fine: the first visible match is
  used). A step whose element is missing or hidden when the tour starts is
  dropped, so a tour adapts to what's on screen: an empty list gets a step
  explaining how to fill it instead of steps about its items, and a button the
  device can't use (no camera, no microphone) is skipped. A tour whose steps
  are all dropped is marked seen without showing anything.
- **Waiting for content.** A page that loads its content (a list fetched from a
  server) waits until it has drawn, up to about eight seconds, before its tour
  starts. Pages that draw at once wait about one second, so the switch
  animation finishes first.
- **The element is scrolled into view** (centred) before it's lit. If it sits
  in a collapsible part of the navigation that's collapsed, that part opens.

## 2. Anatomy

```
┌──────────────────────────────────────────┐
│ Skip                     (dimmed page)   │
│                                          │
│        ╭──────────────────────╮          │
│        │   lit element        │ ◄─ hole: │
│        ╰──────────────────────╯   a box  │
│                 ↑                 shadow │
│                  ╲  chalk arrow   of     │
│                   ╲               200vmax│
│   Pick what shows here: everything, or   │
│   just your saved ones.                  │
│   ● ━━ ●  ●                     [ Next ] │
└──────────────────────────────────────────┘
```

- **Root:** a fixed, full-viewport layer above everything (`z-index` above the
  app's own dialogs). `role="dialog"`, `aria-modal="true"`, labelled by the
  step text.
- **Hole:** a fixed box the size of the lit element plus 8 px padding, with
  rounded corners, a very large spread `box-shadow` that dims everything
  outside it, and a soft white glow just around it. It animates between
  steps (left, top, width, height over 0.3 s), so the light visibly moves
  from one thing to the next. It never takes clicks.
- **Arrow:** a full-viewport SVG with two paths, the line and the head, in a
  chalk colour with a slight roughening filter so it looks hand-drawn. The line
  draws itself in over 0.6 s on each step.
- **Card:** the text (large, about 1.3 rem, light on the dim), the step dots
  (the current one a wider pill) and the **Next** button. It has no box of its
  own: it sits on the dim, except when there's no room for an arrow (§3), when
  it gets a solid backing. It's at most 460 px wide, less on a narrow screen,
  and lined up with the element it points at (§3), rather than centred.
- **Skip:** top left, clear of the safe area.

## 3. Placement

On each step, and again on resize or scroll. The aim: the card sits close to
the element, and the whole arrow, head included, stays on screen whatever the
size of the screen, the element or where the element is.

1. **Scroll:** the element is scrolled to the centre of the viewport, or to its
   top if it's taller than 60 % of the viewport, so its top edge isn't lost.
2. **Hole:** the element's bounding rectangle, padded by 8 px. It may run off
   screen; the rest of the placement uses only the element's **visible part**
   (its rectangle clipped to the viewport).
3. **Card side**, by the room around the visible part:
   - **Below or above**, whichever has more room, if that room fits the card
     plus the minimum arrow gap (36 px). This is the usual case on a phone.
   - Otherwise **right or left**, whichever has more room, if that fits the
     card plus the minimum gap. Where the room is narrower than the card, the
     card narrows to fit, but not below 220 px, and only while its taller
     text still fits the screen's height. This covers a wide, short screen, or
     an element as tall as the screen, such as a navigation column, even on a
     phone.
   - Otherwise there's **no room**: the element fills the screen. The card goes
     at the bottom, or the top if the element's top half is lower, on a
     solid dark backing so its text reads over the lit element, and **no arrow**
     is drawn: there's nowhere for it to go, and the light already shows the
     element. The card is measured with its backing on, so the backing's
     padding can't push it off screen.
4. **Gap:** the arrow gets up to 70 px, shrinking to fit what room there is, but
   never below 36 px.
5. **Card position:** on the chosen side, at most 460 px wide (less on a narrow
   screen), and **lined up with the element**, not centred on the page. Below
   or above, it's centred on the element horizontally. Right or left, it's
   centred on the element vertically. Either way it's clamped to stay 12 px
   inside the viewport. On a phone that's the same as centred. On a big screen
   it keeps the card next to an element at the far edge, rather than across
   the screen from it.
6. **Arrow:** a quadratic curve from the card to the middle of the element's
   near side (kept 12 px in from the element's ends):
   - It starts on the card's edge facing the element, as near opposite the
     tip as the card allows, so the arrow is about as long as the gap.
   - The control point is offset at right angles from the midpoint, by a
     fifth of the arrow's length, so the line bows like a hand drew it.
   - The head is two 14 px strokes back from the tip, at ±0.8π from the
     curve's last direction.
   - **Kept on screen:** the tip, the start and the control point are each
     clamped to at least 20 px inside the viewport (more than the head's
     length). A quadratic curve never leaves the triangle of those three
     points, so the line and its head can't be cut off.

## 4. Accessibility

- The step text is the dialog's label and is `aria-live="polite"`, so each step
  is read as it comes.
- **Next** takes focus on every step (without scrolling the page).
- `Escape` ends the tour (as **Skip** does). `→` moves on (as **Next** does).
- While a tour shows, the page under it doesn't scroll (`overflow: hidden` on
  `body`).
- The drawing (arrow, dots) is `aria-hidden`.
- With `prefers-reduced-motion: reduce`, the hole jumps rather than glides, and
  the arrow appears without drawing in.

## 5. State

| Key | Value | Meaning |
|---|---|---|
| `tour.welcome` | `"done"` | The welcome (the start page's tour) has been seen. |
| `tour.pages` | JSON array of page ids | The other pages whose tours have been seen. |

Both are written when a tour ends, by **Done**, **Skip** or `Escape`. If storage
throws (private mode, blocked site data), treat every tour as seen, so a broken
storage never shows a tour on every visit.

Adding a page to the app adds its tour: existing users see it the first time
they open that page. Changing an existing tour doesn't show it again; give it a
new page id if it must be seen again.

## 6. Integrating with the app's pages

The tours need four things from the app's page switching:

| Need | Shape |
|---|---|
| The page on show | `pages.active()` → id |
| Switching to a page | `pages.open(id)`, as the page's own button would |
| A switch happened | a `pagechange` event on `window` after each switch |
| A window is open over the page | a class on `body` (here `modal-open`) |

A tour's steps can point at elements outside its page (the navigation, a
settings button); they're lit wherever they are.

## 7. Reference implementation

### 7.1 Markup

None in the page: the tour builds its own layer when it starts and removes it
when it ends. Settings needs one container:

```html
<p class="section-label">Show me around</p>
<div id="tourPicks" class="tourPicks"></div>
<p class="note">Each page shows you around the first time you open it. Pick one to see its tour again.</p>
```

### 7.2 CSS

```css
.tour { position: fixed; inset: 0; z-index: 2000; }
.tourHole {
  position: fixed;
  border-radius: 18px;
  box-shadow: 0 0 0 200vmax rgba(8, 14, 10, 0.86), 0 0 24px 8px rgba(255, 255, 255, 0.35);
  transition: left 0.3s ease, top 0.3s ease, width 0.3s ease, height 0.3s ease;
  pointer-events: none;
}
.tourArrow { position: fixed; inset: 0; width: 100%; height: 100%; pointer-events: none; overflow: visible; }
.tourLine, .tourHead {
  fill: none;
  stroke: #f6f1e6;
  stroke-width: 3.5;
  stroke-linecap: round;
  stroke-linejoin: round;
}
/* Drawn in over its own length; the script sets --len. */
.tourLine { stroke-dasharray: var(--len, 600); stroke-dashoffset: var(--len, 600); animation: tour-draw 0.6s ease forwards; }
@keyframes tour-draw { to { stroke-dashoffset: 0; } }
.tourSkip {
  position: fixed;
  top: max(16px, calc(env(safe-area-inset-top) + 12px));
  left: 16px;
  padding: 8px 14px;
  background: none;
  border: 0;
  color: #f6f1e6;
  font-size: 1.05rem;
}
/* Placed by the script (§3): left and top set on each step. */
.tourCard { position: fixed; box-sizing: border-box; width: min(460px, calc(100vw - 24px)); color: #f6f1e6; }
/* No room for an arrow: the card sits on its own backing, over the lit element. */
.tourCard.solid { padding: 14px 16px; border-radius: 16px; background: rgba(8, 14, 10, 0.92); box-shadow: 0 8px 30px rgba(0, 0, 0, 0.5); }
.tourText { font-size: 1.3rem; line-height: 1.35; text-shadow: 0 1px 8px rgba(0, 0, 0, 0.6); }
.tourFoot { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 14px; }
.tourNext { background: #f6f1e6; color: #1a221d; border: 0; border-radius: 999px; padding: 10px 22px; }
.tourDots { display: flex; gap: 6px; }
.tourDots > span { width: 7px; height: 7px; border-radius: 999px; background: rgba(246, 241, 230, 0.4); transition: width 0.2s ease; }
.tourDots > .on { width: 20px; background: #f6f1e6; }
body.touring { overflow: hidden; }
.tourPicks { display: flex; flex-wrap: wrap; gap: 8px; }

@media (prefers-reduced-motion: reduce) {
  .tourHole { transition: none; }
  .tourLine { animation: none; stroke-dashoffset: 0; }
}
```

The dim and chalk colours are fixed rather than themed: the tour reads the same
over a light or a dark page.

### 7.3 JavaScript

```js
(function () {
  const WELCOME_KEY = 'tour.welcome';
  const PAGES_KEY = 'tour.pages';
  const PAD = 8;
  const START = 'home'; // the start page, whose tour is the welcome

  // Each page's steps: `el` a selector (alternatives allowed), `text` one line.
  const TOURS = {
    home: {
      label: 'Home',
      steps: [
        { el: '#summary', text: 'Your day at a glance. Tap it for the details.' },
        { el: '#filterChip', text: 'Pick what shows here.' },
        { el: '#nav', text: 'Each page has its button here. Press and hold one to see what it does.' },
        { el: '#settingsBtn', text: 'Settings can show any page’s tour again.' },
      ],
    },
    search: {
      label: 'Search',
      steps: [
        { el: '#searchBox', text: 'Search by name or code.' },
        { el: '#voiceBtn', text: 'Or say it.' },
        { el: '#results .item, #results .empty', text: 'What you find shows here.' },
      ],
    },
    // ...one entry per page
  };

  let steps = [];
  let at = 0;
  let root = null; // the layer, or `true` while a tour is getting ready
  let page = null;
  let began = null;

  function seen(id) {
    try {
      if (id === START) return localStorage.getItem(WELCOME_KEY) === 'done';
      return JSON.parse(localStorage.getItem(PAGES_KEY) || '[]').includes(id);
    } catch { return true; }
  }
  function markSeen(id) {
    try {
      if (id === START) return localStorage.setItem(WELCOME_KEY, 'done');
      const list = JSON.parse(localStorage.getItem(PAGES_KEY) || '[]');
      if (!list.includes(id)) localStorage.setItem(PAGES_KEY, JSON.stringify([...list, id]));
    } catch { /* shown again next time */ }
  }

  function visible(el) {
    if (!el || el.closest('[hidden]')) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
  }
  const target = (s) => [...document.querySelectorAll(s.el)].find(visible) || null;

  function build() {
    root = document.createElement('div');
    root.className = 'tour';
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-labelledby', 'tourText');
    root.innerHTML =
      '<div class="tourHole"></div>' +
      '<svg class="tourArrow" aria-hidden="true"><defs><filter id="tourChalk"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="2.5"/></filter></defs>' +
      '<path class="tourLine" filter="url(#tourChalk)"/><path class="tourHead" filter="url(#tourChalk)"/></svg>' +
      '<button class="tourSkip" type="button">Skip</button>' +
      '<div class="tourCard"><p id="tourText" class="tourText" aria-live="polite"></p>' +
      '<div class="tourFoot"><span class="tourDots" aria-hidden="true"></span><button class="tourNext" type="button">Next</button></div></div>';
    document.body.appendChild(root);
    root.querySelector('.tourSkip').addEventListener('click', end);
    root.querySelector('.tourNext').addEventListener('click', next);
    root.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') end();
      if (e.key === 'ArrowRight') next();
    });
    window.addEventListener('resize', place);
    window.addEventListener('scroll', place, true);
  }

  function show(i) {
    at = i;
    const el = steps[i].target;
    // §3.1: a tall element from its top.
    const tall = el.getBoundingClientRect().height > innerHeight * 0.6;
    el.scrollIntoView({ block: tall ? 'start' : 'center', behavior: 'instant' });
    root.querySelector('.tourText').textContent = steps[i].text;
    root.querySelector('.tourDots').innerHTML = steps.map((_, n) => `<span${n === i ? ' class="on"' : ''}></span>`).join('');
    root.querySelector('.tourNext').textContent = i === steps.length - 1 ? 'Done' : 'Next';
    requestAnimationFrame(place);
    root.querySelector('.tourNext').focus({ preventScroll: true });
  }

  // §3: the hole, the card on the side with room, lined up with the element, and
  // the arrow between them, all of it on screen.
  const M = 12;        // the card's margin from the viewport's edges
  const EDGE = 20;     // the arrow's: more than the head's length
  const GAP_MIN = 36;
  const GAP_MAX = 70;
  const CARD_MIN = 220; // the narrowest the card goes to fit beside an element
  const clamp = (lo, v, hi) => Math.max(lo, Math.min(v, Math.max(lo, hi)));

  function place() {
    if (!root || root === true) return;
    const el = steps[at]?.target;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const vw = innerWidth, vh = innerHeight;
    const hole = root.querySelector('.tourHole');
    Object.assign(hole.style, {
      left: `${r.left - PAD}px`, top: `${r.top - PAD}px`,
      width: `${r.width + PAD * 2}px`, height: `${r.height + PAD * 2}px`,
    });

    // The element's visible part: all placement works from it.
    const v = {
      left: Math.max(r.left, 0), right: Math.min(r.right, vw),
      top: Math.max(r.top, 0), bottom: Math.min(r.bottom, vh),
    };
    const card = root.querySelector('.tourCard');
    card.classList.remove('solid');
    card.style.width = '';
    let cw = card.offsetWidth, ch = card.offsetHeight;
    const room = {
      below: vh - v.bottom - PAD - M, above: v.top - PAD - M,
      right: vw - v.right - PAD - M, left: v.left - PAD - M,
    };
    let side = null;
    if (Math.max(room.below, room.above) >= ch + GAP_MIN) side = room.below >= room.above ? 'below' : 'above';
    else {
      // Beside it, narrowing the card to fit if need be, while its text still fits the height.
      const s = room.right >= room.left ? 'right' : 'left';
      const fit = room[s] - GAP_MIN;
      if (fit >= Math.min(cw, CARD_MIN)) {
        if (fit < cw) {
          card.style.width = `${fit}px`;
          cw = card.offsetWidth;
          ch = card.offsetHeight;
        }
        if (ch <= vh - M * 2) side = s;
        else card.style.width = '';
      }
    }

    const line = root.querySelector('.tourLine');
    const head = root.querySelector('.tourHead');
    let left, top;
    if (!side) {
      // No room: the card on a backing at the end away from most of the element, no arrow,
      // measured with the backing on.
      card.classList.add('solid');
      cw = card.offsetWidth;
      ch = card.offsetHeight;
      left = (vw - cw) / 2;
      top = (v.top + v.bottom) / 2 > vh / 2 ? M : vh - ch - M;
      Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
      line.setAttribute('d', '');
      head.setAttribute('d', '');
      return;
    }

    const midX = (v.left + v.right) / 2, midY = (v.top + v.bottom) / 2;
    let sx, sy, tx, ty;
    if (side === 'below' || side === 'above') {
      const gap = clamp(GAP_MIN, room[side] - ch, GAP_MAX);
      left = clamp(M, midX - cw / 2, vw - cw - M);
      top = side === 'below' ? v.bottom + PAD + gap : v.top - PAD - gap - ch;
      top = clamp(M, top, vh - ch - M);
      tx = clamp(v.left + 12, midX, v.right - 12);
      ty = side === 'below' ? v.bottom + PAD + 4 : v.top - PAD - 4;
      sx = clamp(left + 24, tx, left + cw - 24);
      sy = side === 'below' ? top - 6 : top + ch + 6;
    } else {
      const gap = clamp(GAP_MIN, room[side] - cw, GAP_MAX);
      left = side === 'right' ? v.right + PAD + gap : v.left - PAD - gap - cw;
      left = clamp(M, left, vw - cw - M);
      top = clamp(M, midY - ch / 2, vh - ch - M);
      tx = side === 'right' ? v.right + PAD + 4 : v.left - PAD - 4;
      ty = clamp(v.top + 12, midY, v.bottom - 12);
      sx = side === 'right' ? left - 6 : left + cw + 6;
      sy = clamp(top + 16, ty, top + ch - 16);
    }
    Object.assign(card.style, { left: `${left}px`, top: `${top}px` });

    // Every point of the arrow EDGE in from the viewport, so none of it is cut off.
    const inX = (x) => clamp(EDGE, x, vw - EDGE);
    const inY = (y) => clamp(EDGE, y, vh - EDGE);
    tx = inX(tx); ty = inY(ty); sx = inX(sx); sy = inY(sy);
    const dx = tx - sx, dy = ty - sy;
    const mx = inX((sx + tx) / 2 - dy * 0.2);
    const my = inY((sy + ty) / 2 + dx * 0.2);

    root.querySelector('.tourArrow').setAttribute('viewBox', `0 0 ${vw} ${vh}`);
    line.setAttribute('d', `M${sx},${sy} Q${mx},${my} ${tx},${ty}`);
    line.style.setProperty('--len', Math.ceil(line.getTotalLength()) + 10);
    const ang = Math.atan2(ty - my, tx - mx);
    const a1 = ang + Math.PI * 0.8, a2 = ang - Math.PI * 0.8, len = 14;
    head.setAttribute('d',
      `M${tx + Math.cos(a1) * len},${ty + Math.sin(a1) * len} L${tx},${ty} L${tx + Math.cos(a2) * len},${ty + Math.sin(a2) * len}`);
  }

  function next() {
    if (at < steps.length - 1) show(at + 1);
    else end();
  }

  function end() {
    if (page) markSeen(page);
    removeEventListener('resize', place);
    removeEventListener('scroll', place, true);
    if (root && root !== true) root.remove();
    root = null;
    page = null;
    document.body.classList.remove('touring');
    const back = began;
    began = null;
    scrollTo({ top: 0, behavior: 'instant' });
    // Back where it began, which may be a page whose own tour is still to see.
    if (back && pages.active() !== back) pages.open(back);
    else setTimeout(forPage, 600);
  }

  // `id`'s tour, on its page.
  function start(id = START) {
    if (root || !TOURS[id]) return;
    const from = pages.active();
    if (from !== id) pages.open(id);
    root = true; // taken, while the page draws
    setTimeout(() => {
      root = null;
      steps = TOURS[id].steps.map((s) => ({ ...s, target: target(s) })).filter((s) => s.target);
      if (!steps.length) {
        markSeen(id);
        if (pages.active() !== from) pages.open(from);
        return;
      }
      page = id;
      began = from;
      document.body.classList.add('touring');
      build();
      show(0);
    }, from === id ? 0 : 400);
  }

  // The page on show's tour, the first time, once it's drawn. `ready(id)` says
  // whether a page that loads its content has it; most pages are ready at once.
  const ready = (id) => true;
  let waiting = null;
  function forPage() {
    const id = pages.active();
    if (!id || root || seen(id) || !TOURS[id]) return;
    clearInterval(waiting);
    let tries = 0;
    waiting = setInterval(() => {
      tries++;
      if (pages.active() !== id || root) return clearInterval(waiting);
      if (ready(id) ? tries < 2 : tries <= 16) return;
      clearInterval(waiting);
      if (!document.body.classList.contains('modal-open')) start(id);
    }, 500);
  }

  // At start-up: the welcome, unless a link opened something.
  function init() {
    addEventListener('pagechange', forPage);
    if (location.hash.length > 1 || location.search) return;
    if (!seen(START) && pages.active() !== START) {
      setTimeout(() => { if (!document.body.classList.contains('modal-open')) start(START); }, 1500);
      return;
    }
    forPage();
  }

  // Settings' Show me around: a button per page.
  function pickers() {
    return Object.entries(TOURS)
      .map(([id, t]) => `<button class="pick" type="button" data-tour="${id}">${t.label}</button>`)
      .join('');
  }

  window.Tour = { init, start, end, pickers };
})();
```

Wiring it up:

```js
Tour.init(); // once the app's pages are set up

// Each time Settings opens:
document.getElementById('tourPicks').innerHTML = Tour.pickers();

document.getElementById('tourPicks').addEventListener('click', (e) => {
  const btn = e.target.closest('[data-tour]');
  if (!btn) return;
  closeSettings();
  setTimeout(() => Tour.start(btn.dataset.tour), 300); // after the window has gone
});
```

## 8. Writing the steps

- **Three to five steps a page.** One element and one line each.
- **Say what it does, not what it is.** "Pick what shows here", not "This is
  the filter chip".
- **Light real things.** Never a placeholder or a mock: if it isn't on the page,
  the step drops out (§1).
- **Cover the empty state.** For a page that's empty until used, add a step on
  its empty message saying how to fill it; it shows only while the page is
  empty, and the steps on its items only once it has some.
- **Alternatives for variants.** A page with tabs or modes lists the matching
  element of each in one selector (`#tabA .fields, #tabB .fields`), so the step
  lights whichever is showing.
- **Keep the welcome short.** It's the first thing a new user sees: the start
  page's two or three key things, then where the other pages are and where to
  replay tours.

## 9. Adding it to an app

1. Add the CSS (§7.2) and the script (§7.3).
2. Give the script the app's page switching (§6): `pages.active()`,
   `pages.open(id)`, a `pagechange` event, and a `modal-open` class while a
   window is open.
3. Write a tour for each page (§8), with an id matching the page's.
4. Call `Tour.init()` once the pages are set up.
5. Add **Show me around** to Settings, with a button per tour.
6. Any automated screenshots or tests of the app's pages should mark every tour
   as seen first (`tour.welcome` = `"done"`, `tour.pages` = every id), so tours
   don't cover them.
