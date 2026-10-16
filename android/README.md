# uwuFix for Android

The Android app, `org.uwuapps.fixup`: the web app at fixup.uwuapps.org in
[Capacitor](https://capacitorjs.com)'s WebView (`capacitor.config.json`, `server.url`). The
site's own updates reach it at once, so the app only needs building again for its native parts.
Those are the things a web page can't do, which the page reaches through Capacitor's bridge
(`main-site/js/app-bridge.js`).

It's shared as an APK file through GitHub Releases (see `release/README.md`), and updates
itself from there.

## What it adds to the site

| Feature | Native side (`native/app/src/main/java/org/uwuapps/fixup/`) | Site side (`main-site/`) |
|---|---|---|
| **Share to uwuFix**: uwuFix in Android's share sheet, and in its Direct Share row above the app list, for any shared link. A quick screen opens over the app you were in with the link already cleaned; Back returns you there | `FixActivity` (`ACTION_SEND`), `DirectShare`, `res/xml/shortcuts.xml` | `script.js` (`?text=`) |
| **Fix link in the text menu**: highlight a link anywhere and pick **Fix link** from the menu that pops up over it. The same quick screen opens. In a box you can type in, **Replace the highlighted link** puts the fixed link back in its place | `FixActivity` (`ACTION_PROCESS_TEXT`), `FixupPlugin.finish` | `script.js` (`#replaceBtn`, `replaceLinkInText`) |
| **Updating itself** from GitHub Releases: a bar at the top of the page when a new version is out, and the Edge Tray's download button, "Check for app updates". Both use Android's own installer | `UpdateActivity` | `js/app-update.js`, `api/app-release.js` |
| **Notifications**, opt-in from the bell in the Edge Tray: new versions of the app (pushed the moment a release is published), and news you send from the Firebase console | `FixupPlugin.setTopic` (FCM topics), `Notifications`, Capacitor's PushNotifications | `js/app-notify.js`, `api/push/release.js`, `api/_push/fcm.js` |
| **Share sheet** for the Share button (the WebView has no `navigator.share`) | `FixupPlugin.share` | `js/app-bridge.js` |
| **Paste** from the clipboard (the WebView can't read it for a page) | `FixupPlugin.paste` | `script.js` (`pasteFromClipboard`) |
| **Open** a fixed link in whichever app takes it (the browser, or X for fixupx.com) | `FixupPlugin.open` | `script.js` (`#openBtn`) |
| **The site's own links** (`https://fixup.uwuapps.org/...`, verified by `.well-known/assetlinks.json`) and `uwu://fixup/` links, such as `uwu://fixup/?url=https://x.com/...` | `MainActivity` | `script.js` (`?url=`) |
| **Status bar** icons that follow the page's light or dark mode, not the phone's | Capacitor's SystemBars | `js/app-bridge.js` |

The website and PWA lose nothing: everything a browser can do stays as it was, and these only
switch on when the page is running in the app. Notifications and the update bar exist only in
the app.

Things the app deliberately doesn't do: it doesn't register as a handler for every web link (it
would show up as a "browser" in Android's default-app settings), and it doesn't watch the
clipboard in the background (Android 10 and later forbid it).

### Permissions

| Permission | Asked | For |
|---|---|---|
| Notifications (`POST_NOTIFICATIONS`) | Only when you turn on a switch under the bell in the Edge Tray (Android 13 and later) | New versions, news |
| Install unknown apps (`REQUEST_INSTALL_PACKAGES`) | The first update | `UpdateActivity` |
| Internet | Not asked: Android grants it | The site itself |

If the app ever goes on Google Play, that build has to drop `UpdateActivity` and
`REQUEST_INSTALL_PACKAGES`, since Play updates apps itself.

## The project

```text
android/
  package.json, package-lock.json   Capacitor and its push plugin
  capacitor.config.json             the site's address, and where the native project is
  www/offline.html                  shown when the site can't load at all (first launch offline)
  native/                           the Android Studio / Gradle project
  build-apk.ps1                     builds the signed APK into release/<version>/
  FIREBASE-SETUP.md                 setting up notifications
```

`npx cap sync android`, which the build script runs, copies `www/` and the config into
`native/` and links the plugins from `node_modules`. What it writes is kept out of git.

## Build the APK

From the project root, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
```

That one command:

1. On the very first run, makes the signing key (`android.keystore` and `keystore.properties`)
   and writes its fingerprint into `main-site/.well-known/assetlinks.json`.
2. Installs the npm packages if they're missing, and runs `npx cap sync android`.
3. Builds the release APK with Gradle, signed with that key.
4. Checks the signature against the fingerprint in `assetlinks.json`.
5. Copies the result to `release/<version>/uwufix-<version>.apk`, with `<version>` taken from
   `versionName` in `native/app/build.gradle`.

(`npm run build` from inside `android/` runs the same script.)

It needs a JDK 21 or later (it finds the newest under Program Files, or `JAVA_HOME`) and the
Android SDK (`ANDROID_HOME`, the one Bubblewrap left in `~/.bubblewrap`, or Android Studio's in
`%LOCALAPPDATA%\Android\Sdk`). Gradle fetches any SDK platform it's missing.

**For a new version**, raise both of these in `native/app/build.gradle` first:

```groovy
versionCode 2          // a whole number, one higher each release: phones only update to a higher one
versionName "1.0.1"    // what people see, and the release folder's name
```

If `release/<version>/` already has an APK, the script warns and replaces it.

Without `native/app/google-services.json` the app builds and works, but has no notifications,
and the bell stays hidden. See `FIREBASE-SETUP.md`.

To try changes on a phone over USB, open `native/` in Android Studio and run it, or use
`native\gradlew.bat installDebug` with the phone plugged in and USB debugging on.

## The first build: back up the key

The first build prints the new key's fingerprint and asks for two things:

1. **Back up `android\android.keystore` and `android\keystore.properties`** somewhere safe and
   private, such as a password manager. Both are kept out of git. An APK signed with a
   different key can't update one already installed, so losing them means every user has to
   uninstall and reinstall.
2. **Commit and deploy `main-site/.well-known/assetlinks.json`**. It lists this key's
   fingerprint, which is what lets the site's links open in the app.

From then on, the script refuses to build if the keystore is missing (restore it from your
backup), and refuses an APK signed with any key other than the one `assetlinks.json` names.

## Google's developer verification

From 30 September 2026, Android in Singapore (with Brazil, Indonesia and Thailand) checks that
apps come from a verified developer, starting with installs through participating app stores,
with more to follow in 2027. To stay ahead of it and keep Play Protect from warning about the
APK:

1. Sign up on the [Android Developer Console](https://developer.android.com/developer-verification/guides/android-developer-console),
   or use the account you made for SG Bus Timings.
2. Register the package `org.uwuapps.fixup` with the SHA-256 fingerprint in `assetlinks.json`.

Check [Google's guide](https://developer.android.com/developer-verification/guides) for the
current steps; they were still settling in October 2026.

## Install it

Copy the APK to the phone and open it. Android asks to allow installing apps from wherever it
was opened (Files, Chrome, Telegram); allow it once. After that, the app updates itself.

## Changing it

- **The site's address, the user agent, the status bars**: `capacitor.config.json`, then
  `npx cap sync android`.
- **Permissions, activities, links**: `native/app/src/main/AndroidManifest.xml`.
- **Something new the page can ask the app for**: a `@PluginMethod` in `FixupPlugin`, called
  from the page with `AppBridge.call('Fixup', 'method', {...})`. Add a word to `info`'s
  `features` so the page can tell builds with it from builds without.
- **A Capacitor plugin from npm**: `npm install` it here, then `npx cap sync android`; the page
  reaches it the same way.
- **Upgrading Capacitor**: raise the `@capacitor/*` versions in `package.json` together (the
  push plugin's numbers run on their own, so take its newest for that Capacitor), `npm install`,
  `npx cap sync android`, and compare `native/` with a fresh `npx cap add android` for template
  changes.
