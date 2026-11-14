# Setting up Firebase Cloud Messaging for the Android app's notifications

The Android app (`flutter/`) gets its notifications through **Firebase Cloud Messaging (FCM)**,
Google's push service for Android. There are two kinds, and people turn each on with the bell in
the Edge Tray:

| Notification | Sent by | FCM topic | Android channel |
|---|---|---|---|
| **New versions of the app**: "Version 1.2.0 of uwuFix is out", the moment you publish a release. Tapping it opens the updates page | This site's server (`main-site/api/push/release.js`), called by a GitHub webhook | `fixup-releases` | `releases` |
| **News from uwuFix**: whatever you want to say, whenever | You, from the Firebase console | `fixup-news` | `news` |

A phone joins a topic when its switch is turned on (`FixupPlugin.setTopic`), so the server keeps no
list of phones and there's no database. The topics carry the `fixup-` prefix because topics are
shared by every app in a Firebase project.

The Google Play build has no "New versions of the app" switch, as Play updates it; news works the
same in both.

Only Cloud Messaging is used: no Analytics, no Firebase database, nothing else, and the app's
manifest switches Firebase Analytics off in case a library ever brings it in. It's free.

**If uwuFix 1.0.x already got notifications**, steps 1 to 5 are done: the Firebase app, the key, the
webhook and Vercel's settings are the same for 1.1.0. Only step 6 is new, as the Flutter app keeps
`google-services.json` in a new place.

Until this is done, the app works fully, but the bell in the Edge Tray stays hidden.

| What | Where it goes | Secret? |
|---|---|---|
| `google-services.json`, which tells the app which Firebase project it belongs to | `flutter/android/app/` | No, but kept out of git anyway |
| uwuFix's service account key (`….json`), which lets this site's server send pushes | Vercel, as `FIREBASE_SERVICE_ACCOUNT` | **Yes.** Anyone with it can push to phones with any app in the UwU Apps project |
| A webhook secret, which proves a "release published" call really came from GitHub | GitHub and Vercel, as `GITHUB_WEBHOOK_SECRET` | **Yes** |
| A GitHub token (optional), which raises GitHub's rate limit for the update check | Vercel, as `GITHUB_TOKEN` | Yes, though it can do nothing but read |

## 1. Add uwuFix to the UwU Apps project, and get `google-services.json`

1. Open <https://console.firebase.google.com> and pick the **UwU Apps** project.
2. Click the gear by **Project Overview**, then **Project settings** > **Your apps** > **Add app** >
   **Android**.
3. **Android package name**: `org.uwuapps.fixup`. It has to be exactly this.
4. **App nickname**: `uwuFix`. Leave **Debug signing certificate SHA-1** empty: FCM doesn't need it.
5. Click **Register app**, then **Download google-services.json**.
6. Click **Next** through the remaining steps without changing anything: the build already applies
   the Google services plugin whenever the file is there (`flutter/android/app/build.gradle`).

The file lists every app in the project, and the build takes the `org.uwuapps.fixup` entry from
it. Download it **after** registering uwuFix, or the build stops with "No matching client found
for package name".

## 2. Check FCM's API is on

In Firebase, open **Project settings** > **Cloud Messaging**. Under **Firebase Cloud Messaging API
(V1)** it should say **Enabled**. (It already is for SG Bus Timings.)

## 3. Make uwuFix's own service account key

The key belongs to uwuFix alone, so it can be deleted without touching SG Bus Timings'.

1. Open <https://console.cloud.google.com/iam-admin/serviceaccounts>, with **UwU Apps** picked at
   the top.
2. **Create service account**: name `fixup-links-push`, description `uwuFix's server, sending
   notifications through FCM`. **Create and continue**.
3. **Select a role**: `Firebase Cloud Messaging API Admin`, and only that. **Continue**, **Done**.
4. In the list, click `fixup-links-push@…` > **Keys** > **Add key** > **Create new key** > **JSON** >
   **Create**. A `.json` file downloads.

> [!WARNING]
> That key is a password. Don't commit it, email it, or paste it anywhere but Vercel. FCM doesn't
> fence a key to one app, so a leaked key can push to every app in UwU Apps. If it ever leaks,
> delete it on the same **Keys** tab and make a new one.

## 4. Give the server its secrets (Vercel)

Open <https://vercel.com>, the project that serves fixup.uwuapps.org, then **Settings** >
**Environment Variables**. Add each with **Production** ticked, marked **Sensitive**:

| Key | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Everything in the key file from step 3, from `{` to `}`. Base64 of the file works too |
| `GITHUB_WEBHOOK_SECRET` | A long random string, made with the command below. Keep it for step 5 |
| `GITHUB_TOKEN` (optional) | A fine-grained GitHub token with **Public repositories (read-only)** and nothing else. Without it, GitHub allows 60 update checks an hour, which the site's cache makes plenty |

```powershell
$b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { '{0:x2}' -f $_ })
```

Then redeploy so the functions see them (**Deployments** > newest > **⋯** > **Redeploy**), and
delete the downloaded key file from your Downloads folder.

## 5. Tell GitHub to call the server when you publish a release (webhook)

1. Open <https://github.com/augy-studios/fixup-links/settings/hooks/new>.
2. **Payload URL** `https://fixup.uwuapps.org/api/push/release`, **Content type**
   `application/json`, **Secret** the same `GITHUB_WEBHOOK_SECRET`, **Let me select individual
   events**: untick **Pushes**, tick **Releases**. **Active** ticked.
3. **Add webhook**. Its first delivery, a ping, should show a green tick and
   `{"ok":true,"pong":true}`. A 401 means the secret doesn't match Vercel's (or Vercel wasn't
   redeployed).

From now on, publishing an `android-v*` release with its APK attached pushes the notification
(`release/README.md`). Drafts, pre-releases, releases without an APK, and re-publishing a version
older than the newest are skipped, and **Recent Deliveries** says why.

## 6. Build the app with Firebase in it

Put `google-services.json` at `flutter\android\app\google-services.json` (beside `build.gradle`),
then:

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1
```

Without the file, the build warns `google-services.json is missing: this build has no
notifications` and the bell stays hidden. With it, install the new APK on your phone.

## How it works in the app

| Piece | What it does |
|---|---|
| `FixupPlugin.setTopic` (Java) | Joins or leaves `fixup-releases` / `fixup-news`, and remembers which |
| `PushNotificationsPlugin` (Java) | Android's notification permission (13 and later), asked only when a switch is turned on |
| `MessagingService` (Java) | A push that comes while the app is open, handed to the Dart side |
| `Notifications.java` | The two channels, `releases` and `news`, each its own switch in Android's settings |
| `MainActivity` | A tapped "new version" notification opens the updates page for that version |
| `lib/features/notify/notify_sheet.dart` | The bell's switches, and a push that comes while the app is open shown at the bottom, with **Update** for a new version |

With the app in the background, Android shows a push itself, on the channel the server names
(`main-site/api/_push/fcm.js`).

## 7. Check it works

1. In the app, tap the bell in the Edge Tray and turn on both switches. Allow notifications when
   Android asks.
2. **News**: in the UwU Apps project, **Messaging** > **New campaign** > **Notifications**. Title and
   text, **Next**; **Target**: **Topic** `fixup-news` (the topic, not the app, so it reaches only
   people who turned news on); **Scheduling**: **Now**; **Additional options** > **Android
   notification channel**: `news`; **Review** > **Publish**. Lock your phone: it should arrive
   within a minute.
3. **New versions**: open the webhook in GitHub, **Recent Deliveries**, and redeliver a past
   `release` delivery. Or wait for your next release.

## If something goes wrong

| What happens | What to do |
|---|---|
| The build stops with `No matching client found for package name 'org.uwuapps.fixup'` | `google-services.json` was downloaded before uwuFix was added. Download it again from **Project settings** > **Your apps** > **uwuFix** |
| No bell in the Edge Tray | The APK was built without `google-services.json`. Check it's at `flutter\android\app\google-services.json`, build again, reinstall |
| "Notifications are off for uwuFix in Android's settings" | You said no to Android's prompt. Tap **Open Android's settings**, turn notifications on, and come back |
| "Couldn't reach Firebase" when turning a switch on | The phone was offline, or has no Google Play services (some Huawei phones), which FCM needs |
| The webhook shows `401 Bad signature` | The secret in GitHub and `GITHUB_WEBHOOK_SECRET` in Vercel differ, or Vercel wasn't redeployed |
| The webhook shows `502` with `FIREBASE_SERVICE_ACCOUNT is not set` | Step 4 is missing or wasn't redeployed |
| The webhook shows `502` with `FCM responded 403` | The service account is missing its role (step 3), or FCM's API is off (step 2) |
| The webhook shows `502` with `Google token responded 400: invalid_grant` | The key was deleted. Make a new one, replace the variable, redeploy |
| The webhook shows `400 Not JSON` | The webhook's content type is form-encoded. Edit it to `application/json` |
