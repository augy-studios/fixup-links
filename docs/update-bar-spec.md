# Update prompt bar (portable)

A slim bar at the very top of the page that appears when a new version of the
site has been downloaded and is waiting, saying so in one sentence and offering
two controls: **Reload** and **Not now**. Nothing reloads until the reader asks
for it.

Drop it into any site that ships a service worker, or that caches its own build
hard enough that a reader can end up looking at yesterday's code. Nothing here
depends on a framework, a bundler, or a particular way of writing CSS.

## What it is for

A service worker exists to serve a site from a cache. The cost of that, on every
site that has one, is that a deploy does not reach anybody: the old worker keeps
answering from the old cache, and the reader carries on using a version that no
longer exists on the server. They find out when something breaks, and what they
report is not "the site is out of date", it is "the button does nothing".

There are three ways to handle that and only one of them is honest.

1. **Do nothing.** The new version arrives at the next hard refresh, whenever
   that is. Weeks, for somebody who keeps a tab open.
2. **Take over silently.** `skipWaiting()` in the worker's `install`, so the new
   version activates the moment it is downloaded. The reader's page is then
   running old JavaScript against new cached assets, mid-session, with a form
   half filled in. This is the one that produces bugs nobody can reproduce.
3. **Tell them and let them decide.** Which is this bar.

**The rule the whole design rests on: a new worker never activates on its own.**
It downloads, it installs, and then it waits. The only thing that promotes it is
a person pressing Reload.

## The mechanism, in three parts

### 1. The worker waits

- The worker calls **`skipWaiting()` nowhere in `install`** and
  **`clients.claim()` nowhere in `activate`**. A worker that claims clients on
  activation is doing silently what the button exists to ask about.
- It carries a **version constant** that changes on every deploy. This is the
  whole trigger: the browser compares the worker script byte for byte, so if the
  file has not changed there is no update to prompt about, however much else in
  the build has moved. **Bump it on every change to the site, not once per
  release cycle.** A version left alone is a prompt nobody ever sees.
- It listens for one message and acts on it:

```js
self.addEventListener('message', (event) => {
  const type = typeof event.data === 'string' ? event.data : event.data?.type;

  // The only place either of these is ever called.
  if (type === 'skip-waiting') {
    event.waitUntil(self.skipWaiting().then(() => self.clients.claim()));
  }
});
```

### 2. The page notices

One module, registering once for the whole site. Not an inline
`navigator.serviceWorker.register('/sw.js')` per page: the prompt needs the
`ServiceWorkerRegistration` object, and an inline script in the markup has
nowhere to hand it to.

```js
const SW_URL = '/sw.js';

let registration = null;
let waitingWorker = null;
let reloading = false;
let dismissed = false;

function watchForUpdate() {
  if (!registration) return;

  // A worker already waiting when the page opened. This is the ordinary case on
  // the second page view after a deploy, and without it the prompt would only
  // ever reach somebody who happened to have the page open at the moment the
  // new worker finished installing.
  if (registration.waiting && navigator.serviceWorker.controller) {
    waitingWorker = registration.waiting;
    render();
  }

  registration.addEventListener('updatefound', () => {
    const installing = registration.installing;
    if (!installing) return;

    installing.addEventListener('statechange', () => {
      // `installed` with a controller present means an update. `installed` with
      // no controller is a first install, which has nothing to prompt about:
      // there is no previous version on screen to protect.
      if (installing.state === 'installed' && navigator.serviceWorker.controller) {
        waitingWorker = registration.waiting ?? installing;
        render();
      }
    });
  });
}

function registerWorker() {
  if (!('serviceWorker' in navigator)) return;

  navigator.serviceWorker
    .register(SW_URL)
    .then((reg) => {
      registration = reg;
      watchForUpdate();
    })
    .catch((cause) => {
      // A refused registration is not a reason to break the page. Private
      // browsing in some browsers, and any http origin that is not localhost,
      // land here.
      console.warn('service worker registration failed:', cause);
    });

  // The swap, once somebody has accepted it. Reloading here rather than in the
  // click handler is what makes the page come back on the new version: the
  // controller has changed by this point, so the reload is served by the new
  // worker and not the one being replaced.
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloading) return;
    reloading = true;
    window.location.reload();
  });
}

// Registration on `load`, not immediately: installing fetches everything the
// worker precaches, and starting that while the page is still fetching its own
// assets is how a service worker makes a first visit slower for no gain.
if (document.readyState === 'complete') registerWorker();
else window.addEventListener('load', registerWorker, { once: true });
```

### 3. The bar

`t()` below is whatever the site already uses to look a string up; on a site
with one language it is the string itself. The button classes are placeholders
for whatever the site's own buttons are called, and the two `data-sw-*`
attributes are the only names this code needs to own.

```js
function render() {
  const existing = document.querySelector('.update-notice');

  if (!waitingWorker || dismissed) {
    existing?.remove();
    return;
  }

  const bar = existing ?? document.createElement('div');
  bar.className = 'update-notice';
  bar.setAttribute('role', 'status');
  bar.setAttribute('aria-label', t('update.label'));
  bar.innerHTML = `
    <div class="update-notice-inner">
      <p>${escapeHtml(t('update.ready'))}</p>
      <button type="button" class="btn btn-primary" data-sw-update>
        ${escapeHtml(t('update.reload'))}
      </button>
      <button type="button" class="btn btn-quiet" data-sw-later>
        ${escapeHtml(t('update.later'))}
      </button>
    </div>
  `;

  bar.querySelector('[data-sw-update]').addEventListener('click', () => {
    // The only place anything asks for skipWaiting. The reload happens on
    // controllerchange, not here.
    waitingWorker?.postMessage('skip-waiting');
  });

  bar.querySelector('[data-sw-later]').addEventListener('click', () => {
    dismissed = true;
    render();
  });

  if (!existing) document.body.prepend(bar);
}
```

The colours below are named as custom properties so they can be pointed at
whatever the site already defines. Only three things about the styling matter:
it is full width at the top of the document, it is visually quieter than the
page's own header, and it is tinted enough to read as a notice rather than as
part of the layout.

```css
.update-notice {
  background: color-mix(in srgb, var(--accent) 12%, transparent);
  border-bottom: 1px solid var(--border);
  color: var(--text);
  font-size: 0.875rem;
}

.update-notice-inner {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  max-width: 72rem;
  margin: 0 auto;
  padding: 0.5rem 1rem;
  /* Under the notch on a phone, where the bar is the topmost thing on screen. */
  padding-top: max(0.5rem, env(safe-area-inset-top));
}

.update-notice p { flex: 1 1 auto; min-width: 0; }
.update-notice .btn { flex: none; }
```

## The details that are easy to get wrong

Each of these is a real failure rather than a style preference.

- **Reload on `controllerchange`, never in the click handler.** Reloading
  immediately after posting the message races the worker: the page comes back
  controlled by the *old* worker, the new one is still waiting, and the prompt
  reappears on the fresh page. Which looks, to a reader, exactly like a button
  that does not work.
- **Guard the reload with a flag.** `controllerchange` can fire more than once,
  and a second `location.reload()` mid-navigation is a reload loop.
- **Handle the worker that was already waiting.** Most readers meet an update
  on their *next* visit, not while watching the page. A build that only listens
  for `updatefound` shows the prompt to almost nobody, and it will look fine in
  testing because that is exactly the case a developer creates by hand.
- **`installed` with no controller is a first install.** Prompting there tells
  somebody a site they have never opened has an update.
- **The version constant is the trigger.** If nothing in the worker file
  changes, the browser sees no update. Bump it on every deploy that changes
  anything the worker serves, and treat forgetting to as a build error rather
  than a habit.
- **Dismissal is for this page view only, and is never stored.** "Not now" means
  not now. Persisting it to `localStorage` means a reader who dismisses once
  never hears about an update again, which is the "do nothing" option with extra
  steps.
- **One bar, one state, one precedence order.** If the site also has an offline
  or connection bar, they share a region and a state machine and only the most
  urgent one draws. Two stacked bars above the header stop being unobtrusive,
  and being unable to reach the site at all outranks a version being ready.
- **`role="status"`, not `role="alert"`.** Nothing is wrong. An alert interrupts
  a screen reader mid-sentence to say a website is slightly newer than it was.
- **On a translated site, redraw the bar when the language changes.** The markup
  is written by JavaScript rather than sitting in the HTML, so whatever attribute
  a translation pass sweeps for is not on it, and it will otherwise stay in the
  language the page opened in.
- **Never auto-reload, on a timer or otherwise.** The reader may be halfway
  through a form. The point of the bar is that the moment is theirs to choose.

## The copy

Three strings, and the whole bar is one sentence and two buttons.

```json
{
  "update.label": "Update",
  "update.ready": "A new version of {site name} is ready.",
  "update.reload": "Reload",
  "update.later": "Not now"
}
```

- **Name the site.** "A new version of X is ready" tells somebody what is being
  updated. "An update is available" reads like an operating system prompt and
  belongs to no particular thing on screen.
- **Say what the button does, not what it means.** "Reload", not "Update now".
  The reader is being asked to consent to a page reload, and that is exactly
  what will happen.
- **"Not now", not "Dismiss" or "Later".** It is honest about being temporary,
  and it does not promise a reminder at a specific time.
- **No version numbers, no release notes, no "what's new" link** unless the site
  actually maintains one. A version string in this bar is noise to everybody who
  is not the person who deployed it.
- **Do not apologise, and do not explain the service worker.** One sentence.

If the site is translated, every one of these is a dictionary key like any other
string, in every language it ships.

## If the site has no service worker

The same bar, driven differently, for a plain static site or an app that caches
in another way. Serve a small JSON file, or reuse whatever build metadata
already exists, carrying a version or a build timestamp:

- The page records the version it booted with.
- On an interval, and on `visibilitychange` when the tab becomes visible again,
  fetch that file with `cache: 'no-store'`.
- If the version differs from the one the page booted with, draw the same bar.
  Reload is a plain `window.location.reload()`, with no message and no
  `controllerchange` to wait for.

Everything under "the copy" and most of "the details that are easy to get wrong"
applies unchanged. The two that do not are the reload timing rules, which exist
only because a worker has to be promoted first.

**Poll on visibility rather than only on a timer.** The reader who has had a tab
open since Tuesday is the exact person this is for, and they come back to it by
switching to the tab.

## Checking it works

There is no way to check this by reading the code, and it is checkable in about
two minutes by hand:

1. Open the site, let the worker install, confirm no bar.
2. Change the version constant in the worker and deploy, or serve locally.
3. Reload once. The new worker downloads and waits. **The bar appears.**
4. Press **Not now**. The bar goes. Navigate to another page: the bar is back,
   because a new version is still ready.
5. Press **Reload**. The page reloads once, and the bar is gone.
6. Confirm in devtools that the old worker is gone rather than still waiting.
7. Repeat with the tab left open across the deploy, which is the
   `updatefound` path rather than the already-waiting one. Both have to work.

Worth adding one scripted check wherever there is a test harness to put it in:
**that the worker's source contains no `skipWaiting()` outside the message
handler.** That is the single change that silently turns this whole design back
into option 2, and it is the kind of line somebody adds to fix a caching
complaint without knowing what it was protecting.

## What this is not

- **Not a release channel.** It says a new version is ready and nothing about
  what changed.
- **Not a forced update.** There is no version this refuses to let somebody keep
  using. A site that genuinely cannot run an old client needs a server side
  answer, not a bar.
- **Not a connection status indicator**, although it may share a region with
  one. "You are offline", "we cannot reach the site", and "a new version is
  ready" are three different claims, and each one gets its own sentence.
