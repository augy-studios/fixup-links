/*
 * The updates page: updates the app to its newest release on GitHub, and shows what's new in every
 * release. Opened by the app's update bar (flutter/lib/features/update/update_bar.dart) when
 * main-site/api/app-release.js names a newer version than this one, by the Edge Tray's "Check for
 * app updates" (org.uwuapps.fixup://update/check, CHECK: it looks first, says if this is the
 * newest version, and asks before downloading one that isn't), and by a tapped "new version is
 * out" notification (MainActivity: a check naming the version the push was about, VERSION, so the
 * release just published is looked up past the site's few minutes of cache).
 *
 * It downloads the APK, checks it, and hands it to Android's own installer, which asks "Do you
 * want to update this app?" as for any APK. Checks before anything is installed:
 * - The APK comes only from this repository's releases on GitHub (RELEASES).
 * - Its SHA-256 matches the checksum GitHub publishes for the file, when it has one.
 * - It's this app, with a higher versionCode than the one installed.
 * Android checks the rest: it only updates an app with an APK signed by the same key.
 *
 * Android 8 and later also want this app allowed to install apps, once, in its "Install unknown
 * apps" setting; once there's an update to install, this sends you there first.
 *
 * Samsung's Auto Blocker (One UI 6 and later) is a second gate: while it's on, only apps from the
 * Play Store or Galaxy Store install, and Android's installer doesn't say so when it stops an
 * update. So on a Samsung device on Android 14 or later, an update that fails or is cancelled, or
 * that the installer never answers for, gets an explanation of Auto Blocker and a button to
 * Security settings, and Try again carries on with the same version.
 *
 * A page of its own in Material 3 (update_activity.xml), its colours from the phone's wallpaper on
 * Android 12 and later (Material You), light or dark as the phone is: what's happening at the top,
 * with Material 3 Expressive's wavy progress bar (WavyProgressView) while it checks and while it
 * downloads, and under it a changelog of every release on a timeline, with what's new in each
 * from its notes on GitHub (main-site/api/app-release.js's `history`, announcements/'s
 * release notes as written), as cards by heading. The release you'd get opens by itself, or the
 * one installed when there's nothing newer.
 *
 * As sgbus-timings' updater, from which it's taken. Not in the Google Play build, which Play
 * updates (src/play/AndroidManifest.xml).
 */
package org.uwuapps.fixup;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.transition.AutoTransition;
import android.transition.TransitionManager;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.ColorUtils;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.widget.NestedScrollView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.color.DynamicColors;
import com.google.android.material.color.MaterialColors;

import org.json.JSONArray;
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
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

public class UpdateActivity extends AppCompatActivity {
    private static final String TAG = "FixupUpdate";
    // The newest release, read from GitHub and cached by the site.
    private static final String LATEST = MainActivity.SITE + "/api/app-release";
    // Where its APK may come from: this repository's releases, and nowhere else.
    private static final String RELEASES =
            "https://github.com/augy-studios/fixup-links/releases/download/";
    // The Edge Tray's "Check for app updates", rather than the update bar's Update.
    private static final String CHECK = "/check";
    // The version a notification said is out, to look it up past the site's cache.
    private static final String EXTRA_VERSION = "org.uwuapps.fixup.update.VERSION";
    // A Samsung device on One UI 6 (Android 14) or later, where Auto Blocker may be on.
    private static final boolean AUTO_BLOCKER = "samsung".equalsIgnoreCase(Build.MANUFACTURER)
            && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE;
    // How long, on such a device, to wait for the installer to answer before taking its silence
    // as Auto Blocker. An update you've confirmed answers well within it, by restarting the app.
    private static final long NO_ANSWER_MS = 30_000;

    // Where the releases are listed, for the changelog's GitHub button with nothing to read.
    private static final String RELEASES_PAGE = "https://github.com/augy-studios/fixup-links/releases";
    // Debuggable builds only, never a release: a file in this app's cache to read the release
    // from instead of the site, and a version to be, so each step of the page can be seen on an
    // emulator (android/README.md, "The updater's page").
    private static final String EXTRA_TEST_JSON = "org.uwuapps.fixup.update.TEST_JSON";
    private static final String EXTRA_TEST_VERSION = "org.uwuapps.fixup.update.TEST_VERSION";
    // A group's first few items, the rest under Show all.
    private static final int FIRST_ITEMS = 4;

    // The window on screen, for InstallStatus to report back to.
    private static WeakReference<UpdateActivity> sShowing = new WeakReference<>(null);

    private TextView mTitle;
    private TextView mSubtitle;
    private MaterialCardView mStatus;
    private FrameLayout mStatusTile;
    private ImageView mStatusIcon;
    private TextView mText;
    private WavyProgressView mProgress;
    private MaterialButton mPrimary;
    private MaterialButton mSecondary;
    private LinearLayout mContent;
    private LinearLayout mReleases;
    // The newest releases and what's new in each, newest first, once read: drawn as the
    // changelog. Empty from a site from before they were sent.
    private volatile List<Notes> mHistory = Collections.emptyList();

    private Thread mWork;
    private volatile boolean mCancelled;
    private boolean mAskedToAllow;
    // Sent to Security settings to turn Auto Blocker off.
    private boolean mAskedToUnblock;
    // Handed to the installer, with no final answer from it yet.
    private boolean mInstalling;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final Runnable mNoAnswer = this::autoBlocked;
    // Only checking, so ask before downloading what it finds.
    private boolean mCheckOnly;
    private String mExpected;
    // The update to install, once found and wanted: kept while you're in "Install unknown
    // apps", and for "Try again", so neither looks it up again.
    private Release mRelease;

    // The update bar's Update (check false: straight to downloading), or the Edge Tray's Check
    // for app updates (check true), from FixupPlugin.update.
    static void start(Activity activity, boolean check, String version) {
        if (check) {
            check(activity, version);
            return;
        }
        activity.startActivity(new Intent(activity, UpdateActivity.class).setData(Uri.parse("org.uwuapps.fixup://update")));
    }

    // A check for the version a tapped notification named (MainActivity).
    static void check(Context context, String version) {
        Intent intent = new Intent(context, UpdateActivity.class)
                .setData(Uri.parse("org.uwuapps.fixup://update" + CHECK));
        if (version != null && version.matches("\\d+(\\.\\d+)*")) intent.putExtra(EXTRA_VERSION, version);
        if (!(context instanceof Activity)) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // The wallpaper's colours over the app's green, where Android has them (12 and later).
        DynamicColors.applyToActivityIfAvailable(this);
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
        buildWindow();
        sShowing = new WeakReference<>(this);
        Uri link = getIntent().getData();
        mCheckOnly = link != null && CHECK.equals(link.getPath());
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
            else problem("Not allowed to update",
                    "uwuFix wasn't allowed to install apps, so it can't update itself.",
                    "Try again", this::askToAllow, "Close", this::finish);
        } else if (mAskedToUnblock && mWork == null) {
            // Back from Security settings, with no telling whether Auto Blocker is off now.
            mAskedToUnblock = false;
            show("Ready to try again", "If Auto Blocker is off now, tap Try again to install " + which() + ".",
                    "Try again", this::start, "Not now", this::finish);
        } else if (mInstalling) {
            // Back from the installer's screen: waiting for its answer again.
            waitForAnswer();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mHandler.removeCallbacks(mNoAnswer);
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
        show("Allow updates", found + "To update itself, uwuFix needs your OK to install apps. Turn on "
                + "\"Allow from this source\" on the next screen, then come back.",
                "Continue", () -> {
                    mAskedToAllow = true;
                    startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:" + getPackageName())));
                }, "Not now", this::finish);
    }

    // Samsung's Auto Blocker, the likeliest reason an update didn't install on a Samsung device
    // that allows this app to install apps. Nothing public says whether it's on, so this says
    // "probably", and Try again carries on with the same version.
    private void autoBlocked() {
        mInstalling = false;
        mHandler.removeCallbacks(mNoAnswer);
        problem("Update blocked", capitalised(which()) + " didn't install. Samsung's Auto Blocker probably stopped it: it "
                + "only lets apps from the Play Store or Galaxy Store install, even with SG Bus "
                + "Timings allowed to install apps.\n\nTurn it off in Settings > Security and "
                + "privacy > Auto Blocker, then come back and tap Try again. It switches itself "
                + "back on after 30 minutes if \"Turn on automatically\" is on; if not, turn it "
                + "back on there once you've updated.",
                "Open settings", this::openSecuritySettings, "Not now", this::finish);
    }

    // Security and privacy, where Auto Blocker is. Samsung publishes no way to open Auto
    // Blocker's own page, so this opens the one above it, or Settings if even that's missing.
    private void openSecuritySettings() {
        mAskedToUnblock = true;
        try {
            startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS));
        } catch (ActivityNotFoundException e) {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    // Handed to the installer: on a Samsung device, its silence for NO_ANSWER_MS is taken as
    // Auto Blocker. Elsewhere the window waits as long as it takes, as before.
    private void waitForAnswer() {
        mHandler.removeCallbacks(mNoAnswer);
        if (AUTO_BLOCKER) mHandler.postDelayed(mNoAnswer, NO_ANSWER_MS);
    }

    // The installer answered: done, or only asking you first (PENDING_USER_ACTION).
    private void heard(boolean done) {
        mHandler.removeCallbacks(mNoAnswer);
        if (done) mInstalling = false;
    }

    private String which() {
        return mRelease != null ? "version " + mRelease.version : "the update";
    }

    private static String capitalised(String text) {
        return Character.toUpperCase(text.charAt(0)) + text.substring(1);
    }

    // Looks for the update, or carries on with the one already found.
    private void start() {
        mCancelled = false;
        mInstalling = false;
        mHandler.removeCallbacks(mNoAnswer);
        Release found = mRelease;
        progress(found != null ? "Updating" : "Checking for updates",
                found != null ? "Downloading version " + found.version + "…"
                : mCheckOnly ? "Checking for updates…" : "Looking for the update…", -1);
        mWork = new Thread(() -> {
            try {
                Release release = found != null ? found : latest();
                if (found == null) ui(this::drawChangelog);
                if (release == null) {
                    ui(() -> show("You're up to date", null,
                            "GitHub", R.drawable.update_ic_github, () -> browse(pageOf(installedVersion())),
                            "Close", this::finish));
                    return;
                }
                if (found == null && mCheckOnly) {
                    ui(() -> show("Update available", null,
                            "Update to " + release.version, R.drawable.update_ic_download, () -> update(release),
                            "Not now", this::finish));
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
                ui(() -> {
                    // Kept on a Samsung device for Try again after Auto Blocker, which then
                    // carries on with this version rather than looking again.
                    if (AUTO_BLOCKER) mRelease = release;
                    progress("Updating", "Opening Android's installer…", -1);
                });
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
        JSONObject json;
        File test = testFile();
        if (test != null) {
            try (InputStream in = new FileInputStream(test)) {
                json = new JSONObject(read(in));
            }
        } else {
            HttpURLConnection conn = open(mExpected == null ? LATEST : LATEST + "?v=" + mExpected);
            if (conn.getResponseCode() != 200) {
                throw new Problem("Couldn't find out what the newest version is. Try again later.");
            }
            try (InputStream in = conn.getInputStream()) {
                json = new JSONObject(read(in));
            } finally {
                conn.disconnect();
            }
        }
        mHistory = Notes.listOf(json.optJSONArray("history"));
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
        ui(() -> progress("Updating", label, 0));

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
                        String sizes = total > 0 ? "\n" + megabytes(done) + " of " + megabytes(total) : "";
                        ui(() -> progress("Updating", label + sizes, percent));
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
            // Waiting from before the commit, so even the quickest answer comes after it.
            ui(() -> {
                mInstalling = true;
                waitForAnswer();
            });
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
            // An answer, so not silence. Waiting starts again when you're back from the screen
            // that asks.
            if (showing != null) showing.heard(status != PackageInstaller.STATUS_PENDING_USER_ACTION);
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
                // "Cancel" on Android's own screen. Also what a screen that ends without
                // Install answers, as Samsung's does when Auto Blocker stops it, so there the
                // window stays to say so.
                Log.i(TAG, "Install aborted: " + intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE));
                if (showing != null && AUTO_BLOCKER) showing.autoBlocked();
                else if (showing != null) showing.finish();
            } else {
                String why = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                Log.w(TAG, "Install failed: " + status + " " + why);
                boolean conflict = status == PackageInstaller.STATUS_FAILURE_CONFLICT
                        || status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE;
                boolean storage = status == PackageInstaller.STATUS_FAILURE_STORAGE;
                if (AUTO_BLOCKER && !conflict && !storage) {
                    if (showing != null) showing.autoBlocked();
                    else Toast.makeText(context, "Samsung's Auto Blocker probably stopped the update. Turn it "
                            + "off in Settings > Security and privacy > Auto Blocker, then update again.",
                            Toast.LENGTH_LONG).show();
                    return;
                }
                String message = conflict
                        ? "Android wouldn't install the update over this app. Uninstall uwuFix, then install it from GitHub."
                        : storage
                        ? "There isn't room on this phone for the update."
                        : "Android couldn't install the update. Try again.";
                if (showing != null) showing.failed(message);
                else Toast.makeText(context, message, Toast.LENGTH_LONG).show();
            }
        }
    }

    // ---------- the page ----------

    private void buildWindow() {
        setContentView(R.layout.update_activity);
        mTitle = findViewById(R.id.update_title);
        mSubtitle = findViewById(R.id.update_subtitle);
        mStatus = findViewById(R.id.update_status);
        mStatusTile = findViewById(R.id.update_status_tile);
        mStatusIcon = findViewById(R.id.update_status_icon);
        mText = findViewById(R.id.update_message);
        mProgress = findViewById(R.id.update_progress);
        mPrimary = findViewById(R.id.update_primary);
        mSecondary = findViewById(R.id.update_secondary);
        mContent = findViewById(R.id.update_content);
        mReleases = findViewById(R.id.update_releases);
        mSubtitle.setText("uwuFix · v" + installedVersion());

        // The buttons over the bottom of the page, the changelog fading out under them, and the
        // page scrolling far enough for its end to come up above them.
        int surface = color(com.google.android.material.R.attr.colorSurface);
        View buttons = findViewById(R.id.update_buttons);
        buttons.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] {
                surface, surface, ColorUtils.setAlphaComponent(surface, 0)}));
        buttons.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            if (b - t != ob - ot) mContent.setPadding(mContent.getPaddingLeft(), mContent.getPaddingTop(),
                    mContent.getPaddingRight(), b - t);
        });
        // Edge to edge: the page under the status and navigation bars, its words and buttons not.
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.update_root), (v, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            mContent.setPadding(dp(20) + bars.left, dp(24) + bars.top, dp(20) + bars.right, mContent.getPaddingBottom());
            buttons.setPadding(dp(20) + bars.left, dp(32), dp(20) + bars.right, dp(16) + bars.bottom);
            View statusBar = findViewById(R.id.update_status_bar);
            statusBar.getLayoutParams().height = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top;
            statusBar.requestLayout();
            return WindowInsetsCompat.CONSUMED;
        });
        filled(mSecondary, false);
    }

    // A step under way: percent from 0 to 100, or -1 while there's no telling.
    private void progress(String title, String text, int percent) {
        mTitle.setText(title);
        status(text, R.drawable.update_ic_download, false);
        mProgress.setIndeterminate(percent < 0);
        if (percent >= 0) mProgress.setProgress(percent, true);
        mProgress.setVisibility(View.VISIBLE);
        button(mPrimary, null, 0, null);
        button(mSecondary, "Cancel", 0, () -> {
            mCancelled = true;
            finish();
        });
    }

    // A title, a message (or null for none) and up to two buttons, with nothing under way.
    private void show(String title, String text, String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        show(title, text, primary, 0, onPrimary, secondary, onSecondary);
    }

    private void show(String title, String text, String primary, int icon, Runnable onPrimary, String secondary, Runnable onSecondary) {
        mTitle.setText(title);
        status(text, R.drawable.update_ic_settings, false);
        mProgress.setVisibility(View.GONE);
        button(mPrimary, primary, icon, onPrimary);
        button(mSecondary, secondary, 0, onSecondary);
        // GitHub, on the changelog, is a way to read more rather than a step on: outlined, as
        // Close is, rather than filled.
        filled(mPrimary, icon != R.drawable.update_ic_github);
    }

    // The same for something that went wrong, its icon on the error colours.
    private void problem(String title, String text, String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        show(title, text, primary, onPrimary, secondary, onSecondary);
        status(text, R.drawable.update_ic_alert, true);
    }

    // The card at the top: a download under way, something for you to do, or a problem.
    private void status(String text, int icon, boolean problem) {
        mStatus.setVisibility(text == null ? View.GONE : View.VISIBLE);
        mText.setText(text);
        mStatusTile.setBackground(rounded(color(problem
                ? com.google.android.material.R.attr.colorErrorContainer
                : com.google.android.material.R.attr.colorPrimaryContainer), dp(12)));
        mStatusIcon.setImageResource(icon);
        mStatusIcon.setImageTintList(ColorStateList.valueOf(color(problem
                ? com.google.android.material.R.attr.colorOnErrorContainer
                : com.google.android.material.R.attr.colorOnPrimaryContainer)));
    }

    private void failed(String message) {
        ui(() -> {
            mInstalling = false;
            mHandler.removeCallbacks(mNoAnswer);
            problem("Couldn't update", message, "Try again", this::start, "Close", this::finish);
        });
    }

    private void button(MaterialButton button, String label, int icon, Runnable onClick) {
        button.setVisibility(label == null ? View.GONE : View.VISIBLE);
        button.setText(label);
        if (icon != 0) button.setIconResource(icon);
        else button.setIcon(null);
        button.setOnClickListener(onClick == null ? null : v -> onClick.run());
    }

    // A button filled in the theme's primary colour, or outlined over the page, opaque so the
    // changelog doesn't show through its words.
    private void filled(MaterialButton button, boolean filled) {
        int over = color(com.google.android.material.R.attr.colorSurfaceContainerLow);
        int ink = color(filled ? com.google.android.material.R.attr.colorOnPrimary : com.google.android.material.R.attr.colorOnSurface);
        button.setBackgroundTintList(ColorStateList.valueOf(filled ? color(androidx.appcompat.R.attr.colorPrimary) : over));
        button.setTextColor(ink);
        button.setIconTint(ColorStateList.valueOf(ink));
        button.setIconGravity(MaterialButton.ICON_GRAVITY_TEXT_START);
        button.setStrokeWidth(filled ? 0 : dp(1));
        button.setStrokeColor(ColorStateList.valueOf(color(com.google.android.material.R.attr.colorOutlineVariant)));
    }

    private void ui(Runnable step) {
        runOnUiThread(() -> {
            if (!isFinishing() && !isDestroyed()) step.run();
        });
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    // A colour of the page's theme, the wallpaper's where Android has them.
    private int color(int attr) {
        return MaterialColors.getColor(this, attr, 0);
    }

    private static GradientDrawable rounded(int color, int radius) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(radius);
        return shape;
    }

    private static GradientDrawable dot(int fill, int stroke, int width) {
        GradientDrawable shape = new GradientDrawable();
        shape.setShape(GradientDrawable.OVAL);
        shape.setColor(fill);
        if (width > 0) shape.setStroke(width, stroke);
        return shape;
    }

    private void browse(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, "No browser to open " + url, Toast.LENGTH_LONG).show();
        }
    }

    // ---------- the changelog ----------

    // Each release on a timeline, newest first: the ones newer than this app marked New, this
    // one Installed, and "Earlier releases" before the rest. The one you'd get opens by itself,
    // or this one when there's nothing newer.
    private void drawChangelog() {
        mReleases.removeAllViews();
        List<Notes> history = mHistory;
        String installed = installedVersion();
        int open = -1;
        for (int i = 0; i < history.size() && open < 0; i++) {
            if (!newer(history.get(i).version, installed)) open = i;
        }
        if (!history.isEmpty() && newer(history.get(0).version, installed)) open = 0;
        boolean labelled = false;
        LayoutInflater inflater = LayoutInflater.from(this);
        for (int i = 0; i < history.size(); i++) {
            Notes notes = history.get(i);
            boolean isNew = newer(notes.version, installed);
            boolean isInstalled = notes.version.equals(installed);
            if (!isNew && !isInstalled && !labelled) {
                labelled = true;
                View label = inflater.inflate(R.layout.update_label, mReleases, false);
                ((TextView) label.findViewById(R.id.label_text)).setText("Earlier releases");
                mReleases.addView(label);
            }
            mReleases.addView(release(inflater, notes, isNew, isInstalled, i == open, i == history.size() - 1));
        }
    }

    private View release(LayoutInflater inflater, Notes notes, boolean isNew, boolean isInstalled, boolean opened, boolean last) {
        View row = inflater.inflate(R.layout.update_release, mReleases, false);
        int primary = color(androidx.appcompat.R.attr.colorPrimary);
        int muted = color(com.google.android.material.R.attr.colorOutline);
        // The release you'd get, or have, as a ring; the rest as a small dot.
        View dot = row.findViewById(R.id.release_dot);
        boolean ring = isNew || isInstalled;
        dot.setBackground(dot(ring ? color(com.google.android.material.R.attr.colorSurface) : muted, primary, ring ? dp(3) : 0));
        FrameLayout.LayoutParams size = (FrameLayout.LayoutParams) dot.getLayoutParams();
        size.width = size.height = dp(ring ? 16 : 10);
        size.topMargin = dp(ring ? 7 : 10);
        if (last) row.findViewById(R.id.release_line).setVisibility(View.INVISIBLE);

        ((TextView) row.findViewById(R.id.release_version)).setText("v" + notes.version);
        TextView chip = row.findViewById(R.id.release_chip);
        if (ring) {
            chip.setVisibility(View.VISIBLE);
            chip.setText(isNew ? "New" : "Installed");
            chip.setBackground(rounded(color(isNew ? androidx.appcompat.R.attr.colorPrimary
                    : com.google.android.material.R.attr.colorPrimaryContainer), dp(16)));
            chip.setTextColor(color(isNew ? com.google.android.material.R.attr.colorOnPrimary
                    : com.google.android.material.R.attr.colorOnPrimaryContainer));
        }
        int count = 0;
        for (Group group : notes.groups) count += group.items.size();
        String when = dateText(notes.date);
        String much = count == 0 ? null : count + (count == 1 ? " change" : " changes");
        ((TextView) row.findViewById(R.id.release_meta)).setText(when != null && much != null
                ? when + " · " + much : when != null ? when : much != null ? much : "");

        LinearLayout body = row.findViewById(R.id.release_body);
        TextView summary = row.findViewById(R.id.release_summary);
        summary.setText(notes.summary);
        summary.setVisibility(notes.summary.isEmpty() ? View.GONE : View.VISIBLE);
        for (int g = 0; g < notes.groups.size(); g++) body.addView(group(inflater, body, notes.groups.get(g), g));

        View head = row.findViewById(R.id.release_head);
        ImageView chevron = row.findViewById(R.id.release_chevron);
        boolean anything = !notes.groups.isEmpty() || !notes.summary.isEmpty();
        chevron.setVisibility(anything ? View.VISIBLE : View.GONE);
        setOpen(body, chevron, head, notes, opened && anything, false);
        if (anything) head.setOnClickListener(v -> setOpen(body, chevron, head, notes, body.getVisibility() != View.VISIBLE, true));
        return row;
    }

    private void setOpen(View body, ImageView chevron, View head, Notes notes, boolean open, boolean animate) {
        if (animate) TransitionManager.beginDelayedTransition(mContent, new AutoTransition().setDuration(200));
        body.setVisibility(open ? View.VISIBLE : View.GONE);
        if (animate) chevron.animate().rotation(open ? 180 : 0).setDuration(200).start();
        else chevron.setRotation(open ? 180 : 0);
        head.setContentDescription("Version " + notes.version + (open ? ", what's new shown" : ", tap for what's new"));
    }

    // A group's card, its colours by its place: primary, tertiary, then secondary, round again.
    private View group(LayoutInflater inflater, ViewGroup parent, Group group, int index) {
        View card = inflater.inflate(R.layout.update_group, parent, false);
        int[][] tones = {
                {com.google.android.material.R.attr.colorPrimaryContainer, com.google.android.material.R.attr.colorOnPrimaryContainer, androidx.appcompat.R.attr.colorPrimary},
                {com.google.android.material.R.attr.colorTertiaryContainer, com.google.android.material.R.attr.colorOnTertiaryContainer, com.google.android.material.R.attr.colorTertiary},
                {com.google.android.material.R.attr.colorSecondaryContainer, com.google.android.material.R.attr.colorOnSecondaryContainer, com.google.android.material.R.attr.colorSecondary},
        };
        int[] tone = tones[index % tones.length];
        card.findViewById(R.id.group_tile).setBackground(rounded(color(tone[0]), dp(10)));
        ImageView icon = card.findViewById(R.id.group_icon);
        icon.setImageResource(groupIcon(group.title));
        icon.setImageTintList(ColorStateList.valueOf(color(tone[1])));
        ((TextView) card.findViewById(R.id.group_title)).setText(group.title);
        TextView count = card.findViewById(R.id.group_count);
        count.setText(String.valueOf(group.items.size()));
        count.setBackground(rounded(color(com.google.android.material.R.attr.colorSurfaceContainerHighest), dp(14)));

        LinearLayout items = card.findViewById(R.id.group_items);
        int accent = color(tone[2]);
        for (int i = 0; i < group.items.size(); i++) {
            View item = inflater.inflate(R.layout.update_item, items, false);
            item.findViewById(R.id.item_dot).setBackground(dot(accent, 0, 0));
            String[] it = group.items.get(i);
            TextView title = item.findViewById(R.id.item_title);
            TextView text = item.findViewById(R.id.item_text);
            title.setText(it[0].isEmpty() ? capitalised(it[1]) : it[0]);
            text.setText(it[1].isEmpty() ? "" : capitalised(it[1]));
            text.setVisibility(it[0].isEmpty() || it[1].isEmpty() ? View.GONE : View.VISIBLE);
            if (i >= FIRST_ITEMS) item.setVisibility(View.GONE);
            items.addView(item);
        }
        if (group.items.size() > FIRST_ITEMS) {
            View more = card.findViewById(R.id.group_more);
            more.setVisibility(View.VISIBLE);
            ((TextView) card.findViewById(R.id.group_more_text)).setText("Show all (" + group.items.size() + ")");
            more.setOnClickListener(v -> {
                TransitionManager.beginDelayedTransition(mContent, new AutoTransition().setDuration(200));
                for (int i = 0; i < items.getChildCount(); i++) items.getChildAt(i).setVisibility(View.VISIBLE);
                more.setVisibility(View.GONE);
            });
        }
        return card;
    }

    // An icon for a group by its heading in the notes: the app's own, as the site has them.
    private static int groupIcon(String title) {
        String t = title.toLowerCase(Locale.ROOT);
        if (t.contains("android") || t.contains("phone")) return R.drawable.update_ic_phone;
        if (t.contains("desktop") || t.contains("windows") || t.contains("linux") || t.contains("mac")) return R.drawable.update_ic_terminal;
        if (t.contains("history") || t.contains("sync") || t.contains("devices")) return R.drawable.update_ic_star;
        if (t.contains("notification") || t.contains("news")) return R.drawable.update_ic_bell;
        if (t.contains("look") || t.contains("theme") || t.contains("colour")) return R.drawable.update_ic_sun;
        if (t.contains("tour") || t.contains("website") || t.contains("site")) return R.drawable.update_ic_eye;
        if (t.contains("setting") || t.contains("update")) return R.drawable.update_ic_settings;
        if (t.contains("link") || t.contains("fix") || t.contains("tracker") || t.contains("embed")) return R.drawable.update_ic_check;
        return R.drawable.update_ic_star;
    }

    // When a release came out: Today, Yesterday, 3 days ago, or 23 Oct 2026, by Singapore's clock.
    private static String dateText(String iso) {
        if (iso == null || iso.isEmpty()) return null;
        SimpleDateFormat in = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT);
        in.setTimeZone(TimeZone.getTimeZone("UTC"));
        Date date;
        try {
            date = in.parse(iso);
        } catch (ParseException e) {
            return null;
        }
        TimeZone sg = TimeZone.getTimeZone("Asia/Singapore");
        long days = dayNumber(new Date(), sg) - dayNumber(date, sg);
        if (days <= 0) return "Today";
        if (days == 1) return "Yesterday";
        if (days < 7) return days + " days ago";
        SimpleDateFormat out = new SimpleDateFormat("d MMM yyyy", Locale.UK);
        out.setTimeZone(sg);
        return out.format(date);
    }

    // Days since 1970 by a time zone's calendar, to count whole days between two moments.
    private static long dayNumber(Date date, TimeZone zone) {
        return Math.floorDiv(date.getTime() + zone.getOffset(date.getTime()), 86_400_000L);
    }

    // A release's page on GitHub, or the list of them.
    private String pageOf(String version) {
        for (Notes notes : mHistory) if (notes.version.equals(version) && !notes.page.isEmpty()) return notes.page;
        return RELEASES_PAGE;
    }

    // What's new in a release, from main-site/api/app-release.js's `history`.
    private static final class Notes {
        final String version;
        final String date;
        final String summary;
        final String page;
        final List<Group> groups = new ArrayList<>();

        Notes(JSONObject json) {
            version = json.optString("version", "");
            date = json.optString("date", "");
            summary = json.optString("summary", "");
            page = json.optString("page", "");
            JSONArray notes = json.optJSONArray("notes");
            for (int i = 0; notes != null && i < notes.length(); i++) {
                JSONObject group = notes.optJSONObject(i);
                if (group != null) groups.add(new Group(group));
            }
        }

        static List<Notes> listOf(JSONArray history) {
            List<Notes> list = new ArrayList<>();
            for (int i = 0; history != null && i < history.length(); i++) {
                JSONObject release = history.optJSONObject(i);
                if (release != null && !release.optString("version", "").isEmpty()) list.add(new Notes(release));
            }
            return list;
        }
    }

    private static final class Group {
        final String title;
        // Each { title, text }, either of which may be empty.
        final List<String[]> items = new ArrayList<>();

        Group(JSONObject json) {
            title = json.optString("title", "What's new");
            JSONArray list = json.optJSONArray("items");
            for (int i = 0; list != null && i < list.length(); i++) {
                JSONObject item = list.optJSONObject(i);
                if (item != null) items.add(new String[] {item.optString("title", ""), item.optString("text", "")});
            }
        }
    }

    // ---------- seeing it on an emulator ----------

    private boolean debuggable() {
        return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    // EXTRA_TEST_JSON's file, in this app's cache, in a debuggable build only.
    private File testFile() {
        String name = debuggable() ? getIntent().getStringExtra(EXTRA_TEST_JSON) : null;
        if (name == null || !name.matches("[\\w.-]+")) return null;
        File file = new File(getCacheDir(), name);
        return file.isFile() ? file : null;
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

    // This app's version, or in a debuggable build one to be (EXTRA_TEST_VERSION).
    private String installedVersion() {
        String test = debuggable() ? getIntent().getStringExtra(EXTRA_TEST_VERSION) : null;
        return test != null && test.matches("\\d+(\\.\\d+)*") ? test : installed().versionName;
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
