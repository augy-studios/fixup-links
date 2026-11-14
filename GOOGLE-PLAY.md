# Putting uwuFix on Google Play

A step-by-step guide for publishing the Android app on Google Play, written for uwuFix 1.1.0 (the
Flutter app), as SG Bus Timings' `GOOGLE-PLAY.md` is for that app. Google changes its rules often,
so each rule names the page it came from (section 12); re-check a page if this date is far behind
you. Written 14 November 2026.

**What's done in the repo:** the Play build (an AAB with no updater), the shrinking and
obfuscation Play measures, the store screenshots and feature graphic, the release notes, and the
privacy page. **What's left is yours:** the developer account, Play Console, and the testing
period.

## Contents

1. [The short version](#1-the-short-version)
2. [How the Play build differs](#2-how-the-play-build-differs)
3. [Signing: one key for both](#3-signing-one-key-for-both)
4. [Build the AAB](#4-build-the-aab)
5. [Developer account](#5-developer-account)
6. [Create the app](#6-create-the-app)
7. [Store listing](#7-store-listing)
8. [App content](#8-app-content)
9. [Data safety](#9-data-safety)
10. [Testing, then production](#10-testing-then-production)
11. [After launch](#11-after-launch)
12. [Sources](#12-sources)

## 1. The short version

1. Build the AAB: `powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab`.
2. Make a Play Console account (US$25 once) and verify your identity, or use SG Bus Timings'.
3. Create the app `uwuFix`, and give Play the app's existing key (section 3).
4. Fill in the listing from section 7 and the pictures in `docs/`.
5. Answer App content and Data safety from sections 8 and 9.
6. Upload to internal testing, then a closed test (12 testers for 14 days on a new personal
   account), then apply for production and roll out with
   `announcements/play-release-notes-1.1.0.md`.

## 2. How the Play build differs

`build-apk.ps1 -Aab` builds the same app as the GitHub APK, with these differences:

| | GitHub APK | Google Play AAB |
|---|---|---|
| File | `release/1.1.0/uwufix-1.1.0.apk` | `release/1.1.0/uwufix-1.1.0.aab` |
| Updates | Its own updater (`UpdateActivity`), the update bar, the updates page | Play updates it. No updater, no update bar, no **Check for app updates** |
| `REQUEST_INSTALL_PACKAGES` | Yes, for its updater | Removed (`android/app/src/play/AndroidManifest.xml`), as Play refuses it in apps that aren't installers |
| "New versions of the app" notification | Yes | No; **News from uwuFix** stays |
| Dart flag | | `--dart-define=FIXUP_PLAY=true` (`playBuild` in `lib/native/native_bridge.dart`) |

Both are shrunk and obfuscated: R8 for the Java (`minifyEnabled`, `shrinkResources`), Dart's
`--obfuscate` with its symbols split off, and native libraries stripped. The AAB carries R8's
mapping and the native debug symbols in its metadata, so Play Console's crash reports read
properly. For Dart stack traces, keep `uwufix-1.1.0-play-symbols.zip` (it isn't uploaded).

Neither build asks for the advertising ID (`AD_ID` is removed), Firebase Analytics is switched
off, and there are no ads. The script refuses a build that has any of them.

Target API: the app targets API 36 (Android 16) (`flutter/android/variables.gradle`), which meets
Play's rule for new apps and updates from 31 August 2026 ([target API][target]).

## 3. Signing: one key for both

Play signs what it delivers with an **app signing key**, and you sign uploads with an **upload
key** ([Play App Signing][signing]). Give Play **the key the GitHub APK is already signed with**
(`flutter\android.keystore`) as the app signing key:

- People with the GitHub APK can move to the Play version, and back, without uninstalling, as
  Android only updates an app to one signed with the same key.
- The site's links keep opening in the app: `main-site/.well-known/assetlinks.json` already names
  this key.

When Play asks for the app signing key, pick **Use existing app signing key from Java keystore**
(or **Export and upload a key from Java keystore**). Play Console gives you its PEPK tool and the
exact command, with its encryption key; run it in PowerShell from `flutter\`, using the alias and
passwords in `flutter\keystore.properties`. It writes an encrypted `.zip` to upload. Never put the
keystore, the properties file or that zip in git.

For the **upload key**, the simplest is the same key, as `build-apk.ps1` already signs the AAB with
it and checks it. Google recommends a separate upload key, which can be reset if it's ever lost;
if you'd like one, make it with `keytool -genkeypair` and register its certificate on the same
Play Console page, and the build script would need pointing at it.

Do this **before the first release goes past internal testing**: after that, the app signing key
can only be upgraded, not chosen.

## 4. Build the AAB

On Windows, from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab
```

It ends `Done: ...\release\1.1.0\uwufix-1.1.0.aab`. Before copying it out, the script checks that
it's signed with the app's key, has no updater and no advertising ID, has R8's mapping inside, and
has its native symbols stripped. `flutter\android\app\google-services.json` must be there for
notifications (`flutter/FIREBASE-SETUP.md`).

Each new Play release needs a higher `versionCode`: raise the number after the `+` in
`flutter/pubspec.yaml` (`1.1.0+3` is versionCode 3). The GitHub APK and the AAB of the same
version share the code.

## 5. Developer account

If SG Bus Timings' Play account is already made and verified, use it and skip to section 6.

1. Sign in to the Google account that will own the app, with 2-Step Verification on.
2. Register at <https://play.google.com/console/signup>: **US$25, once**, by a card in the
   account holder's name. You must be 18 or older, and may be asked for ID ([registration][account]).
3. Personal or organisation: personal is quicker; an organisation needs a D-U-N-S number.
4. Verify your identity, which can take a few days. Creating the app in Play Console registers
   `org.uwuapps.fixup` to the account for Google's developer verification
   ([developer verification][devverify]); check its Home page shows it as registered.
5. **The testing rule:** a personal account made after 13 November 2023 must run a closed test
   with **at least 12 testers opted in for 14 days in a row** before applying for production
   ([testing requirements][testing]). It applies to each new app on the account, so uwuFix needs
   its own, even if SG Bus Timings went through it. Plan for about three weeks.

## 6. Create the app

In Play Console, **Create app** ([setup][release]):

| Field | Answer |
|---|---|
| App name | `uwuFix` |
| Default language | English (United States) – en-US, matching the release notes' `<en-US>` tag |
| App or game | App |
| Free or paid | Free |
| Declarations | Accept the Developer Programme Policies and US export laws |

The package name comes from the first AAB you upload, `org.uwuapps.fixup`, and is permanent.

## 7. Store listing

**Grow users** > **Store presence** > **Main store listing** ([asset specs][assets]).

| Field | Limit | Use |
|---|---|---|
| App name | 30 | `uwuFix` |
| Short description | 80 | `Clean links: strip trackers and fix previews for X, Instagram, TikTok and more` (78) |
| Full description | 4,000 | Below |
| App icon | 512 × 512 PNG | `main-site/UFX-512.png` |
| Feature graphic | 1024 × 500, no alpha | `docs/feature-graphic.png` |
| Phone screenshots | 2 to 8 | `docs/phone-assets/` (8, 1620 × 2880) |
| 7-inch tablet | Up to 8 | `docs/tablet-assets/7-inch/` (8) |
| 10-inch tablet | Up to 8 | `docs/tablet-assets/10-inch/` (8) |
| Chromebook | Up to 8, 16:9 | `docs/desktop-assets/` (8, 2880 × 1620) |
| Category | One | **Tools** |
| Tags | Up to 5 | Pick from Play's list, e.g. link tools, privacy, productivity ([tags][tags]) |
| Contact email | Required | `augy@augystudios.com` |
| Website | Recommended | `https://fixup.uwuapps.org` |
| Privacy policy | Required | `https://fixup.uwuapps.org/privacy` (`main-site/privacy.html`; deploy the site first) |

Upload the screenshots in their numbered order: it's the order the captions tell the story in.
They're made by `flutter test test/shots/` and `flutter/tool/store_assets.mjs`
(`flutter/README.md`), so they can be made again after a change.

**Full description:**

```text
uwuFix cleans the links you share.

Paste a link, or share one to uwuFix from any app, and it comes back without the trackers stuck
to it: utm_ tags, click IDs, share IDs, and the rest. Links to X, Instagram, TikTok, Reddit,
Bluesky, Threads, Facebook, Pixiv, Tumblr, Spotify and more are swapped for ones that show a proper
preview in Discord, Telegram and other chats.

• Share to uwuFix, or highlight a link anywhere and pick Fix link. In a box you can type in,
  Replace puts the clean link back where it was.
• Follows short links and email click-trackers to where they really go, and cleans that too.
• History of everything you've cleaned, with page titles, kept on your phone.
• Share your history with your other devices, phone, tablet or computer, straight from one to the
  other with a code or QR code, through no server.
• Material You colours from your wallpaper, or the UwU Apps look, light or dark.
• Widgets: Fix a link, and Fix copied link in one tap.
• A short tour of each page, and Report a bug with a screenshot when something's wrong.

No ads. No account. No analytics in the app.

uwuFix is also a website, fixup.uwuapps.org, and apps for Windows, macOS and Linux.
```

## 8. App content

**Policy and programmes** > **App content** ([prepare for review][review]):

| Task | Answer |
|---|---|
| Privacy policy | `https://fixup.uwuapps.org/privacy` |
| Ads | **No** |
| App access | All functionality is available without special access |
| Content rating | Fill in the questionnaire: a utility, no violence, no user-generated content others can see, no location, no purchases. Expect the lowest rating |
| Target audience | 18 and over (or 13 and over); not designed for children |
| News app | No |
| Government app | No |
| Financial features | None |
| Health | None |
| Advertising ID | **No**, the app doesn't use it |

## 9. Data safety

Data counts as collected if the app sends it off the device, including through its libraries
([data safety form][datasafety]). Keep it consistent with the privacy page.

| Data type (Play's name) | What happens | Declare |
|---|---|---|
| **App activity: Other user-generated content** (the links you clean) | Sent to uwuFix's server (`/api/resolve`) to follow redirects and read titles, and not kept | Collected, **processed ephemerally**, App functionality. Not shared |
| **Personal info: Email address** | Only if typed into Report a bug's contact box | Collected, optional, App functionality (developer communications) |
| **Personal info: Other info** | A Telegram name, if typed there instead | Collected, optional, App functionality |
| **Photos and videos: Photos** | Pictures and screenshots added to a bug report | Collected, optional, App functionality |
| **App info and performance: Other app performance data** | A bug report's app version, device model, system version, page and language | Collected, optional, App functionality |
| **Device or other IDs** | Firebase Cloud Messaging's token, when notifications are turned on | Collected, optional, App functionality |
| History, through Share history | Goes from one of your devices to the other, encrypted (WebRTC); no server of uwuFix's sees it | Not collected (it doesn't reach the developer); say so if Play's wording asks |

Other answers:

- **Is all user data encrypted in transit?** Yes: HTTPS, and Share history is encrypted end to end.
- **Can people ask for their data to be deleted?** Yes: by email, for bug reports. Everything else
  is only on the device, and goes with uninstalling.
- **Account creation:** the app has no accounts.
- SDKs: Firebase Messaging publishes its own notes in the [Play SDK Index](https://play.google.com/sdks).

## 10. Testing, then production

1. **Internal testing.** Upload `uwufix-1.1.0.aab` to a new internal test release, add yourself
   by email, and install from the link. Check:
   - With the GitHub APK 1.1.0 installed, the Play one installs over it, history kept (that's
     the shared key of section 3).
   - There's no **Check for app updates** in the Edge Tray, and no update bar.
   - The bell's **News from uwuFix** works (`flutter/FIREBASE-SETUP.md`, step 7).
2. **Closed testing.** Make a closed track, add 12 or more testers by email or a Google Group, and
   share the opt-in link: the UwU Apps Telegram channel is a good place to find them. They stay
   opted in for 14 days in a row. A fix needs a higher versionCode.
3. **Apply for production** from the Dashboard once the 14 days are up. Google usually answers
   within seven days.
4. **Production.** Create the release with the same AAB (or a newer one), paste the block from
   `announcements/play-release-notes-1.1.0.md` into **Release notes**, pick the countries
   (worldwide: nothing in uwuFix is tied to one country), and roll out. A staged rollout is
   offered.
5. **Review.** The first can take several days. Watch your email and **Policy status**.

## 11. After launch

- **Each update:** raise the version in `flutter/pubspec.yaml`, build the APK for GitHub and the
  AAB for Play (`release/README.md`), and write Play's notes in
  `announcements/play-release-notes-<version>.md` (500 characters at most).
- **GitHub releases go on as before**, tagged `android-v<version>`, with the APK. Play gets only
  the AAB. Don't upload one to the other.
- **Target API, every year:** Google raises it each August. Raise `targetSdkVersion` in
  `flutter/android/variables.gradle`, and test.
- **A link to the Play listing** can go in the site's README and the Telegram announcements once
  it's live.

## 12. Sources

The rules come from SG Bus Timings' guide, which fetched these pages on 28 October 2026. Check them again before submitting.

[target]: https://support.google.com/googleplay/android-developer/answer/11926878
[signing]: https://support.google.com/googleplay/android-developer/answer/9842756
[account]: https://support.google.com/googleplay/android-developer/answer/6112435
[devverify]: https://developer.android.com/developer-verification/guides
[testing]: https://support.google.com/googleplay/android-developer/answer/14151465
[release]: https://support.google.com/googleplay/android-developer/answer/9859152
[assets]: https://support.google.com/googleplay/android-developer/answer/9866151
[tags]: https://support.google.com/googleplay/android-developer/answer/9859673
[review]: https://support.google.com/googleplay/android-developer/answer/9859455
[datasafety]: https://support.google.com/googleplay/android-developer/answer/10787469
