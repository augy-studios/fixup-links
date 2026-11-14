# Releases

Each version's Android builds, in a folder of its own, built by `flutter\build-apk.ps1` and
committed alongside the code they were built from:

```text
release/1.0.0/uwufix-1.0.0.apk            the WebView app (Capacitor)
release/1.0.1/uwufix-1.0.1.apk
release/1.1.0/uwufix-1.1.0.apk            the Flutter app, for GitHub: what phones update to
release/1.1.0/uwufix-1.1.0.aab            the Flutter app, for Google Play (GOOGLE-PLAY.md)
release/1.1.0/uwufix-1.1.0-mapping.txt    R8's mapping, to read a Java crash
release/1.1.0/uwufix-1.1.0-symbols.zip    the Dart symbols, to read a Dart crash
...
```

A file over 100 MB, GitHub's limit, isn't committed: the build script lists it in `.gitignore`,
and it goes only on the GitHub release (or Play).

The desktop apps' installers aren't here. GitHub Actions builds them when a release is published
(`.github/workflows/build-desktop.yml`) and attaches them to it.

Everything is shared through a **GitHub Release**, from
<https://github.com/augy-studios/fixup-links/releases>. The apps update themselves from there.

## Build one

1. Raise `version:` in `flutter/pubspec.yaml`: `1.1.0+3` is versionName `1.1.0`, versionCode `3`.
   Raise both for every release; phones only update to a higher code.
2. Write what's new in `announcements/` (`announcements/README.md`): `release-notes-<version>.md`
   for GitHub, `announcement-<version>.md` for the Telegram channel, and
   `play-release-notes-<version>.md` for Play.
3. From the project root, in PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1        # the APK
   powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab   # the AAB, for Play
   ```

   Each ends with `Done: ...\release\<version>\uwufix-<version>.apk` (or `.aab`).

## Put it on GitHub

1. **Deploy the site first** if the release needs anything new from it. The update bar,
   `api/app-release.js`, the notifications and Report a bug all come from the site.
2. Commit and push, the new builds included, so the release points at the code it was built from.
3. Open <https://github.com/augy-studios/fixup-links/releases/new>.
4. **Choose a tag**: `android-v<version>`, such as `android-v1.1.0`, **Create new tag on
   publish**, target `main`. Keep to the `android-v` prefix: it's how the apps' updaters find their
   releases.
5. **Release title**: `uwuFix 1.1.0`.
6. **Describe this release**: paste `announcements/release-notes-<version>.md`. The Android
   app's updates page shows it as cards, so keep to its shape (`announcements/README.md`).
7. Attach **only the APK** from `release\<version>\`, and wait for it to finish uploading.
   **Attach it before publishing**: the "new version" notification goes the moment you publish,
   and only for a release that has its APK. The AAB, mapping and symbols stay off GitHub.
8. Tick **Set as the latest release**, then **Publish release**.
9. Publishing starts **Build desktop apps** in the repository's **Actions** tab. In about half an
   hour it attaches the Windows, macOS and Linux installers and the `latest*.yml` files the
   desktop apps update from. If it fails, fix it and run it again from **Actions** > **Build
   desktop apps** > **Run workflow**, with the release's tag: it replaces what's there.
10. Post `announcements/announcement-<version>.md` in the UwU Apps Telegram channel.

`https://github.com/augy-studios/fixup-links/releases/latest` always points at the newest one.

## A desktop-only release

When only the desktop apps change (1.1.1), raise the version as usual but build no APK, and tag
the release `desktop-v<version>`, such as `desktop-v1.1.1`. Publishing it starts the desktop
workflow just the same. Mark it the latest: the desktop apps update from the latest release.
Android ignores it, as it only takes `android-v*` releases with an APK, so phones see no update,
no notification, and nothing new on the updates page. Say in its notes that Android stays on the
last `android-v` version, with a link to it.

## How devices hear about it

- **Android, at once**, if they turned on "New versions of the app" under the bell in the Edge
  Tray: the GitHub webhook calls `main-site/api/push/release.js`, which pushes "Version 1.1.0 of
  uwuFix is out". Tapping it opens the updates page (`flutter/FIREBASE-SETUP.md` sets this up).
- **Android, within about 10 minutes**, for everyone else: a bar at the top of the app next time
  it's opened, read through `main-site/api/app-release.js`, which skips drafts, pre-releases,
  tags that don't start `android-v`, and releases whose APK hasn't finished uploading.
- **Android, any time**, from the Edge Tray's **Check for app updates**, which opens the updates
  page: every version's notes, newest first.
- **The desktop apps**, once the workflow has attached their files: they check soon after they start,
  every hour, and on waking from sleep, then download it and offer to restart into it.
- **Google Play**: Play updates the Play build itself, once you roll the AAB out there.

**Update** on Android downloads the APK inside the app, checks it against GitHub's checksum, and
hands it to Android's installer (`UpdateActivity.java`).

## Before you share it

- **Never upload `flutter\android.keystore`, `flutter\keystore.properties`,
  `google-services.json` or Firebase's service account key.** Only the APK.
- The repository has to be public for others to download from its releases.

## If something goes wrong

| What happens | What to do |
|---|---|
| "App not installed" on the phone | A copy signed with a different key is installed. Uninstall uwuFix, then install again |
| "App not installed as package appears to be invalid" | The download didn't finish. Download it again |
| Play Protect warns about the app | See "Google's developer verification" in `flutter/README.md` |
| You uploaded the wrong file | On the release, **Edit**, delete the file, attach the right one, **Update release**. The app checks the file is newer and matches GitHub's checksum, so phones won't install a mismatch |
| No update bar in the app | The tag doesn't start `android-v`, the release is a draft or pre-release, or it's been under 10 minutes. `https://fixup.uwuapps.org/api/app-release` shows what phones see |
| No notification | The webhook's **Recent Deliveries** in GitHub shows why each did or didn't send (`flutter/FIREBASE-SETUP.md`) |
| No desktop installers on the release | **Actions** > **Build desktop apps**: open the failed run, read the step that failed, then **Run workflow** with the tag once it's fixed |
