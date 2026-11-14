# Peer-to-peer pairing over STUN only (portable)

Two browsers find each other with a short code and then talk directly over a
WebRTC data channel. A free public broker introduces them, and after that
nothing passes through a server. There is no TURN relay, no backend, no
account and no secret, and nothing to deploy beyond static files.

It fits any PWA where one device hosts and one or more others join: a game with
phones as controllers, a second-screen tool, a shared board, a handoff between a
laptop and a phone in the same room. Nothing here depends on a framework, a
bundler, or what the app does with the channel once it is open.

## What STUN-only costs, stated first

**The devices have to be able to reach each other directly.** STUN tells each
device its own public address; it carries no traffic. If the network between the
two will not let a direct path through, the channel never opens, and the only
fix for that is a TURN relay, which this spec deliberately leaves out.

| Situation | Result |
| --- | --- |
| Both on the same wifi or LAN | Works. |
| One device shares a hotspot, the other joins it | Works. **This is the fallback to tell people about.** |
| Two home broadband connections | Usually works. Most home routers keep one external port per device, which STUN can find. |
| Home network and a phone on mobile data | Often fails. Mobile carriers commonly put phones behind a **symmetric NAT** that picks a new external port for each destination, so the address STUN found is wrong by the time the other end uses it. |
| Corporate, university, hotel or "guest" wifi | Often fails, even with both devices on it: **client isolation** blocks device-to-device traffic on the same network. |

What it buys: nothing to pay for, nothing to operate, no credentials to leak, and
the app's data never touches a server anybody is responsible for.

If the product cannot live with the failure cases above, this is the wrong spec:
add TURN.

## How the pieces fit

```text
  Host device                                          Guest device
  new Peer("myapp-" + CODE)                            new Peer()   (random id)
        |                                                    |
        |  1. both hold a WebSocket to the broker            |
        +----------------->  PeerJS broker  <----------------+
                            (0.peerjs.com)
                                  |
            2. the guest asks for "myapp-CODE"; the broker relays the
               offer, the answer and the ICE candidates between the two
                                  |
        3. each device asks a STUN server for its own public address
        |                                                    |
        +========== 4. direct, encrypted data channel ========+
                          (no server in the path)
```

- **PeerJS** wraps `RTCPeerConnection` and the signalling. Pin a version:
  `https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js`, or the
  `peerjs` package from npm. Everything below was checked against 1.5.4.
- **The broker** is PeerJS's free cloud server (`0.peerjs.com:443` by default).
  It is shared by every app that uses the default, has no uptime guarantee, and
  sees peer ids and IP addresses, never what goes over the channel. It can be
  swapped for a self-hosted `peerjs-server` later by setting `host`, `port` and
  `path`; nothing else in this spec changes.
- **STUN servers** are public and free. They answer one question per device and
  carry no application traffic.
- **The data channel** is encrypted end to end with DTLS.

## Rule 1: pass the ICE list yourself, or you are using TURN

**PeerJS's default configuration includes a TURN relay.** In 1.5.x the library's
`defaultConfig` is Google's STUN server plus `turn:eu-0.turn.peerjs.com:3478`
and `turn:us-0.turn.peerjs.com:3478` with shared public credentials. A
`new Peer(id)` with no `config` quietly relays through PeerJS's shared TURN
whenever a direct path fails. Testing that way passes cases a STUN-only build
fails, the relay has no capacity guarantee, and the traffic goes through a third
party.

Options are spread over the defaults rather than deep-merged, so supplying
`config` replaces the whole default, TURN entry included:

```js
const ICE_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun.cloudflare.com:3478" },
];

new Peer(id, { debug: 0, config: { iceServers: ICE_SERVERS } });
```

- Use two STUN servers from different operators, so one outage costs nothing.
- Put no `turn:` or `turns:` URL anywhere.
- Leave `iceTransportPolicy` unset (it defaults to `"all"`). Setting it to
  `"relay"` with no TURN makes every connection fail.
- Every `new Peer` in the app goes through the same options object. One call
  site that forgets it brings TURN back for that path.

**How to check:** open `chrome://webrtc-internals` (Chrome) or `about:webrtc`
(Firefox) during a connection. The ICE server list shows STUN only, and the
selected candidate pair is `host` or `srflx`, never `relay`.

## Rule 2: load it lazily; the app works without it

Pairing is the one part of the app that needs the network, so it is the one part
that must not stop the app booting. Load PeerJS only when somebody opens the
pairing UI, by adding a `<script>` tag on demand, and keep the result in a
module variable. If the load fails, pairing reports that it is unavailable and
everything else carries on unchanged.

## Pairing codes

The host registers with the broker under an id built from a short code, and the
guest connects to that id.

- **Namespace prefix.** The broker is shared by everybody, so prefix every id
  with something specific to the app: `"myapp-" + code`. PeerJS ids must start
  and end with a letter or digit, and may contain `-`, `_` and spaces in between.
- **Alphabet:** `BCDFGHJKLMNPQRSTVWXYZ23456789`. With no vowels a code cannot
  spell a word, and with no `0 O 1 I` it cannot be misread off a screen or
  misheard when read aloud.
- **Length: 6.** That is 29^6, about 5.9 × 10^8 codes. The code is the only
  thing standing between a stranger and the host; see *Security*.
- **Random from `crypto.getRandomValues`**, never `Math.random`.
- **Normalise whatever is typed.** Uppercase it, strip everything that is not
  `A-Z0-9`, and truncate it to the code length, so `bcd-fgh` and ` BCDFGH ` both
  work.
- **Three ways in, all showing the same code:** the code in large type, a link
  (`https://app.example/join?id=CODE`), and a QR code of that link. The join page
  reads `?id=` on load and fills it in.
- **Centre the QR code on the screen.** Centre it horizontally, and keep its
  white quiet zone, so a phone pointed at the middle of the display finds it
  without hunting.
- **Both ends remember.** The host stores its code and reuses it after a reload;
  the guest stores the last code it connected with. A reload on either side then
  comes back to the same pairing without anybody reading the code again.

## Statuses

Both ends report one status at a time, as an event the UI renders.

| Status | Meaning |
| --- | --- |
| `idle` | Nothing running. |
| `connecting` | Library loading, registering with the broker, or the channel negotiating. |
| `waiting` | Host only: registered under its code, no guest connected. |
| `connected` | At least one channel is open. |
| `dropped` | Guest only: the channel was open and then closed. |
| `unreachable` | Guest only: the channel never opened. |
| `error` | The broker or the library reported a problem; carries a message. |

**`dropped` and `unreachable` are different, and the UI must not blur them.**
Track whether each link ever opened. A link that closes without having opened
never reached the other device, and the usual cause is a network that will not
carry peer-to-peer traffic. Telling someone "the host disconnected" in that case
blames a device that did nothing.

**From the host's side both are `waiting`.** A guest that dropped and one that
never arrived leave the host in the same state: nobody is connected and the code
is still live. The UI should say what to do next, not describe the other device.

## Host behaviour

- `new Peer(prefix + code, options)`. On `open`, status `waiting`. On
  `connection`, bind the link.
- **Single-guest apps: a newcomer replaces the incumbent.** Remove the old link
  from your records *before* closing it, so its close handler sees a link that is
  no longer current and stays quiet. In PeerJS 1.5.x `DataConnection.close()`
  emits `close` synchronously, so the order matters.
- **Multi-guest apps: cap the number of seats.** Tell a guest over the cap that
  the session is full, then close their link. Guests get a fresh random peer id
  on every reconnect, so if a guest should keep their seat across a reload, have
  them pass a stable id they keep in `localStorage` in the `metadata` of
  `peer.connect`, and key seats by that id.
- **`unavailable-id` means something else holds the code:** another tab of the
  app, or the broker not yet releasing the id from a page that has just
  reloaded. Publish a fresh code **once**. A second collision in a row is not
  stale state, it is something systematically wrong, and retrying in a loop
  would hammer the broker while showing nothing useful.
- **Stop** destroys the peer, so the code stops working immediately. **New
  code** destroys it, clears the stored code, and starts again.

## Guest behaviour

- `new Peer(options)` with no id; the broker assigns a random one. On the peer's
  first `open`, `peer.connect(prefix + code, { reliable: true })`.
- **Pass `reliable: true`.** In 1.5.x it defaults to false.
- **Time out after 15 seconds.** When ICE cannot find a path nothing errors; it
  just keeps trying, and without a timer the page says "Connecting" forever. A
  handshake across two networks normally takes a second or two, so one that has
  taken fifteen is blocked. Close the link and report `unreachable`.
- **On open, send `hello`.** The host answers with everything the guest needs to
  draw itself.
- **`peer-unavailable`** means the broker has no peer under that code: the host
  is not running, is on a different code, or retired this one. That gets its own
  message, distinct from `unreachable`.

## Broker disconnects

`disconnected` fires on a peer when its WebSocket to the broker drops, for
example after the device sleeps or changes network. **Open data channels
survive it**, because they never went through the broker. What is lost is the
ability to accept new guests (host) or start a new connection (guest).

Call `peer.reconnect()` after a short delay, backing off on repeated failures.
It re-registers under the same id, and works only on a peer that was
disconnected rather than destroyed. It fires `open` again, so the guest must use
`once("open")` for its connect step or it will open a second link after every
broker blip.

A broker error while a channel is open does not end the session. Keep the
status `connected` and let the channel carry on.

## The protocol

Messages are plain objects with a `type` string. Keep them to what JSON could
carry: objects, arrays, strings, numbers, booleans.

### Minimum message set

| Message | Direction | Meaning |
| --- | --- | --- |
| `{ type: "hello", v }` | guest to host | "Send me everything." Carries the protocol version. |
| `{ type: "state", ... }` | host to guest | A full snapshot of what the guest needs to show. |
| `{ type: "input", ... }` | guest to host | One action. Name it for the app: `command`, `move`, `answer`. |
| `{ type: "bye" }` | guest to host | Leaving on purpose. |
| `{ type: "full" }` | host to guest | Multi-guest only: no seat left. |

### Rules

- **The host is authoritative.** Guests send intentions; the host applies them
  and broadcasts the result. A guest does not show an action as done until a
  snapshot says it is.
- **Send full snapshots, not diffs.** Send one on every change and on a timer
  of **20 a second** (every 50 ms, the tick rate Minecraft runs at). Over a
  same-network link that is a trivial load: a 1 KB snapshot 20 times a second
  is 20 KB/s, and a message takes a few milliseconds. A lost message, a late
  joiner or a reconnect then heals itself on the next snapshot, and nothing has
  to replay a history. If the guest shows motion, stamp each snapshot with the
  host's time and extrapolate between them, so movement stays smooth through
  the 50–200 ms stalls phone wifi takes now and then.
- **The periodic snapshot is the heartbeat.** A channel to a device that simply
  vanished (wifi switched off, battery dead) can take tens of seconds to report
  `close`. A guest that hears nothing for **2 seconds** should say the
  connection looks stale. Measure it in time, not in missed intervals: at 20 a
  second, three intervals is 150 ms, shorter than an ordinary wifi stall, and a
  host tab in the background has its timers throttled to about once a second.
  For a host to notice silent guests, guests send a small `ping` when they have
  nothing else to say, and the host drops any guest it has not heard from in a
  similar window.
- **`bye` separates leaving on purpose from an accident.** A closed channel looks
  the same either way. Send `bye` while the channel is still open, then close
  with `link.close({ flush: true })`, which in 1.5.x queues the close behind
  the messages already sent. On `bye` the host retires the code: it clears the
  stored one and publishes a fresh one, so a code shown to a room during one
  session does not keep working in the next. A channel that closes *without*
  `bye` leaves the code live, because the guest is probably coming back. **Never
  send `bye` from `pagehide` or `beforeunload`**: a reload is not a goodbye.
- **Shared editable data gets a revision counter owned by the host.** When
  both ends can edit the same thing, the host sends `rev` with every copy, the
  guest echoes the `rev` it edited from, and the host refuses an edit carrying
  a stale `rev`, replying with the current copy. A refusal is a normal message,
  not an error; the guest redraws. Without it, whichever message arrives last
  silently overwrites the other person's typing.
- **Ignore unknown types, never throw on them.** A PWA's service worker can
  leave one device a build behind the other. `v` in `hello` lets the host tell
  an old guest to reload when the protocol has really changed.
- **Validate every message.** It is input from another device. Check `type`
  against an allowlist, check field types, clamp numbers to sane ranges, never
  `eval` anything and never put received strings into `innerHTML`.
- **Keep messages small.** Tens of kilobytes at most. Anything bigger, such as
  a file, gets split into chunks by the app and tested on every target browser.

## Lifecycle on real devices

- **Backgrounding.** Mobile browsers suspend background pages, and a channel
  often dies with them. On `visibilitychange` back to visible, if the status is
  `dropped` and a code is remembered, reconnect automatically, or show a
  Reconnect button with the code filled in. Do not auto-retry `unreachable`:
  the network has not changed, so the result will not either.
- **Screen wake lock** on whichever device has to stay on (the host display, a
  controller in someone's hand): `navigator.wakeLock.request("screen")` while
  connected. The browser releases it when the page is hidden, so request it again
  on `visibilitychange`.
- **Navigation.** In a multi-page app, leaving the page tears down the peer and
  the channel. Ask for confirmation before navigating away from a live session,
  or keep the paired experience on one page.
- **Two host tabs.** The second one gets `unavailable-id` on the stored code and
  moves to a fresh one, as above.

## PWA integration

- **HTTPS.** Service workers already require it. `localhost` is fine for
  development.
- **Leave the library and the broker to the network.** Do not runtime-cache the
  CDN copy of PeerJS in the service worker. Pairing needs the network anyway, so
  a cached copy buys nothing offline, and an old signalling client talking to a
  live broker is worse than a clear "could not load". If you want the version
  locked to your build, bundle it from npm into your own precached assets
  instead, so it updates with the app.
- **Precache the join page**, so a link from a QR code opens even on a weak
  connection and can show a useful message.
- **Offline:** the app opens and works; the pairing UI says it needs a
  connection instead of spinning. Treat `navigator.onLine` as a hint only.
- **Content Security Policy**, if you set one: `script-src` needs
  `https://cdnjs.cloudflare.com` (unless PeerJS is bundled), and `connect-src`
  needs `https://0.peerjs.com` and `wss://0.peerjs.com`. The HTTPS entry is
  there because a peer created without an id asks the broker for one over HTTPS.
  `connect-src` does not cover STUN traffic.

## What the user sees when it fails

**Never tell someone the other device hung up about a channel that never
opened.**

| Cause | Detected as | Say |
| --- | --- | --- |
| Different networks, symmetric NAT | `unreachable` after 15 s | "Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen." |
| Client-isolated wifi | `unreachable` | Same message. The hotspot advice is what fixes it. |
| Wrong or retired code | `peer-unavailable` | "Nobody is hosting with that code. Check it and try again." |
| Broker down or unreachable | `network`, `server-error`, `socket-error`, `socket-closed` | "Cannot reach the pairing service. Everything else still works." |
| Library blocked or offline | the script load rejects | "Could not load pairing. Check your connection." |
| Very old browser | `browser-incompatible` | "This browser cannot make peer-to-peer connections." |
| Host code collision | `unavailable-id` | Nothing: publish a fresh code once, silently. |

**Do not suggest switching to mobile data.** Two different networks is the case
that fails, so that advice makes things worse.

## Security and privacy

- **The code is a bearer token.** Anyone who has it can join while it is live.
  Retire it on `bye`, offer New code, and do not keep codes alive forever.
  Where joining grants real control, have the host approve each new guest
  ("Allow this device?") before acting on its input, or lengthen the code.
- **IP addresses.** A connected peer learns the other's public IP address from
  the STUN candidates. Browsers hide local addresses behind random `.local`
  names in most cases. The broker operator sees ids and IPs. Say so in the
  privacy policy.
- **Encryption without authentication.** The channel is encrypted, but the
  only proof of who is on the other end is knowing the code, and the broker
  relays the handshake. For anything sensitive, show a short fingerprint on both
  screens and have people compare them, or self-host the broker.
- **The public broker is a courtesy.** For real traffic, run `peerjs-server` (a
  small Node service) and point `host`, `port` and `path` at it. That still
  needs no TURN.

## Reference implementation

One module that covers both ends. It has no dependencies beyond PeerJS, which it
loads itself. Change `PEER_PREFIX` per app.

```js
// p2p.js: host and guest pairing over PeerJS, STUN only.

const PEERJS_URL = "https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js";
const PEER_PREFIX = "myapp-";
const CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXYZ23456789";
export const CODE_LENGTH = 6;
export const PROTOCOL_VERSION = 1;
const CONNECT_TIMEOUT_MS = 15000;

// STUN only. Supplying `config` replaces PeerJS's default, which includes a
// public TURN relay.
const ICE_SERVERS = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun.cloudflare.com:3478" },
];
const PEER_OPTIONS = { debug: 0, config: { iceServers: ICE_SERVERS } };

const BROKER_ERRORS = new Set([
  "network", "server-error", "socket-error", "socket-closed", "disconnected",
]);

/* ---- codes ---- */

export function generateCode() {
  // Bytes at or above this would make some characters likelier than others.
  const limit = 256 - (256 % CODE_ALPHABET.length);
  let code = "";
  while (code.length < CODE_LENGTH) {
    const [byte] = crypto.getRandomValues(new Uint8Array(1));
    if (byte < limit) code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return code;
}

export function normaliseCode(input) {
  return String(input || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LENGTH);
}

export function isValidCode(input) {
  const code = normaliseCode(input);
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c));
}

/* ---- library ---- */

let peerLibrary = null;

function loadPeerJs() {
  if (peerLibrary) return Promise.resolve(peerLibrary);
  if (window.Peer) return Promise.resolve((peerLibrary = window.Peer));

  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = PEERJS_URL;
    script.async = true;
    script.onload = () =>
      window.Peer ? resolve((peerLibrary = window.Peer)) : reject(new Error("PeerJS did not define Peer"));
    script.onerror = () => reject(new Error("Could not load PeerJS"));
    document.head.appendChild(script);
  });
}

export function describePeerError(error) {
  switch (error?.type) {
    case "peer-unavailable":
      return "Nobody is hosting with that code. Check it and try again.";
    case "unavailable-id":
      return "That code is already in use. Generate a new one.";
    case "network":
    case "server-error":
    case "socket-error":
    case "socket-closed":
      return "Cannot reach the pairing service. Everything else still works.";
    case "browser-incompatible":
      return "This browser cannot make peer-to-peer connections.";
    default:
      return "The connection failed.";
  }
}

/* ---- shared ---- */

class Connection extends EventTarget {
  constructor() {
    super();
    this.peer = null;
    this.status = "idle";
  }

  setStatus(status, detail = {}) {
    this.status = status;
    this.dispatchEvent(new CustomEvent("status", { detail: { status, ...detail } }));
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

    link.on("open", () => {
      everOpened = true;
      this.onLinkOpen(link);
    });
    link.on("data", (message) => {
      if (!message || typeof message !== "object" || typeof message.type !== "string") return;
      this.dispatchEvent(new CustomEvent("message", { detail: { message, from: link.peer } }));
    });
    link.on("close", finish);
    link.on("error", finish);
  }

  // The broker socket can drop while channels stay up. Re-register under the
  // same id, backing off while it keeps failing.
  watchBroker() {
    const peer = this.peer;
    let delay = 1000;
    peer.on("open", () => { delay = 1000; });
    peer.on("disconnected", () => {
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

/* ---- host ---- */

export class Host extends Connection {
  constructor({ maxGuests = 1 } = {}) {
    super();
    this.maxGuests = maxGuests;
    this.links = new Map(); // guest peer id -> open link
  }

  async start(code) {
    const Peer = await loadPeerJs();
    this.code = code;
    this.setStatus("connecting");

    this.peer = new Peer(PEER_PREFIX + code, PEER_OPTIONS);
    this.watchBroker();

    this.peer.on("open", () => this.refreshStatus());
    this.peer.on("connection", (link) => {
      if (this.maxGuests === 1) {
        // The newcomer replaces the incumbent.
        for (const old of [...this.links.values()]) this.drop(old);
      } else if (this.links.size >= this.maxGuests) {
        link.on("open", () => {
          link.send({ type: "full" });
          link.close({ flush: true });
        });
        return;
      }
      this.bindLink(link);
    });
    this.peer.on("error", (error) => {
      if (error?.type === "unavailable-id") {
        this.setStatus("error", { message: describePeerError(error), taken: true });
        return;
      }
      // Guests already attached do not need the broker.
      if (this.links.size > 0 && BROKER_ERRORS.has(error?.type)) return;
      this.setStatus("error", { message: describePeerError(error) });
    });
  }

  onLinkOpen(link) {
    this.links.set(link.peer, link);
    this.dispatchEvent(new CustomEvent("join", { detail: { id: link.peer, metadata: link.metadata } }));
    this.refreshStatus();
  }

  onLinkClosed(link) {
    // Links this end dropped, and links that never opened, are not in the map.
    if (this.links.get(link.peer) !== link) return;
    this.links.delete(link.peer);
    this.dispatchEvent(new CustomEvent("leave", { detail: { id: link.peer } }));
    this.refreshStatus();
  }

  // A guest that dropped and one that never came look the same from here.
  refreshStatus() {
    this.setStatus(this.links.size > 0 ? "connected" : "waiting");
  }

  // Removed before closing: close() emits "close" synchronously.
  drop(link) {
    this.links.delete(link.peer);
    link.close();
  }

  // To one guest when `to` is given, otherwise to all of them.
  send(message, to) {
    for (const [id, link] of this.links) {
      if (to && id !== to) continue;
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
    this.setStatus("idle");
  }
}

/* ---- guest ---- */

export class Guest extends Connection {
  constructor() {
    super();
    this.link = null;
    this.timer = null;
  }

  async connect(code, metadata) {
    const Peer = await loadPeerJs();
    this.setStatus("connecting");

    this.peer = new Peer(PEER_OPTIONS);
    this.watchBroker();

    // Nothing errors when ICE cannot find a path; it just keeps trying.
    this.timer = setTimeout(() => {
      if (this.status !== "connecting") return;
      this.hangUp();
      this.setStatus("unreachable");
    }, CONNECT_TIMEOUT_MS);

    // once, not on: a broker reconnect fires "open" again.
    this.peer.once("open", () => {
      this.link = this.peer.connect(PEER_PREFIX + code, { reliable: true, metadata });
      this.bindLink(this.link);
    });
    this.peer.on("error", (error) => {
      if (this.status === "connected" && BROKER_ERRORS.has(error?.type)) return;
      this.hangUp();
      this.setStatus("error", { message: describePeerError(error) });
    });
  }

  onLinkOpen(link) {
    if (link !== this.link) return;
    clearTimeout(this.timer);
    this.setStatus("connected");
    this.send({ type: "hello", v: PROTOCOL_VERSION });
  }

  onLinkClosed(link, everOpened) {
    if (link !== this.link) return;
    this.link = null;
    this.setStatus(everOpened ? "dropped" : "unreachable");
  }

  send(message) {
    if (!this.link?.open) return;
    try {
      this.link.send(message);
    } catch {
      // As on the host.
    }
  }

  // Leaving on purpose: `bye` first, and a flushed close so it arrives.
  leave() {
    this.send({ type: "bye" });
    clearTimeout(this.timer);
    const link = this.link;
    const peer = this.peer;
    this.link = null;
    this.peer = null;
    link?.close({ flush: true });
    setTimeout(() => peer?.destroy(), 1000);
    this.setStatus("idle");
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
    this.setStatus("idle");
  }
}
```

### Wiring the host

```js
import { Host, generateCode, isValidCode } from "./p2p.js";

const CODE_KEY = "myapp.hostCode";
let host = null;
let retriedTaken = false;

function readStored() {
  try { return localStorage.getItem(CODE_KEY); } catch { return null; }
}
function writeStored(code) {
  try { code ? localStorage.setItem(CODE_KEY, code) : localStorage.removeItem(CODE_KEY); } catch {}
}

export async function startHosting() {
  if (host) return;
  const stored = readStored();
  const code = isValidCode(stored) ? stored : generateCode();
  writeStored(code);
  showCode(code, `${location.origin}/join?id=${code}`); // text, link and QR

  host = new Host({ maxGuests: 1 });
  host.addEventListener("status", ({ detail }) => {
    if (detail.taken && !retriedTaken) {
      retriedTaken = true;
      restartWithFreshCode();
      return;
    }
    if (detail.status === "waiting") retriedTaken = false;
    renderStatus(detail);
  });
  host.addEventListener("message", ({ detail: { message, from } }) => {
    switch (message.type) {
      case "hello": host.send(snapshot(), from); break;
      // Single guest: their code is spent. With several, free their seat instead.
      case "bye": restartWithFreshCode(); break;
      case "input": applyInput(message, from); break; // validate inside
      default: break; // unknown types are ignored, never thrown on
    }
  });

  try {
    await host.start(code);
  } catch {
    host = null;
    renderStatus({ status: "error", message: "Could not load pairing. Check your connection." });
  }
}

export function stopHosting() {
  host?.close();
  host = null;
}

export async function restartWithFreshCode() {
  stopHosting();
  writeStored(null);
  await startHosting();
}

// State on every change, plus a steady beat of 20 a second that doubles as the
// heartbeat.
setInterval(() => host?.send(snapshot()), 50);
```

### Wiring the guest

```js
import { Guest, normaliseCode, isValidCode, CODE_LENGTH } from "./p2p.js";

const LAST_KEY = "myapp.lastCode";
let guest = null;
let code = "";

export async function join(input) {
  code = normaliseCode(input);
  if (!isValidCode(code)) {
    renderStatus({ status: "error", message: `A code is ${CODE_LENGTH} characters.` });
    return;
  }

  guest?.close();
  guest = new Guest();
  guest.addEventListener("status", ({ detail }) => renderStatus(detail));
  guest.addEventListener("message", ({ detail: { message } }) => {
    if (message.type === "state") applySnapshot(message);
    if (message.type === "full") renderStatus({ status: "error", message: "This session is full." });
  });

  try {
    await guest.connect(code);
    try { localStorage.setItem(LAST_KEY, code); } catch {}
  } catch {
    renderStatus({ status: "error", message: "Could not load pairing. Check your connection." });
  }
}

export function leave() {
  guest?.leave();
  guest = null;
  try { localStorage.removeItem(LAST_KEY); } catch {}
}

// Fill the code in from the link, or from last time.
let remembered = "";
try { remembered = localStorage.getItem(LAST_KEY) || ""; } catch {}
const initial = normaliseCode(new URLSearchParams(location.search).get("id")) || normaliseCode(remembered);
if (initial) prefillCode(initial);

// Back from the background with a channel that died meanwhile.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && guest?.status === "dropped") join(code);
});
```

`showCode`, `renderStatus`, `snapshot`, `applyInput`, `applySnapshot` and
`prefillCode` are the app's own.

## Acceptance checklist

- [ ] The built output contains no `turn:` or `turns:`, and the WebRTC internals
      page shows STUN servers only and a `host` or `srflx` selected pair.
- [ ] Same wifi, two devices: joins by typed code, by link, and by QR.
- [ ] The QR code sits centred on the host's screen.
- [ ] Connected on the same wifi: the guest receives about 20 snapshots a
      second, and its moving parts glide rather than step.
- [ ] Phone hotspot with the other device joined to it: joins.
- [ ] Home wifi against a phone on mobile data: either joins, or reports
      `unreachable` within 15 seconds with the same-network message. It never
      hangs, and never says the host disconnected.
- [ ] Guest reloads: comes back on the same code without retyping it.
- [ ] Host reloads: republishes the same code, or a fresh one after one
      `unavailable-id`; a guest can rejoin.
- [ ] Guest leaves on purpose: the host moves to a new code, and the old code
      now gets "Nobody is hosting with that code".
- [ ] Single-guest mode, second guest joins: the first is replaced and the code
      is not retired.
- [ ] Phone locked for a minute, then unlocked: the session reconnects or offers
      Reconnect with the code filled in.
- [ ] Offline: the app opens and works, and pairing says it needs a connection.
- [ ] CDN blocked in devtools: pairing reports it could not load; nothing else
      breaks.
- [ ] Broker blocked: the pairing-service message, not a spinner.
- [ ] Broker blocked *after* connecting: the session carries on.
- [ ] Two host tabs: they end up on different codes.
- [ ] Malformed and unknown messages sent from a guest's console are ignored by
      the host.
