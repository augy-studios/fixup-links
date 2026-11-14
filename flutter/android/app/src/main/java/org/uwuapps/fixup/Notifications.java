/*
 * The app's notification channels, each its own switch in Android's settings for the app:
 *
 *   releases  a new version of the app is out (main-site/api/push/release.js)
 *   news      news from uwuFix, sent from the Firebase console (android/FIREBASE-SETUP.md)
 *
 * Both come from FCM topics you join with the bell in the Edge Tray (FixupPlugin.setTopic), and
 * the pushes name these channels (main-site/api/_push/fcm.js). Android only takes a channel's
 * sound and importance from when it's made, so changing one means a new id.
 */
package org.uwuapps.fixup;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;

final class Notifications {
    static final String RELEASES = "releases";
    static final String NEWS = "news";

    private Notifications() {}

    static void createChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);

        NotificationChannel releases = new NotificationChannel(RELEASES, "New versions",
                NotificationManager.IMPORTANCE_DEFAULT);
        releases.setDescription("When a new version of the app is out");

        NotificationChannel news = new NotificationChannel(NEWS, "News from uwuFix",
                NotificationManager.IMPORTANCE_DEFAULT);
        news.setDescription("Now and then: new sites it fixes, and other news");

        manager.createNotificationChannel(releases);
        manager.createNotificationChannel(news);
    }
}
