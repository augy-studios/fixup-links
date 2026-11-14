/* Page tours (page-tour-spec.md in docs/): a few steps over a page the first time it's shown, the
   page dimmed, one thing on it lit, and a chalk arrow to it from a line saying what it does.
   Next moves on, Skip (or Escape) ends it. The home page's is the welcome, the first time the site
   is opened. The Edge Tray's Show me around has each again.

   The site has one page, and two windows that are places of their own: History and Share
   history. Each of the three has a tour, shown the first time it's opened, lighting things inside
   it. Any other window (Theme, QR code) keeps tours away while it's open.

   Each step names its thing by a CSS selector (alternatives allowed: the first visible one is
   lit), and a step whose thing isn't there is left out, so an empty history gets the step about
   filling it, and a full one the steps about its items.

   Tours stay on screen whatever its size: the lit thing is scrolled into view first (inside its
   window, if it's in one), the card goes on the side with room, and every point of the arrow is
   kept inside the viewport (§3).

   Seen: tour.welcome ("done", the home page's) and tour.pages (the others' ids), written when a
   tour ends, whichever way. Storage that throws counts every tour as seen. */
'use strict';

(function () {
  const WELCOME_KEY = 'tour.welcome';
  const PAGES_KEY = 'tour.pages';
  const PAD = 8;
  const START = 'home';

  // The windows that are pages, by tour id.
  const WINDOWS = { history: 'historyModal', sync: 'syncModal' };

  const TOURS = {
    home: {
      label: 'Home',
      steps: [
        { el: '.cleaner-card .input-group', text: 'Paste or type a link here. The paste button fills it in from what you’ve copied.' },
        { el: '#cleanBtn', text: 'Clean it: trackers go, and links to X, Instagram, TikTok and more turn into ones that show a preview.' },
        { el: '#resultArea .result-actions', text: 'Copy the clean link, open it, share it, or make a QR code of it.' },
        { el: '#openHistoryModal', text: 'Every link you clean is kept here, on this device. Share it with your other devices from there.' },
        { el: '#tourBtn', text: 'Show me around has this tour, and the others, again. The arrow above tucks these buttons away.' },
      ],
    },
    history: {
      label: 'History',
      steps: [
        { el: '#historyList .history-item, #historyEmpty', text: 'Every link you’ve cleaned, newest first, with its page’s title. Tap one to clean it again.' },
        { el: '#historyList .history-item-delete', text: 'The bin deletes one link from your history.' },
        { el: '#openSyncBtn', text: 'Share history with your phone, computer or another browser, straight from one to the other.' },
        { el: '#clearHistoryBtn', text: 'Clear All empties your history on this device.' },
      ],
    },
    sync: {
      label: 'Share history',
      steps: [
        { el: '#syncTabs', text: 'One device shows a code, and the other enters it.' },
        { el: '#syncHostCard, #syncJoinForm', text: 'On the other device, type this code, scan the QR code or open the link. Or type the code the other device shows.' },
        { el: '#syncNetNote', text: 'Both have to be on the same wifi, or one on the other’s hotspot. Your history goes straight between them, through no server.' },
      ],
    },
  };

  /* ---------- the app's pages (§6) ---------- */

  const isOpen = (id) => { const m = document.getElementById(id); return !!m && !m.classList.contains('hidden'); };

  const pages = {
    active() {
      if (isOpen('syncModal')) return 'sync';
      if (isOpen('historyModal')) return 'history';
      return 'home';
    },
    open(id) {
      if (id === 'home') {
        for (const m of Object.values(WINDOWS)) if (isOpen(m)) closeModal(m);
      } else if (id === 'history') {
        if (isOpen('syncModal')) closeModal('syncModal');
        document.getElementById('openHistoryModal').click();
      } else if (id === 'sync') {
        if (isOpen('historyModal')) closeModal('historyModal');
        window.HistorySync?.open();
      }
    },
  };

  // Another window over the page: Theme, QR code, Notifications... A page's own window doesn't
  // count.
  function blocked(id) {
    return [...document.querySelectorAll('.modal-backdrop:not(.hidden)')].some((m) => m.id !== WINDOWS[id]);
  }

  /* ---------- state (§5) ---------- */

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

  /* ---------- the layer ---------- */

  let steps = [];
  let at = 0;
  let root = null; // the layer, or `true` while a tour is getting ready
  let page = null;
  let began = null;

  function visible(el) {
    if (!el || el.closest('[hidden]') || el.closest('.modal-backdrop.hidden')) return false;
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
      if (e.key === 'Escape') { e.stopPropagation(); end(); }
      if (e.key === 'ArrowRight') next();
    });
    addEventListener('resize', place);
    addEventListener('scroll', place, true);
  }

  // §3.1: scrolled to the centre, or a tall thing to its top, inside whatever scrolls it (the
  // page, or a window's list), so it's on screen before it's lit.
  function reveal(el) {
    const tall = el.getBoundingClientRect().height > innerHeight * 0.6;
    el.scrollIntoView({ block: tall ? 'start' : 'center', inline: 'nearest', behavior: 'instant' });
  }

  function show(i) {
    at = i;
    const s = steps[i];
    // It may have gone (a result cleared, a list emptied): looked for again.
    if (!s.target.isConnected || !visible(s.target)) s.target = target(s) || s.target;
    reveal(s.target);
    root.querySelector('.tourText').textContent = s.text;
    root.querySelector('.tourDots').innerHTML = steps.map((_, n) => `<span${n === i ? ' class="on"' : ''}></span>`).join('');
    root.querySelector('.tourNext').textContent = i === steps.length - 1 ? 'Done' : 'Next';
    requestAnimationFrame(place);
    root.querySelector('.tourNext').focus({ preventScroll: true });
  }

  // §3: the hole, the card on the side with room, lined up with its thing, and the arrow between
  // them, all of it on screen.
  const M = 12; // the card's margin from the viewport's edges
  const EDGE = 20; // the arrow's: more than the head's length
  const GAP_MIN = 36;
  const GAP_MAX = 70;
  const CARD_MIN = 220;
  const clamp = (lo, v, hi) => Math.max(lo, Math.min(v, Math.max(lo, hi)));

  function place() {
    if (!root || root === true) return;
    const el = steps[at]?.target;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const vw = document.documentElement.clientWidth || innerWidth, vh = innerHeight;
    const hole = root.querySelector('.tourHole');
    Object.assign(hole.style, {
      left: `${r.left - PAD}px`, top: `${r.top - PAD}px`,
      width: `${r.width + PAD * 2}px`, height: `${r.height + PAD * 2}px`,
    });

    // The thing's visible part: all placement works from it.
    const v = {
      left: clamp(0, r.left, vw), right: clamp(0, r.right, vw),
      top: clamp(0, r.top, vh), bottom: clamp(0, r.bottom, vh),
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
      // No room: the card on a backing at the end away from most of the thing, and no arrow.
      card.classList.add('solid');
      cw = card.offsetWidth;
      ch = card.offsetHeight;
      left = clamp(M, (vw - cw) / 2, vw - cw - M);
      top = (v.top + v.bottom) / 2 > vh / 2 ? M : vh - ch - M;
      top = clamp(M, top, vh - ch - M);
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
    if (back && pages.active() !== back) {
      pages.open(back);
      setTimeout(forPage, 600);
    } else setTimeout(forPage, 600);
  }

  // `id`'s tour, on its page.
  function start(id = START) {
    if (root || !TOURS[id]) return;
    const from = pages.active();
    if (from !== id) pages.open(id);
    root = true; // taken, while the page draws
    setTimeout(() => {
      root = null;
      if (pages.active() !== id) return; // the page didn't open (Share history, say, offline)
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
    }, from === id ? 0 : 450);
  }

  // The page on show's tour, the first time, once it's drawn.
  let waiting = null;
  function forPage() {
    const id = pages.active();
    if (!id || root || seen(id) || !TOURS[id]) return;
    clearInterval(waiting);
    let tries = 0;
    waiting = setInterval(() => {
      tries++;
      if (pages.active() !== id || root) return clearInterval(waiting);
      if (tries < 2) return;
      clearInterval(waiting);
      if (!blocked(id)) start(id);
    }, 500);
  }

  // At start-up: the welcome, unless a link opened something (a link came for that, not a tour).
  function init() {
    addEventListener('pagechange', forPage);
    if (location.hash.length > 1 || location.search || window.uwufixOpenedByLink) return;
    forPage();
  }

  // Show me around: a button per page.
  function pickers() {
    return Object.entries(TOURS)
      .map(([id, t]) => `<button class="pick" type="button" data-tour="${id}">${t.label}</button>`)
      .join('');
  }

  document.addEventListener('DOMContentLoaded', () => {
    // After the other scripts' own DOMContentLoaded work, so the page is set up.
    setTimeout(init, 0);
    const picks = document.getElementById('tourPicks');
    const btn = document.getElementById('tourBtn');
    if (!picks || !btn) return;
    btn.addEventListener('click', () => {
      picks.innerHTML = pickers();
      openModal('tourModal');
    });
    picks.addEventListener('click', (e) => {
      const b = e.target.closest('[data-tour]');
      if (!b) return;
      closeModal('tourModal');
      setTimeout(() => start(b.dataset.tour), 300); // after the window has gone
    });
  });

  window.Tour = { init, start, end, pickers, TOURS };
})();
