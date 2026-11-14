# Android app in Flutter: spec for a native app at full parity with its website

An Android app whose every screen is drawn natively in Dart with [Flutter](https://flutter.dev),
with the same features, words, stored data and server API as the product's website, plus native
extras only a phone can do. It's shared as a signed APK through GitHub Releases (and optionally as
an App Bundle on Google Play), and updates itself.

This replaces wrapping the site in a WebView. The website stays the specification: each feature
is ported from the site's code with its storage keys, translation keys and API calls unchanged, so
the two never drift and a WebView app's data comes across as it is.

The same Flutter project builds the desktop apps (`flutter-desktop-app-spec.md`); this document
covers what's shared and what's Android's own.

---

## 0. Decide first

| Decision | Example | Why it matters |
|---|---|---|
| Application id | `org.example.app` | Permanent. A different id is a different app; the signing key, verified links, push and store listing hang on it |
| Signing key | `android.keystore` + `keystore.properties`, never in git | An APK signed with another key can't update an installed one. Back it up |
| The site's host | `app.example.org` | The API's base, verified links, the update check |
| Version | `2.5.0+42` in `pubspec.yaml` | The name, and after `+` the `versionCode`, which only goes up |
| Native extras | notifications, widgets, background work | Each costs permissions and upkeep. Add one only where Dart and a plugin from pub.dev can't (§6) |
| Push | Firebase Cloud Messaging, optional | The app builds and works without its config file |
| Distribution | GitHub Releases APK, optionally Google Play | Play forbids self-updating and some permissions (§10) |

The rule that keeps it maintainable: **one source of truth per feature.** Logic ported from the
site keeps the site's names, keys and words; native code only adds capabilities, behind one
bridge (§4).

---

## 1. The project

```text
<app>/                       one Flutter project for every platform
  pubspec.yaml               version, packages, assets, fonts
  lib/
    main.dart                start-up: storage, bridge, words, theme, data, then runApp
    app/                     the shell: main screen, navigation, links, the app's chrome
    api/                     the HTTP client for the site's /api/*, and the offline state
    data/                    storage, models and pure logic ported from the site's JS
    features/<feature>/      one folder per feature: its pages, sheets and state
    i18n/                    loading the site's translations
    theme/                   the theme: the product's own look and Material You
    native/                  the bridge to platform code (§4)
    widgets/                 shared widgets
  assets/i18n/               the site's translation files, copied by a tool (§3)
  assets/i18n_app/           the few words only the app says
  android/                   the Gradle project: app/ (plugins in Java or Kotlin), extra modules
  test/                      unit tests, parity tests, the guide's screenshots (§12)
  tool/                      maintenance scripts (syncing words, generating expectations)
  build-apk.ps1 / .sh        the signed build (§9)
```

- **Feature registry.** Features register what they add to shared places (a top bar, a menu, a
  page) at start-up, so the shell doesn't import every feature.
- **No code generation needed to build.** Anything generated is committed or produced by a tool
  that runs on demand, so `flutter build` alone works on a fresh checkout.

---

## 2. Storage: the site's keys, as they were

- One key-value store (`shared_preferences`) wrapped in a small class with the site's
  `localStorage` semantics: every value a string, JSON where the site's was JSON, the same key
  names, a change stream per key. A prefix inside the platform store keeps the app's keys apart
  from plugins'.
- An in-memory variant for tests and screenshots, so nothing touches the device.
- **Migration from a WebView app**: on the first launch after updating, a native call reads the
  old WebView's `localStorage` (the WebView's own storage API, from the native side) and copies
  every key the site owns, never over a value the app has set since. Done once, marked by a key,
  and the old copy is left alone. A count is shown once ("Your favourites and settings are here
  from before").

---

## 3. Words

- The site's translation files (one JSON per language) are copied into `assets/i18n/` by a tool,
  and a test fails if they differ from the site's, so a new site string can't be forgotten.
- `tr('key', 'English fallback', {params})`, the same keys and `{placeholders}` as the site.
- The app's own few strings live in `assets/i18n_app/`, in every language.
- The language follows the site's rules (automatic from the device, or chosen), and, on Android
  13+, the per-app language setting, two-way: chosen in either, the other follows.
- A language change redraws every screen in the stack, not just the top one.

---

## 4. The native bridge

One `MethodChannel` carries every call to platform code, in one shape:

```text
Dart                                         Android
Native.call('Plugin', 'method', {options})   → Bridge → Plugin.method(PluginCall) → resolve(JSON)
Native.on('Plugin', 'event', (data) {...})   ← Bridge ← plugin.notifyListeners('event', JSON)
Native.has('feature')                        ← info().features, listed by the app plugin
```

- Options and answers are JSON strings, so the native side needs no codec of its own and plugins
  written for a WebView bridge keep working unchanged.
- Errors arrive as a `NativeError` with the plugin's message, a code (`permission`, `cancelled`,
  `unavailable`…) and data.
- `Native.has()` is the only switch features use to show native-only buttons, so a build or device
  without a capability simply doesn't show it.
- **A host interface.** The bridge can be backed by a Dart object instead of the channel. Tests and
  screenshots install a fake (features list and canned answers, plus fake events); the desktop
  apps install their own host (`flutter-desktop-app-spec.md`). Without any, the bridge reports
  itself unavailable and every call fails fast, so features fall back to their plain path.
- Permissions go through one helper: check, ask with the system prompt, and once refused for good
  open the app's settings page instead.

---

## 5. The shell

- **Pages** in an `IndexedStack`, each built once and kept, so switching back keeps its place.
- **Navigation**: a global navigator key and messenger key; `AppNav.open(route, args)` and
  `AppNav.showPage(id)` from anywhere; a snack bar helper.
- **Links**: the site's own https links (verified with `assetlinks.json` so Android opens them in
  the app), a custom scheme, launcher shortcuts and share intents all go through one
  `Links.open(url)` that maps the site's addresses to pages, so any site link opens the right
  screen.
- **Back**: closes what's open, then goes back through pages to home, then "Press back again to
  exit", and the second press sends the app to the background rather than killing it (so work
  running in the background carries on).
- **Offline**: one notifier says the network is gone; pages that need it give way, a bar says
  why, and it comes back on reconnect.
- **Text scale** clamped (2×) so layouts hold, following the device's font size.
- A `RepaintBoundary` round the whole app for in-app screenshots (bug reports).

---

## 6. Native extras

Each extra is a plugin class in `android/app/src/main/java/…` registered with the bridge, and a
feature flag in `info().features`. Common ones:

| Extra | Android pieces |
|---|---|
| Push notifications | Firebase Messaging service, notification channels, a token sent to the server with the person's choices |
| Work with the screen off | a foreground service of the right type with its ongoing notification; WorkManager for periodic jobs; exact alarms for timed ones |
| Home screen widget | `AppWidgetProvider`, a `RemoteViews` layout, a config activity, a store, a refresh worker; a preview layout for the picker |
| Quick Settings tiles, launcher shortcuts | `TileService`, dynamic `ShortcutManager` shortcuts |
| Picture-in-picture | the activity's PiP params, actions as broadcast intents, the Dart side drawing a small layout |
| Share sheet, opening other apps | `Intent.ACTION_SEND`, package-targeted intents |
| NFC, camera, speech | reader mode, ML Kit, `RecognizerIntent` (no microphone permission) |
| Material You | the system's tonal palettes (`dynamic_color`), read on every resume |
| Restart survival | a boot receiver re-arming alarms and jobs, also after an update |

Rules:

- **Every extra degrades.** Without the feature flag the plain path shows (the site's own
  behaviour). Tests run with no native side at all.
- **Ask late.** A permission is asked the first time the feature that needs it is used, never at
  launch.
- **Keep reflection names.** Release builds go through R8; one ProGuard rule keeps every plugin
  class and its annotated methods, so a new plugin needs no new rule.

---

## 7. Theme

- Two looks: the product's own (its brand colours, font, light/dark/time-based) and Material You
  (the device's palette and fonts), switchable, Material You on by default on Android 12+.
- `ThemeData` built from one place for light and dark, with high contrast, and the theme mode from
  the site's setting.
- Colours from the product's palette are tokens, never literals in widgets.

---

## 8. Updating itself (GitHub Releases)

- The site's server reads the newest release (tag pattern `<platform>-v<version>`, skipping
  drafts, pre-releases, and releases whose APK hasn't finished uploading) and answers the app's
  check, cached for minutes.
- The app shows an update bar, and a page with the release notes as a changelog and a progress
  bar; it downloads the APK, verifies GitHub's SHA-256, and hands it to the system installer
  (`REQUEST_INSTALL_PACKAGES`).
- A webhook from GitHub on publish pushes "x.y.z is out" to a push topic the person opted into.
- Device quirks that block sideloaded updates (an OEM's auto blocker, for example) are detected
  where possible and explained with a button to the right settings page.

---

## 9. Building

- `flutter build apk --release --target-platform android-arm,android-arm64` gives one APK for
  every ARM phone (the updater fetches one file). Other modules (a watch app) build with Gradle.
- The build script finds a JDK (21+) and the Android SDK, reads the version from `pubspec.yaml`,
  builds, verifies each signature with `apksigner`, and copies the files to
  `release/<version>/<app>-<version>.apk`. The R8 mapping file is kept beside them, never
  uploaded.
- Signing config reads `keystore.properties`; both files are git-ignored. The build refuses to
  run without them.
- `versionCode` only goes up; every platform shares the version name.

---

## 10. A store build

A flavour or manifest overlay for the store build removes what the store forbids or reserves:
the self-updater and `REQUEST_INSTALL_PACKAGES`, and permissions only some app categories may
hold (`USE_EXACT_ALARM`, background location, activity recognition, battery-optimisation
exemptions). A Dart `--dart-define` tells the app it's that build, so it hides the matching
buttons, and the build script checks the bundle's merged manifest really lacks them. If the store
re-signs the app, its certificate's SHA-256 is added to `assetlinks.json`.

---

## 11. Parity with the site

- A porting table (`PORTING.md`) lists every part of the site, its Dart, and its status.
- Logic with a right answer (route finding, schedules, calendars, rewards, encoders) is tested
  against the site's own outputs: a tool runs the site's JS on fixtures and writes the expected
  results, and Dart tests compare.
- A web-parity test checks every storage key and translation key the site uses exists in the app.
- The site's guide is the user-facing spec: a feature isn't done until it behaves as its guide
  page says.

---

## 12. Tests and screenshots

- Unit and widget tests run with the in-memory store, a fake bridge and recorded API answers
  (`test/fixtures/`), so they're offline and deterministic.
- **The guide's screenshots are rendered by Flutter's test renderer** at 3× from fixed data, a
  frozen clock and the product's fonts loaded into the test: `flutter test test/shots/` writes
  PNGs into the guide's folder, and `SHOTS=a,b` picks some. They come out identical whenever
  they're taken.
- Golden-style checks for layouts that broke before (landscape sheets, insets, long words).

---

## 13. Releasing

1. Raise `version:` (name and code); every platform shares the name.
2. Build the APK(s) with the script; they land in `release/<version>/`.
3. Commit and push; create the release `<platform>-v<version>` on GitHub with notes; attach the
   APKs **before** publishing (the webhook fires on publish); mark it latest.
4. CI builds and attaches the other platforms' installers on publish.

---

## 14. Checklist

- [ ] One Flutter project, features in folders, a registry for shared slots
- [ ] Storage with the site's keys; migration from the WebView app, once
- [ ] Translations synced from the site and tested; per-app language two-way
- [ ] One bridge over a method channel, with a host interface for tests and desktop
- [ ] Shell: kept pages, links from every source, Back, offline bar, text scale
- [ ] Each native extra behind a feature flag, degrading to the site's behaviour
- [ ] Theme: the product's look and Material You
- [ ] Self-update from GitHub Releases, verified; release push
- [ ] Signed build script, R8 rules, a store build without forbidden parts
- [ ] Parity table, cross-checked logic, web-parity test
- [ ] Deterministic guide screenshots from the test renderer
