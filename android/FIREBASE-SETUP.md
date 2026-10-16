# Setting up Firebase for the Android app's notifications

The Android app shows the site in its own WebView, which has no Web Push. So its notifications
come through **Firebase Cloud Messaging (FCM)**, Google's push service for Android. There are
two kinds, and people turn each on with the bell in the Edge Tray:

| Notification | Sent by | FCM topic |
|---|---|---|
| **New versions of the app**: "Version 1.0.1 of uwuFix is out", the moment you publish a release. Tapping it opens the update window | This site's server (`main-site/api/push/release.js`), called by a GitHub webhook | `fixup-releases` |
| **News from uwuFix**: whatever you want to say, whenever | You, from the Firebase console | `fixup-news` |

A phone joins a topic when its switch is turned on, so the server keeps no list of phones and
there's no database. The topics carry the `fixup-` prefix because topics are shared by every
app in a Firebase project.

uwuFix goes into your existing **UwU Apps** Firebase project, as an app of its own, beside SG
Bus Timings. Only FCM is used: no Analytics, no Firebase database, nothing else. It's free.

Until this is done, the app works fully, but the bell in the Edge Tray stays hidden.

It takes about 20 minutes, and covers four things:

| What | Where it goes | Secret? |
|---|---|---|
| `google-services.json`, which tells the app which Firebase project it belongs to | `android/native/app/` | No, but kept out of git anyway |
| uwuFix's service account key (`….json`), which lets this site's server send pushes | Vercel, as `FIREBASE_SERVICE_ACCOUNT` | **Yes.** Anyone with it can push to phones with any app in the UwU Apps project |
| A webhook secret, which proves a "release published" call really came from GitHub | GitHub and Vercel, as `GITHUB_WEBHOOK_SECRET` | **Yes** |
| A GitHub token (optional), which raises GitHub's rate limit for the update check | Vercel, as `GITHUB_TOKEN` | Yes, though it can do nothing but read |

## 1. Add uwuFix to the UwU Apps project, and get `google-services.json`

1. Open <https://console.firebase.google.com> and pick the **UwU Apps** project.
2. Click the gear by **Project Overview**, then **Project settings** > **Your apps** > **Add
   app** > **Android**.
3. **Android package name**: `org.uwuapps.fixup`. It has to be exactly this.
4. **App nickname**: `uwuFix`. Leave **Debug signing certificate SHA-1** empty, since FCM
   doesn't need it.
5. Click **Register app**.
6. Click **Download google-services.json**. Save it as
   `android\native\app\google-services.json` in this project, beside `build.gradle`.
7. Click **Next** through the remaining steps without changing anything. The project already
   has what they describe: the build applies the Google services plugin whenever the file is
   there.

The file lists every app in the project, and the build takes the `org.uwuapps.fixup` entry from
it. Download it **after** registering uwuFix, or the build stops with "No matching client found
for package name".

## 2. Check FCM's API is on

This should already be done for SG Bus Timings. In Firebase, open **Project settings** >
**Cloud Messaging**. Under **Firebase Cloud Messaging API (V1)** it should say **Enabled**.

## 3. Make uwuFix's own service account key

The key comes from Google Cloud, where Firebase projects live. It belongs to uwuFix alone, so it
can be deleted without touching SG Bus Timings'.

1. Open <https://console.cloud.google.com/iam-admin/serviceaccounts>. At the top, pick the
   **UwU Apps** project.
2. Click **Create service account**:
   - **Service account name**: `fixup-links-push`
   - **Description**: `uwuFix's server, sending notifications through FCM`
   - Click **Create and continue**.
3. Under **Grant this service account access to project**, in **Select a role**, search for
   `Firebase Cloud Messaging API Admin` and pick it. Pick only this one. Click **Continue**,
   then **Done**.
4. In the list, click `fixup-links-push@…`, open the **Keys** tab, and click **Add key** >
   **Create new key** > **JSON** > **Create**. A `.json` file downloads.

> [!WARNING]
> That key is a password. Don't commit it, email it, or paste it anywhere but Vercel. FCM
> doesn't fence a key to one app, so a leaked key can push to every app in UwU Apps. If it ever
> leaks, delete it on the same **Keys** tab and make a new one.

## 4. Give the server its secrets (Vercel)

Open <https://vercel.com>, then the project that serves fixup.uwuapps.org, then **Settings** >
**Environment Variables**. Add each of these with **Production** ticked (and **Preview** if you
test there), and mark each **Sensitive**:

| Key | Value |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Open the key file from step 3 in Notepad and paste **everything** in it, from `{` to `}`. Base64 of the file works too |
| `GITHUB_WEBHOOK_SECRET` | A long random string. Make one in PowerShell with the command below, and keep it for step 5 |
| `GITHUB_TOKEN` (optional) | A GitHub fine-grained token with **Public repositories (read-only)** access and nothing else, from <https://github.com/settings/personal-access-tokens/new>. Without it, GitHub allows 60 update checks an hour across all users, which is plenty while the app is small |

```powershell
$b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { '{0:x2}' -f $_ })
```

Then redeploy so the functions see them: open **Deployments**, then the newest deployment's
**⋯** menu, then **Redeploy**. After that, delete the downloaded key file from your Downloads
folder, since Vercel has it now.

## 5. Tell GitHub to call the server when you publish a release (webhook)

1. Open <https://github.com/augy-studios/fixup-links/settings/hooks/new>.
2. Fill it in:
   - **Payload URL**: `https://fixup.uwuapps.org/api/push/release`
   - **Content type**: `application/json`. It has to be this one.
   - **Secret**: the same `GITHUB_WEBHOOK_SECRET` as in Vercel.
   - **Which events would you like to trigger this webhook?**: pick **Let me select individual
     events**, untick **Pushes**, and tick **Releases**.
   - **Active**: ticked.
3. Click **Add webhook**. GitHub sends a test ping straight away. Under **Recent Deliveries** it
   should show a green tick and the response `{"ok":true,"pong":true}`. A 401 response means
   the secret doesn't match Vercel's (or Vercel hasn't been redeployed since).

From now on, publishing an `android-v*` release with its APK attached pushes the notification
(`release/README.md`). Drafts, pre-releases and releases without an APK are skipped, and so is
re-publishing a version older than the newest. **Recent Deliveries** shows each answer, with
the reason when nothing was sent.

## 6. Build the app with Firebase in it

```powershell
powershell -ExecutionPolicy Bypass -File android\build-apk.ps1
```

The build picks up `google-services.json` by itself, and says
`Firebase: google-services.json found, notifications included.` Install the new APK on your
phone.

## 7. Check it works

1. In the app, tap the bell in the Edge Tray and turn on both switches. When Android asks to
   allow notifications, tap **Allow**.
2. To test news, send yourself a message from the console:
   1. In the UwU Apps project, open **Messaging** (in the left menu under **Run**, or search
      for it).
   2. Click **New campaign** > **Notifications**.
   3. Type a title and some text, then click **Next**.
   4. **Target**: pick **Topic** and type `fixup-news`. Use the topic, not the app: the topic
      reaches only people who turned news on. Click **Next**.
   5. **Scheduling**: **Now**. Then click **Next** until **Additional options**.
   6. **Additional options** > **Android notification channel**: `news`.
   7. Click **Review** > **Publish**.
   8. Lock your phone. It should arrive within a minute.
3. To test new versions without making a release, open the webhook in GitHub, go to **Recent
   Deliveries**, and redeliver a past `release` delivery. Or wait for your next release.

Sending news later works the same way as step 2: **Topic** `fixup-news`, channel `news`.

## If something goes wrong

| What happens | What to do |
|---|---|
| The build stops with `No matching client found for package name 'org.uwuapps.fixup'` | `google-services.json` was downloaded before uwuFix was added. Download it again from **Project settings** > **Your apps** > **uwuFix**. |
| No bell in the Edge Tray | The APK was built without `google-services.json`. Check it's at `android\native\app\google-services.json`, then build again and reinstall. |
| "Notifications are off for uwuFix in Android's settings" | You said no to Android's prompt. Tap **Open Android's settings** under the switches, turn notifications on, and come back. |
| "Couldn't reach Firebase" when turning a switch on | The phone was offline, or has no Google Play services (some Huawei phones), which FCM needs. |
| The webhook shows `401 Bad signature` | The secret in GitHub and `GITHUB_WEBHOOK_SECRET` in Vercel differ, or Vercel wasn't redeployed after adding it. |
| The webhook shows `502` with `FIREBASE_SERVICE_ACCOUNT is not set` | Step 4 is missing or wasn't redeployed. |
| The webhook shows `502` with `FCM responded 403` | The service account is missing its role (step 3.3), or FCM's API is off (step 2). |
| The webhook shows `502` with `Google token responded 400: invalid_grant` | The key was deleted. Make a new one (step 3.4), replace the variable, and redeploy. |
| The webhook shows `400 Not JSON` | The webhook's content type is `application/x-www-form-urlencoded`. Edit it to `application/json`. |
