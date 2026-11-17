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

    private static WeakReference<PushNotificationsPlugin> currentPlugin = new WeakReference<>(null);

    @Override
    public void load() {
        currentPlugin = new WeakReference<>(this);
    }

    // checkPermissions and requestPermissions are every plugin's (bridge/Plugin.java), with the
    // one alias, "receive".

    @PluginMethod
    public void register(PluginCall call) {
        if (!FixupPlugin.firebaseReady(getContext())) {
            JSObject errorEvent = new JSObject();
            errorEvent.put("error", "This copy of the app can't get notifications from the server yet.");
            notifyListeners("registrationError", errorEvent);
            call.resolve();
            return;
        }
        FirebaseMessaging messaging = FirebaseMessaging.getInstance();
        messaging.setAutoInitEnabled(true);
        messaging.getToken().addOnCompleteListener((task) -> {
            if (task.isSuccessful() && task.getResult() != null) {
                token(task.getResult());
            } else {
                JSObject errorEvent = new JSObject();
                Exception exception = task.getException();
                if (exception == null || exception.getMessage() == null) {
                    errorEvent.put("error", "Couldn't reach Firebase");
                } else {
                    errorEvent.put("error", exception.getMessage());
                }
                notifyListeners("registrationError", errorEvent);
            }
        });
        call.resolve();
    }

    static void token(String value) {
        PushNotificationsPlugin plugin = currentPlugin.get();
        if (plugin == null) {
            return;
        }
        JSObject registration = new JSObject();
        registration.put("value", value);
        plugin.notifyListeners("registration", registration);
    }

    // From MessagingService, with the app's process up: a push to hand the Dart side.
    static void received(RemoteMessage message) {
        PushNotificationsPlugin plugin = currentPlugin.get();
        if (plugin == null) {
            return;
        }
        JSObject push = new JSObject();
        push.put("id", message.getMessageId());
        RemoteMessage.Notification notification = message.getNotification();
        if (notification != null) {
            push.put("title", notification.getTitle());
            push.put("body", notification.getBody());
        }
        JSObject data = new JSObject();
        for (java.util.Map.Entry<String, String> entry : message.getData().entrySet()) {
            data.put(entry.getKey(), entry.getValue());
        }
        push.put("data", data);
        plugin.notifyListeners("pushNotificationReceived", push);
    }

    // A notification FCM showed, tapped: the app opens with the push's data as the intent's
    // extras (MainActivity hands every intent here).
    @Override
    protected void handleOnNewIntent(Intent intent) {
        if (intent == null) {
            return;
        }
        Bundle extras = intent.getExtras();
        if (extras == null || !extras.containsKey("google.message_id")) {
            return;
        }
        if ((intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) {
            return;
        }
        JSObject data = new JSObject();
        for (String key : extras.keySet()) {
            Object value = extras.get(key);
            if (value instanceof String || value instanceof Number || value instanceof Boolean) {
                data.put(key, value);
            }
        }
        JSObject notification = new JSObject();
        notification.put("id", extras.getString("google.message_id"));
        notification.put("data", data);
        JSObject action = new JSObject();
        action.put("actionId", "tap");
        action.put("notification", notification);
        notifyListeners("pushNotificationActionPerformed", action, true);
        intent.removeExtra("google.message_id");
    }
}
