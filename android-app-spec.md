# Android app: spec for wrapping an UwU Apps site in Capacitor

An Android app that is the live website, running in [Capacitor](https://capacitorjs.com)'s
WebView, plus a thin native layer for the things a web page can't do: notifications without
Web Push, background work, widgets, Quick Settings tiles, the launcher icon, links that open in
the app, and updating itself from GitHub Releases. It's shared as a signed APK, not through
Google Play.

The site stays the product. Its deploys reach the app the moment it next loads, so the app only
needs rebuilding when its native side changes. The website and PWA lose nothing: everything a
browser can do stays exactly as it was, and native features switch on only inside the app.

This document is self-contained. The reference implementation is **SG PSI**
(`android/`, `main-site/js/app-*.js`); **uwuHere** and **SG Bus Timings** are two more built
the same way, and are named where they do something SG PSI doesn't.

---

## 0. Decide first

| Decision | Example | Why it matters |
|---|---|---|
| Package name | `org.uwuapps.sgpsi` | Permanent. Android treats a different package as a different app, and the signing key, `assetlinks.json`, Firebase and Google's developer verification are all tied to it |
| The site's host | `sgpsi.uwuapps.org` | `server.url`, the verified links, the update check, `MainActivity.SITE` |
| App name and user agent tag | `SG PSI`, `SGPSIApp/1` | The tag lets the page lay itself out for the app from the first paint (§6.2) |
| Native features | alerts, widget, tile | Each one costs permissions, battery or upkeep. Add one only where the web page genuinely can't do it (§7) |
| Firebase | the shared **UwU Apps** project | Needed for any notification from a server. Without it the app still builds and works |
| GitHub repository | `augy-studios/sg-psi` | Must be **public**: a private repo's release APKs can't be downloaded by phones or by the updater |

The rule that keeps the app maintainable: **the native side never duplicates the page.** It
adds capabilities and hands them to the page through one plugin (§5). Layouts, copy and logic
stay in the site.

---

## 1. How it works

```text
 ┌──────────────── Android app (org.uwuapps.<id>) ────────────────┐
 │ MainActivity (Capacitor BridgeActivity)                         │
 │   WebView ── loads https://<host>/ (capacitor.config server.url) │
 │      │  window.Capacitor injected before the page's scripts     │
 │      │                                                          │
 │      ├─ js/app-bridge.js ──► <App>Plugin  (native features)     │
 │      └─ Capacitor plugins: PushNotifications, SystemBars        │
 │                                                                  │
 │ UpdateActivity      downloads the APK, Android's installer      │
 │ Widgets, Tile, WorkManager job   run with the app closed         │
 └──────────────────────────────────────────────────────────────────┘
        │ FCM pushes                     ▲ /api/app-release
        ▼                                │
 Vercel: /api/* (FCM sender, release check, webhook)  ◄── GitHub Releases
```

- The page detects the app by `window.Capacitor` and asks it what it can do (`info().features`).
- Offline on the very first launch, the WebView shows `www/offline.html` (`server.errorPath`).
  After that, the site's own service worker serves it offline, exactly as in Chrome.
- The site's service worker and update bar keep working inside the app; the app's own updates
  share the same bar (§8).

---

## 2. The project

```text
android/
  package.json, package-lock.json   Capacitor and its plugins, pinned exactly
  capacitor.config.json             the site's address, user agent, plugin settings
  www/offline.html                  the first-launch-offline page
  native/                           the Android Studio / Gradle project
    app/build.gradle                versions, signing, dependencies
    app/src/main/AndroidManifest.xml
    app/src/main/java/org/uwuapps/<id>/   MainActivity, <App>Plugin, UpdateActivity, ...
    app/src/main/res/               icons, splash, widgets, strings, colours
    variables.gradle                SDK and library versions
  build-apk.ps1                     one command: key, sync, build, sign, check, copy out
  README.md                         what the app adds, permissions, building
  FIREBASE-SETUP.md                 step by step for notifications
release/
  README.md                         publishing on GitHub
  <version>/<app>-<version>.apk     each build, committed
main-site/
  .well-known/assetlinks.json       the signing key's fingerprint (verified links)
  js/app-bridge.js                  the channel to the app
  js/app-update.js, js/app-*.js     the app-only features' page side
  api/app-release.js                the newest release, for the updater
  api/push/release.js               GitHub webhook: "new version" push
  api/_push/fcm.js                  FCM sender
```

### Versions (October 2026, known to build together)

| Piece | Version | Notes |
|---|---|---|
| `@capacitor/android`, `core`, `cli` | 8.5.3 | Raise all three together |
| `@capacitor/push-notifications` | 8.1.3 | Its numbers run separately: take the newest for that Capacitor |
| Android Gradle Plugin | 8.13.0 | `native/build.gradle` |
| Gradle wrapper | 8.14.3 | Lint says 8.14.6 exists; harmless |
| Google services plugin | 4.4.4 | Applied only when `google-services.json` exists |
| `compileSdk` / `targetSdk` / `minSdk` | 36 / 36 / 24 | 24 is Android 7.0 |
| Java | 21 (any JDK 21+ runs the build; JDK 24 works) | `capacitor.build.gradle` sets 21 |
| `firebase-messaging` | 25.0.1 | The push plugin reads `firebaseMessagingVersion` too |
| `androidx.work:work-runtime` | 2.11.2 | Background refresh |
| `play-services-location` | 21.3.0 | Only if location in the background is used |
| `play-services-nearby` | 19.3.0 | Not 19.5: built with a newer Kotlin than this build reads (uwuHere); 19.4 needs desugaring |

Generated by `npx cap sync`, never edited, and kept out of git: `capacitor.settings.gradle`'s
plugin list is rewritten each sync (commit it anyway, as the reference projects do),
`capacitor-cordova-android-plugins/`, `app/src/main/assets/public/`, and
`app/src/main/assets/capacitor.*.json`.

---

## 3. Setting it up

The fastest start is copying the reference's `android/` and renaming; the equivalent from
scratch is `npm i @capacitor/core @capacitor/cli @capacitor/android`, `npx cap add android`,
then moving `android/` to `native/` and making the changes below.

### 3.1 `capacitor.config.json`

```json
{
  "appId": "org.uwuapps.<id>",
  "appName": "<App name>",
  "webDir": "www",
  "server": { "url": "https://<host>", "errorPath": "offline.html" },
  "android": { "path": "native", "appendUserAgent": "<App>App/1" },
  "plugins": {
    "SystemBars": { "insetsHandling": "css", "initialViewportFitValueHint": "cover" },
    "PushNotifications": { "presentationOptions": ["alert", "sound"] }
  }
}
```

- `server.url` makes the app load the live site. Without it, Capacitor serves `www/` from the
  APK, which is a different app altogether (no deploys, no service worker).
- `appendUserAgent`: bump the number when the page must lay out differently for a newer build
  (uwuHere's `/2` dropped the status bar). The page reads it before the bridge answers (§6.2).
- `SystemBars.insetsHandling: "css"` passes the system bars' sizes into the page as
  `--safe-area-inset-*` (§6.2). Leave it out and content runs under the bars.
- `presentationOptions: ["alert"]` makes Capacitor show a push that arrives while the app is in
  front. Android shows background pushes itself; without this, foreground ones are silent.
- `www/offline.html` must be self-contained (inline CSS, no fonts from the network), match the
  site's colours in both modes, and have a **Try again** link to `https://<host>/`.

### 3.2 `app/build.gradle`

- `namespace` and `applicationId` = the package. `versionCode` (integer, +1 each release) and
  `versionName` (`"1.0.0"`, also the release folder's name).
- Signing from `android/keystore.properties` and `android/android.keystore`, only when present,
  so a fresh checkout still builds debug:

```groovy
def keystoreProps = new Properties()
def keystoreFile = rootProject.file('../keystore.properties')
if (keystoreFile.exists()) keystoreFile.withInputStream { keystoreProps.load(it) }
signingConfigs {
    release {
        if (keystoreProps.storeFile) {
            storeFile rootProject.file("../${keystoreProps.storeFile}")
            storePassword keystoreProps.storePassword
            keyAlias keystoreProps.keyAlias
            keyPassword keystoreProps.keyPassword
        }
    }
}
buildTypes { release { minifyEnabled false; if (keystoreProps.storeFile) signingConfig signingConfigs.release } }
```

- Firebase applied only when its file exists, so the app builds without it:

```groovy
try {
    if (file('google-services.json').text) apply plugin: 'com.google.gms.google-services'
} catch (Exception e) { logger.info("google-services.json not found: no push") }
```

- `minifyEnabled false`: R8 would strip `@PluginMethod`s it can't see being called. Turning it
  on needs keep rules for every plugin class.

### 3.3 `MainActivity`

Extends `BridgeActivity`. In order:

1. `registerPlugin(<App>Plugin.class)` **before** `super.onCreate` (after it, the plugin isn't
   injected into the first page load).
2. `Notifications.createChannels(this)` before anything could post.
3. `layoutInDisplayCutoutMode = SHORT_EDGES` (Android 9+), so the page runs into the camera
   cutout instead of a black strip on phones before Android 15.
4. Back goes back through the page's history (`webView.canGoBack()` / `goBack()`), and at the
   first page `moveTaskToBack(true)` rather than closing, so the page keeps its state.
5. `onWindowFocusChanged(true)`: hide the status bar with
   `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE`. It must be here, not in `onCreate`: Capacitor's
   SystemBars shows the bars as it starts, and the shade or another app can leave them showing.
6. `onNewIntent`: open what the app was opened with (a verified link, a `uwu://<id>/` link, a
   tapped notification's extras) with `bridge.getWebView().loadUrl(url)`. Capacitor calls it
   with the launch intent too, after the home page starts loading. Remove handled extras
   (`intent.removeExtra("type")`), or a recreated activity acts on them twice.

### 3.4 The manifest

- `INTERNET`, `ACCESS_NETWORK_STATE` always. Every other permission has a comment saying what
  asks for it and when (§11).
- `MainActivity`: `launchMode="singleTask"`, `exported="true"`, the long `configChanges` list
  from the template (so rotation and dark-mode switches don't reload the page), and the splash
  theme `AppTheme.NoActionBarLaunch`.
- Intent filters: `MAIN`/`LAUNCHER` (or on activity aliases, §12.4); verified https links with
  `android:autoVerify="true"` for `<host>`; `uwu` scheme with `android:host="<id>"` only, as
  every UwU app shares the scheme.
- Firebase defaults: `default_notification_icon`, `default_notification_color`,
  `default_notification_channel_id`.
- `UpdateActivity` and its `InstallStatus` receiver, both `exported="false"`.

---

## 4. Signing, building, releasing

### 4.1 One command

```powershell
powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
```

`build-apk.ps1` (copy the reference's; change `$package`, the key alias and dname, and the
APK name):

1. Finds a JDK 21+ (`JAVA_HOME`, else the newest under `C:\Program Files\Eclipse Adoptium`,
   `Java`, `Microsoft`) and the SDK (`ANDROID_HOME`, else `~/.bubblewrap/config.json`'s, else
   `%LOCALAPPDATA%\Android\Sdk`).
2. **First run only**: no keystore and `assetlinks.json` still has the template's fingerprint
   (`E4:EB:13:B6:…`, the UwU Apps template's) → makes a 4096-bit RSA PKCS12 key valid 100 years
   with a random password, writes `keystore.properties`, and writes the fingerprint into
   `main-site/.well-known/assetlinks.json`.
3. **Every later run**: if `assetlinks.json` names a key and the keystore is missing, it
   **stops**. It never makes a second key, as a different key can't update installed apps.
4. `npm ci` if `node_modules` is missing, then `npx cap sync android`.
5. `gradlew assembleRelease`, then `apksigner verify --print-certs`, and **refuses an APK whose
   SHA-256 isn't the one in `assetlinks.json`**.
6. Copies it to `release/<versionName>/<app>-<versionName>.apk`, warning if that version
   already has one.

Windows PowerShell 5.1 quirks the script handles, and new scripts must too:

- A native tool writing to stderr becomes a PowerShell error: run tools through a helper that
  sets `$ErrorActionPreference = 'Continue'` and judges by `$LASTEXITCODE` only.
- `Set-Content` defaults to ANSI: pass `-Encoding ASCII` (or UTF8) for files other tools read.
- Gradle is run with `Start-Process -NoNewWindow -Wait -PassThru` so its output streams live.

### 4.2 The key

- `android.keystore` and `keystore.properties` are **never committed**, and must be **backed
  up** (password manager). Losing them means no installed phone can ever update: every user
  uninstalls and reinstalls, and `assetlinks.json` changes.
- A debug build (Android Studio, `installDebug`) is signed with the debug key. Installing a
  release APK over it fails with "App not installed": uninstall first.
- Google's **developer verification** (from 30 September 2026 in Singapore, Brazil, Indonesia,
  Thailand): register the package with the key's SHA-256 on the Android Developer Console, or
  Play Protect warns and, as it rolls out, blocks installs.

### 4.3 `.gitignore`

`android/.gitignore`:

```gitignore
android.keystore
*.keystore
*.jks
*.p12
*.pfx
keystore.properties
google-services.json
*firebase-adminsdk*.json
*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f].json
node_modules/
*.apk
*.aab
*.idsig
```

The root `.gitignore` repeats the key, Firebase and service-account patterns (a key saved
anywhere by mistake), plus `.env`, `.env.*`, `!.env.example`, `.vercel`, `node_modules/`.
It must **not** ignore `*.apk`: `release/<version>/*.apk` is committed. Check after setting up:

```sh
git check-ignore -v --no-index android/android.keystore android/keystore.properties \
  android/native/app/google-services.json main-site/uwu-apps-0123456789ab.json   # all ignored
git check-ignore -q --no-index release/1.0.0/<app>-1.0.0.apk || echo committable
```

`native/.gitignore` is Capacitor's template (build output, `local.properties`, generated
assets); keep it.

### 4.4 Releasing

1. Raise `versionCode` and `versionName`. A phone only takes a **higher `versionCode`**.
2. Build; commit the code and the APK together; deploy the site first if the release needs
   anything new from it.
3. GitHub → Releases → new, tag **`android-v<version>`** (the updater only reads that prefix),
   title `<App> <version>`, attach the APK **before** publishing (the "new version" push goes
   out on publish, and only for a release with its APK), tick **Set as the latest release**.
4. Paste the release notes (§4.5) into **Describe this release**, then post the announcement.

### 4.5 Release notes and the announcement

Three pieces of writing go with a release, each for a different reader:

| Piece | Where | Reader | Length |
|---|---|---|---|
| Release notes | The GitHub release's description | Someone about to download or update | A screen or two |
| Announcement | The app's channel, chat or socials, pasted from a code block | A follower scrolling past | Under 15 lines |
| Patch notes (if the project keeps them) | `main-site/PATCHNOTES.md`, newest first | Someone checking what changed and when | One section per update |

#### The release notes

Template, filled in for a release with every platform; drop the rows and sections a release
doesn't have:

```markdown
<One sentence naming the headline features, as a list: "A Wear OS watch app, Offline Sharing,
reminders that come to you, and your next buses in the desktop tray.">

## Download

| Device | File |
|---|---|
| Android 7.0 or newer | `<app>-<version>.apk` |
| Wear OS 3 or newer watch (new) | `<app>-<version>-watch.apk` |
| Windows 10 or 11 | `<app>-<version>-setup.exe` (or the `.msi`, for installing on many computers at once) |
| Mac with Apple silicon (M1 and later) | `<app>-<version>-mac-arm64.dmg` |
| Mac with an Intel processor | `<app>-<version>-mac-x64.dmg` |
| Debian, Ubuntu, Mint | `<app>-<version>-amd64.deb` |
| Any other Linux | `<app>-<version>-x86_64.AppImage` |

## Updating

**Android**: tap **Update** on the bar at the top of the app, or the download-arrow button in
the Edge Tray. New to the app? Download the `.apk` on your phone and open it. If Play Protect
asks about the app, tap **More details** > **Install anyway**.

**<Each other platform>**: what happens by itself, and what to tap if anything.

**New to the <platform> app?**
- **<Platform>**: how to install, including the one warning they'll see and how past it.

Your favourites and settings stay when you update.

## What's new

### <Platform> app (new)
- **<Feature name>**: what it does for you, in a sentence or two.

### Android app
- **<Feature name>**: what it does, where to find it.
  - Sub-bullets only for a feature with steps or alternatives.

### Everywhere
- **<Feature name>**: a change to the site itself, which every app has at once.

## What's fixed
- **<What was wrong, named as the thing>**: what used to happen, and when. What happens now.

<Optional closing line for anyone moving across a big change: "Coming from Android 1.x? 2.0
starts empty: see the 2.0.0 release notes for how to bring your favourites across with Sync.">
```

For the **first release** of an app, there's nothing to update from:

- The opening sentence starts `The first <App> app for Android: …`.
- **Installing** replaces **Updating**. It gives the install steps, then one paragraph,
  **Updating later**, saying the app updates itself from the bar and the Edge Tray's
  download-arrow button.
- Under the Download table, one line for everyone else: "On an iPhone, a computer or any other
  phone, use [&lt;host&gt;](https://&lt;host&gt;) in the browser, and add it to your home screen
  to install it as an app."
- **What's new** opens with **Everything on the website**: the site's features in one sentence,
  and that it works offline.
- No **What's fixed**.

How to write them:

- **Every feature is `- **Name**: sentence.`**: a bold name a person would call it, a colon,
  then what it does for them. A sentence starts lower case after the colon, as in the template.
  A name alone (`- **Updated app icon**`) is enough when there's nothing to add.
- **Say what it does, not how it's built.** "Alerts follow whichever region you're in", not
  "FCM token re-registration on geofence change". No class names, file names, API names or
  permissions' constant names.
- **Name the controls as the app shows them**, in bold: **Update**, **Send test alert**, **More
  details** > **Install anyway**. Use `>` for a path through screens. Where something lives:
  "under the bell in the Edge Tray", "in Settings", "on a stop's timings".
- **"You" and "your"**, present tense, plain words: "you get a notification when…", "tap…".
- **Concrete numbers**: "20 minutes before", "every half hour", "Android 7.0 or newer".
- **Sub-bullets** only for alternatives or steps inside one feature, never to split a feature
  into fragments.
- **Group by where it works**, in this order: a new platform's app (marked "(new)"), Android,
  the desktop apps, then **Everywhere** for site changes. Repeating the site's changes under
  each app is for the patch notes, not here.
- **Say the cost or the condition** where there is one, in the same bullet: what it asks
  permission for, that it needs Firebase or Play services, that the receiving phone needs the
  internet, that some home screens move the icon.
- **Privacy in one plain clause** where location, contacts or the calendar are involved: "Only
  the region ever leaves your phone."
- **Fixes say what went wrong as the user saw it**, then what happens now: "after a long wait at
  the first stop, a bus that had already left could be taken as yours… Now only a bus that
  could have left in the last few minutes counts."
- **Leave out** anything not in the build, or not working until server setup is done (for
  example notifications before Firebase is set up). Don't promise what the release doesn't do.
- British spelling (colour, optimisation), as the apps use.

#### The announcement

Short, pasted as is, so it's written as plain text (no Markdown bold or links), sent as a code
block so the emoji and line breaks survive copying:

```text
✨UPDATE✨ <App> <version>
<host>

New:
- <Feature, a short phrase with its benefit>
- <Feature>

<Platform> app:
- <Feature>

Telegram bot (@<bot>):
- <Feature>

Download the apps and view patch notes: github.com/<owner>/<repo>/releases/latest
```

- The header is `✨UPDATE✨` with the app and version, for every release after the first. Only a
  first app release says `✨NEW✨`, and what it is: `✨NEW✨ <App> 1.0.0 for Android`.
- One line per feature, a phrase rather than a sentence, leading with what people get: "PSI
  alerts as notifications, even with the app closed".
- Only the headline features: four to six under **New**, fewer under each platform. Fixes only
  when people noticed the bug ("no more blurry bus icon").
- A one-line instruction belongs here only when people must act ("Mac: on 2.0.2, download
  2.0.3 once by hand").
- Groups as in the release notes, each `<Platform> app:` or `Website:`, dropped when empty.
- Always ends with the `releases/latest` link, never a version's own page, so it stays right.

#### The patch notes (SG Bus Timings' `main-site/PATCHNOTES.md`)

- A header with the latest update's date and the app's links, then `---`, then updates newest
  first.
- Each update: `## <day month year>: <title>`, with "(later)", "(evening)" and so on for more
  than one a day, and the apps' version in the title when there's one ("Apps 2.1.0, and a watch
  app").
- `### Web app`, `### Android app <version>`, `### Desktop app <version>`,
  `### Telegram bot`, each with `- **Name** - sentence.` (a dash after the name here).
- Each app's section ends "- The web app's changes above." when it has them too, and a
  site-only update says "A website update, so the apps have it as soon as they open, with no
  new version to install."

---

## 5. The bridge

### 5.1 Page side: `js/app-bridge.js`

Loaded **before** every script that uses it. Plain script or module, whichever the site uses.

```js
const cap = window.Capacitor;
const native = Boolean(cap && typeof cap.nativePromise === "function" && cap.getPlatform?.() === "android");
let info = null;
// call: cap.nativePromise(plugin, method, options)
// on:   cap.addListener(plugin, event, (data, err) => { if (!err) fn(data); }) → { remove() }
// ready(ms): resolves true once <App>.info answered, false after ms
// has(feature): info.features.includes(feature)
```

On load in the app it also sets `data-app="android"`, `data-statusbar="hidden"` (from the user
agent's build number), calls `<App>.info`, and keeps the status bar's icons matching the
page's mode (§6.3).

Rules:

- **Gate every app-only feature on `AppBridge.has("<feature>")`, never on `native` alone.** An
  older APK lacks newer features; the site deploys ahead of the APK and must cope.
- Wait with `AppBridge.ready(5000)` before deciding; `info` arrives asynchronously.
- App-only UI is **in the markup but `hidden`**, or created by script, and revealed only after
  `has()`. A browser must never flash it.
- Every bridge call has a `.catch()`. A rejected call is the normal answer from an old APK.

### 5.2 Native side: `<App>Plugin`

```java
@CapacitorPlugin(name = "<App>", permissions = {
    @Permission(alias = "location", strings = {Manifest.permission.ACCESS_COARSE_LOCATION}),
})
public class <App>Plugin extends Plugin {
    @PluginMethod public void info(PluginCall call) { /* version, versionCode, features[], android */ }
}
```

- `info()` lists features **only when they'll work**: `push` only if
  `!FirebaseApp.getApps(ctx).isEmpty()` (the APK has `google-services.json`), anything Play
  services-based only if `GoogleApiAvailability…isGooglePlayServicesAvailable == SUCCESS`.
- Validate every argument from the page (regex for ids, tokens, names). The page is the site,
  but the WebView will also run whatever a compromised or mistaken deploy sends.
- UI work on `getActivity().runOnUiThread`; network and location on a background executor,
  never the main thread. Resolve the `PluginCall` exactly once on every path.
- Permissions: `requestPermissionForAlias(alias, call, "callbackName")` with a
  `@PermissionCallback private void callbackName(PluginCall call)`. Answer refusals as data
  (`{ state: "denied" }`), not rejections, so the page can say what to do.

---

## 6. Look and feel in the WebView

The page looks identical to Chrome **only if** these are handled.

### 6.1 Edge to edge and the system bars

Capacitor 8 draws the page edge to edge: under the status bar at the top and the gesture or
button bar at the bottom. Android 15+ forces this anyway.

- **The status bar is hidden** (`MainActivity.onWindowFocusChanged`), swipe down to show it
  briefly. The page gets the full height and never needs a top inset. Keep it hidden unless the
  site has a reason; a visible bar means every top-pinned element needs `--safe-top`.
- **The bottom gesture bar overlaps the page.** Anything pinned to the bottom (toasts, map
  attribution, sticky footers, a modal's lower edge) and the page's last content need
  `--safe-bottom` padding.

### 6.2 Safe areas: one set of tokens

Android's WebView reports `env(safe-area-inset-*)` as **0** in this mode; SystemBars passes the
real values as `--safe-area-inset-*`. Read both through tokens and **never use `env()`
directly anywhere else**:

```css
:root {
  --safe-top: var(--safe-area-inset-top, env(safe-area-inset-top, 0px));
  --safe-right: var(--safe-area-inset-right, env(safe-area-inset-right, 0px));
  --safe-bottom: var(--safe-area-inset-bottom, env(safe-area-inset-bottom, 0px));
  --safe-left: var(--safe-area-inset-left, env(safe-area-inset-left, 0px));
}
/* The app hides the status bar (set by js/app-bridge.js from the user agent). */
:root[data-statusbar="hidden"] { --safe-top: 0px; }
```

Where they're needed: the update bar's top padding, the Edge Tray's top and right offset, the
modal backdrop's padding, the column's bottom padding, bottom-fixed elements, and a
full-screen map's controls. `viewport-fit=cover` in the page's viewport meta.

Why `data-statusbar` comes from the **user agent**, not `info()`: the user agent is there
before the first paint; `info()` answers after it, and the page would jump.

### 6.3 Light and dark

- The site decides light or dark itself (`data-mode`), often against the phone's setting. The
  status bar's icons must follow the page:
  `AppBridge.call("SystemBars", "setStyle", { style: mode === "dark" ? "DARK" : "LIGHT" })`,
  on load and whenever `data-mode` changes (a `MutationObserver`). Otherwise dark icons sit on a
  dark page.
- Native screens (splash, update dialog, widgets) follow the **phone's** mode through
  `values-night/`. Give every colour a night value.
- Set `color-scheme` on the page per mode (`:root[data-mode="dark"] { color-scheme: dark }`).
  A page that doesn't may be darkened algorithmically by the WebView in the phone's dark mode,
  which inverts brand colours.

### 6.4 The splash and the first paint

- The theme's `windowBackground` is the site's page colour (light in `values/`, dark in
  `values-night/`), so there's no white flash between splash and page.
- Splash (`Theme.SplashScreen`, core-splashscreen 1.2.0): `windowSplashScreenAnimatedIcon` must
  be a **dedicated high-resolution image**, not the launcher foreground. The splash draws it at
  240dp (with an icon background) or 288dp; a 108dp launcher foreground is stretched 2.7× and
  blurs. Use `drawable-nodpi/splash_icon.png` at 1152px. Only the middle two thirds show
  (a circle), so it's the same widened art as the adaptive foreground (§14).
- The site's inline "no flash" scripts (theme mode, Edge Tray state) work unchanged.

### 6.5 Other things that change the look

| Watch for | In the app | Do |
|---|---|---|
| Fonts from Google Fonts | Load over the network as in Chrome; offline only if the service worker cached them | Keep the SW caching them |
| `100vh` | Full height (no status bar); the keyboard resizes the WebView | Prefer `100dvh` / `100%` for full-screen views |
| Text size | The WebView may scale text with Android's font size setting differently from Chrome | Test at the largest system font size |
| Tap highlight | Android's grey flash on tap | `-webkit-tap-highlight-color: transparent` where the site already styles `:active` |
| Hover styles | Sticky after a tap | Guard hover-only effects with `@media (hover: hover)` |
| `position: sticky` / `fixed` | Work, but a fixed element at `top: 0` sits at the very top of the screen | Pad by `--safe-top` (0 with the bar hidden) |
| External links | Open in the phone's browser, not the app (other hosts) | Fine; don't rely on `target="_blank"` popups |
| Scrollbars | Overlay, as in mobile Chrome | Nothing |

---

## 7. What the WebView can't do

These work in Chrome and **silently fail** in the app. Each needs the app's version or a
graceful fallback, behind `has()`.

| Web feature | In the WebView | The app's way | Reference |
|---|---|---|---|
| Web Push (`PushManager`), `Notification` | Missing | FCM via Capacitor PushNotifications (§10) | SG PSI `js/alerts.js` |
| Screen Wake Lock | Missing | `FLAG_KEEP_SCREEN_ON` from the plugin | uwuHere `keepAwake` |
| Screen brightness | No API on the web either | `WindowManager.LayoutParams.screenBrightness` (this window only) | uwuHere `brightness` |
| Download a file the page made (`blob:`, `a[download]`) | Does nothing | MediaStore Downloads (Android 10+) or `ACTION_CREATE_DOCUMENT` | uwuHere `saveFile` |
| `navigator.share` | Missing | `Intent.ACTION_SEND` chooser | SG Bus Timings `share` |
| Speech recognition | Missing | `RecognizerIntent` (no mic permission) | SG Bus Timings `listen` |
| Picture-in-picture | Missing | `enterPictureInPictureMode` + manifest flag | SG Bus Timings `pip` |
| Fullscreen API | Unreliable | Hide the bars natively instead | |
| Background sync, periodic sync | Missing | WorkManager (§12.1) | SG PSI `ReadingsWorker` |
| Geolocation | **Works**: Capacitor asks Android for the permission, *if the manifest declares it* | Declare `ACCESS_FINE`/`COARSE_LOCATION` | uwuHere |
| Camera (`getUserMedia`) | Works with `CAMERA` declared | Same | SG Bus Timings scan |
| Vibration | Works with `VIBRATE` declared | Same | |
| Clipboard write | Works after a tap | Test it | |
| Service worker, Cache Storage, IndexedDB, localStorage | Work | Nothing, but see below | |
| `beforeinstallprompt`, `display-mode: standalone` | Not fired / not matched | Hide "install the app" prompts when `AppBridge.native` | |

**Storage is separate from Chrome's.** The app starts with empty `localStorage`: no saved
settings, theme, favourites or device ids from the browser. A site with accounts or Sync is
fine; one that keeps everything locally should say so in the release notes (SG Bus Timings 2.0
"starts empty").

---

## 8. Updates

Two kinds, one bar (the site's update prompt bar, `update-bar-spec.md`):

| Precedence | State | Bar says | Primary |
|---|---|---|---|
| 1 | Offline | "You're offline…" | none |
| 2 | New site version waiting | `A new version of <App> is ready.` | Reload (`skip-waiting`) |
| 3 | New app version on GitHub | `Version X of the <App> app is out.` | Update → `UpdateActivity` |

"Not now" lasts the page view, per kind.

### 8.1 Server: `api/app-release.js`

Reads `https://api.github.com/repos/<owner>/<repo>/releases?per_page=30`, keeps releases that
are **not draft, not pre-release, tagged `android-v<version>`, with an `.apk` whose `state` is
`uploaded`**, and answers the highest version:
`{ version, apk, size, sha256, page }` (`sha256` from GitHub's `digest`, `sha256:…`), or
`{ version: null }`. `Cache-Control: public, s-maxage=600, stale-while-revalidate=3600`, so
GitHub sees a request every ten minutes however many phones ask. `GITHUB_TOKEN` (optional)
raises GitHub's 60-an-hour limit. `?v=<version>` is ignored but busts the cache, for a
notification about a release published seconds ago.

Version comparison is number by number (`1.10.0` after `1.9.0`), identical in
`api/_lib/release.js`, `js/app-update.js` and `UpdateActivity.newer()`.

### 8.2 Page: `js/app-update.js`

In the app with `has("update")`: fetch `/api/app-release` (no-store) on load and on returning
to the page after an hour; if newer than `AppBridge.version()`, offer it in the bar. Never in a
browser.

### 8.3 Native: `UpdateActivity`

A small dialog-themed activity (`Theme.Material[.Light].Dialog.NoActionBar`, `values-night`
for dark) started three ways: the bar's Update (downloads at once), the Edge Tray's check
(`check: true`: looks, says "You have the newest version, X" or asks), and a tapped "new
version" notification (`version` given, so it reads past the cache).

Before installing, it checks:

1. The APK URL starts with `https://github.com/<owner>/<repo>/releases/download/`.
2. Its SHA-256 matches GitHub's digest (when there is one).
3. `getPackageArchiveInfo`: same package, **higher versionCode** than installed.
4. Android checks the signature itself: only the same key can update.

Then `PackageInstaller` session → commit with a **mutable** `PendingIntent` to the
non-exported `InstallStatus` receiver → on `STATUS_PENDING_USER_ACTION`, start the confirm
intent (allowed because the dialog is on screen).

`REQUEST_INSTALL_PACKAGES` and Android 8+'s per-app **Install unknown apps** setting: the first
update sends the user to `ACTION_MANAGE_UNKNOWN_APP_SOURCES`; on return (`onResume`) it carries
on. **Android 8–10 restart the app** when that setting is granted: the dialog has to come back
by itself (it does, as the activity is recreated with its intent).

Failure messages are sentences, not codes: conflict/incompatible → "uninstall, then install
from GitHub" (a differently signed copy, e.g. a debug build or a PWABuilder APK); storage →
"no room".

---

## 9. The Edge Tray in the app

The site's Edge Tray (`edge-tray-spec.md`) is unchanged; the app adds global actions to it.

- **Check for updates**: a circled down-arrow (`download` icon:
  `<circle cx="12" cy="12" r="9"/><path d="M12 7.5v8M8.5 12l3.5 3.5 3.5-3.5"/>`), label
  "Check for updates". It calls the service worker's `registration.update()` **and**
  `<App>.update({ check: true })`, so one button covers both kinds of update.
- **Other app-only actions** (a notifications bell when the site has none of its own, Receive
  nearby, …) follow the same pattern.

Rules that keep the tray intact:

- Created by script **only after `has()`**, inserted **before the theme button**
  (`themeBtn.before(button)`): global actions read alerts → app actions → theme.
- `className = "glass-btn"`, `type="button"`, `aria-label` and `title` set, icon via
  `hydrateIcons(button)`.
- **The stagger needs a line per child.** Every extra button needs its own
  `.tray-buttons > :nth-child(N) { --i: N-1; }`, or it pops in without the unroll animation.
  Add lines for the most buttons the app can ever show.
- **Short screens**: with app buttons the column can run past the bottom; the tray column
  must scroll (`max-height` + `overflow-y: auto`) rather than hide the last buttons (SG Bus
  Timings had to fix this).
- The tray's `inert` when collapsed covers added buttons automatically, as they're inside
  `#trayButtons`.
- Long-press labels: on touch, `title` doesn't show; the site's press-and-hold labels (if any)
  must be attached to added buttons too.

---

## 10. Notifications

### 10.1 Choose the shape

| Kind | Delivery | Server keeps |
|---|---|---|
| Personal (an alert for this device's choice) | The **FCM token** as the device's subscription, `{ fcm: token }`, stored like a Web Push subscription | The token, per device |
| Broadcast to opt-ins (news, morning summary, new version) | An **FCM topic**, `<id>-<name>`, joined with `FirebaseMessaging.subscribeToTopic` | Nothing |
| Per-object (an event's check-ins) | A topic named from a secret hash only the owner has | Nothing |

Topics are shared by **every app in the Firebase project**: always prefix with the app's id.

### 10.2 Page side

- `pushSupported()` in the app = `AppBridge.has("push")`.
- Permission through `PushNotifications.checkPermissions` / `requestPermissions` (`receive`:
  `granted`, `denied`, `prompt`). Android 13+ prompts once; after a refusal, only the app's
  notification settings can turn it on: offer an **Open Android's settings** button
  (`<App>.openSettings({ what: "notifications" })`).
- The token: listen for `PushNotifications` `registration` (`{ value }`) and
  `registrationError` **before** calling `register`, with a timeout. Re-send the subscription on
  every page load (the token can change).
- **Never call `PushNotifications.unregister`** to turn one feature off: it deletes the token
  and every topic with it. Tell the server to forget the device instead.
- Ask for permission only when the user turns something on, never on load.

### 10.3 Native side

- Channels in `Notifications.createChannels` (Android 8+): one per kind, each a switch in
  Android's settings. **A channel's importance and sound are fixed at creation**: changing them
  means a new channel id.
- `Notifications.allowed()` (`areNotificationsEnabled`) before posting anything locally.
- Tapped notifications open `MainActivity` with the push's `data` as extras; handle known
  `type`s in `onNewIntent`.

### 10.4 Server side: `api/_push/fcm.js`

FCM HTTP v1 with an OAuth token signed by `node:crypto` from `FIREBASE_SERVICE_ACCOUNT` (the
JSON key, raw or base64), cached until five minutes before expiry, retried once on 401.

- Every message carries `notification` (Android shows it while the app is in the background)
  **and** the same as `data` (strings only) for the page when the app is in front.
- `android.notification`: `channel_id`, `tag` (replaces the previous one), `icon:
  "ic_notification_icon"`. Personal alerts at `priority: "HIGH"`: they all show a notification,
  which is what FCM requires of high priority, and normal priority waits for a dozing phone to
  wake.
- Only `errorCode: "UNREGISTERED"` means the token is gone (treat as Web Push's 410 and drop
  the device). A plain 404 can mean the project in the key is wrong; dropping on it would drop
  every phone.
- Push to browsers (Web Push) and phones (FCM) from the same code path, by the subscription's
  shape. Accept `{ fcm }` in validation with `/^[A-Za-z0-9_:-]{100,400}$/`.

### 10.5 What shows, and the icon

- **The status bar's small icon is drawn from its alpha alone**: colour is ignored. A full
  square icon becomes a white square. Give it a clear silhouette with transparent space.
- Colour shows as the **large icon** beside the text: `setLargeIcon` on the app's own
  notifications. FCM notification messages can't set a large icon; some skins (Samsung,
  Xiaomi) show the app's icon there anyway.
- `default_notification_color` tints the small icon in the expanded header.

### 10.6 The "new version" push

GitHub webhook (Releases events, `application/json`, secret `GITHUB_WEBHOOK_SECRET`) →
`api/push/release.js`, a web-standard handler (`export async function POST(request)`) so the
HMAC is checked against the **raw body**. Only `action: "released"`, only `android-v*` with the
APK uploaded, never for a version older than the newest. Answers `ping` with
`{ ok: true, pong: true }`.

---

## 11. Permissions

The rule: **asked at the moment of use, for the feature in front of the user, never at
launch.** Each has a comment in the manifest and a row in `android/README.md`.

| Permission | When it's asked | Android quirks |
|---|---|---|
| `POST_NOTIFICATIONS` | Turning on a notification | 13+ only; refused twice → settings only |
| `ACCESS_COARSE_LOCATION` / `FINE` | The page's first geolocation use (Capacitor asks), or a native feature's button | 12+ lets the user grant only approximate: handle coarse |
| `ACCESS_BACKGROUND_LOCATION` | After foreground location is granted, separately | 10: in the same dialog ("Allow all the time"); **11+: a settings page**, the user must pick "Allow all the time"; refused → answer `needs-background` and offer settings. Google Play needs a declaration and video |
| `REQUEST_INSTALL_PACKAGES` | The first update | Per-app "Install unknown apps" setting; **not allowed on Google Play** |
| `NFC`, `INTERNET`, `ACCESS_WIFI_STATE`, `VIBRATE` | Never (install-time) | |
| `BLUETOOTH_SCAN`/`CONNECT`/`ADVERTISE`, `NEARBY_WIFI_DEVICES` | The feature's button | One "Nearby devices" prompt (12+ / 13+); before 12, location stands in and must be **switched on** |
| `CAMERA` | The page's `getUserMedia` | |
| `READ_CALENDAR` | Only when picking "use this phone's calendar" | |
| `SCHEDULE_EXACT_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `SYSTEM_ALERT_WINDOW` | Avoid | Play scrutinises them; WorkManager, FCM high priority and widgets cover most needs |

Declaring `uses-feature … required="false"` for hardware features (location, NFC, Bluetooth)
keeps the app installable on phones without them.

Treat refusals as normal: the page explains in a sentence and offers Android's settings, and
the feature stays off, never half on.

---

## 12. Running without the app open

### 12.1 One background job

A single `Worker` (`ReadingsWorker` in SG PSI) on `enqueueUniquePeriodicWork(…, KEEP, …)` with
a `CONNECTED` network constraint, refreshing everything shown outside the app.

- 15 minutes is Android's minimum; pick what the data needs (SG PSI: 30 minutes for hourly
  readings).
- It runs **only while something needs it** (`needed()`: a widget exists, the tile is added, a
  feature is on), and cancels itself otherwise.
- WorkManager survives reboots and updates by itself: **no `RECEIVE_BOOT_COMPLETED`**, no exact
  alarms, no battery-optimisation exemption.
- Keep the latest data in `SharedPreferences` (one small JSON) so widgets and tiles draw
  instantly. **Also accept data from the page** whenever it loads it (`<App>.readings({ now })`),
  stamped with the server's time (`fetchedAt`), and never let older data (an offline copy)
  overwrite newer.

### 12.2 Home screen widgets

- `AppWidgetProvider` + `RemoteViews` layout + `appwidget-provider` XML with
  `updatePeriodMillis="0"` (the worker refreshes).
- `RemoteViews` only supports a fixed set of views (LinearLayout, FrameLayout, TextView,
  ImageView, ImageButton, ListView…) and methods marked remotable: `setColorFilter`,
  `setBackgroundResource`, `setTextColor`, `setContentDescription`. No custom views, no
  `ConstraintLayout`, no custom fonts.
- Colours from `values/` and `values-night/` (the widget follows the phone's mode, not the
  site's).
- Read `OPTION_APPWIDGET_MIN_HEIGHT` in `onAppWidgetOptionsChanged` to drop rows that don't fit.
- A refresh button: an explicit broadcast to the provider, draw "Refreshing…" at once, fetch
  with `goAsync()` on an executor.
- `targetCellWidth/Height` and `previewLayout` are Android 12+; keep `minWidth/Height` and
  `previewImage` for older.

### 12.3 Quick Settings tile

- `TileService` with `BIND_QUICK_SETTINGS_TILE`. `onStartListening` runs every time the shade
  opens: draw from stored data, fetch in the background if stale, redraw if still listening.
- `setSubtitle` is Android 10+; before it, put everything in the label.
- `STATE_ACTIVE` reads as "on": use it for meaning (SG PSI lights it from Unhealthy).
- Tile icons are tinted single-colour vectors.
- `startActivityAndCollapse(PendingIntent)` on Android 14+, the `Intent` overload before;
  `unlockAndRun` when the phone is locked.
- Track `onTileAdded`/`onTileRemoved` so the worker knows it's needed.

### 12.4 A launcher icon that changes

Android has no API for it. The workaround is **activity aliases**: `MainActivity` loses its
`LAUNCHER` filter; N `<activity-alias>` entries (after the activity, `targetActivity`
`.MainActivity`, each with its own `icon`/`roundIcon`, only the default `enabled="true"`) carry
it; switch with `setComponentEnabledSetting(…, DONT_KILL_APP)`, enabling the new one **before**
disabling the old.

What breaks, and must be accepted or worked around:

- **Pixel's and Samsung's launchers remove the icon from the home screen** when its alias is
  disabled; it stays in the app drawer. Make it a setting, and offer a 1×1 "icon widget" that
  shows the same art and never moves.
- Disabling the alias the open task came from can **finish the app's screen**: switch only
  while the app isn't in front (a static `inFront` flag set in `onStart`/`onStop`; apply
  pending changes in `onStop`).
- **Never rename or remove an alias** in a later version: a phone with it enabled is left with
  no launcher entry.
- `getLaunchIntentForPackage` (used by FCM for taps) resolves whichever alias is enabled.

---

## 13. Links

- **Verified https links**: `main-site/.well-known/assetlinks.json` with the package and the
  key's SHA-256 (colon-separated, upper case, as keytool prints it), served as JSON at exactly
  that path (check Vercel's `cleanUrls` doesn't redirect it). The manifest filter has
  `android:autoVerify="true"`. Check on a phone with
  `adb shell pm get-app-links org.uwuapps.<id>` ("verified"). Until it's deployed with the real
  key, links open in the browser.
- **`uwu://<id>/…`**: the scheme is shared by every UwU app; each claims only its host. Map
  paths to site pages in `MainActivity.pageFor`, accepting only known views.
- A hash-only change (`/#map`) loaded into the open page fires `hashchange` rather than
  reloading: the site's router must handle `hashchange`.
- Links to other hosts open in the phone's browser (Capacitor's default). `mailto:` and `tel:`
  open their apps.

---

## 14. Icons and splash

| Asset | Size | Notes |
|---|---|---|
| Legacy launcher `mipmap-*/ic_launcher.png`, `_round.png` | 48dp: 48, 72, 96, 144, 192 px | Android 7.x only; full-square art is fine (lint warns) |
| Adaptive foreground `mipmap-*/ic_launcher_foreground.png` | 108dp: 108, 162, 216, 324, 432 px | Launchers show the middle 72dp; a round mask keeps a 66dp circle |
| `mipmap-anydpi-v26/ic_launcher.xml` (+ `_round`) | | `<background>` colour + `<foreground>` |
| Splash `drawable-nodpi/splash_icon.png` | 1152 px | §6.4 |
| Notification `drawable-*/ic_notification_icon.png` (or a vector) | 24dp: 24–96 px | Alpha only (§10.5) |
| Tile icons | 24dp vectors, white | Tinted |

- **Full-bleed art** (a scene with its own background) must be **widened** for the adaptive
  foreground: render the art at 72/108 of the layer and extend its background, ground and water
  outward to fill the rest (e.g. a `viewBox="-128 -128 768 768"` for 512-unit art, with the
  background and edge-touching shapes stretched). Otherwise parallax and masks show a hard edge.
- Check the art's important parts sit inside the round mask: within ~65% of the half-width
  from the centre for a circle.
- Logo-on-flat-colour art can be scaled to ~62% of the layer on the same colour instead.
- Generate every size from the source SVG (resvg renders SVG to PNG in Node); never upscale a
  small PNG.
- Resource names: lower case, digits and underscores only (`ic_launcher_very_unhealthy`, not
  `very-unhealthy`).
- The website's icons (`manifest.json` 192/512 and a large one for the install splash,
  `favicon.ico` with 16, 32, 48 and 256, apple-touch-icon) come from the same source.

---

## 15. Things that break

The failures met building the three apps, by where they show up.

### Build

- **`--` inside an XML comment** fails resource merging ("The string "--" is not permitted
  within comments"). CSS custom property names in comments (`--band-1`) are the usual culprit.
- **Apostrophes in `strings.xml`** must be `\'`; `%` must be `%%` or a placeholder; a stray
  backslash fails with "Invalid unicode escape". Scripts that write resources through another
  language's string escaping lose the backslash.
- Resource names with hyphens or capitals fail.
- Two resources with the same name and qualifier (a vector `drawable/x.xml` and
  `drawable-mdpi/x.png` is allowed; two in one folder isn't). Delete the old one when changing
  format.
- `google-services.json` downloaded **before** the app was added to the Firebase project:
  "No matching client found for package name". Download it again.
- A library compiled with a newer Kotlin than the build reads (Nearby 19.5): hold the version.
- `npx cap sync` not run after changing plugins or `capacitor.config.json`: the old config or
  plugin list is used.
- Editing a generated file (`capacitor.settings.gradle`, `capacitor.build.gradle`,
  `assets/capacitor.config.json`): overwritten on the next sync.
- `minifyEnabled true` without keep rules: plugin methods vanish at runtime, not at build.

### Look

- `env(safe-area-inset-*)` used directly: 0 in the WebView, content under the gesture bar.
- Status bar shown and the page not padded: the header sits under the clock.
- Status bar icons not synced to the page's mode: invisible icons.
- No `values-night` colours: a white splash or widget in dark mode.
- The launcher foreground used as the splash icon: a blurry splash.
- Unwidened full-bleed art in the adaptive icon: edges and cropped corners.
- An Edge Tray button added without its `:nth-child` stagger line: no unroll animation.
- App-only UI not `hidden` in the markup: flashes in the browser, or shows in old APKs.
- Hover styles without `@media (hover: hover)`: stuck highlights after taps.
- No `color-scheme`: the WebView may darken the page itself.

### Function

- A feature gated on `AppBridge.native` instead of `has()`: breaks on older APKs.
- Web Push, `navigator.share`, Wake Lock, blob downloads, speech recognition used without the
  app's alternative: buttons that do nothing (§7).
- Location declared nowhere in the manifest: the page's geolocation silently fails.
- `PushNotifications.unregister()` to turn one alert off: kills every topic.
- Listening for `registration` after calling `register`: the token is missed.
- A push channel's importance changed in code: no effect on installed phones.
- Background location requested before foreground location: Android ignores it.
- Work done on the main thread in a plugin, widget or tile: ANRs. Location and network on an
  executor.
- A `PluginCall` resolved twice, or never: the page's promise errors or hangs.
- Launcher alias switched while the app is open: the screen closes.
- A widget's `PendingIntent` without `FLAG_IMMUTABLE` (Android 12+ crashes); the installer's
  status intent **must** be mutable.
- `startActivityAndCollapse(Intent)` on Android 14+: throws; use the `PendingIntent` overload.
- Separate storage from Chrome: users "lose" local data moving to the app.
- `/api/app-release` not cached: GitHub's rate limit blocks the update check for everyone.

### Release

- `versionCode` not raised: "App not installed" / no update offered.
- Debug-signed or differently signed copy installed: "App not installed"; uninstall first.
- Tag without `android-v`, a draft, a pre-release, or the APK still uploading: no update bar.
- Repository private: downloads 404 for everyone but you.
- `assetlinks.json` not deployed after the first build: links open in the browser.
- Keystore lost: no updates ever again.
- Deploying the site after the APK: the app's new native calls hit an old page, or the page
  calls methods the old APK lacks. Site first, with `has()` gates, then the APK.

---

## 16. Checklists

### Before the first build

- [ ] Package, host, user agent tag decided (§0); repository public
- [ ] `capacitor.config.json`, `www/offline.html` in the site's colours
- [ ] `app/build.gradle` versions, signing block, conditional Google services
- [ ] `MainActivity`: plugin registered before `super.onCreate`, cutout, back, hidden status
      bar, `onNewIntent`
- [ ] Manifest: permissions each with a comment, verified link filter, `uwu://<id>`
- [ ] Icons in every density, widened adaptive foreground, splash image, notification icon
- [ ] `values-night/` for every colour
- [ ] `.gitignore` at both levels, checked with `git check-ignore`
- [ ] `js/app-bridge.js` loaded first; safe-area tokens; `data-statusbar`
- [ ] Every app-only feature behind `has()`, hidden in the browser
- [ ] `api/app-release.js`, `js/app-update.js`, the Edge Tray update button with its stagger
      line
- [ ] Site deployed with all of the above

### After the first build

- [ ] Keystore and `keystore.properties` backed up
- [ ] `assetlinks.json` committed and deployed; `pm get-app-links` says verified
- [ ] Package registered for developer verification
- [ ] Firebase: app added, `google-services.json` in place, service account key in Vercel,
      webhook added (`FIREBASE-SETUP.md`)

### On a phone, every release

- [ ] Launches to the site with no white flash, in light and dark phone modes
- [ ] No status bar; nothing under the gesture bar; modals clear of both
- [ ] Status bar icons (swipe down) match the page's mode after switching theme
- [ ] Back goes back through the page, then backgrounds the app
- [ ] Airplane mode on first launch: the offline page; after one visit: the site offline
- [ ] Edge Tray: app buttons present, unroll animation, collapse and expand
- [ ] "Check for updates" says newest; with a newer release, the bar offers it and it installs
- [ ] Each notification arrives with the app closed and open, and its tap does the right thing
- [ ] Each permission: allow, refuse, and refuse permanently → the page says what to do
- [ ] Widgets and tile draw, refresh, follow dark mode, open the app
- [ ] A verified link and a `uwu://<id>/` link open the right page in the app
- [ ] The same build of the site in Chrome: no app-only UI, nothing changed

### Publishing

- [ ] `versionCode` raised; APK built and committed with its code; site deployed first
- [ ] Release tagged `android-v<version>`, APK attached before publishing, set as latest
- [ ] Release notes in the house style (§4.5), listing only what works in this build
- [ ] Announcement posted from its code block, ending with the `releases/latest` link
- [ ] Patch notes updated, if the project keeps them
