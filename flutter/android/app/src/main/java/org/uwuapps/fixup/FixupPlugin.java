/*
 * The app itself, to the Dart side (flutter/lib/native/native_bridge.dart): the same calls the
 * site's page made of it when the app was a WebView (main-site/js/app-bridge.js), and a few more.
 *
 *   info()                    { version, versionCode, features, quick, android, release, model }: what this app
 *                             can do. quick is { from: "share" | "select" | "copied", replace,
 *                             text } in the quick screen (FixActivity), or null in the app itself
 *   share({ title, text, url })   Android's share sheet
 *   paste()                   { text }: the clipboard (Android 10 and later only let the app in
 *                             front read it, which it is whenever Paste can be pressed)
 *   open({ url })             a link in whatever app opens it (the browser, or X for fixupx.com)
 *   update({ check, version })  the updates page (UpdateActivity): check, the Edge Tray's "Check
 *                             for app updates", looks first and asks before downloading
 *   finish({ text })          the quick screen's Replace or Done: the text back to the app that
 *                             asked, when it can take it, then closes (FixActivity.finishWith)
 *   background()              to the background, for Back pressed twice on the home page
 *   topics()                  { releases, news }: which notifications you've turned on
 *   setTopic({ topic, on })   turns "releases" (new versions) or "news" on or off, as an FCM topic
 *                             subscription, so the server needs no list of phones
 *   openSettings({ what })    the app's notification settings ("notifications") or its page in
 *                             Android's settings ("app")
 *
 *   "open" events             { url }: the site's address for what the app was opened with
 *                             (MainActivity.pageFor), kept until the Dart side listens
 *   "quick" events            the quick screen's { from, replace, text }, again when it changes
 *                             (a widget's paste button reads the clipboard once it's in front)
 */
package org.uwuapps.fixup;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

import org.uwuapps.fixup.bridge.AppPlugin;
import org.uwuapps.fixup.bridge.JSArray;
import org.uwuapps.fixup.bridge.JSObject;
import org.uwuapps.fixup.bridge.Plugin;
import org.uwuapps.fixup.bridge.PluginCall;
import org.uwuapps.fixup.bridge.PluginMethod;

import java.lang.ref.WeakReference;

@AppPlugin(name = "Fixup")
public class FixupPlugin extends Plugin {
    // FCM topics are shared by every app in the UwU Apps Firebase project, hence the prefix.
    // The server sends new versions to fixup-releases (main-site/api/push/release.js); news goes
    // to fixup-news from the Firebase console (flutter/FIREBASE-SETUP.md).
    private static final String TOPIC_PREFIX = "fixup-";
    private static final String PREFS = "fixup";

    // The main app's plugin, for links it's opened with. The quick screen has its own.
    private static WeakReference<FixupPlugin> sMain = new WeakReference<>(null);
    private static String sPendingOpen;

    @Override
    public void load() {
        if (getActivity() instanceof MainActivity) {
            sMain = new WeakReference<>(this);
            if (sPendingOpen != null) {
                String url = sPendingOpen;
                sPendingOpen = null;
                open(url);
            }
        }
    }

    /** Whether this build updates itself: GitHub's APK does, Google Play's doesn't (its manifest,
     * src/play/AndroidManifest.xml, has no UpdateActivity). */
    static boolean canUpdate() {
        return !BuildConfig.PLAY;
    }

    @PluginMethod
    public void info(PluginCall call) {
        JSObject out = new JSObject();
        try {
            PackageInfo info = getContext().getPackageManager().getPackageInfo(getContext().getPackageName(), 0);
            out.put("version", info.versionName);
            out.put("versionCode", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode);
        } catch (PackageManager.NameNotFoundException e) {
            out.put("version", JSObject.NULL);
        }
        JSArray features = new JSArray();
        features.put("share");
        features.put("paste");
        features.put("open");
        features.put("background");
        if (canUpdate()) {
            features.put("update"); // UpdateActivity, for the update bar
            features.put("checkupdate"); // UpdateActivity's check, for the Edge Tray
        }
        // Firebase is set up for this build (google-services.json): notifications can come.
        if (firebaseReady(getContext())) features.put("push");
        out.put("features", features);
        out.put("quick", quickOf(getActivity()));
        out.put("android", Build.VERSION.SDK_INT);
        // Report a bug's "Android 16 · Google Pixel 9" (lib/features/bug/bug_report.dart).
        out.put("release", Build.VERSION.RELEASE);
        out.put("model", (Build.MODEL.toLowerCase().startsWith(Build.MANUFACTURER.toLowerCase()) ? "" : Build.MANUFACTURER + " ") + Build.MODEL);
        out.put("play", BuildConfig.PLAY);
        call.resolve(out);
    }

    private static Object quickOf(Activity activity) {
        if (!(activity instanceof FixActivity)) return JSObject.NULL;
        FixActivity fix = (FixActivity) activity;
        JSObject quick = new JSObject();
        quick.put("from", fix.from);
        quick.put("replace", fix.canReplace);
        quick.put("text", fix.text);
        return quick;
    }

    /** The quick screen's link, to its own Dart side. */
    static void quick(FixActivity activity) {
        if (activity.bridge() == null) return;
        Plugin plugin = activity.bridge().getPlugin("Fixup");
        if (!(plugin instanceof FixupPlugin)) return;
        JSObject out = (JSObject) quickOf(activity);
        ((FixupPlugin) plugin).notifyListeners("quick", out, true);
    }

    /** A page of the site the app was opened with, to the main app's Dart side. */
    static void open(String url) {
        FixupPlugin plugin = sMain.get();
        if (plugin == null) {
            sPendingOpen = url;
            return;
        }
        JSObject out = new JSObject();
        out.put("url", url);
        plugin.notifyListeners("open", out, true);
    }

    @PluginMethod
    public void share(PluginCall call) {
        String text = call.getString("text", "");
        String url = call.getString("url", "");
        String body = text.isEmpty() ? url : url.isEmpty() ? text : text + " " + url;
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, body);
        String title = call.getString("title");
        if (title != null && !title.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, title);
        getActivity().startActivity(Intent.createChooser(send, title));
        call.resolve();
    }

    @PluginMethod
    public void paste(PluginCall call) {
        JSObject out = new JSObject();
        out.put("text", clipboardText(getContext()));
        call.resolve(out);
    }

    // What's copied, or "" if nothing is (or this app isn't the one in front, on Android 10+).
    static String clipboardText(Context context) {
        ClipboardManager clipboard = (ClipboardManager) context.getSystemService(Context.CLIPBOARD_SERVICE);
        ClipData clip = clipboard == null ? null : clipboard.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return "";
        CharSequence item = clip.getItemAt(0).coerceToText(context);
        return item == null ? "" : item.toString();
    }

    @PluginMethod
    public void open(PluginCall call) {
        String url = call.getString("url", "");
        Uri uri = Uri.parse(url);
        if (!"https".equals(uri.getScheme()) && !"http".equals(uri.getScheme())) {
            call.reject("Only web links can be opened.");
            return;
        }
        try {
            getActivity().startActivity(new Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE));
            call.resolve();
        } catch (ActivityNotFoundException e) {
            call.reject("Nothing on this phone opens that link.");
        }
    }

    @PluginMethod
    public void update(PluginCall call) {
        if (!canUpdate()) {
            call.reject("Google Play updates this app.", "unavailable");
            return;
        }
        UpdateActivity.start(getActivity(), Boolean.TRUE.equals(call.getBoolean("check", false)), call.getString("version"));
        call.resolve();
    }

    @PluginMethod
    public void finish(PluginCall call) {
        String text = call.getString("text");
        call.resolve();
        getActivity().runOnUiThread(() -> {
            if (getActivity() instanceof FixActivity) ((FixActivity) getActivity()).finishWith(text);
            else getActivity().moveTaskToBack(true);
        });
    }

    // Back with nothing left to close, pressed twice: to the background rather than closed.
    @PluginMethod
    public void background(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            if (getActivity() instanceof FixActivity) getActivity().finish();
            else getActivity().moveTaskToBack(true);
            call.resolve();
        });
    }

    @PluginMethod
    public void topics(PluginCall call) {
        SharedPreferences prefs = getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        JSObject out = new JSObject();
        out.put("releases", prefs.getBoolean("topic.releases", false));
        out.put("news", prefs.getBoolean("topic.news", false));
        call.resolve(out);
    }

    @PluginMethod
    public void setTopic(PluginCall call) {
        String topic = call.getString("topic", "");
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        if (!"releases".equals(topic) && !"news".equals(topic)) {
            call.reject("Unknown topic");
            return;
        }
        if (!firebaseReady(getContext())) {
            call.reject("This copy of the app can't get notifications yet.", "unavailable");
            return;
        }
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        (on ? messaging.subscribeToTopic(TOPIC_PREFIX + topic) : messaging.unsubscribeFromTopic(TOPIC_PREFIX + topic))
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful()) {
                        call.reject("Couldn't reach Firebase. Check you're online, then try again.", "offline");
                        return;
                    }
                    getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                            .putBoolean("topic." + topic, on).apply();
                    JSObject out = new JSObject();
                    out.put("topic", topic);
                    out.put("on", on);
                    call.resolve(out);
                });
    }

    @PluginMethod
    public void openSettings(PluginCall call) {
        String pkg = getContext().getPackageName();
        Intent intent;
        if ("notifications".equals(call.getString("what")) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg);
        } else {
            intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null));
        }
        try {
            getActivity().startActivity(intent);
        } catch (ActivityNotFoundException e) {
            getActivity().startActivity(new Intent(Settings.ACTION_SETTINGS));
        }
        call.resolve();
    }

    // Built with google-services.json, which starts Firebase as the app starts. Without it there
    // is no Firebase, and FirebaseMessaging would throw.
    static boolean firebaseReady(Context context) {
        return !FirebaseApp.getApps(context).isEmpty();
    }
}
