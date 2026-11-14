# uwuFix for Android, Windows, macOS and Linux

The uwuFix apps, from 1.1.0: one Flutter project for the phone and the computer. Before 1.1.0 the
Android app was the website in a WebView (Capacitor, in git history under `android/`); now each
screen is the app's own, built to `docs/flutter-android-app-spec.md`,
`docs/flutter-desktop-app-spec.md` and `docs/desktop-features-spec.md`.

The app does what the site does, in the same words, and keeps its data under the same keys and in
the same shapes as the site's `localStorage`, so the 1.0.x app's history and settings come across
by themselves on the first open (`lib/data/migrate.dart`).

| | Android (`org.uwuapps.fixup`) | Windows, macOS, Linux |
|---|---|---|
| **Look** | Material You by default (colours from the wallpaper, the phone's font), or the UwU Apps look in **Look** | The UwU Apps look by default, with the computer's accent colour if wanted, or Material You |
| **Getting a link in** | Share to uwuFix, **Fix link** in the text menu (with Replace in place), widgets, `uwu://fix/` links, the site's own links | Ctrl+K command bar, the tray's **Fix copied link**, Fix a link widgets, `uwu://fix/` links, Jump List (Windows) and Dock menu (macOS) |
| **Updates** | From GitHub Releases, with its own updates page (every version's notes, wavy progress bars). The Google Play build has none: Play updates it | From GitHub Releases (`latest*.yml`, as Electron's updater reads), restarting into the new version |
| **Notifications** | Opt-in, by Firebase Cloud Messaging: new versions and news (`FIREBASE-SETUP.md`) | A notification when a new version is out |
| **Everywhere** | Share history between devices (STUN only, host approves), page tours, Report a bug with Screenshot a page | the same |

What the desktop apps leave out, as it doesn't fit a link cleaner: a map, location, alerts
polling, a tray countdown, the Electron-specific parts, and an apt repository.

## The project

```text
flutter/
  lib/
    main.dart                 starts the phone's app, or the desktop's (desktop/desktop.dart)
    app/                      the root, navigation, the phone's shell and Edge Tray, links
    features/                 home (the cleaner), history, sync (Share history), look, tour,
                              update, notify, bug (Report a bug)
    data/                     linkfix.dart (the site's cleaner, the same results), history,
                              store (the site's keys), migrate (from 1.0.x)
    sync/                     PeerJS's wire protocol in Dart, for Share history with the site
    desktop/                  window, title bar, tray, updater, widgets, screenshots, welcome
    native/native_bridge.dart the channel to Android's Java, and the desktop's answers
    theme/                    Material You and the UwU Apps look
  android/                    the Gradle project; Java plugins in app/src/main/java/org/uwuapps/fixup/
  windows/ macos/ linux/      the desktop runners
  installers/                 NSIS and WiX (Windows), dmg (macOS), deb, rpm, AppImage (Linux)
  test/                       the cleaner and history against the site's, the screens, store shots
  tool/                       makes the test fixtures from the site, the icons, the store assets
  build-apk.ps1               builds the APK and the AAB into release/<version>/
  FIREBASE-SETUP.md           setting up notifications
```

The cleaner (`lib/data/linkfix.dart`) and history merging (`lib/data/history.dart`) are ports of the
site's cleaner in `main-site/script.js` and of `main-site/js/history-merge.js`. Their tests run the site's own code
(`tool/*_expected.mjs`) and check the app gets the same answers, so after a change to the site's
cleaner, port it and run `flutter test`.

## Build the Android app

From the project root, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1        # the APK, for GitHub
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab   # the AAB, for Google Play
```

Each ends with `Done: ...\release\<version>\uwufix-<version>.apk` (or `.aab`), with `<version>`
taken from `version:` in `pubspec.yaml`. For a new version, raise both parts of it first:
`1.1.0+3` is versionName `1.1.0` and versionCode `3`, and phones only update to a higher code.

Both builds are shrunk and obfuscated as Google Play measures it: R8 for the Java and its
libraries with unused resources dropped, Dart's `--obfuscate` with its symbols split off, and the
native libraries' symbols stripped. What reads a crash is kept beside them, and not put on the
GitHub release: `uwufix-<version>-mapping.txt` (R8) and `uwufix-<version>-symbols.zip` (Dart). The
AAB carries both inside it for Play.

The AAB is the Play build: no updater, no `REQUEST_INSTALL_PACKAGES`. Neither build asks for the
advertising ID, and Firebase Analytics is off. The script checks each of these, and the signing
key, before copying a build out, and lists any file over 100 MB, GitHub's limit, in `.gitignore`.

It needs Flutter on the PATH, a JDK 21 or later and the Android SDK (`JAVA_HOME` and
`ANDROID_HOME`, or the newest JDK under Program Files and `%LOCALAPPDATA%\Android\Sdk`).

### The key

`flutter\android.keystore` and `flutter\keystore.properties` sign every version, and are kept out
of git. **Keep them backed up somewhere safe and private.** An APK signed with another key can't
update the one installed, so losing them means everyone uninstalls and reinstalls. The script
refuses to build without them, and refuses a build signed with any key but the one
`main-site/.well-known/assetlinks.json` names.

### Google's developer verification

From 30 September 2026, Android in Singapore checks that apps come from a verified developer. To
keep Play Protect from warning about the APK, register `org.uwuapps.fixup` with the SHA-256
fingerprint in `assetlinks.json` on the
[Android Developer Console](https://developer.android.com/developer-verification/guides/android-developer-console).
An app on Google Play is verified through Play.

## Build the desktop apps

GitHub Actions builds them (`.github/workflows/build-desktop.yml`) when an `android-v*` release is
published, and attaches the installers and `latest*.yml` to it. To build one by hand on its own
system:

```powershell
flutter build windows --release    # or macos, or linux
```

## Test

```powershell
flutter analyze
flutter test
```

`flutter test` checks the cleaner and history merging against the site's, and the screens on a
small phone and a big screen: a tour stays on screen and scrolls to what it lights, Look, History,
Report a bug. The store screenshots are made the same way:

```powershell
$env:SHOTS = 'all'; flutter test test/shots/; node tool/store_assets.mjs
```

which writes the Play listing's pictures to `docs/phone-assets/`, `docs/tablet-assets/`,
`docs/desktop-assets/` and `docs/feature-graphic.png` (`GOOGLE-PLAY.md`).

## Changing it

- **Something new the app asks Android for**: a method in `FixupPlugin.java`, called with
  `Native.call('Fixup', 'method', {...})`. Add a word to `info`'s `features` so the Dart side can
  tell builds and devices with it from those without (`Native.has`). On the desktop,
  `lib/desktop/host.dart` answers instead.
- **Permissions, activities, links**: `android/app/src/main/AndroidManifest.xml` (and
  `android/app/src/play/AndroidManifest.xml` for what the Play build takes out).
- **A new page**: its id in `AppNav.pages` (`lib/app/nav.dart`), `pageFor` in
  `lib/app/shell.dart`, the desktop's rail in `lib/desktop/chrome.dart`, and its tour in
  `lib/features/tour/tour.dart`.
