/*
 * The app: the site at fixup.uwuapps.org in Capacitor's WebView (capacitor.config.json's
 * server.url), so the site's own updates reach it at once, with this app's plugin injected into
 * its pages for what a web page can't do (main-site/js/app-bridge.js):
 *
 *   FixupPlugin        what the app can do, the share sheet, the clipboard, updating itself,
 *                      and which notifications you've turned on
 *   PushNotifications  Capacitor's, for Android's notification permission and the pushes
 *
 * Here: what the app was opened with (one of the site's own links, a uwu://fixup/ link, or a
 * tapped notification) opened in the page, the back button going back through the page's
 * history, the notification channels, and uwuFix's place in the share sheet's Direct Share row.
 *
 * Links shared to uwuFix, and text highlighted elsewhere, open FixActivity instead: a quick
 * screen over the app they came from.
 */
package org.uwuapps.fixup;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.WebView;

import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    static final String SITE = "https://fixup.uwuapps.org";
    static final String HOST = "fixup.uwuapps.org";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        registerPlugin(FixupPlugin.class);
        Notifications.createChannels(this);
        DirectShare.publish(this);
        super.onCreate(savedInstanceState);

        // Back goes back through the page's history, as in a browser. Off the first page, the
        // app goes to the background rather than closing.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView web = bridge == null ? null : bridge.getWebView();
                if (web != null && web.canGoBack()) web.goBack();
                else moveTaskToBack(true);
            }
        });
    }

    // BridgeActivity calls this with the intent the app was opened with too, once the page has
    // started loading the site's home page.
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);

        // "Version 1.2.0 of uwuFix is out", tapped (main-site/api/push/release.js): straight to
        // the update window, which asks before downloading it. Taken off the intent so it isn't
        // asked again if Android recreates the activity with it.
        if ("release".equals(intent.getStringExtra("type"))) {
            UpdateActivity.start(this, true, intent.getStringExtra("version"));
            intent.removeExtra("type");
            return;
        }

        String url = pageFor(intent);
        if (url != null && bridge != null) bridge.getWebView().loadUrl(url);
    }

    // The site's page an intent asks for, or null for the home page as it is.
    static String pageFor(Intent intent) {
        Uri data = intent == null ? null : intent.getData();
        if (data == null) return null;
        // The site's own links.
        if ("https".equals(data.getScheme()) && HOST.equalsIgnoreCase(data.getHost())) {
            return data.toString();
        }
        // uwu://fixup/ to the home page, keeping its query: uwu://fixup/?url=https://x.com/...
        // cleans that link, as the site's own ?url= does. uwu:// is shared by UwU Apps' apps,
        // each answering its own host.
        if ("uwu".equals(data.getScheme()) && "fixup".equalsIgnoreCase(data.getHost())) {
            String query = data.getEncodedQuery();
            return SITE + "/" + (query == null ? "" : "?" + query);
        }
        return null;
    }
}
