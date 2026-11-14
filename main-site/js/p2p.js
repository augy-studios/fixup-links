/* Host and guest pairing over PeerJS, STUN only (STUN-p2p-spec.md in docs/), for sharing history
   between devices (js/sync.js). Two devices find each other with a six-letter code and then talk
   over a direct WebRTC data channel; PeerJS's free broker only introduces them.

   The same ids, ICE servers and wire as the apps' (flutter/lib/sync/peer.dart), so the site, the
   Android app and the desktop apps pair with each other in any combination.

   Loaded only when somebody opens Share history: PeerJS comes from the CDN then, never at boot,
   and isn't cached by the service worker. If it can't load, pairing says so and nothing else
   changes.

     P2P.Host / P2P.Guest           the two ends, EventTargets: "status", "message", "join", "leave"
     P2P.generateCode() ...         codes: six letters from an alphabet with no vowels and no 0 O 1 I */
'use strict';

(function () {
  const PEERJS_URL = 'https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js';
  const PEER_PREFIX = 'uwufix-sync-';
  const CODE_ALPHABET = 'BCDFGHJKLMNPQRSTVWXYZ23456789';
  const CODE_LENGTH = 6;
  const PROTOCOL_VERSION = 1;
  const CONNECT_TIMEOUT_MS = 15000;

  // STUN only. Supplying `config` replaces PeerJS's default, which includes a public TURN relay.
  const ICE_SERVERS = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun.cloudflare.com:3478' },
  ];
  const PEER_OPTIONS = { debug: 0, config: { iceServers: ICE_SERVERS } };

  const BROKER_ERRORS = new Set(['network', 'server-error', 'socket-error', 'socket-closed', 'disconnected']);

  /* ---- codes ---- */

  function generateCode() {
    // Bytes at or above this would make some characters likelier than others.
    const limit = 256 - (256 % CODE_ALPHABET.length);
    let code = '';
    while (code.length < CODE_LENGTH) {
      const [byte] = crypto.getRandomValues(new Uint8Array(1));
      if (byte < limit) code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
    }
    return code;
  }

  function normaliseCode(input) {
    return String(input || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, CODE_LENGTH);
  }

  function isValidCode(input) {
    const code = normaliseCode(input);
    return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c));
  }

  /* ---- library ---- */

  let peerLibrary = null;

  function loadPeerJs() {
    if (peerLibrary) return Promise.resolve(peerLibrary);
    if (window.Peer) return Promise.resolve((peerLibrary = window.Peer));
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = PEERJS_URL;
      script.async = true;
      script.onload = () => (window.Peer ? resolve((peerLibrary = window.Peer)) : reject(new Error('PeerJS did not define Peer')));
      script.onerror = () => {
        script.remove();
        reject(new Error('Could not load PeerJS'));
      };
      document.head.appendChild(script);
    });
  }

  function describePeerError(error) {
    switch (error?.type) {
      case 'peer-unavailable':
        return 'Nobody is sharing with that code. Check it and try again.';
      case 'unavailable-id':
        return 'That code is already in use. Make a new one.';
      case 'network':
      case 'server-error':
      case 'socket-error':
      case 'socket-closed':
        return 'Cannot reach the pairing service. Everything else still works.';
      case 'browser-incompatible':
        return 'This browser cannot make peer-to-peer connections.';
      default:
        return 'The connection failed.';
    }
  }

  /* ---- shared ---- */

  class Connection extends EventTarget {
    constructor() {
      super();
      this.peer = null;
      this.status = 'idle';
    }

    setStatus(status, detail = {}) {
      this.status = status;
      this.dispatchEvent(new CustomEvent('status', { detail: { status, ...detail } }));
    }

    bindLink(link) {
      // A link that closes without ever opening never reached the other device.
      let everOpened = false;
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        this.onLinkClosed(link, everOpened);
      };
      link.on('open', () => {
        everOpened = true;
        this.onLinkOpen(link);
      });
      link.on('data', (message) => {
        if (!message || typeof message !== 'object' || typeof message.type !== 'string') return;
        this.dispatchEvent(new CustomEvent('message', { detail: { message, from: link.peer } }));
      });
      link.on('close', finish);
      link.on('error', finish);
    }

    // The broker socket can drop while channels stay up. Re-register under the same id, backing
    // off while it keeps failing.
    watchBroker() {
      const peer = this.peer;
      let delay = 1000;
      peer.on('open', () => { delay = 1000; });
      peer.on('disconnected', () => {
        setTimeout(() => {
          if (this.peer === peer && !peer.destroyed && peer.disconnected) peer.reconnect();
        }, delay);
        delay = Math.min(delay * 2, 30000);
      });
    }

    destroyPeer() {
      // Cleared first, so the disconnect that destroy() causes is not retried.
      const peer = this.peer;
      this.peer = null;
      peer?.destroy();
    }
  }

  /* ---- host: one guest at a time, a newcomer replacing the one before ---- */

  class Host extends Connection {
    constructor() {
      super();
      this.links = new Map(); // guest peer id -> open link
    }

    async start(code) {
      const Peer = await loadPeerJs();
      this.code = code;
      this.setStatus('connecting');
      this.peer = new Peer(PEER_PREFIX + code, PEER_OPTIONS);
      this.watchBroker();
      this.peer.on('open', () => this.refreshStatus());
      this.peer.on('connection', (link) => {
        for (const old of [...this.links.values()]) this.drop(old);
        this.bindLink(link);
      });
      this.peer.on('error', (error) => {
        if (error?.type === 'unavailable-id') {
          this.setStatus('error', { message: describePeerError(error), taken: true });
          return;
        }
        // A guest already attached doesn't need the broker.
        if (this.links.size > 0 && BROKER_ERRORS.has(error?.type)) return;
        this.setStatus('error', { message: describePeerError(error) });
      });
    }

    onLinkOpen(link) {
      this.links.set(link.peer, link);
      this.dispatchEvent(new CustomEvent('join', { detail: { id: link.peer } }));
      this.refreshStatus();
    }

    onLinkClosed(link) {
      // Links this end dropped, and links that never opened, are not in the map.
      if (this.links.get(link.peer) !== link) return;
      this.links.delete(link.peer);
      this.dispatchEvent(new CustomEvent('leave', { detail: { id: link.peer } }));
      this.refreshStatus();
    }

    // A guest that dropped and one that never came look the same from here.
    refreshStatus() {
      this.setStatus(this.links.size > 0 ? 'connected' : 'waiting');
    }

    // Removed before closing: close() emits "close" synchronously.
    drop(link) {
      this.links.delete(link.peer);
      link.close();
    }

    send(message) {
      for (const link of this.links.values()) {
        try {
          link.send(message);
        } catch {
          // Closed between the check and the send; its close handler reports it.
        }
      }
    }

    close() {
      for (const link of [...this.links.values()]) this.drop(link);
      this.destroyPeer();
      this.setStatus('idle');
    }
  }

  /* ---- guest ---- */

  class Guest extends Connection {
    constructor() {
      super();
      this.link = null;
      this.timer = null;
    }

    async connect(code) {
      const Peer = await loadPeerJs();
      this.setStatus('connecting');
      this.peer = new Peer(PEER_OPTIONS);
      this.watchBroker();
      // Nothing errors when ICE cannot find a path; it just keeps trying.
      this.timer = setTimeout(() => {
        if (this.status !== 'connecting') return;
        this.hangUp();
        this.setStatus('unreachable');
      }, CONNECT_TIMEOUT_MS);
      // once, not on: a broker reconnect fires "open" again.
      this.peer.once('open', () => {
        this.link = this.peer.connect(PEER_PREFIX + code, { reliable: true });
        this.bindLink(this.link);
      });
      this.peer.on('error', (error) => {
        if (this.status === 'connected' && BROKER_ERRORS.has(error?.type)) return;
        this.hangUp();
        this.setStatus('error', { message: describePeerError(error), type: error?.type });
      });
    }

    onLinkOpen(link) {
      if (link !== this.link) return;
      clearTimeout(this.timer);
      this.setStatus('connected');
    }

    onLinkClosed(link, everOpened) {
      if (link !== this.link) return;
      this.link = null;
      this.setStatus(everOpened ? 'dropped' : 'unreachable');
    }

    send(message) {
      if (!this.link?.open) return;
      try {
        this.link.send(message);
      } catch {
        // As on the host.
      }
    }

    // Leaving on purpose: bye first, and a flushed close so it arrives.
    leave() {
      this.send({ type: 'bye' });
      clearTimeout(this.timer);
      const link = this.link;
      const peer = this.peer;
      this.link = null;
      this.peer = null;
      link?.close({ flush: true });
      setTimeout(() => peer?.destroy(), 1000);
      this.setStatus('idle');
    }

    hangUp() {
      clearTimeout(this.timer);
      const link = this.link;
      this.link = null;
      link?.close();
      this.destroyPeer();
    }

    close() {
      this.hangUp();
      this.setStatus('idle');
    }
  }

  window.P2P = {
    Host, Guest, generateCode, normaliseCode, isValidCode, describePeerError,
    CODE_LENGTH, PROTOCOL_VERSION,
  };
})();
