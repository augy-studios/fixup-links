/*
 * The app (1.1.0): its screens are Flutter's (flutter/lib/), where 1.0.0 and 1.0.1 were the site
 * at fixup.uwuapps.org in Capacitor's WebView. The plugins the Dart side reaches over the bridge
 * (FlutterHost):
 *
 *   FixupPlugin              what the app can do, the share sheet, the clipboard, opening links,
 *                            updating itself, and which notifications you've turned on
 *   PushNotificationsPlugin  Android's notification permission, and pushes that come while the
 *                            app is open (Firebase Cloud Messaging)
 *   MigratePlugin            what the site kept in the WebView app (history, theme, Edge Tray)
 *
 * Here: what the app was opened with (one of the site's own links, a uwu://fix/ link, the "Fix a
 * link" widget, or a tapped notification) handed to the Dart side as the site's address for it
 * (FixupPlugin.open), the notification channels, and uwuFix's place in the share sheet's Direct
 * Share row.
 *
 * Links shared to uwuFix, and text highlighted elsewhere, open FixActivity instead: a quick screen
 * over the app they came from.
 */
package org.uwuapps.fixup;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import androidx.core.splashscreen.SplashScreen;

import org.uwuapps.fixup.bridge.Bridge;

public class MainActivity extends FlutterHost {
    static final String SITE = "https://fixup.uwuapps.org";
    static final String HOST = "fixup.uwuapps.org";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        SplashScreen.installSplashScreen(this);
        Notifications.createChannels(this);
        DirectShare.publish(this);
        super.onCreate(savedInstanceState);
    }

    @Override
    protected void registerPlugins(Bridge bridge) {
        bridge.registerPlugin(FixupPlugin.class);
        bridge.registerPlugin(PushNotificationsPlugin.class);
        bridge.registerPlugin(MigratePlugin.class);
    }

    @Override
    protected void route(Intent intent) {
        pluginBridge.onNewIntent(intent);
        // "Version 1.2.0 of uwuFix is out", tapped (main-site/api/push/release.js): FCM opens the
        // app with the push's data as extras. Straight to the updates page, which looks that
        // version up and asks before downloading it. The extras go, so the page doesn't open
        // again when Android recreates this screen.
        if ("release".equals(intent.getStringExtra("type"))) {
            if (FixupPlugin.canUpdate()) {
                UpdateActivity.check(this, intent.getStringExtra("version"));
            }
            intent.removeExtra("type");
            intent.removeExtra("version");
            return;
        }
        String url = pageFor(intent);
        if (url != null) {
            FixupPlugin.open(url);
        }
    }

    // The site's address an intent asks for, or null for the home page as it is.
    static String pageFor(Intent intent) {
        if (intent == null) {
            return null;
        }
        Uri data = intent.getData();
        if (data == null) {
            return null;
        }
        // The site's own links.
        if ("https".equals(data.getScheme()) && HOST.equalsIgnoreCase(data.getHost())) {
            return data.toString();
        }
        // uwu://fix/ (or uwu://fixup/) to the home page. A link after it is cleaned, as the
        // site's own ?url= does: uwu://fix/https://x.com/... Otherwise its query is kept, so
        // uwu://fix/?url=https://x.com/... does the same. uwu:// is shared by UwU Apps' apps,
        // each answering its own hosts.
        if ("uwu".equalsIgnoreCase(data.getScheme())
                && ("fix".equalsIgnoreCase(data.getHost()) || "fixup".equalsIgnoreCase(data.getHost()))) {
            String link = linkIn(data);
            if (link != null) {
                return SITE + "/?url=" + Uri.encode(link);
            }
            String query = data.getEncodedQuery();
            if (query == null) {
                return SITE + "/";
            }
            return SITE + "/" + "?" + query;
        }
        return null;
    }

    // The link in uwu://fix/https://x.com/a?b=c, everything after the host as it was written
    // (Uri would split its query and fragment off as uwu://fix/'s own), or null if there's none.
    private static String linkIn(Uri data) {
        String fullText = data.toString();
        int hostStart = fullText.indexOf("//");
        if (hostStart < 0) {
            return null;
        }
        int hostEnd = hostStart + 2;
        while (hostEnd < fullText.length() && "/?#".indexOf(fullText.charAt(hostEnd)) < 0) {
            hostEnd++;
        }
        if (hostEnd >= fullText.length() || fullText.charAt(hostEnd) != '/') {
            return null;
        }
        String link = fullText.substring(hostEnd + 1);
        if (link.isEmpty() || link.startsWith("?") || link.startsWith("#")) {
            return null;
        }
        if (link.contains("://")) {
            return link;
        }
        // Percent-encoded whole, as some apps write it: uwu://fix/https%3A%2F%2Fx.com%2F...
        return Uri.decode(link);
    }
}
