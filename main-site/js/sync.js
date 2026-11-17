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

  function elementById(id) {
    return document.getElementById(id);
  }

  function readStored(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function writeStored(key, value) {
    try {
      if (value == null) {
        localStorage.removeItem(key);
      } else {
        localStorage.setItem(key, value);
      }
    } catch {
      /* this page view only */
    }
  }

  function history() {
    try {
      let storedText = localStorage.getItem(HISTORY_KEY);
      if (!storedText) {
        storedText = '[]';
      }
      const value = JSON.parse(storedText);
      if (Array.isArray(value)) {
        return value;
      }
      return [];
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
    const userAgent = navigator.userAgent;
    let os;
    if (/Android/.test(userAgent)) {
      os = 'Android';
    } else if (/iPhone|iPad/.test(userAgent)) {
      os = 'iOS';
    } else if (/Mac OS X/.test(userAgent)) {
      os = 'macOS';
    } else if (/Windows/.test(userAgent)) {
      os = 'Windows';
    } else if (/CrOS/.test(userAgent)) {
      os = 'ChromeOS';
    } else if (/Linux/.test(userAgent)) {
      os = 'Linux';
    } else {
      os = 'a device';
    }
    let browser;
    if (/Edg\//.test(userAgent)) {
      browser = 'Edge';
    } else if (/Firefox\//.test(userAgent)) {
      browser = 'Firefox';
    } else if (/Chrome\//.test(userAgent)) {
      browser = 'Chrome';
    } else if (/Safari\//.test(userAgent)) {
      browser = 'Safari';
    } else {
      browser = 'A browser';
    }
    return `${browser} on ${os}`;
  }

  /** The value cut to maxLength if it is a string, otherwise an empty string. */
  function clippedText(value, maxLength) {
    if (typeof value === 'string') {
      return value.slice(0, maxLength);
    }
    return '';
  }

  /** "1 link" or "3 links". */
  function plural(count, one, many) {
    if (count === 1) {
      return `${count} ${one}`;
    }
    return `${count} ${many}`;
  }

  /** The other device's name, or the fallback text when it hasn't given one. */
  function nameOr(name, fallback) {
    if (name) {
      return name;
    }
    return fallback;
  }

  const SAME_NETWORK = 'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.';
  const NO_LIBRARY = 'Could not load sharing. Check your connection.';
  const OFFLINE = 'Sharing history needs a connection. Everything else works offline.';

  /* ---------- the window ---------- */

  let mode = 'host';
  let host = null;
  let guest = null;
  let revision = 0;
  let retriedTaken = false;
  let guestName = '';
  let lastHeard = 0;
  let beatTimer = null;
  let theirs = null; // the host's items, on a guest
  let theirName = '';
  let pendingAdd = null;
  let wakeLock = null;

  /** Switches between showing a code (host) and entering one (guest), starting or stopping each side. */
  function setMode(next) {
    mode = next;
    for (const button of document.querySelectorAll('#syncTabs [data-sync-mode]')) {
      const isActive = button.dataset.syncMode === next;
      button.classList.toggle('active', isActive);
      if (isActive) {
        button.setAttribute('aria-pressed', 'true');
      } else {
        button.setAttribute('aria-pressed', 'false');
      }
    }
    elementById('syncHost').hidden = next !== 'host';
    elementById('syncGuest').hidden = next !== 'guest';
    if (next === 'host') {
      leaveGuest({ quiet: true });
      startHosting();
    } else {
      stopHosting();
      setTimeout(function () {
        elementById('syncCodeInput').focus({ preventScroll: true });
      }, 50);
    }
  }

  /** Puts text in the status line with this id, hiding it when there's no text. */
  function say(elementId, text, kind = '') {
    const paragraph = elementById(elementId);
    if (text) {
      paragraph.textContent = text;
    } else {
      paragraph.textContent = '';
    }
    paragraph.hidden = !text;
    paragraph.dataset.kind = kind;
  }

  /** Keeps the screen on while connected, where the browser allows it. */
  async function keepAwake(shouldStayAwake) {
    try {
      if (shouldStayAwake && !wakeLock && 'wakeLock' in navigator && document.visibilityState === 'visible') {
        wakeLock = await navigator.wakeLock.request('screen');
        wakeLock.addEventListener('release', function () {
          wakeLock = null;
        });
      } else if (!shouldStayAwake && wakeLock) {
        await wakeLock.release();
        wakeLock = null;
      }
    } catch { /* not allowed here: the screen sleeps as usual */ }
  }

  /* ---------- host ---------- */

  function snapshot() {
    return { type: 'state', v: P2P.PROTOCOL_VERSION, rev: revision, name: deviceName(), items: history().slice(0, MAX_ITEMS) };
  }

  function showCode(code) {
    const link = `${location.origin}/join?id=${code}`;
    elementById('syncCode').textContent = code;
    elementById('syncLink').textContent = link;
    elementById('syncLink').href = link;
    const box = elementById('syncQr');
    box.innerHTML = '';
    if (window.QRCode) {
      new QRCode(box, { text: link, width: 168, height: 168, colorDark: '#000000', colorLight: '#ffffff', correctLevel: QRCode.CorrectLevel.M });
    }
  }

  /** Shows the host's connection status, and keeps the screen on while a guest is attached. */
  function renderHost({ status, message }) {
    const statusTexts = {
      connecting: 'Getting a code ready…',
      waiting: 'On the other device, open uwuFix, then History, Share history, Enter a code, and type this code. Or scan the QR code, or open the link.',
      connected: `Connected to ${nameOr(guestName, 'the other device')}. It can see your history, and add yours to its own.`,
    };
    let text = statusTexts[status];
    let kind = '';
    if (status === 'error') {
      text = message;
      kind = 'error';
    } else if (status === 'connected') {
      kind = 'ok';
    }
    if (!text) {
      text = '';
    }
    say('syncHostStatus', text, kind);
    elementById('syncHostCard').hidden = status === 'error' && !host;
    keepAwake(status === 'connected');
    if (status !== 'connected') {
      hideApproval();
    }
  }

  /** Starts hosting under the stored code (or a new one) and answers whatever the guest sends. */
  async function startHosting() {
    if (host) {
      return;
    }
    if (!navigator.onLine) {
      say('syncHostStatus', OFFLINE, 'error');
      return;
    }
    const stored = readStored(HOST_KEY);
    let code;
    if (P2P.isValidCode(stored)) {
      code = P2P.normaliseCode(stored);
    } else {
      code = P2P.generateCode();
    }
    writeStored(HOST_KEY, code);
    showCode(code);
    elementById('syncHostCard').hidden = false;
    const hostConnection = new P2P.Host();
    host = hostConnection;
    hostConnection.addEventListener('status', function ({ detail }) {
      if (host !== hostConnection) {
        return;
      }
      if (detail.taken && !retriedTaken) {
        // Another tab, or the broker still holding the code from before a reload: a fresh code,
        // once. A second collision in a row is something else, shown as it is.
        retriedTaken = true;
        restartWithFreshCode();
        return;
      }
      if (detail.status === 'waiting') {
        retriedTaken = false;
      }
      if (detail.status !== 'connected') {
        guestName = '';
      }
      renderHost(detail);
    });
    hostConnection.addEventListener('join', function () {
      lastHeard = Date.now();
      hostConnection.send(snapshot());
    });
    hostConnection.addEventListener('message', function ({ detail: { message } }) {
      onHostMessage(hostConnection, message);
    });
    try {
      await hostConnection.start(code);
    } catch {
      if (host === hostConnection) {
        host = null;
      }
      say('syncHostStatus', NO_LIBRARY, 'error');
    }
  }

  /** Handles one message from the guest on the host: hello, add, took or bye. */
  function onHostMessage(hostConnection, message) {
    lastHeard = Date.now();
    switch (message.type) {
      case 'hello':
        guestName = nameOr(clippedText(message.name, 60), 'the other device');
        hostConnection.send(snapshot());
        renderHost({ status: 'connected' });
        break;
      case 'add': {
        if (!Array.isArray(message.items)) {
          return;
        }
        const items = message.items.slice(0, MAX_ITEMS);
        const preview = HistoryMerge.merge(history(), items);
        if (preview.added === 0) {
          hostConnection.send({ type: 'added', n: 0 });
          say('syncHostNote', `${nameOr(guestName, 'The other device')} sent its history: nothing new.`);
          return;
        }
        askApproval(hostConnection, items, preview.added);
        break;
      }
      case 'took':
        if (typeof message.n === 'number') {
          const takenCount = Math.max(0, Math.min(MAX_ITEMS, Math.round(message.n)));
          say('syncHostNote', `${nameOr(guestName, 'The other device')} added ${takenCount} of your links to its history.`);
        }
        break;
      case 'bye':
        // Their code is spent: a fresh one, so a code seen once doesn't keep working.
        restartWithFreshCode();
        say('syncHostNote', `${nameOr(guestName, 'The other device')} left. Here's a new code for next time.`);
        break;
      default:
        break; // ping, and anything unknown: heard, nothing more
    }
  }

  // The host says yes before anything from the other device goes into its history.
  function askApproval(hostConnection, items, added) {
    pendingAdd = { hostConnection, items };
    elementById('syncApproveText').textContent = `Add ${plural(added, 'link', 'links')} from ${nameOr(guestName, 'the other device')} to your history?`;
    elementById('syncApprove').hidden = false;
    elementById('syncApproveYes').focus({ preventScroll: true });
  }

  function hideApproval() {
    pendingAdd = null;
    elementById('syncApprove').hidden = true;
  }

  /** The host's answer to a pending add: merge the guest's links in, or tell it no. */
  function approve(yes) {
    const pending = pendingAdd;
    hideApproval();
    if (!pending || pending.hostConnection !== host) {
      return;
    }
    if (!yes) {
      pending.hostConnection.send({ type: 'refused' });
      return;
    }
    const merged = HistoryMerge.merge(history(), pending.items);
    saveMerged(merged.items);
    pending.hostConnection.send({ type: 'added', n: merged.added });
    say('syncHostNote', `Added ${plural(merged.added, 'link', 'links')} from ${nameOr(guestName, 'the other device')}.`, 'ok');
  }

  function stopHosting() {
    const hostConnection = host;
    host = null;
    hostConnection?.close();
    keepAwake(false);
    hideApproval();
  }

  async function restartWithFreshCode() {
    stopHosting();
    writeStored(HOST_KEY, null);
    if (mode === 'host' && isOpen()) {
      await startHosting();
    }
  }

  /* ---------- guest ---------- */

  /** Shows the guest's connection status and which of Join, Reconnect and Leave apply. */
  function renderGuest({ status, message, type }) {
    const statusTexts = {
      connecting: 'Connecting…',
      connected: 'Connected. Getting their history…',
      dropped: 'The connection dropped.',
      unreachable: SAME_NETWORK,
    };
    let kind = '';
    if (status === 'error' || status === 'unreachable') {
      kind = 'error';
    } else if (status === 'connected') {
      kind = 'ok';
    }
    let text = statusTexts[status];
    if (status === 'error') {
      text = message;
    }
    if (!text) {
      text = '';
    }
    say('syncGuestStatus', text, kind);
    const isBusy = status === 'connecting' || status === 'connected';
    elementById('syncJoin').hidden = isBusy;
    if (status === 'dropped') {
      elementById('syncJoin').textContent = 'Reconnect';
    } else {
      elementById('syncJoin').textContent = 'Join';
    }
    elementById('syncLeave').hidden = !isBusy;
    if (status !== 'connected') {
      elementById('syncTheirs').hidden = true;
      theirs = null;
    }
    keepAwake(status === 'connected');
    if (type === 'peer-unavailable') {
      writeStored(LAST_KEY, null);
    }
  }

  /** On a guest: shows how many of the host's links are new here, and how many of ours are new there. */
  function renderTheirs() {
    if (!theirs) {
      return;
    }
    const merged = HistoryMerge.merge(history(), theirs);
    const theirsCleaned = [];
    for (const item of theirs) {
      const cleanedItem = HistoryMerge.sanitize(item);
      if (cleanedItem) {
        theirsCleaned.push(cleanedItem);
      }
    }
    const mineMerged = HistoryMerge.merge(theirsCleaned, history());
    elementById('syncTheirs').hidden = false;
    say('syncGuestStatus', `Connected to ${nameOr(theirName, 'the other device')}.`, 'ok');
    elementById('syncTheirsText').textContent = `Their history has ${plural(theirs.length, 'link', 'links')}, ${merged.added} new to this device. Yours has ${mineMerged.added} new to them.`;
    elementById('syncTake').disabled = merged.added === 0;
    elementById('syncSend').disabled = mineMerged.added === 0;
  }

  /** Joins the host with the typed code, after checking the code and that we're online. */
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
    const guestConnection = new P2P.Guest();
    guest = guestConnection;
    guestConnection.code = code;
    guestConnection.addEventListener('status', function ({ detail }) {
      if (guest !== guestConnection) {
        return;
      }
      if (detail.status === 'connected') {
        lastHeard = Date.now();
        guestConnection.send({ type: 'hello', v: P2P.PROTOCOL_VERSION, name: deviceName() });
      }
      renderGuest(detail);
    });
    guestConnection.addEventListener('message', function ({ detail: { message } }) {
      onGuestMessage(guestConnection, message);
    });
    try {
      await guestConnection.connect(code);
      writeStored(LAST_KEY, code);
    } catch {
      if (guest === guestConnection) {
        guest = null;
      }
      say('syncGuestStatus', NO_LIBRARY, 'error');
    }
  }

  /** Handles one message from the host on the guest: state, added or refused. */
  function onGuestMessage(guestConnection, message) {
    lastHeard = Date.now();
    elementById('syncStale').hidden = true;
    switch (message.type) {
      case 'state':
        if (!Array.isArray(message.items)) {
          return;
        }
        theirs = message.items.slice(0, MAX_ITEMS);
        theirName = clippedText(message.name, 60);
        renderTheirs();
        break;
      case 'added': {
        let note;
        if (typeof message.n === 'number' && message.n > 0) {
          note = `${nameOr(theirName, 'The other device')} added ${Math.round(message.n)} of your links.`;
        } else {
          note = 'They had them all already.';
        }
        say('syncGuestNote', note, 'ok');
        break;
      }
      case 'refused':
        say('syncGuestNote', `${nameOr(theirName, 'The other device')} said not now.`);
        break;
      default:
        break; // beat, and anything unknown
    }
  }

  function take() {
    if (!theirs) {
      return;
    }
    const merged = HistoryMerge.merge(history(), theirs);
    saveMerged(merged.items);
    guest?.send({ type: 'took', n: merged.added });
    say('syncGuestNote', `Added ${plural(merged.added, 'link', 'links')} to your history.`, 'ok');
    renderTheirs();
  }

  function send() {
    if (!guest) {
      return;
    }
    guest.send({ type: 'add', items: history().slice(0, MAX_ITEMS) });
    say('syncGuestNote', `Sent. ${nameOr(theirName, 'The other device')} is asked before they're added.`);
  }

  /** Ends the guest's connection; unless quiet, also forgets the code and resets the guest view. */
  function leaveGuest({ quiet = false } = {}) {
    const guestConnection = guest;
    guest = null;
    if (!guestConnection) {
      return;
    }
    if (guestConnection.status === 'connected') {
      guestConnection.leave();
    } else {
      guestConnection.close();
    }
    keepAwake(false);
    if (!quiet) {
      writeStored(LAST_KEY, null);
      renderGuest({ status: 'idle' });
      say('syncGuestNote', '');
    }
  }

  /* ---------- the heartbeat ---------- */

  /** Runs every second: each side says it's still here, the host drops a silent guest, the guest flags a quiet host. */
  function beat() {
    if (host && host.status === 'connected') {
      host.send({ type: 'beat', rev: revision });
      if (Date.now() - lastHeard > SILENT_MS) {
        for (const link of [...host.links.values()]) {
          host.drop(link);
        }
        host.refreshStatus();
      }
    }
    if (guest && guest.status === 'connected') {
      guest.send({ type: 'ping' });
      elementById('syncStale').hidden = Date.now() - lastHeard < STALE_MS;
    }
  }

  /* ---------- wiring ---------- */

  function isOpen() {
    return !elementById('syncModal').classList.contains('hidden');
  }

  /** Opens the Share history window, on Enter a code with the code filled in when one is given. */
  function open({ code } = {}) {
    if (!window.P2P || !window.HistoryMerge) {
      return;
    }
    openModal('syncModal');
    clearInterval(beatTimer);
    beatTimer = setInterval(beat, BEAT_MS);
    if (code) {
      elementById('syncCodeInput').value = P2P.normaliseCode(code);
      setMode('guest');
      return;
    }
    if (!elementById('syncCodeInput').value) {
      elementById('syncCodeInput').value = P2P.normaliseCode(readStored(LAST_KEY));
    }
    setMode(mode);
  }

  function close() {
    stopHosting();
    leaveGuest({ quiet: true });
    clearInterval(beatTimer);
    say('syncHostNote', '');
    say('syncGuestNote', '');
  }

  document.addEventListener('DOMContentLoaded', function () {
    const modal = elementById('syncModal');
    if (!modal) {
      return;
    }
    elementById('openSyncBtn')?.addEventListener('click', function () {
      closeModal('historyModal');
      open();
    });
    elementById('syncTabs').addEventListener('click', function (event) {
      const button = event.target.closest('[data-sync-mode]');
      if (button && button.dataset.syncMode !== mode) {
        setMode(button.dataset.syncMode);
      }
    });
    elementById('syncNewCode').addEventListener('click', function () {
      say('syncHostNote', '');
      restartWithFreshCode();
    });
    elementById('syncCopyLink').addEventListener('click', function () {
      copyToClipboard(elementById('syncLink').textContent);
    });
    elementById('syncApproveYes').addEventListener('click', function () {
      approve(true);
    });
    elementById('syncApproveNo').addEventListener('click', function () {
      approve(false);
    });
    elementById('syncCodeInput').addEventListener('input', function (event) {
      const value = P2P.normaliseCode(event.target.value);
      if (value !== event.target.value) {
        event.target.value = value;
      }
    });
    elementById('syncJoinForm').addEventListener('submit', function (event) {
      event.preventDefault();
      say('syncGuestNote', '');
      join(elementById('syncCodeInput').value);
    });
    elementById('syncLeave').addEventListener('click', function () {
      leaveGuest();
    });
    elementById('syncTake').addEventListener('click', take);
    elementById('syncSend').addEventListener('click', send);

    // Closing the window ends sharing, whichever way it's closed.
    const closeWatcher = new MutationObserver(function () {
      if (!isOpen()) {
        close();
      }
    });
    closeWatcher.observe(modal, { attributes: true, attributeFilter: ['class'] });

    // The host's history changed (a link fixed, or merged in): everyone connected sees it.
    document.addEventListener('uwufix:history', function () {
      revision++;
      if (host && host.status === 'connected') {
        host.send(snapshot());
      }
      if (guest && theirs) {
        renderTheirs();
      }
    });

    // Back from the background with a channel that died meanwhile: once more, with the same code.
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState !== 'visible' || !isOpen()) {
        return;
      }
      if (guest?.status === 'dropped' && guest.code) {
        join(guest.code);
      }
      if (host?.status === 'connected' || guest?.status === 'connected') {
        keepAwake(true);
      }
    });

    // A join link (/join?id=CODE): the window opens on Enter a code, the code filled in.
    let joinCode = null;
    if (location.pathname.replace(/\/+$/, '') === '/join') {
      joinCode = new URLSearchParams(location.search).get('id');
    }
    if (joinCode) {
      window.uwufixOpenedByLink = true;
      window.history.replaceState(null, '', '/');
      setTimeout(function () {
        open({ code: joinCode });
      }, 300);
    }
  });

  window.HistorySync = { open };
})();
