# Releases

The Android app's APKs, each version in a folder of its own, built by `android\build-apk.ps1`
and committed alongside the code they were built from:

```text
release/1.0.0/uwufix-1.0.0.apk
release/1.0.1/uwufix-1.0.1.apk
...
```

Share them through a **GitHub Release**, where anyone can download them from
<https://github.com/augy-studios/fixup-links/releases>. The app updates itself from there.

## Build one

1. For anything after the first release, raise `versionCode` (one higher) and `versionName` in
   `android\native\app\build.gradle` (`android/README.md`, "Build the APK").
2. From the project root, in PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
   ```

   It ends with `Done: ...\release\<version>\uwufix-<version>.apk`.

## Put it on GitHub

1. **Deploy the site first** if the release needs anything new from it. The update bar,
   `api/app-release.js` and the notifications all come from the site.
2. Commit and push your changes, the new APK included, so the release points at the code it was
   built from.
3. Open <https://github.com/augy-studios/fixup-links/releases/new>.
4. **Choose a tag**: type `android-v<version>`, such as `android-v1.0.0`, and pick **Create new
   tag on publish**. Leave the target as `main`. Keep to the `android-v` prefix: it's how the
   app's updater finds its releases.
5. **Release title**: `uwuFix 1.0.0`.
6. **Describe this release**: what's new, for the people installing it. For example:

   ```markdown
   Download `uwufix-1.0.0.apk` on your Android phone and open it. If Android asks, allow
   installing apps from your browser or Files.

   - Share any link to uwuFix, or highlight one and pick "Fix link", to clean it right there
   - Updates itself, and can tell you when a new version is out
   ```

7. Drag the APK from `release\<version>\` into **Attach binaries by dropping them here**, and
   wait for it to finish uploading. **Attach it before publishing**: the "new version"
   notification is sent the moment you publish, and only for a release that has its APK.
8. Tick **Set as the latest release**, then click **Publish release**.

`https://github.com/augy-studios/fixup-links/releases/latest` always points at the newest one,
which makes a good link to share.

## How phones hear about it

- **At once**, if they turned on "New versions of the app" under the bell in the Edge Tray: the
  GitHub webhook calls `main-site/api/push/release.js`, which pushes "Version 1.0.1 of uwuFix is
  out". Tapping it opens the app's update window (`android/FIREBASE-SETUP.md` sets this up).
- **Within about 10 minutes**, for everyone else: the app shows a bar at the top of the page
  next time it's opened. The bar reads the releases through `main-site/api/app-release.js`,
  which skips drafts, pre-releases, tags that don't start `android-v`, and releases whose APK
  hasn't finished uploading.
- **Any time**, from the Edge Tray's download button, "Check for app updates".

**Update** downloads the APK inside the app, checks it against GitHub's checksum, and hands it
to Android's installer (`UpdateActivity.java`).

## Before you share it

- **The repository has to be public** for others to download the APK. A private repository's
  releases are only visible to people with access to it.
- **Never upload `android.keystore`, `keystore.properties` or Firebase's service account key.**
  Only the APK.

## If something goes wrong

| What happens | What to do |
|---|---|
| "App not installed" on the phone | A copy signed with a different key is installed, such as one from PWABuilder. Uninstall uwuFix, then install again. |
| "App not installed as package appears to be invalid" | The download didn't finish. Download it again. |
| Play Protect warns about the app | See "Google's developer verification" in `android/README.md`. |
| You uploaded the wrong file | On the release, click **Edit**, delete the file with the bin icon, attach the right one, and click **Update release**. The app checks the file is newer and matches GitHub's checksum, so phones won't install a mismatch. |
| No update bar in the app | The tag doesn't start `android-v`, the release is a draft or pre-release, or it's been under 10 minutes. `https://fixup.uwuapps.org/api/app-release` shows what phones see. |
| No notification | Check the webhook's **Recent Deliveries** in GitHub: each one shows why it did or didn't send (`android/FIREBASE-SETUP.md`). |
