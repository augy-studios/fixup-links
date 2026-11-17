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
    private static final long NO_ANSWER_MILLISECONDS = 30_000;

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
    private static WeakReference<UpdateActivity> showingWindow = new WeakReference<>(null);

    private TextView titleView;
    private TextView subtitleView;
    private MaterialCardView statusCard;
    private FrameLayout statusTile;
    private ImageView statusIcon;
    private TextView messageView;
    private WavyProgressView progressView;
    private MaterialButton primaryButton;
    private MaterialButton secondaryButton;
    private LinearLayout contentLayout;
    private LinearLayout releasesLayout;
    // The newest releases and what's new in each, newest first, once read: drawn as the
    // changelog. Empty from a site from before they were sent.
    private volatile List<Notes> releaseHistory = Collections.emptyList();

    private Thread workThread;
    private volatile boolean cancelled;
    private boolean askedToAllow;
    // Sent to Security settings to turn Auto Blocker off.
    private boolean askedToUnblock;
    // Handed to the installer, with no final answer from it yet.
    private boolean installing;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Runnable noAnswerCheck = () -> {
        autoBlocked();
    };
    // Only checking, so ask before downloading what it finds.
    private boolean checkOnly;
    private String expectedVersion;
    // The update to install, once found and wanted: kept while you're in "Install unknown
    // apps", and for "Try again", so neither looks it up again.
    private Release foundRelease;

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
        if (version != null && version.matches("\\d+(\\.\\d+)*")) {
            intent.putExtra(EXTRA_VERSION, version);
        }
        if (!(context instanceof Activity)) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        context.startActivity(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // The wallpaper's colours over the app's green, where Android has them (12 and later).
        DynamicColors.applyToActivityIfAvailable(this);
        EdgeToEdge.enable(this);
        super.onCreate(savedInstanceState);
        buildWindow();
        showingWindow = new WeakReference<>(this);
        Uri link = getIntent().getData();
        checkOnly = link != null && CHECK.equals(link.getPath());
        expectedVersion = getIntent().getStringExtra(EXTRA_VERSION);
        start();
    }

    /**
     * Coming back to the window: from "Install unknown apps" (carry on, or say it wasn't
     * allowed), from Security settings after Auto Blocker (offer Try again), or from the
     * installer's own screen (wait for its answer again).
     */
    @Override
    protected void onResume() {
        super.onResume();
        // Back from "Install unknown apps".
        if (askedToAllow && workThread == null) {
            askedToAllow = false;
            if (allowedToInstall()) {
                start();
            } else {
                problem("Not allowed to update",
                        "uwuFix wasn't allowed to install apps, so it can't update itself.",
                        "Try again", this::askToAllow, "Close", this::finish);
            }
        } else if (askedToUnblock && workThread == null) {
            // Back from Security settings, with no telling whether Auto Blocker is off now.
            askedToUnblock = false;
            show("Ready to try again", "If Auto Blocker is off now, tap Try again to install " + which() + ".",
                    "Try again", this::start, "Not now", this::finish);
        } else if (installing) {
            // Back from the installer's screen: waiting for its answer again.
            waitForAnswer();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        mainHandler.removeCallbacks(noAnswerCheck);
        cancelled = true;
        if (showingWindow.get() == this) {
            showingWindow.clear();
        }
    }

    // ---------- steps ----------

    private boolean allowedToInstall() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || getPackageManager().canRequestPackageInstalls();
    }

    private void askToAllow() {
        String found;
        if (foundRelease != null) {
            found = "Version " + foundRelease.version + " is out. ";
        } else {
            found = "";
        }
        show("Allow updates", found + "To update itself, uwuFix needs your OK to install apps. Turn on "
                + "\"Allow from this source\" on the next screen, then come back.",
                "Continue", () -> {
                    askedToAllow = true;
                    startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:" + getPackageName())));
                }, "Not now", this::finish);
    }

    // Samsung's Auto Blocker, the likeliest reason an update didn't install on a Samsung device
    // that allows this app to install apps. Nothing public says whether it's on, so this says
    // "probably", and Try again carries on with the same version.
    private void autoBlocked() {
        installing = false;
        mainHandler.removeCallbacks(noAnswerCheck);
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
        askedToUnblock = true;
        try {
            startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS));
        } catch (ActivityNotFoundException exception) {
            startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
    }

    // Handed to the installer: on a Samsung device, its silence for NO_ANSWER_MILLISECONDS is
    // taken as Auto Blocker. Elsewhere the window waits as long as it takes, as before.
    private void waitForAnswer() {
        mainHandler.removeCallbacks(noAnswerCheck);
        if (AUTO_BLOCKER) {
            mainHandler.postDelayed(noAnswerCheck, NO_ANSWER_MILLISECONDS);
        }
    }

    // The installer answered: done, or only asking you first (PENDING_USER_ACTION).
    private void heard(boolean done) {
        mainHandler.removeCallbacks(noAnswerCheck);
        if (done) {
            installing = false;
        }
    }

    private String which() {
        if (foundRelease != null) {
            return "version " + foundRelease.version;
        }
        return "the update";
    }

    private static String capitalised(String text) {
        return Character.toUpperCase(text.charAt(0)) + text.substring(1);
    }

    /**
     * Looks for the update, or carries on with the one already found, on a thread of its own:
     * reads the newest release (and draws the changelog), then, unless only checking, makes sure
     * this app may install apps, downloads the APK, checks it, and hands it to the installer.
     */
    private void start() {
        cancelled = false;
        installing = false;
        mainHandler.removeCallbacks(noAnswerCheck);
        Release found = foundRelease;
        String startTitle;
        String startText;
        if (found != null) {
            startTitle = "Updating";
            startText = "Downloading version " + found.version + "…";
        } else if (checkOnly) {
            startTitle = "Checking for updates";
            startText = "Checking for updates…";
        } else {
            startTitle = "Checking for updates";
            startText = "Looking for the update…";
        }
        progress(startTitle, startText, -1);
        workThread = new Thread(() -> {
            try {
                Release release;
                if (found != null) {
                    release = found;
                } else {
                    release = latest();
                }
                if (found == null) {
                    runWhileShowing(this::drawChangelog);
                }
                if (release == null) {
                    runWhileShowing(() -> {
                        show("You're up to date", null,
                                "GitHub", R.drawable.update_ic_github, () -> {
                                    browse(pageOf(installedVersion()));
                                },
                                "Close", this::finish);
                    });
                    return;
                }
                if (found == null && checkOnly) {
                    runWhileShowing(() -> {
                        show("Update available", null,
                                "Update to " + release.version, R.drawable.update_ic_download, () -> {
                                    update(release);
                                },
                                "Not now", this::finish);
                    });
                    return;
                }
                if (!allowedToInstall()) {
                    runWhileShowing(() -> {
                        foundRelease = release;
                        askToAllow();
                    });
                    return;
                }
                File apkFile = download(release);
                if (apkFile == null) {
                    return; // Cancelled.
                }
                check(apkFile);
                runWhileShowing(() -> {
                    // Kept on a Samsung device for Try again after Auto Blocker, which then
                    // carries on with this version rather than looking again.
                    if (AUTO_BLOCKER) {
                        foundRelease = release;
                    }
                    progress("Updating", "Opening Android's installer…", -1);
                });
                install(apkFile);
            } catch (Problem problem) {
                failed(problem.getMessage());
            } catch (IOException | JSONException | NoSuchAlgorithmException | RuntimeException exception) {
                Log.w(TAG, exception);
                failed("Couldn't download the update. Check you're online, then try again.");
            } finally {
                runWhileShowing(() -> {
                    workThread = null;
                });
            }
        }, "update");
        workThread.start();
    }

    // "Update" on what a check found: on to downloading it, by way of "Install unknown apps"
    // if this app isn't allowed to install it yet.
    private void update(Release release) {
        foundRelease = release;
        if (allowedToInstall()) {
            start();
        } else {
            askToAllow();
        }
    }

    // The newest release if it's newer than this app, or null.
    private Release latest() throws IOException, JSONException, Problem {
        // A version from a notification makes a URL of its own, which the site's cache hasn't
        // seen, so it's read from GitHub now rather than up to ten minutes ago.
        JSONObject json;
        File testFile = testFile();
        if (testFile != null) {
            try (InputStream input = new FileInputStream(testFile)) {
                json = new JSONObject(read(input));
            }
        } else {
            String url;
            if (expectedVersion == null) {
                url = LATEST;
            } else {
                url = LATEST + "?v=" + expectedVersion;
            }
            HttpURLConnection connection = open(url);
            if (connection.getResponseCode() != 200) {
                throw new Problem("Couldn't find out what the newest version is. Try again later.");
            }
            try (InputStream input = connection.getInputStream()) {
                json = new JSONObject(read(input));
            } finally {
                connection.disconnect();
            }
        }
        releaseHistory = Notes.listOf(json.optJSONArray("history"));
        String version = json.optString("version", "");
        if (version.isEmpty() || !newer(version, installedVersion())) {
            return null;
        }
        String sha256;
        if (json.isNull("sha256")) {
            sha256 = null;
        } else {
            sha256 = json.getString("sha256");
        }
        Release release = new Release(version, json.getString("apk"), json.optLong("size", -1), sha256);
        if (!release.apkUrl.startsWith(RELEASES)) {
            throw new Problem("The update isn't on uwuFix's GitHub page, so it wasn't downloaded.");
        }
        return release;
    }

    /**
     * Downloads the release's APK into this app's cache, showing how far it's got and working out
     * its SHA-256 on the way, then checks that against the published checksum. Null if cancelled
     * on the way.
     */
    private File download(Release release) throws IOException, NoSuchAlgorithmException, Problem {
        File directory = new File(getCacheDir(), "update");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("No room for " + directory);
        }
        File apkFile = new File(directory, "uwufix.apk");
        String label = "Downloading version " + release.version + "…";
        runWhileShowing(() -> {
            progress("Updating", label, 0);
        });

        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        HttpURLConnection connection = open(release.apkUrl);
        try {
            if (connection.getResponseCode() != 200) {
                throw new Problem("GitHub didn't send the update (" + connection.getResponseCode() + "). Try again later.");
            }
            long total;
            if (connection.getContentLength() > 0) {
                total = connection.getContentLength();
            } else {
                total = release.size;
            }
            try (InputStream input = new DigestInputStream(connection.getInputStream(), sha256);
                 OutputStream output = new FileOutputStream(apkFile)) {
                byte[] buffer = new byte[16 * 1024];
                long done = 0;
                int lastPercent = -1;
                for (int bytesRead; (bytesRead = input.read(buffer)) != -1; ) {
                    if (cancelled) {
                        apkFile.delete();
                        return null;
                    }
                    output.write(buffer, 0, bytesRead);
                    done += bytesRead;
                    int percent;
                    if (total > 0) {
                        percent = (int) Math.min(100, done * 100 / total);
                    } else {
                        percent = -1;
                    }
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        String sizes;
                        if (total > 0) {
                            sizes = "\n" + megabytes(done) + " of " + megabytes(total);
                        } else {
                            sizes = "";
                        }
                        runWhileShowing(() -> {
                            progress("Updating", label + sizes, percent);
                        });
                    }
                }
            }
        } finally {
            connection.disconnect();
        }

        if (release.sha256 != null && !release.sha256.equalsIgnoreCase(hexadecimal(sha256.digest()))) {
            apkFile.delete();
            throw new Problem("The download doesn't match the file on GitHub. Try again.");
        }
        return apkFile;
    }

    // That the file is this app, and newer than the one installed.
    private void check(File apkFile) throws Problem {
        PackageInfo info = getPackageManager().getPackageArchiveInfo(apkFile.getPath(), 0);
        if (info == null || !getPackageName().equals(info.packageName)) {
            apkFile.delete();
            throw new Problem("The download isn't uwuFix, so it wasn't installed.");
        }
        if (versionCode(info) <= versionCode(installed())) {
            apkFile.delete();
            throw new Problem("The download isn't newer than this app, so it wasn't installed.");
        }
    }

    // Hands the APK to Android's installer. Its answer comes to InstallStatus: first that it
    // needs you to confirm, with the screen that asks, then whether it worked.
    private void install(File apkFile) throws IOException {
        PackageInstaller installer = getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams sessionParameters =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        sessionParameters.setAppPackageName(getPackageName());
        sessionParameters.setSize(apkFile.length());
        int sessionId = installer.createSession(sessionParameters);
        try (PackageInstaller.Session session = installer.openSession(sessionId)) {
            try (InputStream input = new FileInputStream(apkFile);
                 OutputStream output = session.openWrite("uwufix.apk", 0, apkFile.length())) {
                byte[] buffer = new byte[64 * 1024];
                for (int bytesRead; (bytesRead = input.read(buffer)) != -1; ) {
                    output.write(buffer, 0, bytesRead);
                }
                session.fsync(output);
            }
            // Mutable, for the installer to add its answer to. Explicit, to InstallStatus only.
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags | PendingIntent.FLAG_MUTABLE;
            }
            PendingIntent status = PendingIntent.getBroadcast(this, sessionId,
                    new Intent(this, InstallStatus.class), flags);
            // Waiting from before the commit, so even the quickest answer comes after it.
            runWhileShowing(() -> {
                installing = true;
                waitForAnswer();
            });
            session.commit(status.getIntentSender());
        } catch (IOException | RuntimeException exception) {
            installer.abandonSession(sessionId);
            throw exception;
        } finally {
            // The session has its own copy now.
            apkFile.delete();
        }
    }

    // The installer's answers. Not exported, so only the installer, through the PendingIntent
    // above, can send them: an exported one would start any screen another app handed it.
    public static class InstallStatus extends BroadcastReceiver {
        /**
         * One answer from the installer: show its confirm screen, close on success, close (or
         * explain Auto Blocker) when cancelled, and otherwise say why it failed, in the window if
         * it's still showing or in a toast if not.
         */
        @Override
        public void onReceive(Context context, Intent intent) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
            UpdateActivity showing = showingWindow.get();
            // An answer, so not silence. Waiting starts again when you're back from the screen
            // that asks.
            if (showing != null) {
                showing.heard(status != PackageInstaller.STATUS_PENDING_USER_ACTION);
            }
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                Intent confirm = intent.getParcelableExtra(Intent.EXTRA_INTENT);
                if (confirm == null) {
                    return;
                }
                // Started while the update window is still on screen, so Android lets it open.
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(confirm);
            } else if (status == PackageInstaller.STATUS_SUCCESS) {
                // Android stops the app to replace it, so this rarely runs.
                if (showing != null) {
                    showing.finish();
                }
            } else if (status == PackageInstaller.STATUS_FAILURE_ABORTED) {
                // "Cancel" on Android's own screen. Also what a screen that ends without
                // Install answers, as Samsung's does when Auto Blocker stops it, so there the
                // window stays to say so.
                Log.i(TAG, "Install aborted: " + intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE));
                if (showing != null && AUTO_BLOCKER) {
                    showing.autoBlocked();
                } else if (showing != null) {
                    showing.finish();
                }
            } else {
                String why = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
                Log.w(TAG, "Install failed: " + status + " " + why);
                boolean conflict = status == PackageInstaller.STATUS_FAILURE_CONFLICT
                        || status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE;
                boolean storage = status == PackageInstaller.STATUS_FAILURE_STORAGE;
                if (AUTO_BLOCKER && !conflict && !storage) {
                    if (showing != null) {
                        showing.autoBlocked();
                    } else {
                        Toast.makeText(context, "Samsung's Auto Blocker probably stopped the update. Turn it "
                                + "off in Settings > Security and privacy > Auto Blocker, then update again.",
                                Toast.LENGTH_LONG).show();
                    }
                    return;
                }
                String message;
                if (conflict) {
                    message = "Android wouldn't install the update over this app. Uninstall uwuFix, then install it from GitHub.";
                } else if (storage) {
                    message = "There isn't room on this phone for the update.";
                } else {
                    message = "Android couldn't install the update. Try again.";
                }
                if (showing != null) {
                    showing.failed(message);
                } else {
                    Toast.makeText(context, message, Toast.LENGTH_LONG).show();
                }
            }
        }
    }

    // ---------- the page ----------

    /**
     * Finds the page's views (update_activity.xml), then lays it out edge to edge: the buttons
     * over the bottom on a fade, the changelog padded to scroll clear of them, and the words kept
     * out from under the status and navigation bars.
     */
    private void buildWindow() {
        setContentView(R.layout.update_activity);
        titleView = findViewById(R.id.update_title);
        subtitleView = findViewById(R.id.update_subtitle);
        statusCard = findViewById(R.id.update_status);
        statusTile = findViewById(R.id.update_status_tile);
        statusIcon = findViewById(R.id.update_status_icon);
        messageView = findViewById(R.id.update_message);
        progressView = findViewById(R.id.update_progress);
        primaryButton = findViewById(R.id.update_primary);
        secondaryButton = findViewById(R.id.update_secondary);
        contentLayout = findViewById(R.id.update_content);
        releasesLayout = findViewById(R.id.update_releases);
        subtitleView.setText("uwuFix · v" + installedVersion());

        // The buttons over the bottom of the page, the changelog fading out under them, and the
        // page scrolling far enough for its end to come up above them.
        int surface = color(com.google.android.material.R.attr.colorSurface);
        View buttons = findViewById(R.id.update_buttons);
        buttons.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] {
                surface, surface, ColorUtils.setAlphaComponent(surface, 0)}));
        buttons.addOnLayoutChangeListener((view, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
            if (bottom - top != oldBottom - oldTop) {
                contentLayout.setPadding(contentLayout.getPaddingLeft(), contentLayout.getPaddingTop(),
                        contentLayout.getPaddingRight(), bottom - top);
            }
        });
        // Edge to edge: the page under the status and navigation bars, its words and buttons not.
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.update_root), (view, insets) -> {
            Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            contentLayout.setPadding(dpToPixels(20) + bars.left, dpToPixels(24) + bars.top,
                    dpToPixels(20) + bars.right, contentLayout.getPaddingBottom());
            buttons.setPadding(dpToPixels(20) + bars.left, dpToPixels(32),
                    dpToPixels(20) + bars.right, dpToPixels(16) + bars.bottom);
            View statusBar = findViewById(R.id.update_status_bar);
            statusBar.getLayoutParams().height = insets.getInsets(WindowInsetsCompat.Type.statusBars()).top;
            statusBar.requestLayout();
            return WindowInsetsCompat.CONSUMED;
        });
        filled(secondaryButton, false);
    }

    // A step under way: percent from 0 to 100, or -1 while there's no telling.
    private void progress(String title, String text, int percent) {
        titleView.setText(title);
        status(text, R.drawable.update_ic_download, false);
        progressView.setIndeterminate(percent < 0);
        if (percent >= 0) {
            progressView.setProgress(percent, true);
        }
        progressView.setVisibility(View.VISIBLE);
        button(primaryButton, null, 0, null);
        button(secondaryButton, "Cancel", 0, () -> {
            cancelled = true;
            finish();
        });
    }

    // A title, a message (or null for none) and up to two buttons, with nothing under way.
    private void show(String title, String text, String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        show(title, text, primary, 0, onPrimary, secondary, onSecondary);
    }

    private void show(String title, String text, String primary, int icon, Runnable onPrimary, String secondary, Runnable onSecondary) {
        titleView.setText(title);
        status(text, R.drawable.update_ic_settings, false);
        progressView.setVisibility(View.GONE);
        button(primaryButton, primary, icon, onPrimary);
        button(secondaryButton, secondary, 0, onSecondary);
        // GitHub, on the changelog, is a way to read more rather than a step on: outlined, as
        // Close is, rather than filled.
        filled(primaryButton, icon != R.drawable.update_ic_github);
    }

    // The same for something that went wrong, its icon on the error colours.
    private void problem(String title, String text, String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        show(title, text, primary, onPrimary, secondary, onSecondary);
        status(text, R.drawable.update_ic_alert, true);
    }

    // The card at the top: a download under way, something for you to do, or a problem.
    private void status(String text, int icon, boolean problem) {
        if (text == null) {
            statusCard.setVisibility(View.GONE);
        } else {
            statusCard.setVisibility(View.VISIBLE);
        }
        messageView.setText(text);
        int tileColor;
        int iconColor;
        if (problem) {
            tileColor = color(com.google.android.material.R.attr.colorErrorContainer);
            iconColor = color(com.google.android.material.R.attr.colorOnErrorContainer);
        } else {
            tileColor = color(com.google.android.material.R.attr.colorPrimaryContainer);
            iconColor = color(com.google.android.material.R.attr.colorOnPrimaryContainer);
        }
        statusTile.setBackground(rounded(tileColor, dpToPixels(12)));
        statusIcon.setImageResource(icon);
        statusIcon.setImageTintList(ColorStateList.valueOf(iconColor));
    }

    private void failed(String message) {
        runWhileShowing(() -> {
            installing = false;
            mainHandler.removeCallbacks(noAnswerCheck);
            problem("Couldn't update", message, "Try again", this::start, "Close", this::finish);
        });
    }

    private void button(MaterialButton button, String label, int icon, Runnable onClick) {
        if (label == null) {
            button.setVisibility(View.GONE);
        } else {
            button.setVisibility(View.VISIBLE);
        }
        button.setText(label);
        if (icon != 0) {
            button.setIconResource(icon);
        } else {
            button.setIcon(null);
        }
        if (onClick == null) {
            button.setOnClickListener(null);
        } else {
            button.setOnClickListener((view) -> {
                onClick.run();
            });
        }
    }

    // A button filled in the theme's primary colour, or outlined over the page, opaque so the
    // changelog doesn't show through its words.
    private void filled(MaterialButton button, boolean filled) {
        int backgroundColor;
        int inkColor;
        int strokeWidth;
        if (filled) {
            backgroundColor = color(androidx.appcompat.R.attr.colorPrimary);
            inkColor = color(com.google.android.material.R.attr.colorOnPrimary);
            strokeWidth = 0;
        } else {
            backgroundColor = color(com.google.android.material.R.attr.colorSurfaceContainerLow);
            inkColor = color(com.google.android.material.R.attr.colorOnSurface);
            strokeWidth = dpToPixels(1);
        }
        button.setBackgroundTintList(ColorStateList.valueOf(backgroundColor));
        button.setTextColor(inkColor);
        button.setIconTint(ColorStateList.valueOf(inkColor));
        button.setIconGravity(MaterialButton.ICON_GRAVITY_TEXT_START);
        button.setStrokeWidth(strokeWidth);
        button.setStrokeColor(ColorStateList.valueOf(color(com.google.android.material.R.attr.colorOutlineVariant)));
    }

    // A step for the window, on the main thread, unless the window's already closing.
    private void runWhileShowing(Runnable step) {
        runOnUiThread(() -> {
            if (!isFinishing() && !isDestroyed()) {
                step.run();
            }
        });
    }

    private int dpToPixels(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    // A colour of the page's theme, the wallpaper's where Android has them.
    private int color(int attribute) {
        return MaterialColors.getColor(this, attribute, 0);
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
        if (width > 0) {
            shape.setStroke(width, stroke);
        }
        return shape;
    }

    private void browse(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (ActivityNotFoundException exception) {
            Toast.makeText(this, "No browser to open " + url, Toast.LENGTH_LONG).show();
        }
    }

    // ---------- the changelog ----------

    // Each release on a timeline, newest first: the ones newer than this app marked New, this
    // one Installed, and "Earlier releases" before the rest. The one you'd get opens by itself,
    // or this one when there's nothing newer.
    private void drawChangelog() {
        releasesLayout.removeAllViews();
        List<Notes> history = releaseHistory;
        String installed = installedVersion();
        int openIndex = -1;
        for (int index = 0; index < history.size() && openIndex < 0; index++) {
            if (!newer(history.get(index).version, installed)) {
                openIndex = index;
            }
        }
        if (!history.isEmpty() && newer(history.get(0).version, installed)) {
            openIndex = 0;
        }
        boolean labelled = false;
        LayoutInflater inflater = LayoutInflater.from(this);
        for (int index = 0; index < history.size(); index++) {
            Notes notes = history.get(index);
            boolean isNew = newer(notes.version, installed);
            boolean isInstalled = notes.version.equals(installed);
            if (!isNew && !isInstalled && !labelled) {
                labelled = true;
                View label = inflater.inflate(R.layout.update_label, releasesLayout, false);
                ((TextView) label.findViewById(R.id.label_text)).setText("Earlier releases");
                releasesLayout.addView(label);
            }
            boolean opened = index == openIndex;
            boolean last = index == history.size() - 1;
            releasesLayout.addView(release(inflater, notes, isNew, isInstalled, opened, last));
        }
    }

    /**
     * One release's row on the timeline: its dot (a ring for the one you'd get or have), its
     * version with a New or Installed chip, when it came out and how many changes, and its notes
     * as group cards that open and close with a tap on the heading.
     */
    private View release(LayoutInflater inflater, Notes notes, boolean isNew, boolean isInstalled, boolean opened, boolean last) {
        View row = inflater.inflate(R.layout.update_release, releasesLayout, false);
        int primary = color(androidx.appcompat.R.attr.colorPrimary);
        int muted = color(com.google.android.material.R.attr.colorOutline);
        // The release you'd get, or have, as a ring; the rest as a small dot.
        View dot = row.findViewById(R.id.release_dot);
        boolean ring = isNew || isInstalled;
        FrameLayout.LayoutParams size = (FrameLayout.LayoutParams) dot.getLayoutParams();
        if (ring) {
            dot.setBackground(dot(color(com.google.android.material.R.attr.colorSurface), primary, dpToPixels(3)));
            size.width = dpToPixels(16);
            size.height = dpToPixels(16);
            size.topMargin = dpToPixels(7);
        } else {
            dot.setBackground(dot(muted, primary, 0));
            size.width = dpToPixels(10);
            size.height = dpToPixels(10);
            size.topMargin = dpToPixels(10);
        }
        if (last) {
            row.findViewById(R.id.release_line).setVisibility(View.INVISIBLE);
        }

        ((TextView) row.findViewById(R.id.release_version)).setText("v" + notes.version);
        TextView chip = row.findViewById(R.id.release_chip);
        if (ring) {
            chip.setVisibility(View.VISIBLE);
            if (isNew) {
                chip.setText("New");
                chip.setBackground(rounded(color(androidx.appcompat.R.attr.colorPrimary), dpToPixels(16)));
                chip.setTextColor(color(com.google.android.material.R.attr.colorOnPrimary));
            } else {
                chip.setText("Installed");
                chip.setBackground(rounded(color(com.google.android.material.R.attr.colorPrimaryContainer), dpToPixels(16)));
                chip.setTextColor(color(com.google.android.material.R.attr.colorOnPrimaryContainer));
            }
        }
        int count = 0;
        for (Group group : notes.groups) {
            count += group.items.size();
        }
        String dateLabel = dateText(notes.date);
        String changesLabel;
        if (count == 0) {
            changesLabel = null;
        } else if (count == 1) {
            changesLabel = count + " change";
        } else {
            changesLabel = count + " changes";
        }
        String meta;
        if (dateLabel != null && changesLabel != null) {
            meta = dateLabel + " · " + changesLabel;
        } else if (dateLabel != null) {
            meta = dateLabel;
        } else if (changesLabel != null) {
            meta = changesLabel;
        } else {
            meta = "";
        }
        ((TextView) row.findViewById(R.id.release_meta)).setText(meta);

        LinearLayout body = row.findViewById(R.id.release_body);
        TextView summary = row.findViewById(R.id.release_summary);
        summary.setText(notes.summary);
        if (notes.summary.isEmpty()) {
            summary.setVisibility(View.GONE);
        } else {
            summary.setVisibility(View.VISIBLE);
        }
        for (int groupIndex = 0; groupIndex < notes.groups.size(); groupIndex++) {
            body.addView(group(inflater, body, notes.groups.get(groupIndex), groupIndex));
        }

        View head = row.findViewById(R.id.release_head);
        ImageView chevron = row.findViewById(R.id.release_chevron);
        boolean anything = !notes.groups.isEmpty() || !notes.summary.isEmpty();
        if (anything) {
            chevron.setVisibility(View.VISIBLE);
        } else {
            chevron.setVisibility(View.GONE);
        }
        setOpen(body, chevron, head, notes, opened && anything, false);
        if (anything) {
            head.setOnClickListener((view) -> {
                setOpen(body, chevron, head, notes, body.getVisibility() != View.VISIBLE, true);
            });
        }
        return row;
    }

    private void setOpen(View body, ImageView chevron, View head, Notes notes, boolean open, boolean animate) {
        if (animate) {
            TransitionManager.beginDelayedTransition(contentLayout, new AutoTransition().setDuration(200));
        }
        int rotation;
        if (open) {
            body.setVisibility(View.VISIBLE);
            rotation = 180;
        } else {
            body.setVisibility(View.GONE);
            rotation = 0;
        }
        if (animate) {
            chevron.animate().rotation(rotation).setDuration(200).start();
        } else {
            chevron.setRotation(rotation);
        }
        if (open) {
            head.setContentDescription("Version " + notes.version + ", what's new shown");
        } else {
            head.setContentDescription("Version " + notes.version + ", tap for what's new");
        }
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
        card.findViewById(R.id.group_tile).setBackground(rounded(color(tone[0]), dpToPixels(10)));
        ImageView icon = card.findViewById(R.id.group_icon);
        icon.setImageResource(groupIcon(group.title));
        icon.setImageTintList(ColorStateList.valueOf(color(tone[1])));
        ((TextView) card.findViewById(R.id.group_title)).setText(group.title);
        TextView count = card.findViewById(R.id.group_count);
        count.setText(String.valueOf(group.items.size()));
        count.setBackground(rounded(color(com.google.android.material.R.attr.colorSurfaceContainerHighest), dpToPixels(14)));

        LinearLayout items = card.findViewById(R.id.group_items);
        int accent = color(tone[2]);
        for (int itemIndex = 0; itemIndex < group.items.size(); itemIndex++) {
            View item = inflater.inflate(R.layout.update_item, items, false);
            item.findViewById(R.id.item_dot).setBackground(dot(accent, 0, 0));
            String[] itemParts = group.items.get(itemIndex);
            String itemTitle = itemParts[0];
            String itemText = itemParts[1];
            TextView title = item.findViewById(R.id.item_title);
            TextView text = item.findViewById(R.id.item_text);
            if (itemTitle.isEmpty()) {
                title.setText(capitalised(itemText));
            } else {
                title.setText(itemTitle);
            }
            if (itemText.isEmpty()) {
                text.setText("");
            } else {
                text.setText(capitalised(itemText));
            }
            if (itemTitle.isEmpty() || itemText.isEmpty()) {
                text.setVisibility(View.GONE);
            } else {
                text.setVisibility(View.VISIBLE);
            }
            if (itemIndex >= FIRST_ITEMS) {
                item.setVisibility(View.GONE);
            }
            items.addView(item);
        }
        if (group.items.size() > FIRST_ITEMS) {
            View more = card.findViewById(R.id.group_more);
            more.setVisibility(View.VISIBLE);
            ((TextView) card.findViewById(R.id.group_more_text)).setText("Show all (" + group.items.size() + ")");
            more.setOnClickListener((view) -> {
                TransitionManager.beginDelayedTransition(contentLayout, new AutoTransition().setDuration(200));
                for (int childIndex = 0; childIndex < items.getChildCount(); childIndex++) {
                    items.getChildAt(childIndex).setVisibility(View.VISIBLE);
                }
                more.setVisibility(View.GONE);
            });
        }
        return card;
    }

    // An icon for a group by its heading in the notes: the app's own, as the site has them.
    private static int groupIcon(String title) {
        String lowercaseTitle = title.toLowerCase(Locale.ROOT);
        if (lowercaseTitle.contains("android") || lowercaseTitle.contains("phone")) {
            return R.drawable.update_ic_phone;
        }
        if (lowercaseTitle.contains("desktop") || lowercaseTitle.contains("windows")
                || lowercaseTitle.contains("linux") || lowercaseTitle.contains("mac")) {
            return R.drawable.update_ic_terminal;
        }
        if (lowercaseTitle.contains("history") || lowercaseTitle.contains("sync") || lowercaseTitle.contains("devices")) {
            return R.drawable.update_ic_star;
        }
        if (lowercaseTitle.contains("notification") || lowercaseTitle.contains("news")) {
            return R.drawable.update_ic_bell;
        }
        if (lowercaseTitle.contains("look") || lowercaseTitle.contains("theme") || lowercaseTitle.contains("colour")) {
            return R.drawable.update_ic_sun;
        }
        if (lowercaseTitle.contains("tour") || lowercaseTitle.contains("website") || lowercaseTitle.contains("site")) {
            return R.drawable.update_ic_eye;
        }
        if (lowercaseTitle.contains("setting") || lowercaseTitle.contains("update")) {
            return R.drawable.update_ic_settings;
        }
        if (lowercaseTitle.contains("link") || lowercaseTitle.contains("fix")
                || lowercaseTitle.contains("tracker") || lowercaseTitle.contains("embed")) {
            return R.drawable.update_ic_check;
        }
        return R.drawable.update_ic_star;
    }

    // When a release came out: Today, Yesterday, 3 days ago, or 23 Oct 2026, by Singapore's clock.
    private static String dateText(String isoDate) {
        if (isoDate == null || isoDate.isEmpty()) {
            return null;
        }
        SimpleDateFormat isoFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.ROOT);
        isoFormat.setTimeZone(TimeZone.getTimeZone("UTC"));
        Date date;
        try {
            date = isoFormat.parse(isoDate);
        } catch (ParseException exception) {
            return null;
        }
        TimeZone singaporeZone = TimeZone.getTimeZone("Asia/Singapore");
        long days = dayNumber(new Date(), singaporeZone) - dayNumber(date, singaporeZone);
        if (days <= 0) {
            return "Today";
        }
        if (days == 1) {
            return "Yesterday";
        }
        if (days < 7) {
            return days + " days ago";
        }
        SimpleDateFormat displayFormat = new SimpleDateFormat("d MMM yyyy", Locale.UK);
        displayFormat.setTimeZone(singaporeZone);
        return displayFormat.format(date);
    }

    // Days since 1970 by a time zone's calendar, to count whole days between two moments.
    private static long dayNumber(Date date, TimeZone zone) {
        return Math.floorDiv(date.getTime() + zone.getOffset(date.getTime()), 86_400_000L);
    }

    // A release's page on GitHub, or the list of them.
    private String pageOf(String version) {
        for (Notes notes : releaseHistory) {
            if (notes.version.equals(version) && !notes.page.isEmpty()) {
                return notes.page;
            }
        }
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
            for (int index = 0; notes != null && index < notes.length(); index++) {
                JSONObject group = notes.optJSONObject(index);
                if (group != null) {
                    groups.add(new Group(group));
                }
            }
        }

        static List<Notes> listOf(JSONArray history) {
            List<Notes> list = new ArrayList<>();
            for (int index = 0; history != null && index < history.length(); index++) {
                JSONObject release = history.optJSONObject(index);
                if (release != null && !release.optString("version", "").isEmpty()) {
                    list.add(new Notes(release));
                }
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
            for (int index = 0; list != null && index < list.length(); index++) {
                JSONObject item = list.optJSONObject(index);
                if (item != null) {
                    items.add(new String[] {item.optString("title", ""), item.optString("text", "")});
                }
            }
        }
    }

    // ---------- seeing it on an emulator ----------

    private boolean debuggable() {
        return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    // EXTRA_TEST_JSON's file, in this app's cache, in a debuggable build only.
    private File testFile() {
        if (!debuggable()) {
            return null;
        }
        String name = getIntent().getStringExtra(EXTRA_TEST_JSON);
        if (name == null || !name.matches("[\\w.-]+")) {
            return null;
        }
        File file = new File(getCacheDir(), name);
        if (file.isFile()) {
            return file;
        }
        return null;
    }

    // ---------- helpers ----------

    private static final class Release {
        final String version;
        final String apkUrl;
        final long size;
        final String sha256;

        Release(String version, String apkUrl, long size, String sha256) {
            this.version = version;
            this.apkUrl = apkUrl;
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
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(15_000);
        connection.setReadTimeout(30_000);
        connection.setRequestProperty("User-Agent", "uwuFix for Android " + installedVersion());
        // GitHub sends the APK on from its own address to its file storage's, both https.
        connection.setInstanceFollowRedirects(true);
        return connection;
    }

    private PackageInfo installed() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0);
        } catch (PackageManager.NameNotFoundException exception) {
            throw new IllegalStateException(exception); // This app is always installed.
        }
    }

    // This app's version, or in a debuggable build one to be (EXTRA_TEST_VERSION).
    private String installedVersion() {
        String testVersion = null;
        if (debuggable()) {
            testVersion = getIntent().getStringExtra(EXTRA_TEST_VERSION);
        }
        if (testVersion != null && testVersion.matches("\\d+(\\.\\d+)*")) {
            return testVersion;
        }
        return installed().versionName;
    }

    @SuppressWarnings("deprecation")
    private static long versionCode(PackageInfo info) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return info.getLongVersionCode();
        }
        return info.versionCode;
    }

    // Whether version candidate comes after version current, number by number: 1.10.0 after
    // 1.9.0. The same as newer() in main-site/api/app-release.js.
    static boolean newer(String candidate, String current) {
        String[] candidateParts = candidate.split("\\.");
        String[] currentParts = current.split("\\.");
        for (int index = 0; index < Math.max(candidateParts.length, currentParts.length); index++) {
            int difference = number(candidateParts, index) - number(currentParts, index);
            if (difference != 0) {
                return difference > 0;
            }
        }
        return false;
    }

    private static int number(String[] parts, int index) {
        if (index >= parts.length) {
            return 0;
        }
        try {
            return Integer.parseInt(parts[index].replaceAll("\\D", ""));
        } catch (NumberFormatException exception) {
            return 0;
        }
    }

    private static String read(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8 * 1024];
        for (int bytesRead; (bytesRead = input.read(buffer)) != -1; ) {
            output.write(buffer, 0, bytesRead);
        }
        return output.toString("UTF-8");
    }

    private static String hexadecimal(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte singleByte : bytes) {
            builder.append(String.format(Locale.ROOT, "%02x", singleByte));
        }
        return builder.toString();
    }

    private static String megabytes(long bytes) {
        return String.format(Locale.ROOT, "%.1f MB", bytes / 1_000_000.0);
    }
}
