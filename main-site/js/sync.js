/* Share history: your fix history between two devices, directly, over STUN-only WebRTC
   (js/p2p.js, STUN-p2p-spec.md in docs/). Nothing passes through a server once they've found each
   other, and there's no account.

   One device shows a code (the host), the other types it, follows its link, or scans its QR code
   (the guest). The guest then sees the host's history and can:
     - Add theirs to mine: the host's links merged into this device's history;
     - Send mine to them: this device's links offered to the host, which asks first ("Add 12
       links from Chrome on Windows?") before merging them.
   Merging is js/history-merge.js's, the same on every platform. The Android and desktop apps do
   the same (flutter/lib/features/sync/), so any two pair.

   The protocol, version 1. Plain objects with a type; anything else is ignored:
     guest -> host   hello { v, name }        "send me everything"
                     add { items }            Send mine to them
                     took { n }               Add theirs to mine happened, n new here
                     ping                     still here (every second)
                     bye                      leaving on purpose: the host retires its code
     host -> guest   state { v, rev, name, items }   the host's history, again on every change
                     beat { rev }             still here (every second)
                     added { n } / refused    the answer to add

   Kept: uwufix.sync.hostCode (the host's code, reused after a reload) and uwufix.sync.lastCode
   (the code a guest last joined). */
'use strict';

(function () {
  const HOST_KEY = 'uwufix.sync.hostCode';
  const LAST_KEY = 'uwufix.sync.lastCode';
  const HISTORY_KEY = 'uwufix_history';
  const BEAT_MS = 1000;
  const STALE_MS = 3000; // a guest that hears nothing for this long says so
  const SILENT_MS = 6000; // a host drops a guest it hasn't heard from in this long
  const MAX_ITEMS = 200;

  const $ = (id) => document.getElementById(id);
  const read = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
  const write = (k, v) => { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* this page view only */ } };

  function history() {
    try {
      const v = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
      return Array.isArray(v) ? v : [];
    } catch {
      return [];
    }
  }

  function saveMerged(items) {
    try {
      localStorage.setItem(HISTORY_KEY, JSON.stringify(items));
    } catch { /* full or blocked: nothing kept */ }
    document.dispatchEvent(new CustomEvent('uwufix:history'));
  }

  // "Chrome on Windows", for the other device to show.
  function deviceName() {
    const ua = navigator.userAgent;
    const os = /Android/.test(ua) ? 'Android' : /iPhone|iPad/.test(ua) ? 'iOS' : /Mac OS X/.test(ua) ? 'macOS'
      : /Windows/.test(ua) ? 'Windows' : /CrOS/.test(ua) ? 'ChromeOS' : /Linux/.test(ua) ? 'Linux' : 'a device';
    const browser = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'A browser';
    return `${browser} on ${os}`;
  }

  const str = (v, n) => (typeof v === 'string' ? v.slice(0, n) : '');
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

  const SAME_NETWORK = 'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.';
  const NO_LIBRARY = 'Could not load sharing. Check your connection.';
  const OFFLINE = 'Sharing history needs a connection. Everything else works offline.';

  /* ---------- the window ---------- */

  let mode = 'host';
  let host = null;
  let guest = null;
  let rev = 0;
  let retriedTaken = false;
  let guestName = '';
  let lastHeard = 0;
  let beatTimer = null;
  let theirs = null; // the host's items, on a guest
  let theirName = '';
  let pendingAdd = null;
  let wakeLock = null;

  function setMode(next) {
    mode = next;
    for (const b of document.querySelectorAll('#syncTabs [data-sync-mode]')) {
      const on = b.dataset.syncMode === next;
      b.classList.toggle('active', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    }
    $('syncHost').hidden = next !== 'host';
    $('syncGuest').hidden = next !== 'guest';
    if (next === 'host') {
      leaveGuest({ quiet: true });
      startHosting();
    } else {
      stopHosting();
      setTimeout(() => $('syncCodeInput').focus({ preventScroll: true }), 50);
    }
  }

  function say(el, text, kind = '') {
    const p = $(el);
    p.textContent = text || '';
    p.hidden = !text;
    p.dataset.kind = kind;
  }

  async function keepAwake(on) {
    try {
      if (on && !wakeLock && 'wakeLock' in navigator && document.visibilityState === 'visible') {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', () => { wakeLock = null; });
      } else if (!on && wakeLock) {
        await wakeLock.release();
        wakeLock = null;
      }
    } catch { /* not allowed here: the screen sleeps as usual */ }
  }

  /* ---------- host ---------- */

  function snapshot() {
    return { type: 'state', v: P2P.PROTOCOL_VERSION, rev, name: deviceName(), items: history().slice(0, MAX_ITEMS) };
  }

  function showCode(code) {
    const link = `${location.origin}/join?id=${code}`;
    $('syncCode').textContent = code;
    $('syncLink').textContent = link;
    $('syncLink').href = link;
    const box = $('syncQr');
    box.innerHTML = '';
    if (window.QRCode) {
      new QRCode(box, { text: link, width: 168, height: 168, colorDark: '#000000', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
  }

  function renderHost({ status, message }) {
    const text = {
      connecting: 'Getting a code ready…',
      waiting: 'On the other device, open uwuFix, then History, Share history, Enter a code, and type this code. Or scan the QR code, or open the link.',
      connected: `Connected to ${guestName || 'the other device'}. It can see your history, and add yours to its own.`,
    }[status];
    say('syncHostStatus', status === 'error' ? message : text || '', status === 'error' ? 'error' : status === 'connected' ? 'ok' : '');
    $('syncHostCard').hidden = status === 'error' && !host;
    keepAwake(status === 'connected');
    if (status !== 'connected') hideApproval();
  }

  async function startHosting() {
    if (host) return;
    if (!navigator.onLine) {
      say('syncHostStatus', OFFLINE, 'error');
      return;
    }
    const stored = read(HOST_KEY);
    const code = P2P.isValidCode(stored) ? P2P.normaliseCode(stored) : P2P.generateCode();
    write(HOST_KEY, code);
    showCode(code);
    $('syncHostCard').hidden = false;
    const h = new P2P.Host();
    host = h;
    h.addEventListener('status', ({ detail }) => {
      if (host !== h) return;
      if (detail.taken && !retriedTaken) {
        // Another tab, or the broker still holding the code from before a reload: a fresh code,
        // once. A second collision in a row is something else, shown as it is.
        retriedTaken = true;
        restartWithFreshCode();
        return;
      }
      if (detail.status === 'waiting') retriedTaken = false;
      if (detail.status !== 'connected') guestName = '';
      renderHost(detail);
    });
    h.addEventListener('join', () => {
      lastHeard = Date.now();
      h.send(snapshot());
    });
    h.addEventListener('message', ({ detail: { message } }) => onHostMessage(h, message));
    try {
      await h.start(code);
    } catch {
      if (host === h) host = null;
      say('syncHostStatus', NO_LIBRARY, 'error');
    }
  }

  function onHostMessage(h, m) {
    lastHeard = Date.now();
    switch (m.type) {
      case 'hello':
        guestName = str(m.name, 60) || 'the other device';
        h.send(snapshot());
        renderHost({ status: 'connected' });
        break;
      case 'add': {
        if (!Array.isArray(m.items)) return;
        const items = m.items.slice(0, MAX_ITEMS);
        const preview = HistoryMerge.merge(history(), items);
        if (preview.added === 0) {
          h.send({ type: 'added', n: 0 });
          say('syncHostNote', `${guestName || 'The other device'} sent its history: nothing new.`);
          return;
        }
        askApproval(h, items, preview.added);
        break;
      }
      case 'took':
        if (typeof m.n === 'number') say('syncHostNote', `${guestName || 'The other device'} added ${`${Math.max(0, Math.min(MAX_ITEMS, Math.round(m.n)))} of your links`} to its history.`);
        break;
      case 'bye':
        // Their code is spent: a fresh one, so a code seen once doesn't keep working.
        restartWithFreshCode();
        say('syncHostNote', `${guestName || 'The other device'} left. Here's a new code for next time.`);
        break;
      default:
        break; // ping, and anything unknown: heard, nothing more
    }
  }

  // The host says yes before anything from the other device goes into its history.
  function askApproval(h, items, added) {
    pendingAdd = { h, items };
    $('syncApproveText').textContent = `Add ${plural(added, 'link', 'links')} from ${guestName || 'the other device'} to your history?`;
    $('syncApprove').hidden = false;
    $('syncApproveYes').focus({ preventScroll: true });
  }

  function hideApproval() {
    pendingAdd = null;
    $('syncApprove').hidden = true;
  }

  function approve(yes) {
    const p = pendingAdd;
    hideApproval();
    if (!p || p.h !== host) return;
    if (!yes) {
      p.h.send({ type: 'refused' });
      return;
    }
    const merged = HistoryMerge.merge(history(), p.items);
    saveMerged(merged.items);
    p.h.send({ type: 'added', n: merged.added });
    say('syncHostNote', `Added ${plural(merged.added, 'link', 'links')} from ${guestName || 'the other device'}.`, 'ok');
  }

  function stopHosting() {
    const h = host;
    host = null;
    h?.close();
    keepAwake(false);
    hideApproval();
  }

  async function restartWithFreshCode() {
    stopHosting();
    write(HOST_KEY, null);
    if (mode === 'host' && isOpen()) await startHosting();
  }

  /* ---------- guest ---------- */

  function renderGuest({ status, message, type }) {
    const text = {
      connecting: 'Connecting…',
      connected: 'Connected. Getting their history…',
      dropped: 'The connection dropped.',
      unreachable: SAME_NETWORK,
    }[status];
    const kind = status === 'error' || status === 'unreachable' ? 'error' : status === 'connected' ? 'ok' : '';
    say('syncGuestStatus', status === 'error' ? message : text || '', kind);
    $('syncJoin').hidden = status === 'connecting' || status === 'connected';
    $('syncJoin').textContent = status === 'dropped' ? 'Reconnect' : 'Join';
    $('syncLeave').hidden = !(status === 'connecting' || status === 'connected');
    if (status !== 'connected') {
      $('syncTheirs').hidden = true;
      theirs = null;
    }
    keepAwake(status === 'connected');
    if (type === 'peer-unavailable') write(LAST_KEY, null);
  }

  function renderTheirs() {
    if (!theirs) return;
    const merged = HistoryMerge.merge(history(), theirs);
    const mineMerged = HistoryMerge.merge(theirs.map(HistoryMerge.sanitize).filter(Boolean), history());
    $('syncTheirs').hidden = false;
    say('syncGuestStatus', `Connected to ${theirName || 'the other device'}.`, 'ok');
    $('syncTheirsText').textContent = `Their history has ${plural(theirs.length, 'link', 'links')}, ${merged.added} new to this device. Yours has ${mineMerged.added} new to them.`;
    $('syncTake').disabled = merged.added === 0;
    $('syncSend').disabled = mineMerged.added === 0;
  }

  async function join(input) {
    const code = P2P.normaliseCode(input);
    if (!P2P.isValidCode(code)) {
      say('syncGuestStatus', `A code is ${P2P.CODE_LENGTH} letters and numbers.`, 'error');
      return;
    }
    if (!navigator.onLine) {
      say('syncGuestStatus', OFFLINE, 'error');
      return;
    }
    leaveGuest({ quiet: true });
    const g = new P2P.Guest();
    guest = g;
    g.code = code;
    g.addEventListener('status', ({ detail }) => {
      if (guest !== g) return;
      if (detail.status === 'connected') {
        lastHeard = Date.now();
        g.send({ type: 'hello', v: P2P.PROTOCOL_VERSION, name: deviceName() });
      }
      renderGuest(detail);
    });
    g.addEventListener('message', ({ detail: { message } }) => onGuestMessage(g, message));
    try {
      await g.connect(code);
      write(LAST_KEY, code);
    } catch {
      if (guest === g) guest = null;
      say('syncGuestStatus', NO_LIBRARY, 'error');
    }
  }

  function onGuestMessage(g, m) {
    lastHeard = Date.now();
    $('syncStale').hidden = true;
    switch (m.type) {
      case 'state':
        if (!Array.isArray(m.items)) return;
        theirs = m.items.slice(0, MAX_ITEMS);
        theirName = str(m.name, 60);
        renderTheirs();
        break;
      case 'added':
        say('syncGuestNote', typeof m.n === 'number' && m.n > 0
          ? `${theirName || 'The other device'} added ${`${Math.round(m.n)} of your links`}.`
          : 'They had them all already.', 'ok');
        break;
      case 'refused':
        say('syncGuestNote', `${theirName || 'The other device'} said not now.`);
        break;
      default:
        break; // beat, and anything unknown
    }
  }

  function take() {
    if (!theirs) return;
    const merged = HistoryMerge.merge(history(), theirs);
    saveMerged(merged.items);
    guest?.send({ type: 'took', n: merged.added });
    say('syncGuestNote', `Added ${plural(merged.added, 'link', 'links')} to your history.`, 'ok');
    renderTheirs();
  }

  function send() {
    if (!guest) return;
    guest.send({ type: 'add', items: history().slice(0, MAX_ITEMS) });
    say('syncGuestNote', `Sent. ${theirName || 'The other device'} is asked before they're added.`);
  }

  function leaveGuest({ quiet = false } = {}) {
    const g = guest;
    guest = null;
    if (!g) return;
    if (g.status === 'connected') g.leave();
    else g.close();
    keepAwake(false);
    if (!quiet) {
      write(LAST_KEY, null);
      renderGuest({ status: 'idle' });
      say('syncGuestNote', '');
    }
  }

  /* ---------- the heartbeat ---------- */

  function beat() {
    if (host && host.status === 'connected') {
      host.send({ type: 'beat', rev });
      if (Date.now() - lastHeard > SILENT_MS) {
        for (const link of [...host.links.values()]) host.drop(link);
        host.refreshStatus();
      }
    }
    if (guest && guest.status === 'connected') {
      guest.send({ type: 'ping' });
      $('syncStale').hidden = Date.now() - lastHeard < STALE_MS;
    }
  }

  /* ---------- wiring ---------- */

  const isOpen = () => !$('syncModal').classList.contains('hidden');

  function open({ code } = {}) {
    if (!window.P2P || !window.HistoryMerge) return;
    openModal('syncModal');
    clearInterval(beatTimer);
    beatTimer = setInterval(beat, BEAT_MS);
    if (code) {
      $('syncCodeInput').value = P2P.normaliseCode(code);
      setMode('guest');
      return;
    }
    if (!$('syncCodeInput').value) $('syncCodeInput').value = P2P.normaliseCode(read(LAST_KEY));
    setMode(mode);
  }

  function close() {
    stopHosting();
    leaveGuest({ quiet: true });
    clearInterval(beatTimer);
    say('syncHostNote', '');
    say('syncGuestNote', '');
  }

  document.addEventListener('DOMContentLoaded', () => {
    const modal = $('syncModal');
    if (!modal) return;
    $('openSyncBtn')?.addEventListener('click', () => {
      closeModal('historyModal');
      open();
    });
    $('syncTabs').addEventListener('click', (e) => {
      const b = e.target.closest('[data-sync-mode]');
      if (b && b.dataset.syncMode !== mode) setMode(b.dataset.syncMode);
    });
    $('syncNewCode').addEventListener('click', () => {
      say('syncHostNote', '');
      restartWithFreshCode();
    });
    $('syncCopyLink').addEventListener('click', () => copyToClipboard($('syncLink').textContent));
    $('syncApproveYes').addEventListener('click', () => approve(true));
    $('syncApproveNo').addEventListener('click', () => approve(false));
    $('syncCodeInput').addEventListener('input', (e) => {
      const v = P2P.normaliseCode(e.target.value);
      if (v !== e.target.value) e.target.value = v;
    });
    $('syncJoinForm').addEventListener('submit', (e) => {
      e.preventDefault();
      say('syncGuestNote', '');
      join($('syncCodeInput').value);
    });
    $('syncLeave').addEventListener('click', () => leaveGuest());
    $('syncTake').addEventListener('click', take);
    $('syncSend').addEventListener('click', send);

    // Closing the window ends sharing, whichever way it's closed.
    new MutationObserver(() => { if (!isOpen()) close(); }).observe(modal, { attributes: true, attributeFilter: ['class'] });

    // The host's history changed (a link fixed, or merged in): everyone connected sees it.
    document.addEventListener('uwufix:history', () => {
      rev++;
      if (host && host.status === 'connected') host.send(snapshot());
      if (guest && theirs) renderTheirs();
    });

    // Back from the background with a channel that died meanwhile: once more, with the same code.
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible' || !isOpen()) return;
      if (guest?.status === 'dropped' && guest.code) join(guest.code);
      if ((host?.status === 'connected' || guest?.status === 'connected')) keepAwake(true);
    });

    // A join link (/join?id=CODE): the window opens on Enter a code, the code filled in.
    const joinCode = location.pathname.replace(/\/+$/, '') === '/join' ? new URLSearchParams(location.search).get('id') : null;
    if (joinCode) {
      window.uwufixOpenedByLink = true;
      window.history.replaceState(null, '', '/');
      setTimeout(() => open({ code: joinCode }), 300);
    }
  });

  window.HistorySync = { open };
})();
