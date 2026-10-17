/*
 * The app itself, to the page (main-site/js/app-bridge.js):
 *
 *   info()                    { version, versionCode, features, quick }: what this app can do.
 *                             quick is { from: "share" | "select" | "copied", replace } in the
 *                             quick screen (FixActivity), or null in the app itself
 *   share({ title, text, url })   Android's share sheet, as navigator.share is in Chrome: the
 *                             WebView has none (js/app-bridge.js stands this in for it)
 *   paste()                   { text }: the clipboard, which the WebView can't read for the
 *                             page's Paste button
 *   open({ url })             a link in whatever app opens it (the browser, or X for fixupx.com)
 *   update({ check, version })  the update window (UpdateActivity): check, the Edge Tray's
 *                             "Check for app updates", looks first and asks before downloading
 *   finish({ text })          the quick screen's Replace or Done: the text back to the app that
 *                             asked, when it can take it, then closes (FixActivity.finishWith)
 *   topics()                  { releases, news }: which notifications you've turned on
 *   setTopic({ topic, on })   turns "releases" (new versions) or "news" on or off, as an FCM
 *                             topic subscription, so the server needs no list of phones
 *   openSettings({ what })    the app's notification settings ("notifications") or its page in
 *                             Android's settings ("app")
 */
package org.uwuapps.fixup;

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

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

@CapacitorPlugin(name = "Fixup")
public class FixupPlugin extends Plugin {
    // FCM topics are shared by every app in the UwU Apps Firebase project, hence the prefix.
    // The server sends new versions to fixup-releases (main-site/api/push/release.js); news goes
    // to fixup-news from the Firebase console (android/FIREBASE-SETUP.md).
    private static final String TOPIC_PREFIX = "fixup-";
    private static final String PREFS = "fixup";

    @PluginMethod
    public void info(PluginCall call) {
        JSObject out = new JSObject();
        try {
            PackageInfo info = getContext().getPackageManager().getPackageInfo(getContext().getPackageName(), 0);
            out.put("version", info.versionName);
            out.put("versionCode", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode);
        } catch (PackageManager.NameNotFoundException e) {
            out.put("version", null);
        }
        JSArray features = new JSArray();
        features.put("share");
        features.put("paste");
        features.put("open");
        features.put("update"); // UpdateActivity, for the update bar
        features.put("checkupdate"); // UpdateActivity's check, for the Edge Tray
        // Firebase is set up for this build (google-services.json): notifications can come.
        if (firebaseReady()) features.put("push");
        out.put("features", features);

        if (getActivity() instanceof FixActivity) {
            FixActivity fix = (FixActivity) getActivity();
            JSObject quick = new JSObject();
            quick.put("from", fix.from);
            quick.put("replace", fix.canReplace);
            out.put("quick", quick);
        } else {
            out.put("quick", JSObject.NULL);
        }
        out.put("android", Build.VERSION.SDK_INT);
        call.resolve(out);
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

    // Android 10 and later only let the app in front read the clipboard, which it is whenever
    // the page's Paste button can be pressed.
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
        UpdateActivity.start(getActivity(), Boolean.TRUE.equals(call.getBoolean("check", false)), call.getString("version"));
        call.resolve();
    }

    @PluginMethod
    public void finish(PluginCall call) {
        String text = call.getString("text");
        call.resolve();
        getActivity().runOnUiThread(() -> {
            if (getActivity() instanceof FixActivity) ((FixActivity) getActivity()).finishWith(text);
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
        if (!firebaseReady()) {
            call.reject("This copy of the app can't get notifications yet.");
            return;
        }
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        (on ? messaging.subscribeToTopic(TOPIC_PREFIX + topic) : messaging.unsubscribeFromTopic(TOPIC_PREFIX + topic))
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful()) {
                        call.reject("Couldn't reach Firebase. Check you're online, then try again.");
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
    private boolean firebaseReady() {
        return !FirebaseApp.getApps(getContext()).isEmpty();
    }
}
