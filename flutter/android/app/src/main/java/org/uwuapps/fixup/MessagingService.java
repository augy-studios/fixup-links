/*
 * Firebase Cloud Messaging's pushes, with the app's process up (PushNotificationsPlugin). With the
 * app in the background, a push with a notification is shown by Android itself and never comes
 * here; with it in front, it comes here and the Dart side decides what to show.
 */
package org.uwuapps.fixup;

import androidx.annotation.NonNull;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class MessagingService extends FirebaseMessagingService {

    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        PushNotificationsPlugin.received(message);
    }

    @Override
    public void onNewToken(@NonNull String token) {
        PushNotificationsPlugin.token(token);
    }
}
