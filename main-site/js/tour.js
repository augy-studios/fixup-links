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
        { selector: '.cleaner-card .input-group', text: 'Paste or type a link here. The paste button fills it in from what you’ve copied.' },
        { selector: '#cleanBtn', text: 'Clean it: trackers go, and links to X, Instagram, TikTok and more turn into ones that show a preview.' },
        { selector: '#resultArea .result-actions', text: 'Copy the clean link, open it, share it, or make a QR code of it.' },
        { selector: '#openHistoryModal', text: 'Every link you clean is kept here, on this device. Share it with your other devices from there.' },
        { selector: '#tourBtn', text: 'Show me around has this tour, and the others, again. The arrow above tucks these buttons away.' },
      ],
    },
    history: {
      label: 'History',
      steps: [
        { selector: '#historyList .history-item, #historyEmpty', text: 'Every link you’ve cleaned, newest first, with its page’s title. Tap one to clean it again.' },
        { selector: '#historyList .history-item-delete', text: 'The bin deletes one link from your history.' },
        { selector: '#openSyncBtn', text: 'Share history with your phone, computer or another browser, straight from one to the other.' },
        { selector: '#clearHistoryBtn', text: 'Clear All empties your history on this device.' },
      ],
    },
    sync: {
      label: 'Share history',
      steps: [
        { selector: '#syncTabs', text: 'One device shows a code, and the other enters it.' },
        { selector: '#syncHostCard, #syncJoinForm', text: 'On the other device, type this code, scan the QR code or open the link. Or type the code the other device shows.' },
        { selector: '#syncNetNote', text: 'Both have to be on the same wifi, or one on the other’s hotspot. Your history goes straight between them, through no server.' },
      ],
    },
  };

  /* ---------- the app's pages (§6) ---------- */

  function isOpen(id) {
    const modal = document.getElementById(id);
    return !!modal && !modal.classList.contains('hidden');
  }

  const pages = {
    active() {
      if (isOpen('syncModal')) {
        return 'sync';
      }
      if (isOpen('historyModal')) {
        return 'history';
      }
      return 'home';
    },
    open(id) {
      if (id === 'home') {
        for (const modalId of Object.values(WINDOWS)) {
          if (isOpen(modalId)) {
            closeModal(modalId);
          }
        }
      } else if (id === 'history') {
        if (isOpen('syncModal')) {
          closeModal('syncModal');
        }
        document.getElementById('openHistoryModal').click();
      } else if (id === 'sync') {
        if (isOpen('historyModal')) {
          closeModal('historyModal');
        }
        window.HistorySync?.open();
      }
    },
  };

  // Another window over the page: Theme, QR code, Notifications... A page's own window doesn't
  // count.
  function blocked(id) {
    for (const modal of document.querySelectorAll('.modal-backdrop:not(.hidden)')) {
      if (modal.id !== WINDOWS[id]) {
        return true;
      }
    }
    return false;
  }

  /* ---------- state (§5) ---------- */

  /** The ids of the pages (other than home) whose tours have been seen, from storage. Throws if storage does. */
  function seenPages() {
    let storedText = localStorage.getItem(PAGES_KEY);
    if (!storedText) {
      storedText = '[]';
    }
    return JSON.parse(storedText);
  }

  function seen(id) {
    try {
      if (id === START) {
        return localStorage.getItem(WELCOME_KEY) === 'done';
      }
      return seenPages().includes(id);
    } catch {
      return true;
    }
  }

  function markSeen(id) {
    try {
      if (id === START) {
        localStorage.setItem(WELCOME_KEY, 'done');
        return;
      }
      const list = seenPages();
      if (!list.includes(id)) {
        localStorage.setItem(PAGES_KEY, JSON.stringify([...list, id]));
      }
    } catch { /* shown again next time */ }
  }

  /* ---------- the layer ---------- */

  let steps = [];
  let at = 0;
  let root = null; // the layer, or `true` while a tour is getting ready
  let page = null;
  let began = null;

  /** Whether the element is on the page and drawn: not hidden, not in a closed window, not zero-sized. */
  function visible(element) {
    if (!element || element.closest('[hidden]') || element.closest('.modal-backdrop.hidden')) {
      return false;
    }
    const rectangle = element.getBoundingClientRect();
    return rectangle.width > 0 && rectangle.height > 0 && getComputedStyle(element).visibility !== 'hidden';
  }

  /** The first visible element matching the step's selector, or null. */
  function target(step) {
    for (const element of document.querySelectorAll(step.selector)) {
      if (visible(element)) {
        return element;
      }
    }
    return null;
  }

  /** Creates the tour layer (hole, chalk arrow, Skip, and the card) and wires its buttons and keys. */
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
    root.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') {
        event.stopPropagation();
        end();
      }
      if (event.key === 'ArrowRight') {
        next();
      }
    });
    addEventListener('resize', place);
    addEventListener('scroll', place, true);
  }

  // §3.1: scrolled to the centre, or a tall thing to its top, inside whatever scrolls it (the
  // page, or a window's list), so it's on screen before it's lit.
  function reveal(element) {
    const tall = element.getBoundingClientRect().height > innerHeight * 0.6;
    let block = 'center';
    if (tall) {
      block = 'start';
    }
    element.scrollIntoView({ block, inline: 'nearest', behavior: 'instant' });
  }

  /** Shows step number stepIndex: its thing scrolled into view, its text, the dots, and Next or Done. */
  function show(stepIndex) {
    at = stepIndex;
    const step = steps[stepIndex];
    // It may have gone (a result cleared, a list emptied): looked for again.
    if (!step.target.isConnected || !visible(step.target)) {
      const foundAgain = target(step);
      if (foundAgain) {
        step.target = foundAgain;
      }
    }
    reveal(step.target);
    root.querySelector('.tourText').textContent = step.text;
    let dotsHtml = '';
    for (let dotIndex = 0; dotIndex < steps.length; dotIndex++) {
      if (dotIndex === stepIndex) {
        dotsHtml += '<span class="on"></span>';
      } else {
        dotsHtml += '<span></span>';
      }
    }
    root.querySelector('.tourDots').innerHTML = dotsHtml;
    if (stepIndex === steps.length - 1) {
      root.querySelector('.tourNext').textContent = 'Done';
    } else {
      root.querySelector('.tourNext').textContent = 'Next';
    }
    requestAnimationFrame(place);
    root.querySelector('.tourNext').focus({ preventScroll: true });
  }

  // §3: the hole, the card on the side with room, lined up with its thing, and the arrow between
  // them, all of it on screen.
  const MARGIN = 12; // the card's margin from the viewport's edges
  const EDGE = 20; // the arrow's: more than the head's length
  const GAP_MIN = 36;
  const GAP_MAX = 70;
  const CARD_MIN = 220;

  /** The value kept between low and high (and never below low, even when high is). */
  function clamp(low, value, high) {
    return Math.max(low, Math.min(value, Math.max(low, high)));
  }

  /**
   * Lays out the current step: the hole over its thing, the card on whichever side has room (or on
   * a backing when no side has), and the chalk arrow from the card to the thing, all inside the
   * viewport. Runs on every step, resize and scroll.
   */
  function place() {
    if (!root || root === true) {
      return;
    }
    const element = steps[at]?.target;
    if (!element) {
      return;
    }
    const rectangle = element.getBoundingClientRect();
    let viewportWidth = document.documentElement.clientWidth;
    if (!viewportWidth) {
      viewportWidth = innerWidth;
    }
    const viewportHeight = innerHeight;
    const hole = root.querySelector('.tourHole');
    Object.assign(hole.style, {
      left: `${rectangle.left - PAD}px`, top: `${rectangle.top - PAD}px`,
      width: `${rectangle.width + PAD * 2}px`, height: `${rectangle.height + PAD * 2}px`,
    });

    // The thing's visible part: all placement works from it.
    const shown = {
      left: clamp(0, rectangle.left, viewportWidth), right: clamp(0, rectangle.right, viewportWidth),
      top: clamp(0, rectangle.top, viewportHeight), bottom: clamp(0, rectangle.bottom, viewportHeight),
    };
    const card = root.querySelector('.tourCard');
    card.classList.remove('solid');
    card.style.width = '';
    let cardWidth = card.offsetWidth;
    let cardHeight = card.offsetHeight;
    const room = {
      below: viewportHeight - shown.bottom - PAD - MARGIN, above: shown.top - PAD - MARGIN,
      right: viewportWidth - shown.right - PAD - MARGIN, left: shown.left - PAD - MARGIN,
    };
    let side = null;
    if (Math.max(room.below, room.above) >= cardHeight + GAP_MIN) {
      if (room.below >= room.above) {
        side = 'below';
      } else {
        side = 'above';
      }
    } else {
      // Beside it, narrowing the card to fit if need be, while its text still fits the height.
      let besideSide = 'left';
      if (room.right >= room.left) {
        besideSide = 'right';
      }
      const fit = room[besideSide] - GAP_MIN;
      if (fit >= Math.min(cardWidth, CARD_MIN)) {
        if (fit < cardWidth) {
          card.style.width = `${fit}px`;
          cardWidth = card.offsetWidth;
          cardHeight = card.offsetHeight;
        }
        if (cardHeight <= viewportHeight - MARGIN * 2) {
          side = besideSide;
        } else {
          card.style.width = '';
        }
      }
    }

    const line = root.querySelector('.tourLine');
    const head = root.querySelector('.tourHead');
    let left;
    let top;
    if (!side) {
      // No room: the card on a backing at the end away from most of the thing, and no arrow.
      card.classList.add('solid');
      cardWidth = card.offsetWidth;
      cardHeight = card.offsetHeight;
      left = clamp(MARGIN, (viewportWidth - cardWidth) / 2, viewportWidth - cardWidth - MARGIN);
      if ((shown.top + shown.bottom) / 2 > viewportHeight / 2) {
        top = MARGIN;
      } else {
        top = viewportHeight - cardHeight - MARGIN;
      }
      top = clamp(MARGIN, top, viewportHeight - cardHeight - MARGIN);
      Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
      line.setAttribute('d', '');
      head.setAttribute('d', '');
      return;
    }

    const middleX = (shown.left + shown.right) / 2;
    const middleY = (shown.top + shown.bottom) / 2;
    // The arrow runs from (startX, startY) at the card to (tipX, tipY) at the thing.
    let startX;
    let startY;
    let tipX;
    let tipY;
    if (side === 'below' || side === 'above') {
      const gap = clamp(GAP_MIN, room[side] - cardHeight, GAP_MAX);
      left = clamp(MARGIN, middleX - cardWidth / 2, viewportWidth - cardWidth - MARGIN);
      if (side === 'below') {
        top = shown.bottom + PAD + gap;
      } else {
        top = shown.top - PAD - gap - cardHeight;
      }
      top = clamp(MARGIN, top, viewportHeight - cardHeight - MARGIN);
      tipX = clamp(shown.left + 12, middleX, shown.right - 12);
      if (side === 'below') {
        tipY = shown.bottom + PAD + 4;
      } else {
        tipY = shown.top - PAD - 4;
      }
      startX = clamp(left + 24, tipX, left + cardWidth - 24);
      if (side === 'below') {
        startY = top - 6;
      } else {
        startY = top + cardHeight + 6;
      }
    } else {
      const gap = clamp(GAP_MIN, room[side] - cardWidth, GAP_MAX);
      if (side === 'right') {
        left = shown.right + PAD + gap;
      } else {
        left = shown.left - PAD - gap - cardWidth;
      }
      left = clamp(MARGIN, left, viewportWidth - cardWidth - MARGIN);
      top = clamp(MARGIN, middleY - cardHeight / 2, viewportHeight - cardHeight - MARGIN);
      if (side === 'right') {
        tipX = shown.right + PAD + 4;
      } else {
        tipX = shown.left - PAD - 4;
      }
      tipY = clamp(shown.top + 12, middleY, shown.bottom - 12);
      if (side === 'right') {
        startX = left - 6;
      } else {
        startX = left + cardWidth + 6;
      }
      startY = clamp(top + 16, tipY, top + cardHeight - 16);
    }
    Object.assign(card.style, { left: `${left}px`, top: `${top}px` });

    // Every point of the arrow EDGE in from the viewport, so none of it is cut off.
    function insideX(coordinate) {
      return clamp(EDGE, coordinate, viewportWidth - EDGE);
    }
    function insideY(coordinate) {
      return clamp(EDGE, coordinate, viewportHeight - EDGE);
    }
    tipX = insideX(tipX);
    tipY = insideY(tipY);
    startX = insideX(startX);
    startY = insideY(startY);
    const deltaX = tipX - startX;
    const deltaY = tipY - startY;
    // The curve's control point, pushed off to one side of the straight line so the arrow bends.
    const controlX = insideX((startX + tipX) / 2 - deltaY * 0.2);
    const controlY = insideY((startY + tipY) / 2 + deltaX * 0.2);

    root.querySelector('.tourArrow').setAttribute('viewBox', `0 0 ${viewportWidth} ${viewportHeight}`);
    line.setAttribute('d', `M${startX},${startY} Q${controlX},${controlY} ${tipX},${tipY}`);
    line.style.setProperty('--length', Math.ceil(line.getTotalLength()) + 10);
    const angle = Math.atan2(tipY - controlY, tipX - controlX);
    const firstBarbAngle = angle + Math.PI * 0.8;
    const secondBarbAngle = angle - Math.PI * 0.8;
    const barbLength = 14;
    head.setAttribute('d',
      `M${tipX + Math.cos(firstBarbAngle) * barbLength},${tipY + Math.sin(firstBarbAngle) * barbLength} L${tipX},${tipY} L${tipX + Math.cos(secondBarbAngle) * barbLength},${tipY + Math.sin(secondBarbAngle) * barbLength}`);
  }

  function next() {
    if (at < steps.length - 1) {
      show(at + 1);
    } else {
      end();
    }
  }

  /** Ends the tour (Skip, Escape or Done): marks it seen, removes the layer, and goes back where it began. */
  function end() {
    if (page) {
      markSeen(page);
    }
    removeEventListener('resize', place);
    removeEventListener('scroll', place, true);
    if (root && root !== true) {
      root.remove();
    }
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
    } else {
      setTimeout(forPage, 600);
    }
  }

  // `id`'s tour, on its page.
  function start(id = START) {
    if (root || !TOURS[id]) {
      return;
    }
    const from = pages.active();
    if (from !== id) {
      pages.open(id);
    }
    root = true; // taken, while the page draws
    let delay = 450;
    if (from === id) {
      delay = 0;
    }
    setTimeout(function () {
      root = null;
      if (pages.active() !== id) {
        return; // the page didn't open (Share history, say, offline)
      }
      steps = [];
      for (const step of TOURS[id].steps) {
        const stepTarget = target(step);
        if (stepTarget) {
          steps.push({ ...step, target: stepTarget });
        }
      }
      if (!steps.length) {
        markSeen(id);
        if (pages.active() !== from) {
          pages.open(from);
        }
        return;
      }
      page = id;
      began = from;
      document.body.classList.add('touring');
      build();
      show(0);
    }, delay);
  }

  // The page on show's tour, the first time, once it's drawn.
  let waiting = null;
  function forPage() {
    const id = pages.active();
    if (!id || root || seen(id) || !TOURS[id]) {
      return;
    }
    clearInterval(waiting);
    let tries = 0;
    waiting = setInterval(function () {
      tries++;
      if (pages.active() !== id || root) {
        clearInterval(waiting);
        return;
      }
      if (tries < 2) {
        return;
      }
      clearInterval(waiting);
      if (!blocked(id)) {
        start(id);
      }
    }, 500);
  }

  // At start-up: the welcome, unless a link opened something (a link came for that, not a tour).
  function init() {
    addEventListener('pagechange', forPage);
    if (location.hash.length > 1 || location.search || window.uwufixOpenedByLink) {
      return;
    }
    forPage();
  }

  // Show me around: a button per page.
  function pickers() {
    let html = '';
    for (const [id, tour] of Object.entries(TOURS)) {
      html += `<button class="pick" type="button" data-tour="${id}">${tour.label}</button>`;
    }
    return html;
  }

  document.addEventListener('DOMContentLoaded', function () {
    // After the other scripts' own DOMContentLoaded work, so the page is set up.
    setTimeout(init, 0);
    const picks = document.getElementById('tourPicks');
    const button = document.getElementById('tourBtn');
    if (!picks || !button) {
      return;
    }
    button.addEventListener('click', function () {
      picks.innerHTML = pickers();
      openModal('tourModal');
    });
    picks.addEventListener('click', function (event) {
      const pickButton = event.target.closest('[data-tour]');
      if (!pickButton) {
        return;
      }
      closeModal('tourModal');
      setTimeout(function () {
        start(pickButton.dataset.tour);
      }, 300); // after the window has gone
    });
  });

  window.Tour = { init, start, end, pickers, TOURS };
})();
