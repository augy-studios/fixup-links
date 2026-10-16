/*
 * Updates the app to its newest release on GitHub. A small window over the page that downloads
 * the APK, checks it, and hands it to Android's own installer, which asks "Do you want to update
 * this app?" as for any APK. Started three ways, all through start():
 *
 * - The site's update bar's Update (main-site/js/app-update.js), once main-site/api/app-release.js
 *   names a newer version than this one. That has already asked, so it downloads straight away.
 * - The Edge Tray's "Check for app updates" (CHECK): it looks first, says if this is the newest
 *   version, and asks before downloading one that isn't.
 * - The "new version is out" notification, tapped (MainActivity): a check, naming the version
 *   the push was about (VERSION), so the release just published is looked up fresh rather than
 *   from the site's few minutes of cache.
 *
 * Checks before anything is installed:
 * - The APK comes only from this repository's releases on GitHub (RELEASES).
 * - Its SHA-256 matches the checksum GitHub publishes for the file, when it has one.
 * - It's this app, with a higher versionCode than the one installed.
 * Android checks the rest: it only updates an app with an APK signed by the same key.
 *
 * Android 8 and later also want this app allowed to install apps, once, in its "Install unknown
 * apps" setting; once there's an update to install, this sends you there first. Android 8 to
 * 10 restart the app when it's allowed, which brings this window back with the setting on, and
 * it carries on from there.
 *
 * Not exported (AndroidManifest.xml): only this app opens it.
 */
package org.uwuapps.fixup;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.ref.WeakReference;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;

public class UpdateActivity extends Activity {
    private static final String TAG = "UwuFixUpdate";
    // The newest release, read from GitHub and cached by the site.
    private static final String LATEST = MainActivity.SITE + "/api/app-release";
    // Where its APK may come from: this repository's releases, and nowhere else.
    private static final String RELEASES =
            "https://github.com/augy-studios/fixup-links/releases/download/";
    // Only checking, so ask before downloading what it finds.
    private static final String EXTRA_CHECK = "org.uwuapps.fixup.update.CHECK";
    // The version a notification said is out, to look it up past the site's cache.
    private static final String EXTRA_VERSION = "org.uwuapps.fixup.update.VERSION";

    // The window on screen, for InstallStatus to report back to.
    private static WeakReference<UpdateActivity> sShowing = new WeakReference<>(null);

    private TextView mText;
    private ProgressBar mProgress;
    private Button mPrimary;
    private Button mSecondary;

    private Thread mWork;
    private volatile boolean mCancelled;
    private boolean mAskedToAllow;
    private boolean mCheckOnly;
    private String mExpected;
    // The update to install, once found and wanted: kept while you're in "Install unknown
    // apps", and for "Try again", so neither looks it up again.
    private Release mRelease;

    static void start(Context context, boolean check, String version) {
        Intent intent = new Intent(context, UpdateActivity.class)
                .putExtra(EXTRA_CHECK, check);
        if (version != null && version.matches("\\d+(\\.\\d+)*")) intent.putExtra(EXTRA_VERSION, version);
        if (!(context instanceof Activity)) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setFinishOnTouchOutside(false);
        buildWindow();
        sShowing = new WeakReference<>(this);
        mCheckOnly = getIntent().getBooleanExtra(EXTRA_CHECK, false);
        mExpected = getIntent().getStringExtra(EXTRA_VERSION);
        start();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Back from "Install unknown apps".
        if (mAskedToAllow && mWork == null) {
            mAskedToAllow = false;
            if (allowedToInstall()) start();
            else show("uwuFix wasn't allowed to install apps, so it can't update itself.",
                    "Try again", this::askToAllow, "Close", this::finish);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mCancelled = true;
        if (sShowing.get() == this) sShowing.clear();
    }

    // ---------- steps ----------

    private boolean allowedToInstall() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || getPackageManager().canRequestPackageInstalls();
    }

    private void askToAllow() {
        String found = mRelease != null ? "Version " + mRelease.version + " is out. " : "";
        show(found + "To update itself, uwuFix needs your OK to install apps. Turn on "
                + "\"Allow from this source\" on the next screen, then come back.",
                "Continue", () -> {
                    mAskedToAllow = true;
                    startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:" + getPackageName())));
                }, "Not now", this::finish);
    }

    // Looks for the update, or carries on with the one already found.
    private void start() {
        mCancelled = false;
        Release found = mRelease;
        progress(found != null ? "Downloading version " + found.version + "…"
                : mCheckOnly ? "Checking for updates…" : "Looking for the update…", -1);
        mWork = new Thread(() -> {
            try {
                Release release = found != null ? found : latest();
                if (release == null) {
                    ui(() -> show("You have the newest version, " + installedVersion() + ".",
                            "Close", this::finish, null, null));
                    return;
                }
                if (found == null && mCheckOnly) {
                    ui(() -> show("Version " + release.version + " is out. You have "
                                    + installedVersion() + ".",
                            "Update", () -> update(release), "Not now", this::finish));
                    return;
                }
                if (!allowedToInstall()) {
                    ui(() -> {
                        mRelease = release;
                        askToAllow();
                    });
                    return;
                }
                File apk = download(release);
                if (apk == null) return; // Cancelled.
                check(apk);
                ui(() -> progress("Opening Android's installer…", -1));
                install(apk);
            } catch (Problem p) {
                failed(p.getMessage());
            } catch (IOException | JSONException | NoSuchAlgorithmException | RuntimeException e) {
                Log.w(TAG, e);
                failed("Couldn't download the update. Check you're online, then try again.");
            } finally {
                ui(() -> mWork = null);
            }
        }, "update");
        mWork.start();
    }

    // "Update" on what a check found: on to downloading it, by way of "Install unknown apps"
    // if this app isn't allowed to install it yet.
    private void update(Release release) {
        mRelease = release;
        if (allowedToInstall()) start();
        else askToAllow();
    }

    // The newest release if it's newer than this app, or null.
    private Release latest() throws IOException, JSONException, Problem {
        // A version from a notification makes a URL of its own, which the site's cache hasn't
        // seen, so it's read from GitHub now rather than up to ten minutes ago.
        HttpURLConnection conn = open(mExpected == null ? LATEST : LATEST + "?v=" + mExpected);
        if (conn.getResponseCode() != 200) {
            throw new Problem("Couldn't find out what the newest version is. Try again later.");
        }
        JSONObject json;
        try (InputStream in = conn.getInputStream()) {
            json = new JSONObject(read(in));
        } finally {
            conn.disconnect();
        }
        String version = json.optString("version", "");
        if (version.isEmpty() || !newer(version, installedVersion())) return null;
        Release release = new Release(version, json.getString("apk"),
                json.optLong("size", -1), json.isNull("sha256") ? null : json.getString("sha256"));
        if (!release.apk.startsWith(RELEASES)) {
            throw new Problem("The update isn't on uwuFix's GitHub page, so it wasn't downloaded.");
        }
        return release;
    }

    // The APK, in this app's cache, or null if cancelled on the way.
    private File download(Release release) throws IOException, NoSuchAlgorithmException, Problem {
        File dir = new File(getCacheDir(), "update");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("No room for " + dir);
        File apk = new File(dir, "uwufix.apk");
        String label = "Downloading version " + release.version + "…";
        ui(() -> progress(label, 0));

        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        HttpURLConnection conn = open(release.apk);
        try {
            if (conn.getResponseCode() != 200) {
                throw new Problem("GitHub didn't send the update (" + conn.getResponseCode() + "). Try again later.");
            }
            long total = conn.getContentLength() > 0 ? conn.getContentLength() : release.size;
            try (InputStream in = new DigestInputStream(conn.getInputStream(), sha256);
                 OutputStream out = new FileOutputStream(apk)) {
                byte[] buf = new byte[16 * 1024];
                long done = 0;
                int lastPercent = -1;
                for (int n; (n = in.read(buf)) != -1; ) {
                    if (mCancelled) {
                        apk.delete();
                        return null;
                    }
                    out.write(buf, 0, n);
                    done += n;
                    int percent = total > 0 ? (int) Math.min(100, done * 100 / total) : -1;
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        String sizes = total > 0 ? " " + megabytes(done) + " of " + megabytes(total) : "";
                        ui(() -> progress(label + sizes, percent));
                    }
                }
            }
        } finally {
            conn.disconnect();
        }

        if (release.sha256 != null && !release.sha256.equalsIgnoreCase(hex(sha256.digest()))) {
            apk.delete();
            throw new Problem("The download doesn't match the file on GitHub. Try again.");
        }
        return apk;
    }

    // That the file is this app, and newer than the one installed.
    private void check(File apk) throws Problem {
        PackageInfo info = getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
        if (info == null || !getPackageName().equals(info.packageName)) {
            apk.delete();
            throw new Problem("The download isn't uwuFix, so it wasn't installed.");
        }
        if (versionCode(info) <= versionCode(installed())) {
            apk.delete();
            throw new Problem("The download isn't newer than this app, so it wasn't installed.");
        }
    }

    // Hands the APK to Android's installer. Its answer comes to InstallStatus: first that it
    // needs you to confirm, with the screen that asks, then whether it worked.
    private void install(File apk) throws IOException {
        PackageInstaller installer = getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(getPackageName());
        params.setSize(apk.length());
        int id = installer.createSession(params);
        try (PackageInstaller.Session session = installer.openSession(id)) {
            try (InputStream in = new FileInputStream(apk);
                 OutputStream out = session.openWrite("uwufix.apk", 0, apk.length())) {
                byte[] buf = new byte[64 * 1024];
                for (int n; (n = in.read(buf)) != -1; ) out.write(buf, 0, n);
                session.fsync(out);
            }
            // Mutable, for the installer to add its answer to. Explicit, to InstallStatus only.
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0);
            PendingIntent status = PendingIntent.getBroadcast(this, id,
                    new Intent(this, InstallStatus.class), flags);
            session.commit(status.getIntentSender());
        } catch (IOException | RuntimeException e) {
            installer.abandonSession(id);
            throw e;
        } finally {
            // The session has its own copy now.
            apk.delete();
        }
    }

    // The installer's answers. Not exported, so only the installer, through the PendingIntent
    // above, can send them: an exported one would start any screen another app handed it.
    public static class InstallStatus extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
            UpdateActivity showing = sShowing.get();
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                if (confirm == null) return;
                // Started while the update window is still on screen, so Android lets it open.
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(confirm);
            } else if (status == PackageInstaller.STATUS_SUCCESS) {
                // Android stops the app to replace it, so this rarely runs.
                if (showing != null) showing.finish();
            } else if (status == PackageInstaller.STATUS_FAILURE_ABORTED) {
                // "Cancel" on Android's own screen.
                if (showing != null) showing.finish();
            } else {
                String why = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                Log.w(TAG, "Install failed: " + status + " " + why);
                String message = status == PackageInstaller.STATUS_FAILURE_CONFLICT
                        || status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE
                        ? "Android wouldn't install the update over this app. Uninstall uwuFix, then install it from GitHub."
                        : status == PackageInstaller.STATUS_FAILURE_STORAGE
                        ? "There isn't room on this phone for the update."
                        : "Android couldn't install the update. Try again.";
                if (showing != null) showing.failed(message);
                else Toast.makeText(context, message, Toast.LENGTH_LONG).show();
            }
        }
    }

    // ---------- the window ----------

    private void buildWindow() {
        int pad = dp(24);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(pad, pad, pad, dp(12));
        box.setMinimumWidth(dp(280));

        TextView title = new TextView(this);
        title.setText("Update uwuFix");
        title.setTextAppearance(this, android.R.style.TextAppearance_DeviceDefault_Large);
        box.addView(title);

        mText = new TextView(this);
        mText.setTextAppearance(this, android.R.style.TextAppearance_DeviceDefault_Medium);
        mText.setPadding(0, dp(16), 0, dp(12));
        box.addView(mText);

        mProgress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        mProgress.setMax(100);
        box.addView(mProgress, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        LinearLayout buttons = new LinearLayout(this);
        buttons.setGravity(Gravity.END);
        buttons.setPadding(0, dp(12), 0, 0);
        mSecondary = new Button(this, null, android.R.attr.buttonBarButtonStyle);
        mPrimary = new Button(this, null, android.R.attr.buttonBarButtonStyle);
        buttons.addView(mSecondary);
        buttons.addView(mPrimary);
        box.addView(buttons, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        setContentView(box);
    }

    // A step under way: percent from 0 to 100, or -1 while there's no telling.
    private void progress(String text, int percent) {
        mText.setText(text);
        mProgress.setVisibility(View.VISIBLE);
        mProgress.setIndeterminate(percent < 0);
        if (percent >= 0) mProgress.setProgress(percent);
        button(mPrimary, null, null);
        button(mSecondary, "Cancel", () -> {
            mCancelled = true;
            finish();
        });
    }

    // A message and up to two buttons, with nothing under way.
    private void show(String text, String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        mText.setText(text);
        mProgress.setVisibility(View.GONE);
        button(mPrimary, primary, onPrimary);
        button(mSecondary, secondary, onSecondary);
    }

    private void failed(String message) {
        ui(() -> show(message, "Try again", this::start, "Close", this::finish));
    }

    private static void button(Button button, String label, Runnable onClick) {
        button.setVisibility(label == null ? View.GONE : View.VISIBLE);
        button.setText(label);
        button.setOnClickListener(onClick == null ? null : v -> onClick.run());
    }

    private void ui(Runnable step) {
        runOnUiThread(() -> {
            if (!isFinishing() && !isDestroyed()) step.run();
        });
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    // ---------- helpers ----------

    private static final class Release {
        final String version;
        final String apk;
        final long size;
        final String sha256;

        Release(String version, String apk, long size, String sha256) {
            this.version = version;
            this.apk = apk;
            this.size = size;
            this.sha256 = sha256;
        }
    }

    // A message for the window, not a stack trace.
    private static final class Problem extends Exception {
        Problem(String message) {
            super(message);
        }
    }

    private HttpURLConnection open(String url) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(15_000);
        conn.setReadTimeout(30_000);
        conn.setRequestProperty("User-Agent", "uwuFix for Android " + installedVersion());
        // GitHub sends the APK on from its own address to its file storage's, both https.
        conn.setInstanceFollowRedirects(true);
        return conn;
    }

    private PackageInfo installed() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0);
        } catch (PackageManager.NameNotFoundException e) {
            throw new IllegalStateException(e); // This app is always installed.
        }
    }

    private String installedVersion() {
        return installed().versionName;
    }

    @SuppressWarnings("deprecation")
    private static long versionCode(PackageInfo info) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode;
    }

    // Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same
    // as newer() in main-site/api/app-release.js.
    static boolean newer(String a, String b) {
        String[] x = a.split("\\.");
        String[] y = b.split("\\.");
        for (int i = 0; i < Math.max(x.length, y.length); i++) {
            int d = number(x, i) - number(y, i);
            if (d != 0) return d > 0;
        }
        return false;
    }

    private static int number(String[] parts, int i) {
        try {
            return i < parts.length ? Integer.parseInt(parts[i].replaceAll("\\D", "")) : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String read(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8 * 1024];
        for (int n; (n = in.read(buf)) != -1; ) out.write(buf, 0, n);
        return out.toString("UTF-8");
    }

    private static String hex(byte[] bytes) {
        StringBuilder s = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) s.append(String.format(Locale.ROOT, "%02x", b));
        return s.toString();
    }

    private static String megabytes(long bytes) {
        return String.format(Locale.ROOT, "%.1f MB", bytes / 1_000_000.0);
    }
}
