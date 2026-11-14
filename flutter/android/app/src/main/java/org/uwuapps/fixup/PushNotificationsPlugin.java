/*
 * Notifications from the server, through Firebase Cloud Messaging (android/FIREBASE-SETUP.md):
 * Service Alerts, the Get Off Alert when the app was closed mid-trip, and new versions of the
 * app. The same calls and events Capacitor's push plugin had (2.0.0 to 2.3.1), for the Dart
 * side's alerts (android/lib/features/alerts/):
 *
 *   checkPermissions()     { receive }: "granted", "denied" or "prompt"
 *   requestPermissions()   Android's notification prompt (13 and later), then { receive }
 *   register()             the phone's FCM token, as a "registration" event { value }, or
 *                          "registrationError" { error }
 *
 *   "pushNotificationReceived"         { id, title, body, data }: a push that came while the
 *                                      app's in front, which FCM leaves to the app to show
 *   "pushNotificationActionPerformed"  { actionId: "tap", notification: { id, data } }: a
 *                                      notification Android showed itself, tapped (kept until
 *                                      something listens, so a tap that opened the app counts)
 *
 * Android shows a push itself while the app's in the background, on the channel the server
 * names (main-site/api/_push/fcm.js, Notifications.java).
 */
package org.uwuapps.fixup;

import android.Manifest;
import android.content.Intent;
import android.os.Bundle;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.RemoteMessage;

import org.uwuapps.fixup.bridge.AppPlugin;
import org.uwuapps.fixup.bridge.JSObject;
import org.uwuapps.fixup.bridge.Permission;
import org.uwuapps.fixup.bridge.Plugin;
import org.uwuapps.fixup.bridge.PluginCall;
import org.uwuapps.fixup.bridge.PluginMethod;

import java.lang.ref.WeakReference;

@AppPlugin(
        name = "PushNotifications",
        permissions = @Permission(alias = "receive", strings = {Manifest.permission.POST_NOTIFICATIONS})
)
public class PushNotificationsPlugin extends Plugin {

    private static WeakReference<PushNotificationsPlugin> sPlugin = new WeakReference<>(null);

    @Override
    public void load() {
        sPlugin = new WeakReference<>(this);
    }

    // checkPermissions and requestPermissions are every plugin's (bridge/Plugin.java), with the
    // one alias, "receive".

    @PluginMethod
    public void register(PluginCall call) {
        if (!FixupPlugin.firebaseReady(getContext())) {
            JSObject e = new JSObject();
            e.put("error", "This copy of the app can't get notifications from the server yet.");
            notifyListeners("registrationError", e);
            call.resolve();
            return;
        }
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        messaging.getToken().addOnCompleteListener(task -> {
            if (task.isSuccessful() && task.getResult() != null) {
                token(task.getResult());
            } else {
                JSObject e = new JSObject();
                Exception ex = task.getException();
                e.put("error", ex == null || ex.getMessage() == null ? "Couldn't reach Firebase" : ex.getMessage());
                notifyListeners("registrationError", e);
            }
        });
        call.resolve();
    }

    static void token(String value) {
        PushNotificationsPlugin plugin = sPlugin.get();
        if (plugin == null) return;
        JSObject out = new JSObject();
        out.put("value", value);
        plugin.notifyListeners("registration", out);
    }

    // From MessagingService, with the app's process up: a push to hand the Dart side.
    static void received(RemoteMessage message) {
        PushNotificationsPlugin plugin = sPlugin.get();
        if (plugin == null) return;
        JSObject out = new JSObject();
        out.put("id", message.getMessageId());
        RemoteMessage.Notification n = message.getNotification();
        if (n != null) {
            out.put("title", n.getTitle());
            out.put("body", n.getBody());
        }
        JSObject data = new JSObject();
        for (java.util.Map.Entry<String, String> e : message.getData().entrySet()) data.put(e.getKey(), e.getValue());
        out.put("data", data);
        plugin.notifyListeners("pushNotificationReceived", out);
    }

    // A notification FCM showed, tapped: the app opens with the push's data as the intent's
    // extras (MainActivity hands every intent here).
    @Override
    protected void handleOnNewIntent(Intent intent) {
        Bundle extras = intent == null ? null : intent.getExtras();
        if (extras == null || !extras.containsKey("google.message_id")) return;
        if ((intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return;
        JSObject data = new JSObject();
        for (String key : extras.keySet()) {
            Object v = extras.get(key);
            if (v instanceof String || v instanceof Number || v instanceof Boolean) data.put(key, v);
        }
        JSObject notification = new JSObject();
        notification.put("id", extras.getString("google.message_id"));
        notification.put("data", data);
        JSObject out = new JSObject();
        out.put("actionId", "tap");
        out.put("notification", notification);
        notifyListeners("pushNotificationActionPerformed", out, true);
        intent.removeExtra("google.message_id");
    }
}
